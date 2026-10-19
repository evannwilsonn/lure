defmodule Mix.Tasks.Lure.Train do
  @shortdoc "Trains and evaluates the scam models; writes priv/model and results/eval.json"
  @moduledoc """
      mix lure.train

  Downloads the dataset if it isn't there, splits it 70/15/15, and compares:

    * always "real" (the floor any model has to beat)
    * the red-flag patterns alone, scored by how many fire
    * TF-IDF with logistic regression, written from scratch
    * MiniLM sentence embeddings with a small Axon network
    * the average of those two

  Everything is chosen on the validation part (which model ships, and the threshold that
  turns its score into a verdict); the test part is scored once, at the end.
  """
  use Mix.Task

  alias Lure.{Data, Embedder, Flags, Head, Logistic, Metrics, Tfidf}

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    Application.ensure_all_started([:exla, :bumblebee])
    ensure_data()

    postings = Data.load()
    %{train: train, valid: valid, test: test} = Data.split(postings)

    info(
      "#{length(postings)} unique postings (#{Enum.count(postings, & &1.fraud)} scams): #{length(train)} train, #{length(valid)} validation, #{length(test)} test"
    )

    labels = fn set -> Enum.map(set, & &1.fraud) end

    flag_score = fn set ->
      Enum.map(set, fn p -> length(Flags.find(p.text)) / length(Flags.all()) end)
    end

    info("fitting TF-IDF")
    tfidf = Tfidf.fit(Enum.map(train, & &1.text))
    vec = fn set -> Enum.map(set, &Tfidf.transform(tfidf, &1.text)) end
    info("training logistic regression on #{map_size(tfidf.vocab)} features")
    lr = Logistic.train(Enum.zip(vec.(train), labels.(train)), dims: map_size(tfidf.vocab))
    lr_probs = fn set -> Enum.map(vec.(set), &Logistic.probability(lr, &1)) end

    serving = Embedder.serving()
    embed = fn name, set -> cached_embeddings(name, serving, Enum.map(set, & &1.text)) end
    {xtr, xva, xte} = {embed.("train", train), embed.("valid", valid), embed.("test", test)}
    info("training the network head")
    head = Head.train(xtr, labels.(train))
    avg = fn a, b -> Enum.zip_with(a, b, &((&1 + &2) / 2)) end

    {lr_v, lr_t, nn_v, nn_t} =
      {lr_probs.(valid), lr_probs.(test), Head.predict(head, xva), Head.predict(head, xte)}

    candidates = %{
      "always_real" => {List.duplicate(0.0, length(valid)), List.duplicate(0.0, length(test))},
      "red_flags" => {flag_score.(valid), flag_score.(test)},
      "tfidf_logistic" => {lr_v, lr_t},
      "minilm_network" => {nn_v, nn_t},
      "average" => {avg.(lr_v, nn_v), avg.(lr_t, nn_t)}
    }

    results =
      Map.new(candidates, fn {name, {pv, pt}} ->
        best = Metrics.best_threshold(pv, labels.(valid))

        {name,
         %{
           valid_average_precision: Metrics.average_precision(pv, labels.(valid)),
           threshold: best.threshold,
           test_average_precision: Metrics.average_precision(pt, labels.(test)),
           test: Metrics.at(pt, labels.(test), best.threshold)
         }}
      end)

    shipped =
      ~w(tfidf_logistic minilm_network average)
      |> Enum.max_by(&results[&1].valid_average_precision)

    info("shipping #{shipped}")

    top_words =
      lr.weights
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(25)
      |> Enum.map(fn {i, w} -> %{token: Tfidf.token(tfidf, i), weight: Float.round(w, 3)} end)

    File.mkdir_p!("priv/model")
    File.mkdir_p!("results")

    artifact = %{
      method: shipped,
      threshold: results[shipped].threshold,
      tfidf: tfidf,
      logistic: lr,
      head: Nx.serialize(Nx.backend_copy(head.data, Nx.BinaryBackend))
    }

    File.write!("priv/model/lure.etf", :erlang.term_to_binary(artifact, compressed: 9))

    samples = pick_samples(test, results[shipped].threshold, lr, tfidf, head, shipped, xte)
    File.write!("priv/model/samples.json", Jason.encode_to_iodata!(samples, pretty: true))

    File.write!(
      "results/eval.json",
      Jason.encode_to_iodata!(
        %{
          dataset: %{
            postings: length(postings),
            scams: Enum.count(postings, & &1.fraud),
            train: length(train),
            valid: length(valid),
            test: length(test)
          },
          shipped: shipped,
          models: results,
          top_scam_words: top_words,
          flags_on_test: flag_rates(test)
        },
        pretty: true
      )
    )

    File.cp!("results/eval.json", "priv/model/eval.json")

    for {name, r} <- Enum.sort_by(results, &(-elem(&1, 1).test_average_precision)) do
      t = r.test

      info(
        :io_lib.format(
          "~-16s test AP ~.3f  precision ~.3f  recall ~.3f  F1 ~.3f  (threshold ~.3f)",
          [name, r.test_average_precision, t.precision, t.recall, t.f1, r.threshold * 1.0]
        )
        |> to_string()
      )
    end
  end

  # Three ads from the test set for the page's example buttons: the clearest scam that also
  # trips red flags, an ordinary real ad, and the ad scored closest to the line.
  defp pick_samples(test, threshold, lr, tfidf, head, shipped, xte) do
    lrp = Enum.map(test, &Logistic.probability(lr, Tfidf.transform(tfidf, &1.text)))
    nnp = Head.predict(head, xte)

    scores =
      case shipped do
        "tfidf_logistic" -> lrp
        "minilm_network" -> nnp
        "average" -> Enum.zip_with(lrp, nnp, &((&1 + &2) / 2))
      end

    scored = Enum.zip(test, scores)
    short = fn {p, _} -> String.length(p.text) in 500..2200 end

    scam =
      scored
      |> Enum.filter(fn {p, s} = x ->
        p.fraud and s >= threshold and short.(x) and length(Flags.find(p.text)) >= 2
      end)
      |> Enum.max_by(&elem(&1, 1), fn ->
        scored |> Enum.filter(&elem(&1, 0).fraud) |> Enum.max_by(&elem(&1, 1))
      end)

    real =
      scored
      |> Enum.filter(fn {p, s} = x -> not p.fraud and s < threshold / 4 and short.(x) end)
      |> Enum.at(3)

    close = scored |> Enum.filter(short) |> Enum.min_by(fn {_, s} -> abs(s - threshold) end)

    for {label, {p, _}} <- [
          {"A scam from the test set", scam},
          {"A real ad", real},
          {"A close call", close}
        ] do
      %{label: label, title: p.title, text: readable(p.text), fraud: p.fraud}
    end
  end

  defp flag_rates(test) do
    Map.new(Flags.all(), fn %{key: key} ->
      hits = Enum.filter(test, fn p -> Enum.any?(Flags.find(p.text), &(&1.key == key)) end)
      {key, %{ads: length(hits), scams: Enum.count(hits, & &1.fraud)}}
    end)
  end

  defp cached_embeddings(name, serving, texts) do
    path = "priv/data/embeddings-#{name}-#{:erlang.phash2(texts)}.nx"

    if File.exists?(path) do
      path |> File.read!() |> Nx.deserialize()
    else
      info("embedding #{length(texts)} #{name} postings with MiniLM")
      t0 = System.monotonic_time(:second)

      x =
        Embedder.embed_all(serving, texts, fn i ->
          if rem(i, 1600) == 0,
            do: info("  #{i}/#{length(texts)} after #{System.monotonic_time(:second) - t0}s")
        end)

      File.write!(path, Nx.serialize(Nx.backend_copy(x, Nx.BinaryBackend)))
      x
    end
  end

  defp ensure_data do
    unless File.exists?(Data.path()) do
      File.mkdir_p!(Path.dirname(Data.path()))
      info("downloading the dataset")
      {_, 0} = System.cmd("curl", ["-sSfL", "-o", Data.path(), Data.url()])
    end
  end

  defp info(msg), do: Mix.shell().info(msg)

  # The dataset's masked contacts, written the way a person would read them.
  defp readable(text) do
    text
    |> String.replace(~r/#URL_[0-9a-f]+#/, "[link removed]")
    |> String.replace(~r/#EMAIL_[0-9a-f]+#/, "[email removed]")
    |> String.replace(~r/#PHONE_[0-9a-f]+#/, "[phone removed]")
  end
end
