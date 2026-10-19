defmodule Lure.Head do
  @moduledoc """
  A small neural network on top of the sentence embeddings, built and trained with Axon:
  384 inputs, one hidden layer of 64 with dropout, and a single output for the chance an ad is
  a scam. Scams are weighted up in the loss by the same ratio as the logistic regression.
  """

  def model do
    Axon.input("embedding", shape: {nil, 384})
    |> Axon.dense(64, activation: :relu, name: "hidden")
    |> Axon.dropout(rate: 0.2)
    |> Axon.dense(1, activation: :sigmoid, name: "out")
  end

  @doc "Trains on an `{n, 384}` tensor and a list of booleans; returns the trained model state."
  def train(x, labels, opts \\ []) do
    epochs = Keyword.get(opts, :epochs, 40)
    y = labels |> Enum.map(&if(&1, do: 1.0, else: 0.0)) |> Nx.tensor() |> Nx.reshape({:auto, 1})
    pos = Enum.count(labels, & &1)
    w = (length(labels) - pos) / max(pos, 1)
    # Binary cross-entropy with each scam counted `w` times.
    loss = fn y_true, y_pred ->
      p = Nx.clip(y_pred, 1.0e-7, 1.0 - 1.0e-7)

      y_true
      |> Nx.multiply(w)
      |> Nx.multiply(Nx.log(p))
      |> Nx.add(Nx.multiply(Nx.subtract(1, y_true), Nx.log(Nx.subtract(1, p))))
      |> Nx.negate()
      |> Nx.mean()
    end

    # One fixed shuffle so batches mix scams and real ads; Axon walks the batches each epoch.
    {perm, _} = Nx.Random.shuffle(Nx.Random.key(42), Nx.iota({Nx.axis_size(x, 0)}))
    batches = Enum.zip(Nx.to_batched(Nx.take(x, perm), 64), Nx.to_batched(Nx.take(y, perm), 64))
    data = Enum.map(batches, fn {a, b} -> {%{"embedding" => a}, b} end)

    model()
    |> Axon.Loop.trainer(loss, Polaris.Optimizers.adamw(learning_rate: 1.0e-3, decay: 1.0e-4),
      log: 0
    )
    |> Axon.Loop.run(data, Axon.ModelState.empty(), epochs: epochs, compiler: EXLA)
  end

  def predict(state, x) do
    {_init, predict} = Axon.build(model(), compiler: EXLA)
    state |> predict.(%{"embedding" => x}) |> Nx.reshape({:auto}) |> Nx.to_list()
  end
end
