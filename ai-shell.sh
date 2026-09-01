# ai-shell — quick Claude answers at the shell prompt, with follow-ups.
# https://github.com/bataras/ai-shell
#
# Source this file from .zshrc or .bashrc (install.sh does it for you).
# Requires the `claude` CLI (https://claude.com/claude-code), logged in.
#
# Config (set before sourcing, or export any time):
#   ASK_MODEL  model for one-shot answers (default: opus)
#   ASK_DIR    state directory for conversation threads (default: ~/.ai-shell)

: "${ASK_DIR:=$HOME/.ai-shell}"
: "${ASK_MODEL:=opus}"

# Bake the user's platform into the prompts so answers match their shell/OS.
_ai_os=$(uname -sm 2>/dev/null || echo "unknown OS")
if [ -n "${ZSH_VERSION:-}" ]; then _ai_shell=zsh; else _ai_shell=bash; fi

# Absolute path of the directory holding this file, so ask-version/ask-update
# can talk to the checkout we were sourced from. zsh's ${(%):-%x} is a parse
# error under bash, so it has to go through eval rather than a plain branch.
if [ -n "${ZSH_VERSION:-}" ]; then
  eval '_ai_self=${(%):-%x}'
else
  _ai_self=${BASH_SOURCE[0]:-$0}
fi
_ai_root=$(CDPATH= cd -- "$(dirname -- "$_ai_self")" 2>/dev/null && pwd) || _ai_root=
unset _ai_self

ASK_SYS_CHAT="Terse, direct answers for an expert engineer at a shell prompt ($_ai_os, $_ai_shell). No preamble, no markdown fences, no restating the question. Commands on their own line. A few sentences at most unless asked to expand."
ASK_SYS_CMD="Output shell command lines only, for $_ai_os / $_ai_shell. Print the single best command line for the task, then one short explanation line. No markdown fences, no preamble."
ASK_SYS_CMDONLY="Print ONLY the command line, for $_ai_os / $_ai_shell. One line. No explanation, no markdown, no backticks."

_ai_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    printf 'ai-shell: no uuid source (need uuidgen or /proc)\n' >&2
    return 1
  fi
}

_ai_copy() {
  if command -v pbcopy >/dev/null 2>&1; then pbcopy
  elif command -v wl-copy >/dev/null 2>&1; then wl-copy
  elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard
  elif command -v xsel >/dev/null 2>&1; then xsel -ib
  else
    cat >/dev/null
    printf 'ai-shell: no clipboard tool found (pbcopy/wl-copy/xclip/xsel)\n' >&2
  fi
}

# _ask_send <thread-file|-> <system-prompt> <usage-name> <prompt...>
# "-" = anonymous thread (fresh conversation). Either way the conversation
# becomes "current", so `af` can follow up on it.
_ask_send() {
  local f=$1 sys=$2 name=$3; shift 3
  if [ -z "$*" ]; then
    printf 'usage: %s <question>\n' "$name" >&2
    return 2
  fi
  command -v claude >/dev/null 2>&1 || {
    printf 'ai-shell: `claude` CLI not found — install Claude Code first\n' >&2
    return 127
  }
  mkdir -p "$ASK_DIR/threads"
  local sid out
  local -a sess
  if [ "$f" != - ] && [ -s "$f" ]; then
    sid=$(<"$f") || return
    sess=(--resume "$sid")
  else
    sid=$(_ai_uuid) || return
    sess=(--session-id "$sid")
  fi
  out=$(claude -p --safe-mode --model "$ASK_MODEL" --tools "" \
        --system-prompt "$sys" "${sess[@]}" "$*") || return
  [ "$f" != - ] && printf '%s\n' "$sid" >| "$f"
  printf '%s\n' "$sid" >| "$ASK_DIR/current"
  printf '%s\n' "$out"
}

# ask <question> — terse general answer; starts a fresh conversation.
ask() { _ask_send - "$ASK_SYS_CHAT" ask "$*"; }

# howto <task> — the command line for a task, plus one explanation line.
howto() { _ask_send - "$ASK_SYS_CMD" howto "$*"; }

# howtoc <task> — the command line only, echoed and copied to the clipboard.
howtoc() {
  local out
  out=$(_ask_send - "$ASK_SYS_CMDONLY" howtoc "Raw command only, no backticks: $*") || return
  printf '%s\n' "$out"
  printf '%s' "$out" | _ai_copy
}

