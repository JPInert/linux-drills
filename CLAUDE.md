# linux-drills: contributor rules

Scenario contract: `scenarios/SPEC.md`. These rules apply to anyone (human or AI agent) changing the repo.

- **A container named `drill` (or your `DRILL_NS`) may be someone's live drill.** Never `./drill.sh clean` on
  a machine where a drill is running, never remove a box you did not start, never run `check`/`hint` in it.
  Test in your own boxes: `DRILL_NS=dbg-<x> ./drill.sh up <scenario>`, then remove only your own (and only
  the lab your own box created: `. lab/lab.sh; lab_down_owner dbg-<x>`).
- **Never edit `drill.sh` in place while a drill is running from it.** Write `drill.sh.new`, `bash -n` it,
  then `mv` it over. bash reads a running script by byte offset; the running copy executes garbage when it
  resumes. The running instance keeps the old inode, so `mv` is safe.
- **After any edit to a scenario or `image/`: `./drill.sh selftest <names>`** (the whole set for `image/`).
  Selftest does not read hints/solution text: run every command in that text as `tech` in a debug box.
  Commands that need root (grep on a root-only conf, `journalctl -u`, `lsof +L1`) must say `sudo`.
- **Commands a learner reads are the plainest that work**, narrowed with `| grep`, every flag explained on a
  `=>` line (SPEC "Commands a human types"). No filter expressions like `ss 'sport = :8080'`, no
  `ps -o` format strings, no Go templates.
- **solution.md keeps the SPEC line shapes and 80 columns**: the in-box `solution` command colours and pages
  by line shape; a changed shape renders as plain text. `awk 'length>80' solution.md` must print nothing.
- **Everything the box prints must survive copy + paste**: no `$ ` before a command, side notes as
  `# comments`, a command inside a card border repeated below the card.
- **A pty test through `drill.sh run` writes to the drill log** (`~/.local/share/linux-drills/drills.tsv`):
  set `DRILL_HOME` to a scratch dir for tests.
- **Scenario dirs are bind-mounted into a live box** (`/drill`): editing the files of a running drill changes
  its check/hint mid-run. Stage elsewhere and swap the whole dir by rename.
- **A network drill's far end runs in the sidecar `<NS>-lab`, never on the box** (SPEC `lab-box.sh` /
  `lab-side.sh`). Anything planted on the box gets chased as if it were the fault. check.sh tests the far end
  over the network only.
- **Cheat sheet**: build the PDF with `print/render.mjs`, not `chrome --print-to-pdf` (Chrome silently
  shrinks an overflowing page to fit; render.mjs prints at scale 1 and reports overflow).
- **Feedback on a run comes from the path log** (`./drill.sh review`, `~/.local/share/linux-drills/runs/`),
  not from memory of what happened.
