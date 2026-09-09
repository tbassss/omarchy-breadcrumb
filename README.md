# Breadcrumb

A save point for your work — an Omarchy plugin for activity-based checkpoints, written by you or your agent.

**Not a published release.** This tree is first-candidate *preparation* for
[issue #8](https://github.com/tbassss/omarchy-breadcrumb/issues/8). It is not
live-installed, not directory-listed, and not verified by owner dogfood.
Passing Python tests and isolated offscreen component tests are not live
desktop acceptance.

License: MIT. Copyright (c) 2026 tbassss. See [LICENSE](LICENSE).

## Experience

- Named activities with a current status, next step, optional context and links.
- Persistent checkpoints, recoverable drafts, and per-activity history.
- Manual updates and an agent-independent local command interface.
- Local storage; no cloud account, embedded AI, or activity surveillance.

## Data location

Checkpoints and drafts live **outside** the plugin folder:

| Path | Contents |
|---|---|
| `${XDG_DATA_HOME:-$HOME/.local/share}/breadcrumb/breadcrumb.sqlite` | Activities, checkpoints, drafts, prefs |
| `BREADCRUMB_DATA_DIR` | Optional override used by tests |

Removing the plugin is intended to leave this directory in place. Do not
commit that database, real checkpoints, or personal screenshots.

## Install / remove (owner approval required)

Do **not** run these on a live desktop until the owner approves the
[live test plan](docs/LIVE_TEST_PLAN.md). The plugin is a `bar-widget`
(`tbassss.breadcrumb`). Official host commands on Omarchy 4.0.3:

```bash
omarchy plugin validate ./path-to-breadcrumb
# After approval:
omarchy plugin add <git-url>            # clones into ~/.config/omarchy/plugins/<id>/; disabled unless --enable
omarchy plugin enable tbassss.breadcrumb --section right
# Optional, only if the bar widget does not appear after enable:
# omarchy-restart-shell
omarchy plugin disable tbassss.breadcrumb
omarchy plugin remove tbassss.breadcrumb --yes
```

`omarchy plugin add` requires a git URL and lands the plugin **disabled**
unless `--enable`. A private GitHub clone will fail without credentials
(`GIT_TERMINAL_PROMPT=0`). Public listing is a separate approval.

After a live install, the public command is:

```bash
python3 ~/.config/omarchy/plugins/tbassss.breadcrumb/bin/breadcrumb list
python3 ~/.config/omarchy/plugins/tbassss.breadcrumb/bin/breadcrumb read    < payload.json
python3 ~/.config/omarchy/plugins/tbassss.breadcrumb/bin/breadcrumb publish < payload.json
```

See [docs/COMMAND.md](docs/COMMAND.md). Agents must not use `bin/breadcrumb-store`.

## Local checks

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py
git diff --check
```

Isolated native Compact/Expanded polish, keyboard, geometry, and fictional
screenshots are a component test on the-cave (`tests/native/`). KeyboardPanel
and host Panel are stubbed there. See [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md)
and [docs/RELEASE_PREP.md](docs/RELEASE_PREP.md).

## Project records

- [Approved product spec](docs/PRODUCT_SPEC.md)
- [Public command](docs/COMMAND.md)
- [Issue #7 implementation notes](docs/IMPLEMENTATION.md)
- [Release-candidate preparation](docs/RELEASE_PREP.md)
- [Live install/rollback plan](docs/LIVE_TEST_PLAN.md) (gated)
- [Fictional screenshots](docs/screenshots/README.md)
- [Contributing](CONTRIBUTING.md)
- [Agent instructions](AGENTS.md)

## Privacy and remaining gates

Keep real checkpoints, credentials, and personal screenshots out of this
repository, including while private. Public visibility, GitHub release
publication, and plugins.omarchy.org listing submission are **not** authorized
by issue #8. Independent frozen-candidate review and owner usability feedback
are still required.
