# Claude Code uses the image permission bypass policy. See README "Security model".
alias claude='claude --dangerously-skip-permissions'
# Run Codex's app server in-process so Herdr's SessionStart hook sees the pane
# and Herdr can resume Codex panes after a restart. See README "Terminal integration".
alias codex='codex --no-daemon'
