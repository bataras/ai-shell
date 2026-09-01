#!/bin/sh
# Uninstall ai-shell: removes the marker-guarded block from your rc files.
# Usage: ./uninstall.sh [--purge]   (--purge also deletes the ~/.ask state dir)
set -eu

begin="# >>> ai-shell >>>"
end="# <<< ai-shell <<<"

for rc in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if grep -Fqx "$begin" "$rc"; then
    awk -v b="$begin" -v e="$end" '
      $0==b {skip=1; next}
      $0==e {skip=0; next}
      !skip
    ' "$rc" > "$rc.ai-shell.tmp" && mv "$rc.ai-shell.tmp" "$rc"
    echo "removed ai-shell block from $rc"
  fi
done

if [ "${1:-}" = --purge ]; then
  rm -rf "${ASK_DIR:-$HOME/.ask}"
  echo "removed ${ASK_DIR:-$HOME/.ask}"
fi

echo "Done. Open a new shell (already-loaded functions persist until then)."
