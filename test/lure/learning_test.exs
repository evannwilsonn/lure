defmodule Lure.LearningTest do
  use ExUnit.Case, async: true

  alias Lure.{Data, Flags, Logistic, Metrics, Tfidf, Tokens}

  describe "tokens" do
    test "words keep their place in the text, and numbers collapse into one shape" do
      text = "Earn $5,000 weekly. Earn $7,500!"
      words = Tokens.words(text)
      assert Enum.map(words, &elem(&1, 0)) == ["earn", "$0,0", "weekly", "earn", "$0,0"]
      for {_w, s, l} <- words, do: assert(binary_part(text, s, l) =~ ~r/\S/)
    end

    test "links, emails and phone numbers read the same masked or real" do
      masked = "Apply at #URL_9f2c0a# or #EMAIL_ab12# or call #PHONE_77ee#"
      real = "Apply at https://jobs.example.com/x or hr@example.com or call (555) 123-4567"
      shown = "Apply at [link removed] or [email removed] or call [phone removed]"
      expected = ["apply", "at", "<link>", "or", "<email>", "or", "call", "<phone>"]

      for text <- [masked, real, shown],
          do: assert(Enum.map(Tokens.words(text), &elem(&1, 0)) == expected)
    end

    test "bigrams cover both words" do
      assert {"data entry", 0, 10} in Tokens.grams("data entry clerk")
    end
  end

  describe "red flags" do
    test "finds a payment request and points at it" do
      text = "You must pay a $50 fee for your starter kit before training."
      [flag] = text |> Flags.find() |> Enum.filter(&(&1.key == :pay_to_work))
      [{s, l}] = flag.spans
      assert binary_part(text, s, l) =~ "pay"
    end

    test "chat-app interviews, free email contacts and quick earnings" do
      keys =
        "Interview via Telegram. Email recruiter.jobs@gmail.com. Earn $900 per week!"
        |> Flags.find()
        |> Enum.map(& &1.key)

      assert :off_platform in keys
      assert :free_email in keys
      assert :big_earnings in keys
    end

    test "an ordinary ad trips nothing" do
      assert Flags.find(
               "We are hiring a senior accountant to join our finance team in Austin. Apply through our careers page."
             ) == []
    end
  end

  describe "metrics" do
    test "precision, recall and F1 at a threshold" do
      m = Metrics.at([0.9, 0.8, 0.2, 0.1], [true, false, true, false], 0.5)
      assert {m.tp, m.fp, m.fn, m.tn} == {1, 1, 1, 1}
      assert m.precision == 0.5 and m.recall == 0.5 and m.f1 == 0.5
    end

    test "average precision is 1 for a perfect ranking and lower otherwise" do
      assert Metrics.average_precision([0.9, 0.8, 0.1], [true, true, false]) == 1.0
      assert Metrics.average_precision([0.9, 0.8, 0.1], [false, true, true]) < 0.6
    end
  end

  describe "TF-IDF and logistic regression" do
    test "vectors are unit length, and the model separates two kinds of ad" do
      scams = for i <- 1..30, do: "earn money from home fast wire transfer opportunity #{i}"
      reals = for i <- 1..30, do: "senior engineer role on our platform team with benefits #{i}"
      tfidf = Tfidf.fit(scams ++ reals, min_df: 2)

      v = Tfidf.transform(tfidf, hd(scams))
      norm = v |> Map.values() |> Enum.map(&(&1 * &1)) |> Enum.sum()
      assert_in_delta norm, 1.0, 1.0e-9

      examples =
        Enum.map(scams, &{Tfidf.transform(tfidf, &1), true}) ++
          Enum.map(reals, &{Tfidf.transform(tfidf, &1), false})

      model = Logistic.train(examples, dims: map_size(tfidf.vocab), steps: 150)
      assert Logistic.probability(model, Tfidf.transform(tfidf, "earn money from home")) > 0.8

      assert Logistic.probability(
               model,
               Tfidf.transform(tfidf, "senior engineer on our platform team")
             ) < 0.2
    end
  end

  describe "data split" do
    test "is deterministic and keeps the share of scams in each part" do
      postings =
        for i <- 1..400, do: %{id: "#{i}", text: "ad #{i}", title: "", fraud: rem(i, 20) == 0}

      a = Data.split(postings)
      assert a == Data.split(Enum.reverse(postings))
      assert length(a.train) == 280

      for part <- [a.train, a.valid, a.test],
          do: assert_in_delta(Enum.count(part, & &1.fraud) / length(part), 0.05, 0.01)
    end
  end
end
