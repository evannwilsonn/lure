defmodule Lure.Logistic do
  @moduledoc """
  Logistic regression on sparse TF-IDF features, written from scratch.

  Training is full-batch gradient descent with Adam, run on EXLA. The postings are held as a
  sparse matrix (row, column, value triples), so each step scatters and gathers only the
  non-zero entries instead of multiplying a 11,000 x 30,000 dense matrix.

  Scams are about one ad in twenty, so each scam counts `pos_weight` times in the loss; without
  that, the cheapest way to be accurate is to call everything real. L2 regularisation keeps the
  weights small so rare words can't carry a whole decision.
  """

  import Nx.Defn

  defstruct weights: %{}, bias: 0.0

  @type t :: %__MODULE__{weights: %{non_neg_integer() => float()}, bias: float()}

  @spec train([{map(), boolean()}], keyword()) :: t
  def train(examples, opts \\ []) do
    steps = Keyword.get(opts, :steps, 400)
    l2 = Keyword.get(opts, :l2, 1.0e-4)
    dims = Keyword.fetch!(opts, :dims)
    n = length(examples)
    pos = Enum.count(examples, &elem(&1, 1))
    pos_weight = Keyword.get(opts, :pos_weight, (n - pos) / max(pos, 1))

    triples =
      examples
      |> Enum.with_index()
      |> Enum.flat_map(fn {{x, _}, row} -> Enum.map(x, fn {col, v} -> {row, col, v} end) end)

    rows = triples |> Enum.map(&elem(&1, 0)) |> Nx.tensor(type: :s32)
    cols = triples |> Enum.map(&elem(&1, 1)) |> Nx.tensor(type: :s32)
    vals = triples |> Enum.map(&elem(&1, 2)) |> Nx.tensor(type: :f32)
    y = examples |> Enum.map(&if(elem(&1, 1), do: 1.0, else: 0.0)) |> Nx.tensor(type: :f32)
    sample_w = Nx.select(Nx.equal(y, 1), pos_weight, 1.0)

    data = %{rows: rows, cols: cols, vals: vals, y: y, sw: sample_w}

    init = %{
      w: Nx.broadcast(0.0, {dims}),
      b: Nx.tensor(0.0),
      mw: Nx.broadcast(0.0, {dims}),
      vw: Nx.broadcast(0.0, {dims}),
      mb: Nx.tensor(0.0),
      vb: Nx.tensor(0.0)
    }

    step = Nx.Defn.jit(&adam_step/4, compiler: EXLA)

    state =
      Enum.reduce(1..steps, init, fn t, s ->
        step.(s, data, Nx.tensor(t, type: :f32), Nx.tensor(l2))
      end)

    weights =
      state.w
      |> Nx.to_flat_list()
      |> Enum.with_index()
      |> Enum.reject(fn {w, _} -> w == 0.0 end)
      |> Map.new(fn {w, i} -> {i, w} end)

    %__MODULE__{weights: weights, bias: Nx.to_number(state.b)}
  end

  defn adam_step(s, d, t, l2) do
    n = Nx.size(d.y)
    {gw, gb} = grads(s.w, s.b, d, n, l2)
    {b1, b2, lr, eps} = {0.9, 0.999, 0.05, 1.0e-8}
    mw = b1 * s.mw + (1 - b1) * gw
    vw = b2 * s.vw + (1 - b2) * gw * gw
    mb = b1 * s.mb + (1 - b1) * gb
    vb = b2 * s.vb + (1 - b2) * gb * gb
    c1 = 1 - b1 ** t
    c2 = 1 - b2 ** t
    w = s.w - lr * (mw / c1) / (Nx.sqrt(vw / c2) + eps)
    b = s.b - lr * (mb / c1) / (Nx.sqrt(vb / c2) + eps)
    %{w: w, b: b, mw: mw, vw: vw, mb: mb, vb: vb}
  end

  # Weighted log-loss gradient, computed on the sparse matrix: logits gather each row's
  # non-zero weights, the weight gradient scatters each row's error back to its columns.
  defnp grads(w, b, d, n, l2) do
    contrib = Nx.take(w, d.cols) * d.vals
    logits = Nx.indexed_add(Nx.broadcast(0.0, {n}), Nx.new_axis(d.rows, 1), contrib) + b
    p = Nx.sigmoid(logits)
    err = (p - d.y) * d.sw / Nx.sum(d.sw)

    gw =
      Nx.indexed_add(
        Nx.broadcast(0.0, Nx.shape(w)),
        Nx.new_axis(d.cols, 1),
        Nx.take(err, d.rows) * d.vals
      ) + l2 * w

    {gw, Nx.sum(err)}
  end

  @spec probability(t, map()) :: float()
  def probability(%__MODULE__{} = m, x), do: sigmoid(score(m, x))

  def score(%__MODULE__{weights: w, bias: b}, x),
    do: Enum.reduce(x, b, fn {i, v}, acc -> acc + Map.get(w, i, 0.0) * v end)

  @doc "Each feature's push on the score for this input: positive means more scam-like."
  def contributions(%__MODULE__{weights: w}, x),
    do: Map.new(x, fn {i, v} -> {i, Map.get(w, i, 0.0) * v} end)

  defp sigmoid(z) when z >= 0, do: 1 / (1 + :math.exp(-z))
  defp sigmoid(z), do: :math.exp(z) / (1 + :math.exp(z))
end