# af [question] — follow up on the last answer (from ask/howto/howtoc/askt).
# With no arguments, opens that conversation in the full interactive claude CLI.
af() {
  local sid out
  [ -s "$ASK_DIR/current" ] || {
    printf 'af: nothing to follow up on yet\n' >&2
    return 1
  }
  sid=$(<"$ASK_DIR/current") || return
  if [ $# -eq 0 ]; then
    claude --resume "$sid"
    return
  fi
  out=$(claude -p --safe-mode --model "$ASK_MODEL" --tools "" \
        --system-prompt "$ASK_SYS_CHAT" --resume "$sid" "$*") || return
  printf '%s\n' "$out"
}

# askt [name] [question] — named, long-lived threads.
#   askt                 list threads (most recent first)
#   askt rust <question> ask in thread "rust" (created on first use)
askt() {
  if [ $# -eq 0 ]; then
    ls -t "$ASK_DIR/threads" 2>/dev/null
    return
  fi
  local name=$1; shift
  case $name in
    */*|.*) printf 'askt: bad thread name: %s\n' "$name" >&2; return 2 ;;
  esac
  _ask_send "$ASK_DIR/threads/$name" "$ASK_SYS_CHAT" "askt $name" "$*"
}

# ask-help — the command list, straight from the README's table so it can't drift.
ask-help() {
  local readme=${_ai_root:+$_ai_root/README.md}
  if [ -z "$readme" ] || [ ! -r "$readme" ]; then
    printf 'ask-help: README.md not found in %s\n' "${_ai_root:-<unknown>}" >&2
    return 1
  fi
  awk -F'|' '
    /^\|/ {
      if (++n <= 2) next                 # header and separator rows
      cmd=$2; desc=$3
      gsub(/`|\*\*/, "", cmd); gsub(/`|\*\*/, "", desc)
      gsub(/^ +| +$/, "", cmd); gsub(/^ +| +$/, "", desc)
      printf "  %-26s %s\n", cmd, desc
      next
    }
    n { exit }                           # first table only
  ' "$readme"
}

# --- version & updates -------------------------------------------------------
# Versions are git tags; the checkout is the source of truth, so there's no
# version constant here to drift out of sync with the tags.

# _ai_git <args...> — run git against the checkout this file came from.
_ai_git() {
  [ -n "$_ai_root" ] || return 1
  git -C "$_ai_root" "$@" 2>/dev/null
}

_ai_have_clone() {
  _ai_git rev-parse --git-dir >/dev/null 2>&1
}

# Installed version: the exact tag when we're on one, otherwise a
# tag-plus-distance like v0.1.0-3-gabc1234, or a bare sha before any tag.
_ai_version_installed() {
  _ai_git describe --tags --always --dirty
}

# Newest release tag on the remote. git sorts by version itself, so this
# doesn't depend on `sort -V` (which BSD/macOS sort lacks).
_ai_version_latest() {
  _ai_git ls-remote --tags --refs --sort=-v:refname origin \
    | head -1 | sed 's|.*refs/tags/||'
}

# ask-version — installed version, plus the newest release if the network answers.
ask-version() {
  local cur latest
  if ! _ai_have_clone; then
    printf 'ask-version: %s is not a git checkout\n' "${_ai_root:-<unknown>}" >&2
    return 1
  fi
  cur=$(_ai_version_installed)
  latest=$(_ai_version_latest)
  if [ -z "$latest" ] || [ "$cur" = "$latest" ]; then
    printf 'ai-shell %s\n' "$cur"
  else
    printf 'ai-shell %s  (latest: %s)\n' "$cur" "$latest"
  fi
}

# ask-update — check for a newer release and check it out.
ask-update() {
  local cur latest
  if ! _ai_have_clone; then
    printf 'ask-update: %s is not a git clone; update it however you installed it\n' \
      "${_ai_root:-<unknown>}" >&2
    return 1
  fi
  # Tracked modifications only: untracked files are yours and harmless here.
  if [ -n "$(_ai_git status --porcelain -uno)" ]; then
    printf 'ask-update: %s has local changes; commit, stash, or discard them first\n' "$_ai_root" >&2
    return 1
  fi
  _ai_git fetch --tags --quiet origin || {
    printf 'ask-update: fetch failed\n' >&2
    return 1
  }
  latest=$(_ai_version_latest)
  if [ -z "$latest" ]; then
    printf 'ask-update: no releases published yet\n' >&2
    return 1
  fi
  cur=$(_ai_version_installed)
  if [ "$cur" = "$latest" ]; then
    printf 'ai-shell %s is already the latest\n' "$cur"
    return 0
  fi
  printf 'updating %s -> %s\n' "$cur" "$latest"
  _ai_git checkout --quiet "$latest" || {
    printf 'ask-update: checkout of %s failed\n' "$latest" >&2
    return 1
  }
  printf '  %s\n' "$_ai_root"
  . "$_ai_root/ai-shell.sh"
  printf 'reloaded here; run `exec %s` in other shells.\n' "$_ai_shell"
}
