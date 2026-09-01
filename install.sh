#!/bin/sh
# Install ai-shell: adds a marker-guarded source line to your shell rc file(s).
# Usage: ./install.sh [--zsh] [--bash] [--all]
# With no flags, installs for your login shell ($SHELL).
set -eu

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
begin="# >>> ai-shell >>>"
end="# <<< ai-shell <<<"

zsh_rc="${ZDOTDIR:-$HOME}/.zshrc"
bash_rc="$HOME/.bashrc"

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

do_zsh=false do_bash=false
if [ $# -eq 0 ]; then
  case "${SHELL:-}" in
    */zsh)  do_zsh=true ;;
    */bash) do_bash=true ;;
    *) echo "Couldn't detect zsh or bash from \$SHELL; pass --zsh, --bash, or --all" >&2; exit 2 ;;
  esac
fi
for arg in "$@"; do
  case $arg in
    --zsh)  do_zsh=true ;;
    --bash) do_bash=true ;;
    --all)  do_zsh=true do_bash=true ;;
    *) echo "usage: $0 [--zsh] [--bash] [--all]" >&2; exit 2 ;;
  esac
done

$do_zsh  && install_to "$zsh_rc"
$do_bash && install_to "$bash_rc"

echo "Open a new shell, or run:  . $dir/ai-shell.sh"
