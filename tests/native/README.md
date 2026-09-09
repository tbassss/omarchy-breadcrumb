# Isolated native harness (issue #3)

Component test: real `Panel.qml` + `/usr/bin/qs` + Qt offscreen. Not full omarchy-shell host integration. Not a live install.

## What it asserts

1. UI-driven create + save of a fictional checkpoint.
2. Same-instance close/open keeps the published `current.*`.
3. A genuine in-memory draft (`dirty=true` with different editor text) survives `refresh()` / open — get must not broadly reset dirty.
4. Destroy + recreate the Panel (Loader `active=false` then `true`). Published `current.*` reloads **and** editor fields hydrate (`editSummary === current.summary`, dirty is false).

Step 4 is native evidence. A Python source-contract pass is not a substitute.

## Run on the-cave only

Isolated `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`, unique `XDG_RUNTIME_DIR`. No Wayland, no live plugin enable, no `shell.json` mutation, no shell restart.

```bash
ARCHIVE=/path/to/candidate.tar \
CANDIDATE_SHA=<git sha> \
EVIDENCE_DIR=/tmp/breadcrumb-evidence-XXXX \
HARNESS_SRC=/path/to/tests/native/harness \
  ./tests/native/run-isolated.sh
```

`ARCHIVE` is a `git archive` of the candidate plugin tree. The script copies it into disposable `/tmp/breadcrumb-native-*`.

Results and Qt API notes: [`docs/IMPLEMENTATION.md`](../../docs/IMPLEMENTATION.md).
