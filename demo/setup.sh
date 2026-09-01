# Sourced (hidden) at the start of demo/demo.tape, from the repo root.
# Uses a throwaway state dir and the demo `claude` shim so the recording
# never touches real conversation state or the network.
setopt interactive_comments 2>/dev/null || true
export ASK_DIR=$(mktemp -d)
export PATH="$PWD/demo/bin:$PATH"
. ./ai-shell.sh
