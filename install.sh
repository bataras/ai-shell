#!/bin/sh
# Install ai-shell: adds a marker-guarded source line to your shell rc file(s).
# Usage: ./install.sh [--zsh] [--bash] [--all] [--check]
#   (no flags)  install for your login shell ($SHELL); when $SHELL says nothing
#               useful — a container, `env -i`, cron — fall back to whichever
#               of zsh/bash is actually installed
#   --check     only report on prerequisites; touch no rc file
#
# This script installs no software. What ai-shell leans on (the claude CLI,
# git, a clipboard tool) belongs to your package manager, so anything missing
# is reported with the command that fixes it.
set -eu

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
begin="# >>> ai-shell >>>"
end="# <<< ai-shell <<<"

zsh_rc="${ZDOTDIR:-$HOME}/.zshrc"
bash_rc="$HOME/.bashrc"

usage() { echo "usage: $0 [--zsh] [--bash] [--all] [--check]" >&2; }

# --- install -----------------------------------------------------------------

strip_block() { # remove any existing ai-shell block from $1
  [ -f "$1" ] || return 0
  awk -v b="$begin" -v e="$end" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip
  ' "$1" > "$1.ai-shell.tmp" && mv "$1.ai-shell.tmp" "$1"
}

install_to() {
  rc=$1
  strip_block "$rc"
  {
    printf '%s\n' "$begin"
    printf '[ -f "%s/ai-shell.sh" ] && . "%s/ai-shell.sh"\n' "$dir" "$dir"
    printf '%s\n' "$end"
  } >> "$rc"
  echo "installed: $rc sources $dir/ai-shell.sh"
}

# --- prerequisite reporting --------------------------------------------------
# Warnings are collected as they're found and printed after the install lines,
# so the last thing on screen is what still needs doing.

warned=false
warn() { warned=true; printf '\n! %s\n' "$1" >&2; }
hint() { printf '    %s\n' "$1" >&2; }

apt_pkgs=
need_apt() { apt_pkgs="${apt_pkgs:+$apt_pkgs }$1"; }

is_debian() {
  [ -r /etc/os-release ] || return 1
  grep -Eq '^(ID|ID_LIKE)=.*(debian|ubuntu)' /etc/os-release
}

have_clipboard() {
  for c in pbcopy wl-copy xclip xsel; do
    command -v "$c" >/dev/null 2>&1 && return 0
  done
  return 1
}

# bash reads ~/.bash_profile (then ~/.bash_login, then ~/.profile) for login
# shells and ~/.bashrc for interactive non-login ones. If the first profile
# file that exists doesn't pull in ~/.bashrc, login shells — macOS Terminal,
# `ssh host`, `su -` — never see ai-shell. Debian and Ubuntu ship a ~/.profile
# that does source it, so this usually stays quiet.
check_bash_profile() {
  for p in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    [ -f "$p" ] || continue
    grep -q bashrc "$p" && return 0
    warn "$p doesn't source ~/.bashrc, so bash login shells won't load ai-shell."
    hint "add to $p:  [ -f ~/.bashrc ] && . ~/.bashrc"
    return 0
  done
  return 0
}

check_deps() {
  if ! command -v claude >/dev/null 2>&1; then
    if [ -x "$HOME/.local/bin/claude" ]; then
      warn "claude is installed at ~/.local/bin/claude, but ~/.local/bin isn't on your PATH."
      hint 'add to your rc file:  export PATH="$HOME/.local/bin:$PATH"'
    else
      warn "the claude CLI isn't installed — every ai-shell command is a front end for it."
      hint 'install:  curl -fsSL https://claude.ai/install.sh | bash'
      hint 'then log in by running:  claude'
      command -v curl >/dev/null 2>&1 || need_apt 'curl ca-certificates'
    fi
  fi

  if ! command -v git >/dev/null 2>&1; then
    warn "git isn't installed — ask-version and ask-update need it."
    need_apt git
  fi

  # A conversation id comes from uuidgen, or from the kernel on Linux.
  if ! command -v uuidgen >/dev/null 2>&1 && [ ! -r /proc/sys/kernel/random/uuid ]; then
    warn "no uuid source — ai-shell needs uuidgen or /proc/sys/kernel/random/uuid."
    need_apt uuid-runtime
  fi

  # Optional: only howtoc's copy step needs it, and a headless box has no use
  # for a clipboard, so this one stays out of the apt line below.
  if ! have_clipboard; then
    warn "no clipboard tool — howtoc will print the command without copying it."
    hint 'install one of: pbcopy (macOS), wl-copy, xclip, xsel'
  fi

  if [ -n "$apt_pkgs" ] && is_debian; then
    if [ "$(id -u)" = 0 ]; then sudo=; else sudo='sudo '; fi
    printf '\n  Debian/Ubuntu:  %sapt-get update && %sapt-get install -y %s\n' \
      "$sudo" "$sudo" "$apt_pkgs" >&2
  fi
}

# --- argument handling -------------------------------------------------------

do_zsh=false do_bash=false check_only=false
for arg in "$@"; do
  case $arg in
    --zsh)   do_zsh=true ;;
    --bash)  do_bash=true ;;
    --all)   do_zsh=true; do_bash=true ;;
    --check) check_only=true ;;
    *) usage; exit 2 ;;
  esac
done

if $check_only; then
  check_deps
  $warned || echo "prerequisites: all present"
  exit 0
fi

if ! $do_zsh && ! $do_bash; then
  case "${SHELL:-}" in
    */zsh)  do_zsh=true ;;
    */bash) do_bash=true ;;
    *)
      # $SHELL is unset or names neither shell. Fall back to what's installed,
      # and only ask when both are, since only then is there a real choice.
      have_zsh=false have_bash=false
      command -v zsh  >/dev/null 2>&1 && have_zsh=true
      command -v bash >/dev/null 2>&1 && have_bash=true
      if $have_zsh && $have_bash; then
        echo "Couldn't tell which shell to install for (\$SHELL is ${SHELL:-unset}); pass --zsh, --bash, or --all" >&2
        exit 2
      elif $have_zsh; then
        do_zsh=true
      elif $have_bash; then
        do_bash=true
      else
        echo "Neither zsh nor bash is installed; ai-shell needs one of them" >&2
        exit 2
      fi
      ;;
  esac
fi

if $do_zsh;  then install_to "$zsh_rc"; fi
if $do_bash; then install_to "$bash_rc"; check_bash_profile; fi

echo "Open a new shell, or run:  . $dir/ai-shell.sh"
check_deps
