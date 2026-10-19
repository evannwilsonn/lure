defmodule Lure.Metrics do
  @moduledoc "Precision, recall, F1 and average precision for a binary classifier."

  @doc "Counts and rates at one threshold."
  def at(probs, labels, threshold) do
    pairs = Enum.zip(probs, labels)
    tp = Enum.count(pairs, fn {p, y} -> y and p >= threshold end)
    fp = Enum.count(pairs, fn {p, y} -> not y and p >= threshold end)
    fn_ = Enum.count(pairs, fn {p, y} -> y and p < threshold end)
    tn = length(pairs) - tp - fp - fn_
    precision = if tp + fp == 0, do: 0.0, else: tp / (tp + fp)
    recall = if tp + fn_ == 0, do: 0.0, else: tp / (tp + fn_)
    f1 = if precision + recall == 0, do: 0.0, else: 2 * precision * recall / (precision + recall)

    %{
      threshold: threshold,
      tp: tp,
      fp: fp,
      fn: fn_,
      tn: tn,
      precision: precision,
      recall: recall,
      f1: f1
    }
  end

  @doc """
  Average precision: the area under the precision-recall curve, summed at each scam the ranking
  finds. A model that ranks every scam above every real ad scores 1; random guessing scores the
  share of scams (about 0.05 here).
  """
  def average_precision(probs, labels) do
    positives = Enum.count(labels, & &1)

    {sum, _tp, _seen} =
      Enum.zip(probs, labels)
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.reduce({0.0, 0, 0}, fn {_p, y}, {sum, tp, seen} ->
        seen = seen + 1
        if y, do: {sum + (tp + 1) / seen, tp + 1, seen}, else: {sum, tp, seen}
      end)

    if positives == 0, do: 0.0, else: sum / positives
  end

  @doc "The threshold that maximises F1, searched over the scores themselves."
  def best_threshold(probs, labels) do
    probs
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.take_every(max(1, div(length(probs), 2000)))
    |> Enum.map(&at(probs, labels, &1))
    |> Enum.max_by(& &1.f1)
  end
end
