defmodule Lure.Tokens do
  @moduledoc """
  Splits text into lower-case words and adjacent word pairs, keeping each token's position in
  the original text so the app can underline the exact words that moved the score.
  """

  # Links, email addresses and phone numbers each become one token. The training ads had them
  # masked (`#URL_9f2c…#`, `#EMAIL_…#`, `#PHONE_…#`); ads people paste have real ones. Mapping
  # both to the same token means the model reads "there is a link here" either way.
  @contact ~r/#(?:URL|EMAIL|PHONE)_[0-9a-f]+#|\[(?:link|email|phone) removed\]|(?<url>https?:\/\/[^\s<>"]+|www\.[^\s<>"]+)|(?<email>[\w.+-]+@[\w-]+(?:\.[\w-]+)+)|(?<phone>\+?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b)/u
  @word ~r/[\p{L}\p{N}$€£][\p{L}\p{N}'’$€£.,%-]*[\p{L}\p{N}%]|[\p{L}\p{N}$€£]/u

  @doc "Words with their byte offsets: `[{word, start, length}]`."
  @spec words(String.t()) :: [{String.t(), non_neg_integer(), non_neg_integer()}]
  def words(text) do
    contacts =
      Regex.scan(@contact, text, return: :index)
      |> Enum.map(fn [{start, len} | _] ->
        {contact_token(binary_part(text, start, len)), start, len}
      end)

    taken = fn s -> Enum.any?(contacts, fn {_, cs, cl} -> s >= cs and s < cs + cl end) end

    words =
      Regex.scan(@word, text, return: :index)
      |> Enum.reject(fn [{start, _}] -> taken.(start) end)
      |> Enum.map(fn [{start, len}] ->
        {text |> binary_part(start, len) |> normalise(), start, len}
      end)

    Enum.sort_by(contacts ++ words, &elem(&1, 1))
  end

  defp contact_token(match) do
    cond do
      String.starts_with?(match, ["#URL_", "[link"]) or match =~ ~r/^(https?:|www\.)/ ->
        "<link>"

      String.starts_with?(match, ["#EMAIL_", "[email"]) or String.contains?(match, "@") ->
        "<email>"

      true ->
        "<phone>"
    end
  end

  @doc "Unigrams and bigrams, each with the span of text it covers."
  @spec grams(String.t()) :: [{String.t(), non_neg_integer(), non_neg_integer()}]
  def grams(text) do
    ws = words(text)

    bigrams =
      ws
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{a, s1, _}, {b, s2, l2}] -> {a <> " " <> b, s1, s2 + l2 - s1} end)

    ws ++ bigrams
  end

  # Numbers are collapsed into shapes, so "$5,000" and "$7,500" count as the same signal.
  defp normalise(word) do
    word
    |> String.downcase()
    |> String.replace(~r/\d+/u, "0")
    |> String.trim_trailing(".")
    |> String.trim_trailing(",")
  end
end
