defmodule Lure.Embedder do
  @moduledoc """
  Sentence embeddings from all-MiniLM-L6-v2 (a 22M-parameter transformer from the
  sentence-transformers project), run in Elixir by Bumblebee and compiled with EXLA. Each ad
  becomes 384 numbers that place it among ads with similar meaning, even when the wording differs.

  The model reads the first 256 word pieces: the title and the opening of the ad, which is
  where scams make their pitch.
  """

  @repo "sentence-transformers/all-MiniLM-L6-v2"
  @seq 256

  def serving(opts \\ []) do
    {:ok, model} = Bumblebee.load_model({:hf, @repo})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @repo})

    Bumblebee.Text.text_embedding(model, tokenizer,
      output_pool: :mean_pooling,
      output_attribute: :hidden_state,
      embedding_processor: :l2_norm,
      compile: [batch_size: Keyword.get(opts, :batch_size, 16), sequence_length: @seq],
      defn_options: [compiler: EXLA]
    )
  end

  @doc "Embeds texts in batches; returns an `{n, 384}` tensor."
  def embed_all(serving, texts, progress \\ fn _ -> :ok end) do
    texts
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.map(fn {batch, i} ->
      progress.(i * 16)
      serving |> Nx.Serving.run(batch) |> Enum.map(& &1.embedding) |> Nx.stack()
    end)
    |> Nx.concatenate()
  end
end
