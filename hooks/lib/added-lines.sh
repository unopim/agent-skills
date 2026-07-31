#!/usr/bin/env bash
# Prints only the lines the working tree adds to FILE relative to HEAD.
# Contract: added-lines.sh FILE -> added line content on stdout, exit 0.
#
# An untracked file, a file in a repository with no commits, and a file
# outside any repository all count entirely as added: new code must be clean
# from its first line. A binary or empty file yields nothing. Staged changes
# count as added too, which is why the diff is taken against HEAD and not
# against the index.
set -uo pipefail

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
    echo "usage: added-lines.sh FILE" >&2
    exit 1
fi

FILE="$1"
[ -f "$FILE" ] || exit 0

DIR="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)"
[ -n "$DIR" ] || exit 0
ABS="$DIR/$(basename "$FILE")"

LC_ALL=C grep -Iq . -- "$ABS" 2>/dev/null || exit 0

whole_file() {
    cat -- "$ABS" 2>/dev/null
    exit 0
}

git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || whole_file
git -C "$DIR" ls-files --error-unmatch -- "$ABS" >/dev/null 2>&1 || whole_file
git -C "$DIR" rev-parse --verify -q HEAD >/dev/null 2>&1 || whole_file

git -C "$DIR" diff -U0 --no-color --no-ext-diff --no-textconv HEAD -- "$ABS" 2>/dev/null | awk '
    /^diff --git / { hunk = 0; next }
    /^@@/          { hunk = 1; next }
    hunk && /^\+/  { print substr($0, 2) }
'

exit 0
