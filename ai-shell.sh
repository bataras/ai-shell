# ai-shell — quick Claude answers at the shell prompt, with follow-ups.
# https://github.com/bataras/ai-shell
#
# Source this file from .zshrc or .bashrc (install.sh does it for you).
# Requires the `claude` CLI (https://claude.com/claude-code), logged in.
#
# Config (set before sourcing, or export any time). These beat anything saved
# by ask-set-model-default, so a shell that states its own model keeps it:
#   ASK_MODEL  model for one-shot answers (default: opus)
#   ASK_EFFORT effort level, low|medium|high|xhigh|max (default: claude's own)
#   ASK_DIR    state directory for threads and saved defaults (default: ~/.ai-shell)

: "${ASK_DIR:=$HOME/.ai-shell}"

# _ai_read_defaults — load what ask-set-model-default saved into
# _ai_def_model / _ai_def_effort, empty when there's nothing saved. Parsed
# rather than sourced, so a mangled file can't run anything.
_ai_read_defaults() {
  _ai_def_model= _ai_def_effort=
  [ -r "$ASK_DIR/defaults" ] || return 0
  local k v
  while read -r k v; do
    case $k in
      model)  _ai_def_model=$v ;;
      effort) _ai_def_effort=$v ;;
    esac
  done < "$ASK_DIR/defaults"
  return 0
}

_ai_read_defaults
: "${ASK_MODEL:=$_ai_def_model}"
: "${ASK_EFFORT:=$_ai_def_effort}"
: "${ASK_MODEL:=opus}"

# What ask-set-model accepts. The models are `claude --model` aliases, each of
# which tracks the newest release in its family; the efforts are the full set
# `claude --effort` takes. ASK_EFFORT is deliberately left unset by default so
# claude applies its own.
ASK_MODELS="fable opus sonnet haiku"
ASK_EFFORTS="low medium high xhigh max"

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

# One-shots get a sandboxed Bash tool (claude's auto permission mode blocks
# dangerous actions but does allow workspace writes), so these prompt rules
# are what separate the read-only commands from askw in practice.
#
# Catastrophe refusal, shared by every one-shot.
ASK_SYS_REFUSE="If the requested command would be catastrophically destructive (delete the root directory, wipe a disk, fork bomb, and the like), do not print or run it; answer exactly: fuck you. I won't do that."
# ask/af/askt: shell allowed, strictly read-only.
ASK_SYS_RO="You may run shell commands when they help answer, but keep them strictly read-only: inspect, never modify the filesystem or system state. If the user asks to change state (create, write, delete, move, install, kill), print the command for them to run instead of running it. $ASK_SYS_REFUSE"
# askw: writes allowed, with a sanity guard.
ASK_SYS_RW="You may run shell commands, including ones that create, modify, or delete files, when that is what the user asks for. Sanity guard: stay inside the current directory tree, make the smallest change that satisfies the request, never touch more than the request clearly names, and say what you did. $ASK_SYS_REFUSE"

_ai_sys_style="Terse, direct answers for an expert engineer at a shell prompt ($_ai_os, $_ai_shell). No preamble, no markdown fences, no restating the question. Commands on their own line. A few sentences at most unless asked to expand."
ASK_SYS_CHAT="$_ai_sys_style $ASK_SYS_RO"
ASK_SYS_CHATW="$_ai_sys_style $ASK_SYS_RW"
unset _ai_sys_style
# howto/howtoc print commands rather than act, so they carry only the refusal.
ASK_SYS_CMD="Output shell command lines only, for $_ai_os / $_ai_shell. Print the single best command line for the task, then one short explanation line. No markdown fences, no preamble. $ASK_SYS_REFUSE"
ASK_SYS_CMDONLY="Print ONLY the command line, for $_ai_os / $_ai_shell. One line. No explanation, no markdown, no backticks. $ASK_SYS_REFUSE"

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

# _ai_flags — fill the global array _ai_flags_out with the flags every one-shot
# passes to claude. --effort is included only when ASK_EFFORT is set, since
# claude has no "default" level to name.
_ai_flags() {
  _ai_flags_out=(-p --safe-mode --model "$ASK_MODEL" --tools "Bash" --permission-mode auto)
  [ -n "${ASK_EFFORT:-}" ] && _ai_flags_out+=(--effort "$ASK_EFFORT")
  return 0
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
  _ai_flags
  out=$(claude "${_ai_flags_out[@]}" \
        --system-prompt "$sys" "${sess[@]}" "$*") || return
  [ "$f" != - ] && printf '%s\n' "$sid" >| "$f"
  printf '%s\n' "$sid" >| "$ASK_DIR/current"
  printf '%s\n' "$out"
}

# ask <question> — terse general answer; starts a fresh conversation.
# Read-only: it can look at the filesystem but never changes it.
ask() { _ask_send - "$ASK_SYS_CHAT" ask "$*"; }

