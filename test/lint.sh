#!/bin/sh
# Static checks: every file parses under the shells that will read it, and
# every documented command actually gets defined. Run by CI and by hand.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

fns='ask howto howtoc af askt ask-model ask-set-model ask-set-model-default ask-version ask-update ask-help'
status=0
say() { printf '%s\n' "$1"; }

# ai-shell.sh is sourced by bash/zsh only; the scripts are /bin/sh.
bash -n ai-shell.sh || status=1
for f in install.sh uninstall.sh test/*.sh; do
  sh -n "$f" || status=1
done
say "syntax ok (bash, sh)"

bash -c '. ./ai-shell.sh; for f in '"$fns"'; do
  typeset -f "$f" >/dev/null || { echo "bash: missing $f" >&2; exit 1; }
done' || status=1
say "bash defines every command"

if command -v zsh >/dev/null 2>&1; then
  zsh -n ai-shell.sh || status=1
  zsh -c '. ./ai-shell.sh; for f in '"$fns"'; do
    typeset -f "$f" >/dev/null || { echo "zsh: missing $f" >&2; exit 1; }
  done' || status=1
  say "zsh defines every command"
else
  say "zsh not installed — skipping its checks"
fi

exit "$status"
