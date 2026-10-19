defmodule Lure.Flags do
  @moduledoc """
  Red flags that consumer-protection guidance (the FTC's job-scam advice, among others) tells
  people to look for, written as patterns so the app can point at the exact words. They explain
  the score rather than make it: the model decides, the flags show what a reader should check.
  """

  @flags [
    {:pay_to_work, "Asks you to pay",
     "Real employers don't charge for training, starter kits, equipment or background checks.",
     ~r/\b(pay|paying|fee|fees|deposit|purchase|buy|invest)\b[^.\n]{0,50}\b(training|kit|equipment|starter|registration|background check|certification|materials|software)\b/iu},
    {:off_platform, "Moves the conversation off the job board",
     "Interviews held over chat apps are a common way to avoid scrutiny.",
     ~r/\b(whatsapp|telegram|signal app|hangouts|google chat|wickr|kik|text (me|us) at|interview (via|over|on) (chat|text|skype|hangouts))\b/iu},
    {:free_email, "Contact through a free email account",
     "Established companies hire from their own domain, not Gmail or Yahoo.",
     ~r/\b[\w.+-]+@(gmail|yahoo|hotmail|outlook|aol|icloud|ymail|live|mail|protonmail)\.(com|net)\b/iu},
    {:money_handling, "Handles money or packages for the company",
     "Receiving and forwarding payments or parcels is how scams launder money and goods.",
     ~r/\b(reship\w*|package (forwarding|handler|inspector)|receive (and|&) (forward|reship|ship)|process(ing)? payments?|payment processor|money transfers?|wire transfers?|cash(ing)? checks?|check deposits?|mystery shopper|financial agent)\b/iu},
    {:big_earnings, "Promises big, quick earnings",
     "Pay quoted per day or week, or \"unlimited\", is how scams make an offer feel urgent.",
     ~r/(\b(earn|make|income of|paid)\b[^.\n]{0,30}[$€£]\s?\d[\d,]*(\.\d+)?\s*(\+\s*)?(per|a|an|\/|each)\s*(day|week|hour)|\bunlimited (earning|income)|\bearn (up to )?[$€£]\s?\d[\d,]{3,})/iu},
    {:sensitive_info, "Asks for financial or identity details",
     "Bank, card or Social Security details belong in onboarding paperwork after an offer, never in an application.",
     ~r/\b(bank account (details|number|info)|routing number|social security( number)?|\bssn\b|credit card (details|number)|copy of (your )?(id|passport|driver'?s licen[sc]e))\b/iu},
    {:no_bar, "No experience, starts now",
     "Hiring anyone, immediately, with no interview is the opposite of how real hiring works.",
     ~r/\b(no experience (is )?(needed|required|necessary)|immediate(ly)? (start|hire|hiring)|start (today|immediately|tomorrow)|urgent(ly)? (hiring|needed)|hired on the spot|no interview)\b/iu},
    {:home_typing, "Data entry or typing from home",
     "Simple at-home typing jobs with high pay are among the most common scam ads.",
     ~r/\b(data entry|typing|form filling|copy paste|ad posting)\b[^.\n]{0,40}\b(from home|at home|online|remote|anywhere)\b/iu},
    {:guarantee, "Guarantees income or the job",
     "No real employer guarantees pay or a position before you've applied.",
     ~r/\bguarantee(d)?\b[^.\n]{0,20}\b(income|job|position|pay|placement|earnings|hire)\b/iu}
  ]

  def all,
    do: Enum.map(@flags, fn {key, title, why, _re} -> %{key: key, title: title, why: why} end)

  @doc "Flags found in the text, each with the spans (byte offset, length) that triggered it."
  def find(text) do
    for {key, title, why, re} <- @flags,
        spans = Regex.scan(re, text, return: :index) |> Enum.map(&hd/1),
        spans != [] do
      %{key: key, title: title, why: why, spans: spans}
    end
  end
end
