defmodule Lure.Data do
  @moduledoc """
  The Employment Scam Aegean Dataset (EMSCAD): 17,880 real job ads posted between 2012 and 2014,
  866 of them marked fraudulent by the job board's staff. Published by the University of the
  Aegean and mirrored on Hugging Face under CC0.

  A reader can only paste what an ad says, so the model sees text alone: the title, company
  profile, description, requirements and benefits. The board's own metadata (whether the ad had
  a logo, screening questions, and so on) isn't used, because nobody checking an ad has it.
  """

  NimbleCSV.define(Lure.Data.CSV, separator: ",", escape: "\"")

  @url "https://huggingface.co/datasets/victor/real-or-fake-fake-jobposting-prediction/resolve/main/fake_job_postings.csv"
  def url, do: @url
  def path, do: Path.join(:code.priv_dir(:lure), "data/fake_job_postings.csv")

  @fields ~w(title company_profile description requirements benefits)

  @type posting :: %{id: String.t(), text: String.t(), title: String.t(), fraud: boolean()}

  @doc "Every posting, deduplicated on its text (the board has repeats of the same ad)."
  @spec load(String.t()) :: [posting]
  def load(path \\ path()) do
    [header | rows] = path |> File.read!() |> Lure.Data.CSV.parse_string(skip_headers: false)
    index = header |> Enum.with_index() |> Map.new()

    rows
    |> Enum.map(fn row ->
      get = fn field -> row |> Enum.at(index[field]) |> to_string() end

      text =
        @fields
        |> Enum.map(&get.(&1))
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")

      %{id: get.("job_id"), title: get.("title"), text: text, fraud: get.("fraudulent") == "1"}
    end)
    |> Enum.uniq_by(&normalise(&1.text))
  end

  defp normalise(text),
    do: text |> String.downcase() |> String.replace(~r/\s+/u, " ") |> String.trim()

  @doc """
  A fixed train / validation / test split (70 / 15 / 15), stratified so each part keeps the
  same share of scams. Which part a posting lands in depends only on a hash of its id, so the
  split is the same on every machine and every run.
  """
  @spec split([posting]) :: %{train: [posting], valid: [posting], test: [posting]}
  def split(postings) do
    postings
    |> Enum.group_by(& &1.fraud)
    |> Enum.reduce(%{train: [], valid: [], test: []}, fn {_label, group}, acc ->
      sorted = Enum.sort_by(group, &:erlang.phash2({"lure", &1.id}))
      n = length(sorted)
      {train, rest} = Enum.split(sorted, round(n * 0.70))
      {valid, test} = Enum.split(rest, round(n * 0.15))
      %{train: acc.train ++ train, valid: acc.valid ++ valid, test: acc.test ++ test}
    end)
  end
end
