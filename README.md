# ai-shell

Quick AI answers from Claude at the shell prompt — without opening an interactive session — plus the ability to **follow up** when one answer isn't enough.

## Usage

The core loop — a terse answer, then a follow-up that keeps the context:

```
$ howto rule the world
say "I now rule the world" && printf 'World status: RULED\n'
Announces your dominion via macOS text-to-speech, then prints confirmation — harmless fun, since actual world domination isn't a shell command.

$ howto fetch main while on this branch
git fetch origin main:main
Fast-forwards your local main from origin without checking it out (fails harmlessly if it would be a non-fast-forward).

$ af what does main:main mean
It's a refspec: `<source>:<destination>`. Source is `main` on the remote (`refs/heads/main` on origin), destination is your local `main` (`refs/heads/main`).

So it says: fetch origin's main and write it directly into your local main ref, instead of only updating `origin/main`. Git refuses if the update isn't a fast-forward (unless you prefix with `+`, e.g. `+main:main`), and it refuses outright if `main` is the currently checked-out branch.
```

### One-shot answers

```
$ ask "what does set -u do? one line"
Treats unset variables as an error and exits instead of silently substituting empty string.

$ howto "count lines in all .ts files recursively"
find . -name "*.ts" -type f -print0 | xargs -0 wc -l
Recursively finds all .ts files and counts their lines, with a total at the end.

$ howtoc "tarball this directory excluding .git"
tar --exclude='./.git' -czf "../${PWD##*/}.tar.gz" .
```

### One-shot answers in the clipboard
`howtoc` puts the command on your clipboard, ready to paste.

```
$ howtoc "tarball this directory excluding .git"
tar --exclude='./.git' -czf "../${PWD##*/}.tar.gz" .
```

### Following up

`af` continues the most recent conversation — no re-explaining context:

```
$ howto "count lines in all .ts files recursively"
find . -name "*.ts" -type f -print0 | xargs -0 wc -l
...

$ af "exclude node_modules"
find . -path "*/node_modules" -prune -o -type f -name "*.ts" -print0 | xargs -0 wc -l
```

When a quick question turns into a real discussion, drop into the full interactive CLI **with the conversation intact**:

```
$ af
# opens `claude` resumed on that same conversation
```

### Named threads

For topics you return to across days, give the thread a name:

```
$ askt rust "difference between Box<dyn Trait> and impl Trait?"
...

$ askt rust "when would I prefer the Box version?"
...

$ askt          # list your threads
rust
```

`af` follows up on whatever ran last, including an `askt` thread.

Small shell functions (zsh and bash) on top of the [Claude Code](https://claude.com/claude-code) CLI:

| Command | What it does |
|---|---|
| `ask <question>` | Terse general answer; starts a fresh conversation |
| `howto <task>` | The command line for a task, plus one explanation line |
| `howtoc <task>` | The command line **only**, echoed and copied to your clipboard |
| `af <question>` | **Follow up** on the last answer, whichever command produced it |
| `af` (no args) | Open the last conversation in the full interactive `claude` CLI |
| `askt <name> <question>` | Ask in a named, long-lived thread (created on first use) |
| `askt` (no args) | List named threads, most recently used first |
| `ask-version` | Show the installed version, and the newest release available |
| `ask-update` | Update the checkout to the newest release |
| `ask-help` | Show this command list |

Every one-shot quietly keeps its conversation, so a terse answer can always be expanded, questioned, or taken interactive — nothing is lost by asking tersely first.

## Requirements

- **zsh or bash**
- the **`claude` CLI** installed and logged in ([install instructions](https://code.claude.com/docs/en/quickstart))
- **git** (the install is a clone; `ask-update` uses it)
- macOS or Linux; `uuidgen` (preinstalled on macOS, `util-linux` on Linux)
- for `howtoc`'s clipboard: `pbcopy` (macOS) or `wl-copy`/`xclip`/`xsel` (Linux)

## Install

```sh
git clone https://github.com/bataras/ai-shell.git ~/.ai-shell
~/.ai-shell/install.sh
```

The installer appends a marker-guarded block to your rc file that sources `ai-shell.sh`. With no flags it targets your login shell (`$SHELL`); or choose explicitly:

```sh
~/.ai-shell/install.sh --zsh    # ~/.zshrc (respects $ZDOTDIR)
~/.ai-shell/install.sh --bash   # ~/.bashrc
~/.ai-shell/install.sh --all    # both
```

`~/.ai-shell` holds everything — the code and your conversation state (the state
files are gitignored, so updates stay clean).

Re-running is safe (the block is replaced, not duplicated). Then open a new shell, or:

```sh
. ~/.ai-shell/ai-shell.sh
```

> **bash on macOS:** login shells read `~/.bash_profile`, not `~/.bashrc`. If your `~/.bash_profile` doesn't already source `~/.bashrc`, add: `[ -f ~/.bashrc ] && . ~/.bashrc`

## Uninstall

```sh
~/.ai-shell/uninstall.sh          # removes the rc-file block(s)
~/.ai-shell/uninstall.sh --purge  # also deletes the ~/.ai-shell state directory
rm -rf ~/.ai-shell                # remove everything: clone and state
```

## Updating

Versions are git tags, so the checkout is the source of truth — there's no version
string in the source to drift out of sync.

```
$ ask-version
ai-shell v0.1.0  (latest: v0.2.0)

$ ask-update
updating v0.1.0 -> v0.2.0
  ~/.ai-shell
reloaded here; run `exec zsh` in other shells.
```

`ask-update` leaves the checkout on the release tag (a detached HEAD — expected).
It refuses to run if the install isn't a git clone, or if you have uncommitted
changes to tracked files; untracked files of your own are left alone. Nothing
checks for updates automatically — no startup network call, no nag.

## Configuration

Environment variables, settable per-invocation or exported:

| Variable | Default | Meaning |
|---|---|---|
| `ASK_MODEL` | `opus` | Model for answers (e.g. `sonnet` for faster/cheaper) |
| `ASK_DIR` | `~/.ai-shell` | Where conversation-thread state lives |

```sh
ASK_MODEL=sonnet ask "quick one: default ssh port?"
```

The functions call `claude` with `--safe-mode` and `--tools ""`: no tools run, and none of your local Claude Code customizations (CLAUDE.md, hooks, MCP servers) load — answers are fast, cheap, and side-effect-free. `af` with no arguments opens a normal interactive session with your full setup.

## Releasing

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which syntax-checks
the scripts under bash, zsh, and sh, confirms every command is defined in both
shells, and then publishes a GitHub release with auto-generated notes.

```sh
git tag v0.1.0
git push origin v0.1.0
```

A tag that fails the checks never becomes a release.

## Contributing

Issues and pull requests are welcome — fork the repo, branch, and open a PR against `main`. Direct pushes to `main` are restricted to the maintainer.

## License

[MIT](LICENSE)