# askw <question> — like ask, but allowed to act on the filesystem
# (create/modify/delete what the request names), with a sanity guard.
askw() { _ask_send - "$ASK_SYS_CHATW" askw "$*"; }

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
  _ai_flags
  out=$(claude "${_ai_flags_out[@]}" \
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

# _ai_list <values> <current> — one space-separated value per line, with the
# current one marked. Split via tr rather than a `for` loop: zsh doesn't
# word-split unquoted expansions, so the loop form isn't portable.
_ai_list() {
  local cur=$2 v
  printf '%s\n' "$1" | tr ' ' '\n' | while read -r v; do
    [ -n "$v" ] || continue
    if [ "$v" = "$cur" ]; then printf '  * %s\n' "$v"; else printf '    %s\n' "$v"; fi
  done
}

# _ai_show_model — the one-line summary the setters echo back.
_ai_show_model() {
  printf 'model: %s   effort: %s\n' "$ASK_MODEL" "${ASK_EFFORT:-(claude default)}"
}

# ask-model — every model and effort level ask-set-model accepts, with the
# ones in use starred.
ask-model() {
  printf 'models:\n'
  _ai_list "$ASK_MODELS" "$ASK_MODEL"
  printf 'efforts:\n'
  _ai_list "$ASK_EFFORTS default" "${ASK_EFFORT:-default}"
}

# _ai_check_args <command-name> <model> [effort] — shared argument checking
# for the two setters.
_ai_check_args() {
  local name=$1; shift
  if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    printf 'usage: %s <%s> [%s|default]\n' "$name" \
      "${ASK_MODELS// /|}" "${ASK_EFFORTS// /|}" >&2
    return 2
  fi
  case " $ASK_MODELS " in
    *" $1 "*) ;;
    *) printf '%s: bad model: %s (%s)\n' "$name" "$1" "${ASK_MODELS// /|}" >&2
       return 2 ;;
  esac
  if [ $# -eq 2 ] && [ "$2" != default ]; then
    case " $ASK_EFFORTS " in
      *" $2 "*) ;;
      *) printf '%s: bad effort: %s (%s)\n' "$name" "$2" "${ASK_EFFORTS// /|}" >&2
         return 2 ;;
    esac
  fi
}

# ask-set-model <model> [effort] — set the model, and optionally the effort
# level, for this shell and anything it starts. An effort of "default" hands
# the choice back to claude. Nothing is written to disk; use
# ask-set-model-default for that.
ask-set-model() {
  _ai_check_args ask-set-model "$@" || return
  export ASK_MODEL=$1
  case ${2:-} in
    '') ;;
    default) unset ASK_EFFORT ;;
    *) export ASK_EFFORT=$2 ;;
  esac
  _ai_show_model
}

# ask-set-model-default <model> [effort] — save the model, and optionally the
# effort level, as what every new shell starts with; also applies here. An
# omitted effort keeps whatever was already saved, and "default" drops it so
# claude chooses. A shell that exports its own ASK_MODEL/ASK_EFFORT is
# unaffected — the environment wins over the saved file.
ask-set-model-default() {
  _ai_check_args ask-set-model-default "$@" || return
  # Base the effort on the saved file, not this shell, so an ad-hoc
  # ask-set-model earlier in the session doesn't leak into the default.
  _ai_read_defaults
  local effort=$_ai_def_effort
  case ${2:-} in
    '') ;;
    default) effort= ;;
    *) effort=$2 ;;
  esac
  mkdir -p "$ASK_DIR" || return
  {
    printf 'model %s\n' "$1"
    [ -n "$effort" ] && printf 'effort %s\n' "$effort"
    :
  } >| "$ASK_DIR/defaults" || return
  export ASK_MODEL=$1
  if [ -n "$effort" ]; then export ASK_EFFORT=$effort; else unset ASK_EFFORT; fi
  _ai_show_model
  printf 'saved as the default for new shells in %s\n' "$ASK_DIR/defaults"
}

# ask-help — the command list, straight from the README's table so it can't drift.
ask-help() {
  local readme=${_ai_root:+$_ai_root/README.md}
  if [ -z "$readme" ] || [ ! -r "$readme" ]; then
    printf 'ask-help: README.md not found in %s\n' "${_ai_root:-<unknown>}" >&2
    return 1
  fi
  # Rows are buffered so the command column can be sized to the widest one,
  # rather than a constant that a longer command silently overflows.
  awk -F'|' '
    function clean(x) { gsub(/`|\*\*/, "", x); gsub(/^ +| +$/, "", x); return x }
    /^\|/ {
      if (++n <= 2) next                 # header and separator rows
      cmd[++m]=clean($2); desc[m]=clean($3)
      if (length(cmd[m]) > w) w=length(cmd[m])
      next
    }
    n { exit }                           # first table only
    END { for (i=1; i<=m; i++) printf "  %-*s  %s\n", w, cmd[i], desc[i] }
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
