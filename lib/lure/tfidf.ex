defmodule Lure.Tfidf do
  @moduledoc """
  TF-IDF features, written from scratch. The vocabulary is the unigrams and bigrams that appear
  in at least `min_df` training postings, capped at the `max_features` most common. Each posting
  becomes a sparse map of `token index => weight`, L2-normalised so long ads don't dominate.
  """

  defstruct vocab: %{}, idf: %{}, tokens: {}

  @type t :: %__MODULE__{
          vocab: %{String.t() => non_neg_integer()},
          idf: %{non_neg_integer() => float()},
          tokens: tuple()
        }

  @spec fit([String.t()], keyword()) :: t
  def fit(texts, opts \\ []) do
    min_df = Keyword.get(opts, :min_df, 3)
    max_features = Keyword.get(opts, :max_features, 30_000)
    n = length(texts)

    df =
      texts
      |> Enum.flat_map(fn t ->
        t |> Lure.Tokens.grams() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_tok, c} -> c >= min_df end)
      |> Enum.sort_by(fn {tok, c} -> {-c, tok} end)
      |> Enum.take(max_features)

    tokens = Enum.map(df, &elem(&1, 0))
    vocab = tokens |> Enum.with_index() |> Map.new()

    idf =
      df
      |> Enum.with_index()
      |> Map.new(fn {{_tok, c}, i} -> {i, :math.log((1 + n) / (1 + c)) + 1} end)

    %__MODULE__{vocab: vocab, idf: idf, tokens: List.to_tuple(tokens)}
  end

  @doc "Sparse TF-IDF vector for one text."
  @spec transform(t, String.t()) :: %{non_neg_integer() => float()}
  def transform(%__MODULE__{} = m, text) do
    counts =
      text
      |> Lure.Tokens.grams()
      |> Enum.flat_map(fn {tok, _, _} -> List.wrap(Map.get(m.vocab, tok)) end)
      |> Enum.frequencies()

    weighted = Map.new(counts, fn {i, c} -> {i, (1 + :math.log(c)) * m.idf[i]} end)
    norm = weighted |> Map.values() |> Enum.reduce(0.0, &(&1 * &1 + &2)) |> :math.sqrt()
    if norm == 0, do: weighted, else: Map.new(weighted, fn {i, w} -> {i, w / norm} end)
  end

  def token(%__MODULE__{tokens: t}, i), do: elem(t, i)
end
