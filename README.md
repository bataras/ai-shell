# ai-shell

Quick AI answers at the shell prompt — without opening an interactive session — plus the ability to **follow up** when one answer isn't enough.

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

Every one-shot quietly keeps its conversation, so a terse answer can always be expanded, questioned, or taken interactive — nothing is lost by asking tersely first.

## Requirements

- **zsh or bash**
- the **`claude` CLI** installed and logged in ([install instructions](https://code.claude.com/docs/en/quickstart))
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

Re-running is safe (the block is replaced, not duplicated). Then open a new shell, or:

```sh
. ~/.ai-shell/ai-shell.sh
```

> **bash on macOS:** login shells read `~/.bash_profile`, not `~/.bashrc`. If your `~/.bash_profile` doesn't already source `~/.bashrc`, add: `[ -f ~/.bashrc ] && . ~/.bashrc`

## Usage

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

`howtoc` also puts the command on your clipboard, ready to paste.

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

## Configuration

Environment variables, settable per-invocation or exported:

| Variable | Default | Meaning |
|---|---|---|
| `ASK_MODEL` | `opus` | Model for answers (e.g. `sonnet` for faster/cheaper) |
| `ASK_DIR` | `~/.ask` | Where conversation-thread state lives |

```sh
ASK_MODEL=sonnet ask "quick one: default ssh port?"
```

The functions call `claude` with `--safe-mode` and `--tools ""`: no tools run, and none of your local Claude Code customizations (CLAUDE.md, hooks, MCP servers) load — answers are fast, cheap, and side-effect-free. `af` with no arguments opens a normal interactive session with your full setup.

## Uninstall

```sh
~/.ai-shell/uninstall.sh          # removes the rc-file block(s)
~/.ai-shell/uninstall.sh --purge  # also deletes the ~/.ask state directory
rm -rf ~/.ai-shell                # remove the clone itself
```

## Contributing

Issues and pull requests are welcome — fork the repo, branch, and open a PR against `main`. Direct pushes to `main` are restricted to the maintainer.

## License

[MIT](LICENSE)
