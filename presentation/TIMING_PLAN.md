# Presentation plan — HW/SW Co-design (00460882)

**Presenters:** Taha Taha and Lana Bakre
**Required:** 20–25 min talk + 5–10 min questions (Project.pdf §9)
**Target:** 22:00 — the middle of the window, leaving slack for a slow start

The brief says the best structure is to *"follow the flow of your project work,
from initial analysis to optimization and hardware proposal"*, and that the goal
is to **teach a fellow ECE student who did not do the project**. So each
benchmark is presented as one complete arc — analysis → optimization → hardware —
rather than splitting the deck into an "all software" half and an "all hardware"
half.

## Who presents what, and why this split

Each presenter owns one **complete benchmark arc**. That way neither person is
reciting the other's analysis, and each can answer questions on their whole
chain of reasoning — which matters, because the Q&A is 5–10 minutes.

| | Taha | Lana |
|---|---|---|
| Owns | opening, method, **pyflate** end to end | **raytrace** end to end, synthesis, close |
| Paradigm | dataflow accelerator | systolic array |
| Time | 11:00 | 10:00 |

Shared close: 1:00.

## Slide-by-slide budget

| # | Slide | Speaker | Time | Cumulative |
|---|---|---|---|---|
| 1 | Title | Taha | 0:20 | 0:20 |
| 2 | The task, and why these two benchmarks | Taha | 1:20 | 1:40 |
| 3 | How we measured — three views | Taha | 1:10 | 2:50 |
| 4 | Two traps in the suggested perf command | Taha | 1:10 | 4:00 |
| 5 | pyflate — what the benchmark does | Taha | 0:50 | 4:50 |
| 6 | pyflate — the profile | Taha | 1:10 | 6:00 |
| 7 | pyflate — the surprise: 2.3, not 250 | Taha | 1:30 | 7:30 |
| 8 | pyflate — what we changed | Taha | 1:10 | 8:40 |
| 9 | pyflate — results, and why | Taha | 1:20 | 10:00 |
| 10 | pyflate — the dataflow accelerator | Taha | 1:20 | 11:20 |
| 11 | raytrace — what the benchmark does | Lana | 0:50 | 12:10 |
| 12 | raytrace — the profile | Lana | 1:10 | 13:20 |
| 13 | raytrace — one line, 49% | Lana | 1:20 | 14:40 |
| 14 | raytrace — what we changed, and what each was worth | Lana | 1:20 | 16:00 |
| 15 | raytrace — results, and a trap | Lana | 1:20 | 17:20 |
| 16 | raytrace — the systolic array | Lana | 1:20 | 18:40 |
| 17 | The square root: a real area/performance knob | Lana | 1:00 | 19:40 |
| 18 | Verification — and the bug it caught | Lana | 1:00 | 20:40 |
| 19 | Two benchmarks, two paradigms | both | 0:40 | 21:20 |
| 20 | What we did not finish | Taha | 0:25 | 21:45 |
| 21 | Summary — requirement met | Lana | 0:15 | 22:00 |

Backup slides B1–B6 are **not** presented; they exist to answer questions.

## Pacing checkpoints

Glance at the clock at these three points. If you are behind, the listed slides
are the ones to compress — they carry detail that the backup slides repeat.

| Checkpoint | Should be at | If late, compress |
|---|---|---|
| End of slide 4 | 4:00 | slide 4 (traps) — say one trap, not two |
| Handover, slide 10 → 11 | 11:20 | slide 8 (list O1–O5 faster) |
| End of slide 17 | 19:40 | slide 17 (state the trade, skip the ulp numbers) |

## Before you walk in

- [ ] `ssh ece882-031@naranja7.cslcs.technion.ac.il` already open in a terminal,
      sitting in `/csl/ece882-031/hwsw-project`
- [ ] `./tools/regress.sh` run once, so the nine PASS lines are on screen
- [ ] `python3 tools/verify.py` ready to run live — it is the correctness claim
- [ ] Both flame-graph SVGs open in browser tabs (baseline and optimized)
- [ ] The brief requires working code available to demonstrate — this is that

## Live demo, if asked

Fast enough to run in front of the room (19 seconds):

```bash
for v in baseline optimized; do taskset -c 9 python3 benchmarks/pyflate/pyflate_$v.py -o /tmp/d_$v.json -p3 -w1 -n3 -l0; done && python3 -m pyperf compare_to /tmp/d_baseline.json /tmp/d_optimized.json --table
```
