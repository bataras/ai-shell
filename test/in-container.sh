#!/bin/sh
# Install-and-use checks, run INSIDE a virgin Debian/Ubuntu container by
# test/docker-install.sh. The checkout is mounted read-only at /src.
#
# Two phases:
#   offline — the image exactly as it ships: no git, no curl, no claude, and
#             no $SHELL. install.sh has to cope and say what's missing.
#   online  — the prerequisites the README asks for, installed the documented
#             way, ending with `install.sh --check` reporting a clean box.
# Set AI_SHELL_TEST_OFFLINE=1 to stop after the first phase (no network use).
#
# What isn't tested: an actual answer from claude — that needs a logged-in
# account, which a throwaway container doesn't have.
set -u

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

# t <description> <shell snippet> — snippet's exit status decides.
t() { d=$1; shift; if eval "$*" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

# has <description> <file> <text> — file contains text.
has() { if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else bad "$1"; fi; }

section() { printf '\n--- %s\n' "$1"; }

marker='# >>> ai-shell >>>'
fns='ask howto howtoc af askt ask-model ask-set-model ask-set-model-default ask-version ask-update ask-help'

# Everything runs as root in a container, with HOME=/root.
export HOME=/root
out=/tmp/out err=/tmp/err

# run <cmd...> — capture stdout/stderr to $out/$err, return the exit status.
run() { "$@" >"$out" 2>"$err"; }

printf '=== %s ===\n' "$(grep -m1 PRETTY_NAME /etc/os-release | cut -d'"' -f2)"

# --- phase 1: the image as it ships ------------------------------------------

section 'virgin image: nothing installed, $SHELL unset'

t 'image has no $SHELL'   '! env | grep -q "^SHELL="'
t 'image has no git'      '! command -v git'
t 'image has no curl'     '! command -v curl'
t 'image has no claude'   '! command -v claude'
t 'image has no uuidgen'  '! command -v uuidgen'
t 'kernel uuid readable'  '[ -r /proc/sys/kernel/random/uuid ]'

# No git yet, so this stands in for the documented clone.
cp -r /src /root/ai-shell && chmod -R u+w /root/ai-shell

run /root/ai-shell/install.sh
st=$?
[ $st -eq 0 ] && ok 'install.sh succeeds with no flags and no $SHELL' \
              || bad "install.sh exited $st with no flags and no \$SHELL"
has 'install.sh reports the rc file it wrote'  "$out" 'installed: /root/.bashrc'
has 'preflight flags the missing claude CLI'   "$err" "claude CLI isn't installed"
has 'preflight flags missing git'              "$err" "git isn't installed"
has 'preflight gives an apt-get line'          "$err" 'apt-get install -y'
has 'apt-get line covers curl'                 "$err" 'curl ca-certificates'
has 'rc file got the ai-shell block'           /root/.bashrc "$marker"

run /root/ai-shell/install.sh --bash
t 'reinstall leaves exactly one block' '[ "$(grep -cF "$marker" /root/.bashrc)" = 1 ]'

section 'the shell functions, without claude present'

t 'an interactive bash loads ai-shell' \
  '[ "$(bash -i -c "type -t ask" 2>/dev/null)" = function ]'
t 'every command is defined' \
  'bash -c ". /root/ai-shell/ai-shell.sh; for f in '"$fns"'; do typeset -f \$f >/dev/null || exit 1; done"'
t 'ask-help lists every command' \
  '[ "$(bash -c ". /root/ai-shell/ai-shell.sh; ask-help" | wc -l)" -eq 13 ]'
t 'ask-model stars the default model' \
  'bash -c ". /root/ai-shell/ai-shell.sh; ask-model" | grep -q "^  \* opus"'
t 'ask-set-model switches model and effort' \
  'bash -c ". /root/ai-shell/ai-shell.sh; ask-set-model sonnet high" | grep -q "model: sonnet   effort: high"'
t 'ask-set-model rejects an unknown model' \
  '! bash -c ". /root/ai-shell/ai-shell.sh; ask-set-model gpt" 2>/dev/null'

bash -c '. /root/ai-shell/ai-shell.sh; ask hi' >"$out" 2>"$err"
[ $? -eq 127 ] && ok 'ask exits 127 without the claude CLI' \
               || bad 'ask should exit 127 without the claude CLI'
has 'ask says how to install claude' "$err" 'curl -fsSL https://claude.ai/install.sh'

# Not a git clone here (it was copied), which these two must survive.
t 'ask-version explains a non-clone' \
  'bash -c ". /root/ai-shell/ai-shell.sh; ask-version" 2>&1 | grep -q "not a git checkout"'
t 'ask-update refuses a non-clone' \
  '! bash -c ". /root/ai-shell/ai-shell.sh; ask-update"'

section 'uninstall'

run /root/ai-shell/uninstall.sh
t 'uninstall removes the block'   '! grep -qF "$marker" /root/.bashrc'
t 'uninstall keeps the rc file'   '[ -s /root/.bashrc ]'

if [ "${AI_SHELL_TEST_OFFLINE:-0}" = 1 ]; then
  printf '\n(offline mode: skipping the prerequisites phase)\n'
  printf '\n%s passed, %s failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
  exit $?
fi

# --- phase 2: prerequisites installed the way the README says ----------------

section 'installing prerequisites (git, curl, zsh, xclip)'

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq git curl ca-certificates zsh xclip >/dev/null 2>&1
t 'git installed'  'command -v git'
t 'curl installed' 'command -v curl'
t 'zsh installed'  'command -v zsh'

# The bind mount is owned by the host user, which git in the container reads as
# dubious; irrelevant to ai-shell, an artifact of testing from a mount.
git config --global --add safe.directory '*' >/dev/null 2>&1
t 'the documented git clone works' 'git clone -q /src /root/.ai-shell'
# The clone carries the last commit; the point of the run is the working tree,
# so overwrite the tracked scripts with what's actually mounted. The .git the
# clone brought is what ask-version needs.
cp /src/*.sh /src/README.md /root/.ai-shell/ 2>/dev/null
cp -r /src/test /root/.ai-shell/ 2>/dev/null

section 'install with both shells present'

run /root/.ai-shell/install.sh
st=$?
[ $st -eq 2 ] && ok 'no-flag install asks which shell when both are installed' \
              || bad "no-flag install should exit 2 with zsh and bash both installed (got $st)"
has 'the ambiguity message names the flags' "$err" 'pass --zsh, --bash, or --all'

run /root/.ai-shell/install.sh --all
st=$?
[ $st -eq 0 ] && ok 'install --all succeeds' || bad "install --all exited $st"
has 'bash rc got the block' /root/.bashrc "$marker"
has 'zsh rc got the block'  /root/.zshrc  "$marker"

t 'zsh loads ai-shell' \
  'zsh -c ". /root/.ai-shell/ai-shell.sh; typeset -f ask >/dev/null"'
t 'every command is defined under zsh' \
  'zsh -c ". /root/.ai-shell/ai-shell.sh; for f in '"$fns"'; do typeset -f \$f >/dev/null || exit 1; done"'

section 'installing the claude CLI'

curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1
t 'claude landed in ~/.local/bin' '[ -x /root/.local/bin/claude ]'

# The official installer doesn't touch PATH, and neither Debian nor Ubuntu puts
# ~/.local/bin on root's — the case ai-shell has to name accurately.
run /root/.ai-shell/install.sh --check
has 'check names the PATH problem, not a missing claude' "$err" "isn't on your PATH"
bash -c '. /root/.ai-shell/ai-shell.sh; ask hi' >"$out" 2>"$err"
[ $? -eq 127 ] && ok 'ask exits 127 when claude is off PATH' \
               || bad 'ask should exit 127 when claude is off PATH'
has 'ask names the PATH problem' "$err" 'not on your PATH'

section 'with ~/.local/bin on PATH'

export PATH="/root/.local/bin:$PATH"
t 'claude runs' 'claude --version'
run /root/.ai-shell/install.sh --check
st=$?
[ $st -eq 0 ] && ok 'install.sh --check exits 0' || bad "install.sh --check exited $st"
has 'check reports a clean box' "$out" 'prerequisites: all present'
t 'ask-version works from a clone' \
  'bash -c ". /root/.ai-shell/ai-shell.sh; ask-version" | grep -q "^ai-shell "'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
