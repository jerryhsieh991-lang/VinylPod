# Deferred Items — Phase 00

Out-of-scope discoveries logged during execution (not fixed; see executor scope boundary).

## From 00-01 execution (2026-07-03)

1. **iCloud-duplicated junk git ref files break `git log --all`.**
   `.git/refs/heads/claude/` contains iCloud conflict-copies named with a trailing ` 2`
   (`security-crash-fixes 2`, `great-montalcini-5d1355 2`). `git branch -a` lists broken
   `+`-prefixed entries and any command touching `--all` dies with
   `fatal: bad object refs/heads/claude/great-montalcini-5d1355 2`.
   Root cause: the repo lives on the iCloud-synced Desktop (same root cause as the
   `.build` xattr breakage fixed in 00-01). Cleanup = delete the ` 2` ref files after
   verifying they are byte-duplicates of the real refs — needs a deliberate, careful pass
   (touching `.git` internals mid-phase was judged out of scope). Longer term: migrate the
   working repo off iCloud (the `~/Projects/VinylPodMac` clone already exists).

2. **make_app.sh does not abort on build failure.**
   Line `swift build -c "$CONFIG" 2>&1 | grep -Ev ... | tail -3` — the pipeline's exit
   status is `tail`'s, so `set -e` never sees a failed build; the script continues to the
   `--show-bin-path` step and can bundle a stale binary. Pre-existing (also noted in
   project memory). Fix candidate: `set -o pipefail` at top of script.
