# ai-shell

Quick AI answers from Claude at the shell prompt — without opening an interactive session — plus the ability to **follow up** when one answer isn't enough.

![ai-shell demo](demo/demo.gif)

## Usage

### What's that command?

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

### Give me that command in the clipboard
`howtoc` puts the command on your clipboard, ready to paste.

```
$ howtoc "tarball this directory excluding .git"
tar --exclude='./.git' -czf "../${PWD##*/}.tar.gz" .

$ howtoc "count lines in all .ts files recursively"
find . -name "*.ts" -type f -print0 | xargs -0 wc -l
```

### One-shot answers with followups
`af` continues the most recent conversation — no re-explaining context:

```
$ ask "what does set -u do? one line"
Treats unset variables as an error and exits instead of silently substituting empty string.

$ ask when will AGI occur in one line
Nobody knows — expert forecasts cluster loosely around 2030–2060, with wide error bars and no agreed definition of "AGI," so treat any specific date as marketing rather than prediction.

$ ask what is the meaning of life, the universe and everything
42

$ af "are you sure?"
Deep Thought spent 7.5 million years on it, so yes. The catch is nobody knows the question. 
```

When a quick question turns into a real discussion, drop into the full interactive CLI **with the conversation intact**:

```
$ af
# opens `claude` resumed on that same conversation
```

### Picking the model

`ask-model` lists every model and effort level on offer, starring the ones in
use:

```
$ ask-model
models:
    fable
  * opus
    sonnet
    haiku
efforts:
    low
    medium
  * high
    xhigh
    max
    default
```

`ask-set-model` changes them for the current shell. The effort level is
optional and independent of the model:

```
$ ask-set-model sonnet
model: sonnet   effort: high

$ ask-set-model opus high
model: opus   effort: high

$ ask-set-model opus default    # hand the effort choice back to claude
model: opus   effort: (claude default)
```

`ask-set-model` lasts only for the shell you run it in. To change every new
terminal, use `ask-set-model-default` — it saves the choice to
`~/.ai-shell/defaults` and applies it to the current shell too:

```
$ ask-set-model-default sonnet high
model: sonnet   effort: high
saved as the default for new shells in /Users/you/.ai-shell/defaults
```

It takes the same arguments as `ask-set-model`: omitting the effort keeps
whatever was already saved, and `default` drops it so `claude` chooses.

Precedence is environment first, then the saved default, then `opus`: a shell
that exports its own `ASK_MODEL` / `ASK_EFFORT` (from your `.zshrc`, or from an
`ask-set-model` in the parent shell) keeps that, and `ask-set-model-default`
won't override it.

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
| `wtf <question>` | `ask` with "what " already typed: `wtf is a symlink` |
| `howto <task>` | The command line for a task, plus one explanation line |
| `howtoc <task>` | The command line **only**, echoed and copied to your clipboard |
| `af <question>` | **Follow up** on the last answer, whichever command produced it |
| `af` (no args) | Open the last conversation in the full interactive `claude` CLI |
| `askt <name> <question>` | Ask in a named, long-lived thread (created on first use) |
| `askt` (no args) | List named threads, most recently used first |
| `ask-model` | List the models and effort levels available, marking the ones in use |
| `ask-set-model <model> [effort]` | Set the model, and optionally the effort level, for this shell |
| `ask-set-model-default <model> [effort]` | Save the model/effort as the default for every new shell |
| `ask-version` | Show the installed version, and the newest release available |
| `ask-update` | Update the checkout to the newest release |
| `ask-help` | Show this command list |

Every one-shot quietly keeps its conversation, so a terse answer can always be expanded, questioned, or taken interactive — nothing is lost by asking tersely first.

## Requirements

- **zsh or bash**
- the **`claude` CLI** installed and logged in ([install instructions](https://code.claude.com/docs/en/quickstart))
- **git** (the install is a clone; `ask-update` uses it)
- macOS or Linux. Conversation ids come from `uuidgen`, or from
  `/proc/sys/kernel/random/uuid` where there's no `uuidgen` — so on Linux
  nothing extra is needed
- for `howtoc`'s clipboard: `pbcopy` (macOS) or `wl-copy`/`xclip`/`xsel` (Linux)

`install.sh --check` reports on all of this without touching a thing, so you can
run it any time to see what's missing.

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
~/.ai-shell/install.sh --check  # only report on prerequisites; change nothing
```

Where `$SHELL` says nothing useful — a container, `env -i`, cron — the installer
falls back to whichever of zsh/bash is actually installed, and asks for a flag
only when both are.

It installs no software of its own: anything missing (the `claude` CLI, git, a
clipboard tool) is reported afterwards with the command that fixes it.

### Debian / Ubuntu

A stock image has none of the prerequisites, not even git. Start with them:

```sh
sudo apt-get update
sudo apt-get install -y git curl ca-certificates
curl -fsSL https://claude.ai/install.sh | bash    # installs ~/.local/bin/claude
claude                                            # log in
```

That installer doesn't put `~/.local/bin` on your `PATH`, and Debian and Ubuntu
don't either, so add it above the ai-shell block in your rc file:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Then clone and install as above. Optional extras: `xclip` (or `wl-clipboard`)
for `howtoc`'s clipboard, `zsh` if you'd rather use it than bash.

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

**ai-shell is read-only — it never mutates anything.** One-shots do get a shell so they can *look* (`ask list the current folder` actually lists it), but it runs under claude's `plan` permission mode, which mechanically denies any mutating command — this is enforced, not just prompted. Anything state-changing you ask for is printed for you to run yourself. The functions also pass `--safe-mode`, so none of your local Claude Code customizations (CLAUDE.md, hooks, MCP servers) load — answers are fast and cheap. `af` with no arguments opens a normal interactive session with your full setup, including its normal ability to act.

## Testing

```sh
test/lint.sh                      # syntax under sh/bash/zsh; every command defined
test/docker-install.sh            # full install in debian:stable-slim + ubuntu:24.04
test/docker-install.sh debian:12  # or any image you name
```

`docker-install.sh` starts from a stock image — no git, no curl, no `claude`, no
`$SHELL` — and checks that the installer copes and says what's missing, then
installs the prerequisites the way the README does and checks the result comes
out clean under both bash and zsh. `AI_SHELL_TEST_OFFLINE=1` stops after the
first phase, which needs no network. The one thing it can't cover is an actual
answer from `claude`: that needs a logged-in account.

Both run in CI on every push (`.github/workflows/ci.yml`).

## Releasing

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which runs the same
lint and container installs, then publishes a GitHub release with auto-generated
notes.

```sh
git tag v0.1.0
git push origin v0.1.0
```

A tag that fails the checks never becomes a release.

## Contributing

Issues and pull requests are welcome — fork the repo, branch, and open a PR against `main`. Direct pushes to `main` are restricted to the maintainer.

## License

[MIT](LICENSE)
