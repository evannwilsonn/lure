defmodule Lure.Detector do
  @moduledoc """
  Scores a pasted job ad with the model `mix lure.train` shipped, and explains the score:
  which words pushed it (from the TF-IDF logistic regression, whose weights can be read
  directly) and which red flags the text contains.
  """

  alias Lure.{Flags, Head, Logistic, Tfidf}

  @key {__MODULE__, :model}

  def artifact_path, do: Path.join(:code.priv_dir(:lure), "model/lure.etf")

  @doc "Loads the trained model into persistent storage; called once at boot."
  def load! do
    m = artifact_path() |> File.read!() |> :erlang.binary_to_term()
    :persistent_term.put(@key, %{m | head: Nx.deserialize(m.head)})
  end

  def model, do: :persistent_term.get(@key)
  def needs_embeddings?, do: model().method in ["minilm_network", "average"]

  @type result :: %{
          score: float(),
          threshold: float(),
          verdict: :scam | :caution | :clear,
          words: [
            %{token: String.t(), weight: float(), spans: [{non_neg_integer(), non_neg_integer()}]}
          ],
          flags: [map()]
        }

  @spec check(String.t()) :: result
  def check(text) do
    m = model()
    x = Tfidf.transform(m.tfidf, text)
    lr = Logistic.probability(m.logistic, x)

    score =
      case m.method do
        "tfidf_logistic" -> lr
        "minilm_network" -> network(m, text)
        "average" -> (lr + network(m, text)) / 2
      end

    verdict =
      cond do
        score >= m.threshold -> :scam
        score >= m.threshold / 2 -> :caution
        true -> :clear
      end

    %{
      score: score,
      threshold: m.threshold,
      verdict: verdict,
      words: words(m, x, text),
      flags: Flags.find(text)
    }
  end

  defp network(m, text) do
    %{embedding: e} = Nx.Serving.batched_run(Lure.Embeddings, text)
    [p] = Head.predict(m.head, Nx.new_axis(e, 0))
    p
  end

  # The words and word pairs with the biggest push in each direction, with where they appear.
  defp words(m, x, text) do
    contrib = Logistic.contributions(m.logistic, x)
    spans = text |> Lure.Tokens.grams() |> Enum.group_by(&elem(&1, 0), fn {_, s, l} -> {s, l} end)

    {up, down} =
      contrib |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.split_with(&(elem(&1, 1) > 0))

    (Enum.take(up, 10) ++ Enum.take(Enum.reverse(down), 6))
    |> Enum.map(fn {i, w} ->
      token = Tfidf.token(m.tfidf, i)
      %{token: token, weight: w, spans: Map.get(spans, token, [])}
    end)
    |> Enum.reject(&(&1.spans == [] or abs(&1.weight) < 0.02))
  end
end
