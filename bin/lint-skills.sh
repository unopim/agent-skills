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

    requires="$(field requires "$fm")"
    if [ -n "$requires" ]; then
        printf '%s\n' "$requires" | tr ',' '\n' | while read -r dep; do
            dep="$(printf '%s' "$dep" | tr -d '[:space:]')"
            [ -n "$dep" ] || continue
            [ -d "$SKILLS_DIR/$dep" ] || \
                printf '%s: REQUIRES_UNRESOLVED: %s\n' "$skill_md" "requires '$dep' but no such skill directory"
        done | tee /tmp/lint-requires.$$
        if [ -s /tmp/lint-requires.$$ ]; then
            VIOLATIONS=$((VIOLATIONS + $(grep -c '' /tmp/lint-requires.$$)))
        fi
        rm -f /tmp/lint-requires.$$
    fi

    lines="$(grep -c '' "$skill_md")"
    if [ "$lines" -gt 150 ] && ! grep -qxF "$dir_name" "$SKILLS_DIR/.lint-allow" 2>/dev/null; then
        fail "$skill_md" SIZE_SKILL "$lines lines; a SKILL.md must be 150 or fewer — move depth into a reference file, or allowlist in skills/.lint-allow"
    fi

    for md in "$skill_dir"/*.md; do
        [ -e "$md" ] || continue
        [ "$md" = "$skill_md" ] && continue
        ref_lines="$(grep -c '' "$md")"
        [ "$ref_lines" -le 500 ] || \
            fail "$md" SIZE_REFERENCE "$ref_lines lines; a reference file must be 500 or fewer"
    done

    { grep -ohE '\]\(([A-Za-z0-9_./-]+\.md)\)' "$skill_dir"/*.md 2>/dev/null || true; } \
        | sed -E 's/^\]\((.*)\)$/\1/' | sort -u | while read -r link; do
        [ -e "$skill_dir/$link" ] || \
            printf '%s: DANGLING_LINK: %s\n' "$skill_md" "links to '$link' which does not exist in $dir_name/"
    done > /tmp/lint-links.$$
    if [ -s /tmp/lint-links.$$ ]; then
        cat /tmp/lint-links.$$
        VIOLATIONS=$((VIOLATIONS + $(grep -c '' /tmp/lint-links.$$)))
    fi
    rm -f /tmp/lint-links.$$

    if [ -n "$UNOPIM_PATH" ]; then
        { grep -ohE '`packages/Webkul/[A-Za-z0-9_./-]+`' "$skill_dir"/*.md 2>/dev/null || true; } \
            | tr -d '`' | sort -u | while read -r cited; do
            [ -e "$UNOPIM_PATH/$cited" ] || \
                printf '%s: EXEMPLAR_MISSING: %s\n' "$skill_md" "cites '$cited' which is not in the UnoPim checkout"
        done > /tmp/lint-cite.$$
        if [ -s /tmp/lint-cite.$$ ]; then
            cat /tmp/lint-cite.$$
            VIOLATIONS=$((VIOLATIONS + $(grep -c '' /tmp/lint-cite.$$)))
        fi
        rm -f /tmp/lint-cite.$$
    fi
done

# The roots are factored into one alternation group rather than spelled out as
# three separate rooted paths, so that this line does not itself read as a
# leaked path to the same check run over the whole repository.
LEAKED="$(grep -rnE '/(home|Users|var/www)/[A-Za-z0-9._-]+/' \
    --include='*.md' --include='*.sh' --exclude-dir=fixtures "$SKILLS_DIR" 2>/dev/null || true)"

if [ -n "$LEAKED" ]; then
    printf '%s\n' "$LEAKED" | while IFS= read -r hit; do
        printf '%s: ABSOLUTE_PATH: %s\n' "${hit%%:*}" "a machine-specific path is published here — use \$SKILLS_REPO, \$UNOPIM or a repo-relative path"
    done
    VIOLATIONS=$((VIOLATIONS + $(printf '%s\n' "$LEAKED" | grep -c '')))
fi

DUPES="$(for d in "$SKILLS_DIR"/*/SKILL.md; do
    [ -e "$d" ] || continue
    frontmatter "$d" | sed -n 's/^name: *//p' | head -1
done | sort | uniq -d)"

if [ -n "$DUPES" ]; then
    printf '%s\n' "$DUPES" | while read -r dupe; do
        printf '%s: DUPLICATE_NAME: %s\n' "$SKILLS_DIR" "skill name '$dupe' is declared by more than one directory"
    done
    VIOLATIONS=$((VIOLATIONS + $(printf '%s\n' "$DUPES" | grep -c '')))
fi

if [ "$VIOLATIONS" -gt 0 ]; then
    printf '\n%s violation(s)\n' "$VIOLATIONS"
    exit 1
fi

echo "skills lint clean"
