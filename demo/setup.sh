# Sourced (hidden) at the start of demo/demo.tape, from the repo root.
# Uses a throwaway state dir and the demo `claude` shim so the recording
# never touches real conversation state or the network.
setopt interactive_comments 2>/dev/null || true
# Blank line after each command's output (i.e. before every prompt but the
# first) so the recording reads less densely.
_demo_first=1
precmd() { if [ -n "$_demo_first" ]; then _demo_first=; else print; fi }
export ASK_DIR=$(mktemp -d)
export PATH="$PWD/demo/bin:$PATH"
. ./ai-shell.sh
