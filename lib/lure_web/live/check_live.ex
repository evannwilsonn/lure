defmodule LureWeb.CheckLive do
  @moduledoc "The page: paste a job ad, get a verdict, see why."
  use LureWeb, :live_view

  import LureWeb.Marks
  alias Lure.Detector

  @max 20_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Is this job ad real?",
       text: "",
       result: nil,
       checking: false,
       error: nil
     )
     |> assign(samples: read_json("samples.json", []), eval: read_json("eval.json", nil))
     |> assign(form: to_form(%{"text" => ""}, as: :ad))}
  end

  @impl true
  def handle_event("change", %{"ad" => %{"text" => text}}, socket) do
    {:noreply, assign(socket, text: text, form: to_form(%{"text" => text}, as: :ad))}
  end

  def handle_event("check", %{"ad" => %{"text" => text}}, socket),
    do: {:noreply, start_check(socket, text)}

  def handle_event("sample", %{"i" => i}, socket) do
    sample =
      case Integer.parse(to_string(i)) do
        {n, ""} when n >= 0 -> Enum.at(socket.assigns.samples, n)
        _ -> nil
      end

    case sample do
      nil ->
        {:noreply, socket}

      sample ->
        {:noreply,
         socket
         |> assign(form: to_form(%{"text" => sample["text"]}, as: :ad))
         |> start_check(sample["text"])}
    end
  end

  @impl true
  def handle_async(:check, {:ok, {text, result}}, socket) do
    {:noreply, assign(socket, checking: false, result: Map.put(result, :text, text), error: nil)}
  end

  def handle_async(:check, {:exit, _reason}, socket) do
    {:noreply,
     assign(socket, checking: false, error: "The checker didn't answer. Try again in a moment.")}
  end

  defp start_check(socket, text) do
    text = text |> String.slice(0, @max) |> String.trim()

    if String.length(text) < 40 do
      assign(socket,
        text: text,
        error: "Paste the whole ad: the title, the description and how to apply."
      )
    else
      socket
      |> assign(text: text, checking: true, error: nil)
      |> start_async(:check, fn -> {text, Detector.check(text)} end)
    end
  end

  defp read_json(name, default) do
    path = Path.join(:code.priv_dir(:lure), "model/" <> name)

    with {:ok, body} <- File.read(path),
         {:ok, data} <- Jason.decode(body),
         do: data,
         else: (_ -> default)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="wrap">
      <header class="top">
        <a class="mark" href="/"><b>LURE</b><span>Job ad inspection</span></a>
        <nav>
          <a href="#how">How it decides</a>
          <a href="https://github.com/evannwilsonn/lure">Source</a>
          <button id="theme" class="theme" type="button" phx-click={JS.dispatch("phx:toggle-theme")}>Light / dark</button>
        </nav>
      </header>

      <section class="intro">
        <div>
          <h1>Is this job ad real?</h1>
          <p>
            Paste an ad and Lure scores it with a model trained on 15,872 real postings, 713 of them scams caught by a job board's staff.
            It marks the words that moved the score and the red flags worth checking before you send anything.
          </p>
        </div>
        <.rosette class="guilloche" />
      </section>

      <div class="desk">
        <section class="panel" aria-labelledby="h-paste">
          <h2 id="h-paste">The ad</h2>
          <p class="hint">
            Copy everything: the title, the description, and how they want you to apply.
          </p>
          <.form for={@form} id="ad-form" phx-change="change" phx-submit="check">
            <label for="ad-text" class="label">Job ad text</label>
            <textarea
              id="ad-text"
              name="ad[text]"
              class="ad"
              maxlength="20000"
              placeholder="Data Entry Clerk, remote. Earn $750 a week from home…"
              phx-debounce="300"
            >{@form[:text].value}</textarea>
            <div :if={@samples != []} class="row samples">
              <span class="label">Or try</span>
              <button
                :for={{s, i} <- Enum.with_index(@samples)}
                type="button"
                class="chip"
                id={"sample-#{i}"}
                phx-click="sample"
                phx-value-i={i}
              >{s["label"]}</button>
            </div>
            <div class="row">
              <button id="check" class="go" type="submit" disabled={@checking}>{if @checking,
                do: "Inspecting…",
                else: "Inspect this ad"}</button>
              <span class="counter num">{String.length(@form[:text].value || "")} / 20,000</span>
            </div>
            <p :if={@error} id="error" class="hint error" role="alert">{@error}</p>
          </.form>
        </section>

        <section class="panel" aria-labelledby="h-result" aria-live="polite">
          <h2 id="h-result">The verdict</h2>
          <div :if={is_nil(@result)} class="empty">
            <p class="hint">Nothing inspected yet. Lure will show:</p>
            <ol>
              <li>a verdict: passes, check first, or fails inspection</li>
              <li>its score against the line where the model calls a scam</li>
              <li>the red flags it found, and the words that pushed the score either way</li>
            </ol>
          </div>
          <div :if={@result} id="result" class={"v-#{@result.verdict}"}>
            <div class="verdict">
              <.seal verdict={@result.verdict} />
              <div>
                <h3>{headline(@result.verdict)}</h3>
                <p>{explain(@result)}</p>
              </div>
            </div>
            <div
              class="scale"
              role="img"
              aria-label={"Score #{pct(@result.score)} of 100; the line is at #{pct(@result.threshold)}"}
            >
              <span class="line" style={"left: #{pct(@result.threshold)}%"}></span>
              <span class="needle" style={"left: #{pct(@result.score)}%"}></span>
            </div>
            <div class="scale-legend">
              <span>Looks normal</span><span class="num">score {pct(@result.score)} · line {pct(
                @result.threshold
              )}</span><span>Scam</span>
            </div>

            <ol :if={@result.flags != []} class="flags" id="flags">
              <li :for={{f, i} <- Enum.with_index(@result.flags, 1)}>
                <span class="n">{i}</span>
                <div><b>{f.title}</b><span>{f.why}</span></div>
              </li>
            </ol>
            <p :if={@result.flags == []} class="noflags">
              No red-flag patterns in the text. The verdict comes from the wording as a whole.
            </p>
          </div>
        </section>
      </div>

      <section :if={@result} class="panel markup" aria-labelledby="h-markup">
        <h2 id="h-markup">The ad, marked up</h2>
        <div class="key">
          <span><span class="w-up">&nbsp;word&nbsp;</span> pushed toward scam</span>
          <span><span class="w-down">&nbsp;word&nbsp;</span> pushed toward real</span>
          <span><span class="f-span">wavy underline</span><span class="f-num">1</span> red flag</span>
        </div>
        <div class="text" id="marked" tabindex="0">
          <%= for {seg, cls, flag} <- segments(@result) do %>
            <span class={cls}>{seg}</span><sup :if={flag} class="f-num">{flag}</sup>
          <% end %>
        </div>
      </section>

      <section :if={@eval} id="how" class="ledger">
        <div>
          <h2>How Lure decides</h2>
          <p>
            Two models read the ad. One is logistic regression on word and word-pair frequencies (TF-IDF), written from scratch in Elixir; its weights are why each word can be marked.
            The other is a small neural network, trained with Axon, on MiniLM sentence embeddings run in Elixir through Bumblebee, which catches ads that say the same thing in other words.
            They were compared on ads they never saw, and the one that ranked scams best on the validation set ships.
          </p>
          <div class="tablewrap">
            <table class="models">
              <thead>
                <tr>
                  <th>Model</th><th class="num">Avg. precision</th><th class="num">Precision</th><th class="num">
                    Recall
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{name, label} <- model_rows()}
                  class={if @eval["shipped"] == name, do: "shipped"}
                >
                  <td>{label}{if @eval["shipped"] == name, do: " (shipped)"}</td>
                  <td class="num">{fmt(@eval["models"][name]["test_average_precision"])}</td>
                  <td class="num">{fmt(@eval["models"][name]["test"]["precision"])}</td>
                  <td class="num">{fmt(@eval["models"][name]["test"]["recall"])}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="note">
            Scored on {@eval["dataset"]["test"]} held-out ads. Average precision is 1.0 when every scam ranks above every real ad; guessing scores about 0.045, the share of scams.
          </p>
        </div>
        <div>
          <h2>Words that lean scam</h2>
          <p>
            The terms the logistic regression weighs most toward fraud, learned from the training ads.
          </p>
          <div class="words">
            <span :for={w <- Enum.take(@eval["top_scam_words"] || [], 18)}>{w["token"]}</span>
          </div>
          <p class="note">
            A score is a reason to look closer, not proof. If an ad asks for money or your bank details, stop, and report it at <a href="https://reportfraud.ftc.gov">reportfraud.ftc.gov</a>.
          </p>
        </div>
      </section>

      <footer>
        <span>Built by Evan Wilson in Elixir, Phoenix LiveView, Nx, Axon and Bumblebee.</span>
        <span>Training data: EMSCAD, University of the Aegean (CC0).</span>
      </footer>
    </div>
    """
  end

  defp headline(:scam), do: "This looks like a scam"
  defp headline(:caution), do: "Check this one before applying"
  defp headline(:clear), do: "This reads like a real ad"

  defp explain(%{verdict: :scam, flags: f}),
    do:
      "Its wording matches the scams Lure learned from#{if f != [], do: ", and it trips #{length(f)} red flag#{plural(f)}", else: ""}. Don't send money or personal details."

  defp explain(%{verdict: :caution, flags: f}),
    do:
      "It shares some wording with scams#{if f != [], do: " and has #{length(f)} red flag#{plural(f)}", else: ""}. Look the company up on your own before you apply."

  defp explain(%{verdict: :clear, flags: []}),
    do: "Its wording matches real postings and nothing in it trips a red flag."

  defp explain(%{verdict: :clear, flags: f}),
    do:
      "Its wording matches real postings, but it has #{length(f)} red flag#{plural(f)} worth checking."

  defp plural([_]), do: ""
  defp plural(_), do: "s"

  defp pct(x), do: x |> Kernel.*(100) |> min(100) |> max(0) |> round()
  defp fmt(nil), do: "–"
  defp fmt(x), do: :erlang.float_to_binary(x * 1.0, decimals: 3)

  defp model_rows do
    [
      {"always_real", "Always say real"},
      {"red_flags", "Red-flag patterns alone"},
      {"tfidf_logistic", "TF-IDF + logistic regression"},
      {"minilm_network", "MiniLM + neural network"},
      {"average", "Average of the two"}
    ]
  end

  # Splits the ad at every place a highlight starts or ends, so each piece of text carries the
  # strongest word highlight covering it and, at the end of a red-flag match, its number.
  defp segments(%{text: text, words: words, flags: flags}) do
    word_spans =
      for w <- words,
          {s, l} <- w.spans,
          do: {s, s + l, if(w.weight > 0, do: "w-up", else: "w-down"), abs(w.weight)}

    flag_spans = for {f, i} <- Enum.with_index(flags, 1), {s, l} <- f.spans, do: {s, s + l, i}

    cuts =
      ([0, byte_size(text)] ++
         Enum.flat_map(word_spans, &[elem(&1, 0), elem(&1, 1)]) ++
         Enum.flat_map(flag_spans, &[elem(&1, 0), elem(&1, 1)]))
      |> Enum.uniq()
      |> Enum.sort()

    cuts
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] ->
      word =
        word_spans
        |> Enum.filter(fn {s, e, _, _} -> s <= a and b <= e end)
        |> Enum.max_by(&elem(&1, 3), fn -> nil end)

      in_flag = Enum.find(flag_spans, fn {s, e, _} -> s <= a and b <= e end)
      ends_flag = Enum.find(flag_spans, fn {_, e, _} -> e == b end)

      cls =
        [word && elem(word, 2), in_flag && "f-span"]
        |> Enum.reject(&(&1 in [nil, false]))
        |> Enum.join(" ")

      {binary_part(text, a, b - a), cls, ends_flag && elem(ends_flag, 2)}
    end)
  end
end
