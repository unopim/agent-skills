#!/usr/bin/env bash
set -euo pipefail

SKILLS_DIR=""
UNOPIM_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --skills) SKILLS_DIR="$2"; shift 2 ;;
        --unopim) UNOPIM_PATH="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$SKILLS_DIR" ]; then
    SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills" && pwd)"
fi

VIOLATIONS=0

fail() {
    printf '%s: %s: %s\n' "$1" "$2" "$3"
    VIOLATIONS=$((VIOLATIONS + 1))
}

frontmatter() {
    awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside {print}' "$1"
}

field() {
    printf '%s\n' "$2" | sed -n "s/^$1: *//p" | head -1
}

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
    [ -e "$skill_md" ] || continue
    skill_dir="$(dirname "$skill_md")"
    dir_name="$(basename "$skill_dir")"
    fm="$(frontmatter "$skill_md")"

    if [ -z "$fm" ]; then
        fail "$skill_md" FRONTMATTER_MISSING "file must open with a --- delimited YAML block"
        continue
    fi

    name="$(field name "$fm")"
    desc="$(field description "$fm")"
    desc="${desc%\"}"; desc="${desc#\"}"

    case "$name" in
        "") fail "$skill_md" NAME_MISSING "frontmatter needs a name field" ;;
        "$dir_name") ;;
        *) fail "$skill_md" NAME_MISMATCH "name '$name' must equal directory '$dir_name'" ;;
    esac

    if ! printf '%s' "$name" | grep -qE '^[a-z0-9-]+$'; then
        fail "$skill_md" NAME_FORMAT "name must be lowercase letters, numbers and hyphens only"
    fi

    if [ -z "$desc" ]; then
        fail "$skill_md" DESCRIPTION_MISSING "frontmatter needs a description field"
    else
        case "$desc" in
            "Use when"*) ;;
            *) fail "$skill_md" DESCRIPTION_PREFIX "description must begin with 'Use when'" ;;
        esac
        if ! printf '%s' "$desc" | grep -qF 'Trigger phrases include'; then
            fail "$skill_md" DESCRIPTION_TRIGGERS "description must end with a 'Trigger phrases include \"…\"' sentence"
        fi
        if [ "${#desc}" -gt 900 ]; then
            fail "$skill_md" DESCRIPTION_LENGTH "description is ${#desc} chars; keep frontmatter under the 1024 char limit"
        fi
    fi
done

if [ "$VIOLATIONS" -gt 0 ]; then
    printf '\n%s violation(s)\n' "$VIOLATIONS"
    exit 1
fi

echo "skills lint clean"
