#!/usr/bin/env bash
# Installs the enforcement hooks into an UnoPim checkout:
#   TARGET/.claude/hooks/        the gates, their lib/ and the rule table
#   TARGET/.claude/settings.json hook registration, merged not overwritten
#   TARGET/.git/hooks/pre-commit optional, with --with-git-hook
# Re-running is idempotent. Files this repo does not have yet are reported
# and skipped rather than aborting the install.
set -euo pipefail

usage() {
    echo "usage: install-hooks.sh TARGET_UNOPIM_PATH [--with-git-hook]"
}

TARGET=""
WITH_GIT_HOOK=0

while [ $# -gt 0 ]; do
    case "$1" in
        --with-git-hook) WITH_GIT_HOOK=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -n "$TARGET" ]; then
                printf 'unexpected argument: %s\n' "$1" >&2
                usage >&2
                exit 2
            fi
            TARGET="$1"
            ;;
    esac
    shift
done

if [ -z "$TARGET" ]; then
    usage >&2
    exit 1
fi

if [ ! -d "$TARGET" ]; then
    printf 'install-hooks.sh: %s does not exist.\n' "$TARGET" >&2
    usage >&2
    exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"
IS_UNOPIM=0
if [ -f "$TARGET/artisan" ]; then
    if [ -d "$TARGET/packages/Webkul" ]; then
        IS_UNOPIM=1
    elif grep -qi 'unopim' "$TARGET/composer.json" 2>/dev/null; then
        IS_UNOPIM=1
    fi
fi

if [ "$IS_UNOPIM" -eq 0 ]; then
    {
        echo "install-hooks.sh: that path does not look like an UnoPim checkout."
        echo "Expected an artisan file plus packages/Webkul, or a composer.json"
        echo "naming unopim. Point it at the root of an UnoPim application."
    } >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$TARGET/.claude/hooks"
mkdir -p "$DEST/lib"

MISSING=""
note_missing() { MISSING="$MISSING  $1"$'\n'; }

copy_if_present() {
    if [ -f "$1" ]; then
        cp "$1" "$2"
        return 0
    fi
    note_missing "$3"
    return 0
}

for gate in "$HERE"/hooks/*.sh; do
    [ -f "$gate" ] || continue
    cp "$gate" "$DEST/"
done

for lib in "$HERE"/hooks/lib/*.sh; do
    [ -f "$lib" ] || continue
    cp "$lib" "$DEST/lib/"
done

copy_if_present "$HERE/hooks/rules.txt" "$DEST/" "hooks/rules.txt — grep-gate has no rule table without it"
copy_if_present "$HERE/hooks/lib/payload.sh" "$DEST/lib/" "hooks/lib/payload.sh — the gates cannot read a hook payload without it"
copy_if_present "$HERE/hooks/lib/added-lines.sh" "$DEST/lib/" "hooks/lib/added-lines.sh — grep-gate cannot see added lines without it"
copy_if_present "$HERE/hooks/grep-gate.sh" "$DEST/" "hooks/grep-gate.sh — the ratchet itself"
copy_if_present "$HERE/hooks/sweep-gate.sh" "$DEST/" "hooks/sweep-gate.sh — nothing catches a violation written by Bash"
copy_if_present "$HERE/bin/skills-conformance-scan.sh" "$DEST/" "bin/skills-conformance-scan.sh — sweep-gate has no engine without it"
copy_if_present "$HERE/skills/unopim-exec/detect-env.sh" "$DEST/" "skills/unopim-exec/detect-env.sh — the session card falls back to unknowns"

chmod +x "$DEST"/*.sh 2>/dev/null || true
chmod +x "$DEST"/lib/*.sh 2>/dev/null || true
echo "installed hooks into .claude/hooks"

SETTINGS="$TARGET/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    python3 - "$SETTINGS" "$HERE/hooks/settings.json" <<'PY'
import json
import sys

target, incoming = sys.argv[1], sys.argv[2]

try:
    with open(target) as handle:
        existing = json.load(handle)
except (ValueError, OSError) as error:
    sys.stderr.write("install-hooks.sh: %s is not readable JSON (%s).\n" % (target, error))
    sys.stderr.write("Left it untouched. Fix or move it, then run this again.\n")
    sys.exit(1)

if not isinstance(existing, dict):
    sys.stderr.write("install-hooks.sh: %s is not a JSON object. Left it untouched.\n" % target)
    sys.exit(1)

with open(incoming) as handle:
    add = json.load(handle)

hooks = existing.setdefault("hooks", {})
if not isinstance(hooks, dict):
    sys.stderr.write("install-hooks.sh: the hooks key in %s is not an object. Left it untouched.\n" % target)
    sys.exit(1)

added = 0
for event, entries in add.get("hooks", {}).items():
    bucket = hooks.setdefault(event, [])
    # Dedupe across the whole event, not just the matching slot: Stop and
    # SessionStart entries carry no matcher, so two registrations of the same
    # command can land in different slots and both fire.
    installed = {
        hook.get("command")
        for slot in bucket
        if isinstance(slot, dict)
        for hook in slot.get("hooks", [])
        if isinstance(hook, dict)
    }
    for entry in entries:
        entry = json.loads(json.dumps(entry))
        entry["hooks"] = [
            h for h in entry.get("hooks", [])
            if not (isinstance(h, dict) and h.get("command") in installed)
        ]
        if not entry["hooks"]:
            continue
        installed.update(h.get("command") for h in entry["hooks"])
        matcher = entry.get("matcher")
        slot = next(
            (e for e in bucket if isinstance(e, dict) and e.get("matcher") == matcher),
            None,
        )
        if slot is None:
            bucket.append(json.loads(json.dumps(entry)))
            added += len(entry.get("hooks", []))
            continue
        present = {
            h.get("command")
            for h in slot.setdefault("hooks", [])
            if isinstance(h, dict)
        }
        for hook in entry.get("hooks", []):
            if hook.get("command") not in present:
                slot["hooks"].append(json.loads(json.dumps(hook)))
                present.add(hook.get("command"))
                added += 1

with open(target, "w") as handle:
    json.dump(existing, handle, indent=2)
    handle.write("\n")

print("merged %d hook registration(s) into .claude/settings.json" % added)
PY
else
    mkdir -p "$TARGET/.claude"
    cp "$HERE/hooks/settings.json" "$SETTINGS"
    echo "wrote .claude/settings.json"
fi

if [ "$WITH_GIT_HOOK" -eq 1 ]; then
    if [ ! -f "$HERE/hooks/pre-commit" ]; then
        echo "warning: hooks/pre-commit is missing from this repo; skipped it" >&2
    elif GIT_DIR_PATH="$(git -C "$TARGET" rev-parse --git-dir 2>/dev/null)"; then
        case "$GIT_DIR_PATH" in
            /*) ;;
            *) GIT_DIR_PATH="$TARGET/$GIT_DIR_PATH" ;;
        esac
        mkdir -p "$GIT_DIR_PATH/hooks"
        cp "$HERE/hooks/pre-commit" "$GIT_DIR_PATH/hooks/pre-commit"
        chmod +x "$GIT_DIR_PATH/hooks/pre-commit"
        echo "installed the git pre-commit hook"
    else
        echo "warning: that path is not a git repository; skipped the pre-commit hook" >&2
    fi
fi

if [ -n "$MISSING" ]; then
    {
        echo
        echo "not installed, because this skills repo does not have it yet:"
        printf '%s' "$MISSING"
    } >&2
fi

echo "done. The gates judge only the lines an edit adds."
