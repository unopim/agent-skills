#!/usr/bin/env bash
# Prints the edited file path from a Claude Code hook payload read on stdin.
# Contract: exactly one line on stdout (empty when the payload names no file),
# always exit 0, never read anything but stdin.
#
# The python source is passed with -c. A heredoc to `python3 -` would become
# python's stdin and swallow the piped payload, so the path would come back
# empty and every gate downstream would pass without checking anything.
set -euo pipefail

if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if not isinstance(data, dict):
    sys.exit(0)

source = data.get("tool_input")
if not isinstance(source, dict):
    source = {}

for key in ("file_path", "notebook_path", "path"):
    value = source.get(key) or data.get(key)
    if isinstance(value, str) and value:
        print(value)
        break
' || true
else
    { tr -d '\n' \
        | sed -nE 's/.*"(file_path|notebook_path|path)"[[:space:]]*:[[:space:]]*"([^"]*)".*/\2/p'
    } || true
fi

exit 0
