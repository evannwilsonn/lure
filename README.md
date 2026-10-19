# Lure

Paste a job ad and Lure says whether it reads like an employment scam. It underlines the words that pushed the score up or down and points out red flags worth checking, such as being asked to pay for training or to move the interview to a chat app. It's written in Elixir: the model is trained in Elixir with Nx, served by Phoenix LiveView, and ships as one container.

[![pipeline](https://github.com/evannwilsonn/lure/actions/workflows/pipeline.yml/badge.svg)](https://github.com/evannwilsonn/lure/actions/workflows/pipeline.yml)

**Live demo:** on Google Cloud Run, deployed from `main` by the pipeline (see [Deployment](#7-deployment)).

Project 13a of my AI project roadmap, the capstone, built three times in a language I hadn't used before. The other two are [Recall](https://github.com/evannwilsonn/recall) and [Squiggle](https://github.com/evannwilsonn/squiggle).

## 1. Problem

Fake job ads are a common way to steal money and identities: the "job" needs a fee for a starter kit, or a bank login for "direct deposit", or a quick interview over a chat app. The goal is a checker someone can paste an ad into before replying, which gives a score, a verdict, and its reasons. Scams are rare, so success is measured by average precision (how well scams rank above real ads) and by precision and recall at the threshold the app uses, not by accuracy.

## 2. Data

[EMSCAD](http://emscad.samos.aegean.gr/) (Employment Scam Aegean Dataset; University of the Aegean, CC0) has 17,880 job ads from a real job board, 866 of them marked as fraud by the board's staff. The copy used is [`victor/real-or-fake-fake-jobposting-prediction`](https://huggingface.co/datasets/victor/real-or-fake-fake-jobposting-prediction) on Hugging Face.

- The model sees only text a reader could paste: title, company profile, description, requirements and benefits.
- The board reposted ads, so ads are deduplicated on their normalised text: 15,872 unique ads, 713 scams (4.5%).
- They're split 70 / 15 / 15 (11,110 train, 2,381 validation, 2,381 test). The split is stratified, so each part keeps the same share of scams, and set by a hash of each ad's id, so it never changes.
- EMSCAD replaced every link, email address and phone number with a hashed token (`#URL_9f2c…#`). Ads people paste have real ones. Lure maps both to the same three tokens, `<link>`, `<email>` and `<phone>`, so the model learns "there's a link here" and can use it on real ads.

Every choice below was made on the validation ads; the test ads were scored once.

## 3. Baseline

- **Always say real:** average precision 0.023, which is just the share of scams.
- **Red-flag patterns alone:** nine hand-written patterns for things the FTC and job boards warn about (pay-to-work fees, chat-app interviews, free email domains, handling money, big earnings, asking for bank or ID details, "no experience needed", typing from home, guaranteed income). Average precision 0.028.

The patterns barely beat guessing on this data, and the reason is useful. EMSCAD's scams are mostly 2012–2014 ads for admin, customer service and oil and gas jobs. They don't read like today's text-message scams, and the dataset hides the contact details where many of today's red flags appear. So the patterns stay in the app as a checklist for the reader, but the verdict comes from the model.

## 4. Model

```
ad text ─► tokens + word pairs ─► TF-IDF (30,000 features) ─► logistic regression ─► score ─► verdict
        │                                                         └─ per-word weights ─► underlines
        └─► red-flag patterns ─► checklist
```

Two models were trained and compared, plus their average:

- **TF-IDF + logistic regression, written from scratch.** The text becomes lower-case words and adjacent word pairs. Numbers collapse to one shape (`$5,000` and `$7,500` are the same token), and contacts become `<link>` / `<email>` / `<phone>`. Terms in at least 3 ads are kept, up to 30,000, weighted by `(1 + log tf) · idf` and scaled to unit length. Logistic regression trains with full-batch Adam on the sparse matrix in EXLA, using `Nx.indexed_add` and `Nx.take`, with scams weighted up by the class ratio and light L2. Each word's weight times its TF-IDF value is how much it moved the score, which is what the app underlines.
- **MiniLM + a small network.** Bumblebee runs `sentence-transformers/all-MiniLM-L6-v2` in Elixir to turn each ad (its first 256 word pieces) into 384 numbers. An Axon network (384 → 64 ReLU → dropout 0.2 → 1) is trained on those with class-weighted cross-entropy.
- **Average:** the mean of the two scores.

The model with the best validation average precision ships, and its threshold is the one with the best validation F1. The verdict is "looks like a scam" at or above the threshold, "worth a closer look" from half the threshold, and "looks normal" below that.

## 5. Evaluation

On the 2,381 test ads (107 scams):

| Model | Avg. precision | Precision | Recall | F1 |
|---|---|---|---|---|
| Always say real | 0.023 | 0.045 | 1.000 | 0.086 |
| Red-flag patterns | 0.028 | 0.098 | 0.093 | 0.096 |
| **TF-IDF + logistic regression (shipped)** | **0.889** | **0.927** | 0.710 | **0.804** |
| MiniLM + network | 0.766 | 0.737 | 0.682 | 0.709 |
| Average of the two | 0.862 | 0.804 | **0.766** | 0.785 |

At its threshold, the shipped model catches 76 of the 107 scams and wrongly flags 6 of the 2,274 real ads. The average of the two models catches 6 more scams but flags 20 real ads, so it loses on validation average precision and doesn't ship. The words that lean most toward scam on the board's data are below; the app shows the same list.

`link <link>` · `below link` · `data entry` · `$0` · `apply using` · `administrative` · `earn` · `customer service` · `administrative assistant` · `oil and gas`

## 6. Improvement

- **Contacts as tokens.** At first, the hashed `#URL_…#` placeholders became random one-off tokens, and a real `https://…` link split into pieces the model had never seen. Mapping both to `<link>` keeps the signal the model learned ("apply using the link below") working on ads people paste. Test scores stayed the same (AP 0.889 before and after), and the model now behaves the same on real and masked ads.
- **Sparse training in EXLA.** The first logistic regression was plain Elixir with per-example SGD and took minutes per pass. Rewritten as full-batch Adam over a COO sparse matrix in one compiled EXLA function, 400 steps take under two minutes on two CPU cores.
- **Weighted loss.** Axon 0.8's built-in weighted loss expects integer labels, so the network's class-weighted cross-entropy is written out by hand.

## 7. Deployment

```
push to main ─► check: format, compile --warnings-as-errors, mix test
              └► image: docker build ─► smoke test on :7860 (page + framing header) ─► ghcr.io/evannwilsonn/lure
                                                                                     └► Google Cloud Run
```

- **Container:** a Phoenix release on Debian slim, running as uid 1000 on port 7860, the port the pipeline's smoke test and Cloud Run use. MiniLM's weights are downloaded at build time and the app runs with `BUMBLEBEE_OFFLINE=true`. With no `SECRET_KEY_BASE` set it makes a random one per boot; there are no accounts or sessions to lose.
- **Cloud Run:** the pipeline's last job copies this commit's tested image from GHCR to Google's registry and deploys it to Cloud Run in us-east1, with 2 GB of memory and up to 2 instances. It scales to zero when nobody's using it. It logs in to Google through workload identity, so no key is stored anywhere; the one-time setup is `cloudrun-setup.sh` in [Conveyor](https://github.com/evannwilsonn/conveyor), and the job runs once the repo has the variables it prints. Hugging Face Spaces was the first plan, but Docker Spaces now need a paid account.
- **Framing:** the app may be embedded by itself and by huggingface.co (`frame-ancestors`), and sends no `X-Frame-Options`. The smoke test checks both.
- **Pipeline board:** the run shows up on [Conveyor](https://evannwilsonn.github.io/conveyor/) with the other projects.

## Reproducing the numbers

```sh
mix deps.get
mix lure.train        # downloads EMSCAD, trains, writes priv/model/ and results/eval.json
mix test
mix phx.server        # http://localhost:4000
```

On two CPU cores the first `mix lure.train` takes about half an hour, most of it MiniLM embedding the ads. The embeddings are cached in `priv/data/`, so later runs take about six minutes.

## Layout

```
lib/lure/            data, tokens, tfidf, logistic, embedder, head, metrics, flags, detector
lib/mix/tasks/       lure.train
lib/lure_web/live/   check_live.ex: the page
priv/model/          lure.etf (the shipped model), eval.json, samples.json
results/eval.json    the evaluation this README quotes
```

## Limits

- The training ads are ten years old and from one board. New scam styles (crypto "tasks", text-message recruiters) look different, and the score will miss some of them. The red-flag checklist is there for that.
- A score is a reason to look closer, not proof. If an ad asks for money or your bank details, stop, and report it at [reportfraud.ftc.gov](https://reportfraud.ftc.gov).
- Ads are checked in memory and not stored.
