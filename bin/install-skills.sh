#!/usr/bin/env bash
#
# Install UnoPim agent skills into an AI coding agent's skills directory.
#
# Usage:
#   bin/install-skills.sh [options] [skill-name ...]
#
# Contract:
#   - Named skills install with their `requires:` chain resolved transitively.
#   - No skill name may contain '/' or '..'.
#   - Symlink is the default; --copy is the fallback for containers and images
#     where a symlink out of the project tree does not resolve.
#   - An existing path that this installer did not create is never overwritten.
#   - Exit status is non-zero if any requested skill failed to install.
#
# Agent resolution order: --agent, then $UNOPIM_SKILLS_AGENT, then an existing
# agent dot-directory in the working directory, then an interactive prompt.
# Prompts happen only on a terminal; with stdin redirected the installer picks
# the project-local directory rather than blocking.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SKILLS_SRC="$REPO_ROOT/skills"

KNOWN_AGENTS="claude codex copilot cursor gemini junie opencode"
KNOWN_AGENT_DIRS=".claude .codex .github .cursor .gemini .junie .opencode"

INSTALL_MODE="symlink"
AGENT=""
TARGET_DIR=""
SCOPE=""
INSTALL_ALL=0
RESOLVED=" "
FAILURES=0

if [ -t 1 ]; then
    C_RED="$(printf '\033[0;31m')"
    C_GREEN="$(printf '\033[0;32m')"
    C_YELLOW="$(printf '\033[0;33m')"
    C_BLUE="$(printf '\033[0;34m')"
    C_OFF="$(printf '\033[0m')"
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_OFF=""
fi

ok()   { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_OFF" "$1" >&2; }
err()  { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_OFF" "$1" >&2; }
info() { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_OFF" "$1"; }

available_skills() {
    local skill_md
    for skill_md in "$SKILLS_SRC"/*/SKILL.md; do
        [ -e "$skill_md" ] || continue
        basename "$(dirname "$skill_md")"
    done
}

usage() {
    cat <<'EOF'
Usage: install-skills.sh [options] [skill-name ...]

Arguments:
  skill-name        One or more skills to install. Each skill's `requires:`
                    chain is resolved and installed with it. Omit to install
                    every skill (same as --all).

Options:
  -a, --agent NAME  claude, codex, copilot, cursor, gemini, junie, opencode
      --all         Install every skill in this repository
      --copy        Copy instead of symlinking (containers, images, CI)
      --local       Install into ./<agent-dir>/skills (default)
      --global      Install into ~/<agent-dir>/skills
      --list        List available skill names and exit
  -h, --help        Show this help and exit

Environment:
  UNOPIM_SKILLS_AGENT   Agent to use when --agent is not given
EOF
    printf '\nAvailable skills:\n'
    available_skills | sed 's/^/  /'
}

agent_to_dir() {
    case "$1" in
        claude)   printf '.claude' ;;
        codex)    printf '.codex' ;;
        copilot)  printf '.github' ;;
        cursor)   printf '.cursor' ;;
        gemini)   printf '.gemini' ;;
        junie)    printf '.junie' ;;
        opencode) printf '.opencode' ;;
        *)
            err "unknown agent: $1"
            err "supported agents: $KNOWN_AGENTS"
            return 1
            ;;
    esac
}

dir_to_agent() {
    case "$1" in
        .claude)   printf 'claude' ;;
        .codex)    printf 'codex' ;;
        .github)   printf 'copilot' ;;
        .cursor)   printf 'cursor' ;;
        .gemini)   printf 'gemini' ;;
        .junie)    printf 'junie' ;;
        .opencode) printf 'opencode' ;;
        *)         printf '%s' "$1" ;;
    esac
}

detect_agent_dir() {
    local dot_dir
    for dot_dir in $KNOWN_AGENT_DIRS; do
        [ -d "./$dot_dir" ] || continue
        printf '%s' "$dot_dir"
        return 0
    done
    return 1
}

interactive() {
    [ -t 0 ] && [ -r /dev/tty ]
}

prompt_user() {
    printf '%s' "$1" > /dev/tty
    local answer
    read -r answer < /dev/tty
    printf '%s' "$answer"
}

canonical() {
    if [ -d "$1" ]; then
        ( cd "$1" && pwd -P )
    else
        printf '%s' "$1"
    fi
}

skill_requires() {
    local skill_md="$SKILLS_SRC/$1/SKILL.md"
    [ -f "$skill_md" ] || return 0
    awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside {print}' "$skill_md" \
        | sed -n 's/^requires: *//p' \
        | head -1 \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | grep . || true
}

validate_skill_name() {
    case "$1" in
        */*|*..*)
            err "invalid skill name '$1': must not contain '/' or '..'"
            return 1
            ;;
    esac
    if ! printf '%s' "$1" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
        err "invalid skill name '$1': lowercase letters, digits and hyphens only"
        return 1
    fi
    return 0
}

# A target may be replaced only when it is a previous install of this same skill:
# a link into this checkout, a link left dangling by a moved checkout, or a
# directory whose SKILL.md declares the same name. Anything else is the user's.
target_is_ours() {
    local target="$1" src="$2" name="$3"

    [ -L "$target" ] && [ ! -e "$target" ] && return 0
    [ "$(canonical "$target")" = "$(canonical "$src")" ] && return 0

    if [ -d "$target" ] && [ -f "$target/SKILL.md" ]; then
        grep -qE "^name:[[:space:]]*$name[[:space:]]*$" "$target/SKILL.md" && return 0
    fi

    return 1
}

place_skill() {
    local name="$1" src="$SKILLS_SRC/$1" target="$2/$1"

    if [ -e "$target" ] || [ -L "$target" ]; then
        if ! target_is_ours "$target" "$src" "$name"; then
            err "refusing to overwrite $target: it was not installed from this repository"
            err "remove or rename it, then re-run"
            return 1
        fi
    fi

    if [ "$INSTALL_MODE" = "copy" ]; then
        local staged="$target.installing.$$"
        rm -rf "$staged"
        cp -R "$src" "$staged"
        rm -rf "$target"
        mv "$staged" "$target"
        ok "installed (copy): $name"
        return 0
    fi

    if [ -L "$target" ] && [ -e "$target" ] && [ "$(canonical "$target")" = "$(canonical "$src")" ]; then
        info "already installed: $name"
        return 0
    fi

    rm -rf "$target"
    ln -s "$src" "$target"
    ok "installed: $name"
}

install_skill() {
    local name="$1" target_dir="$2" required_by="${3:-}"

    case "$RESOLVED" in
        *" $name "*) return 0 ;;
    esac

    if [ ! -d "$SKILLS_SRC/$name" ]; then
        if [ -n "$required_by" ]; then
            err "unknown skill '$name' required by '$required_by'"
        else
            err "unknown skill '$name'"
            printf 'Available skills:\n' >&2
            available_skills | sed 's/^/  /' >&2
        fi
        return 1
    fi

    RESOLVED="$RESOLVED$name "
    mkdir -p "$target_dir"

    local status=0
    place_skill "$name" "$target_dir" || status=1

    local dep
    while read -r dep; do
        [ -n "$dep" ] || continue
        validate_skill_name "$dep" || { status=1; continue; }
        install_skill "$dep" "$target_dir" "$name" || status=1
    done < <(skill_requires "$name")

    return "$status"
}

resolve_target_dir() {
    local agent_dir="$1"

    case "$SCOPE" in
        global) TARGET_DIR="$HOME/$agent_dir/skills"; return 0 ;;
        local)  TARGET_DIR="./$agent_dir/skills"; return 0 ;;
    esac

    if [ -d "./$agent_dir" ] || ! interactive; then
        TARGET_DIR="./$agent_dir/skills"
        return 0
    fi

    local answer
    answer="$(prompt_user "No $agent_dir directory here. Install (g)lobally in ~/$agent_dir/skills or (l)ocally in ./$agent_dir/skills? [g/l]: ")"
    case "$answer" in
        g|G|global) TARGET_DIR="$HOME/$agent_dir/skills" ;;
        *)          TARGET_DIR="./$agent_dir/skills" ;;
    esac
}

resolve_agent() {
    local agent_dir

    if [ -n "$AGENT" ]; then
        agent_dir="$(agent_to_dir "$AGENT")"
        resolve_target_dir "$agent_dir"
        return 0
    fi

    if [ -n "${UNOPIM_SKILLS_AGENT:-}" ]; then
        AGENT="$UNOPIM_SKILLS_AGENT"
        agent_dir="$(agent_to_dir "$AGENT")"
        info "using agent from UNOPIM_SKILLS_AGENT: $AGENT"
        resolve_target_dir "$agent_dir"
        return 0
    fi

    local detected
    if detected="$(detect_agent_dir)"; then
        AGENT="$(dir_to_agent "$detected")"
        if ! interactive; then
            info "detected $AGENT ($detected/skills)"
            TARGET_DIR="./$detected/skills"
            return 0
        fi
        local answer
        answer="$(prompt_user "Detected $AGENT ($detected/skills). Install there? [Y/n/agent-name]: ")"
        case "$answer" in
            ""|y|Y|yes|Yes) TARGET_DIR="./$detected/skills"; return 0 ;;
            n|N|no|No)      err "installation cancelled"; exit 1 ;;
            *)              AGENT="$answer" ;;
        esac
    elif interactive; then
        AGENT="$(prompt_user "Which agent? ($KNOWN_AGENTS): ")"
    else
        err "cannot tell which agent to install for"
        err "pass --agent NAME or set UNOPIM_SKILLS_AGENT ($KNOWN_AGENTS)"
        exit 2
    fi

    [ -n "$AGENT" ] || { err "no agent specified"; exit 2; }
    agent_dir="$(agent_to_dir "$AGENT")"
    resolve_target_dir "$agent_dir"
}

SKILL_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--agent)
            [ $# -ge 2 ] || { err "$1 needs an agent name"; exit 2; }
            AGENT="$2"; shift 2 ;;
        --agent=*) AGENT="${1#*=}"; shift ;;
        --copy)    INSTALL_MODE="copy"; shift ;;
        --local)   SCOPE="local"; shift ;;
        --global)  SCOPE="global"; shift ;;
        --all)     INSTALL_ALL=1; shift ;;
        --list)    available_skills; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        -*)        err "unknown option: $1"; usage >&2; exit 2 ;;
        *)         SKILL_ARGS+=("$1"); shift ;;
    esac
done

if [ "${#SKILL_ARGS[@]}" -eq 0 ]; then
    INSTALL_ALL=1
fi

if [ "$INSTALL_ALL" -eq 1 ]; then
    while read -r skill; do
        SKILL_ARGS+=("$skill")
    done < <(available_skills)
fi

if [ "${#SKILL_ARGS[@]}" -eq 0 ]; then
    err "no skills found in $SKILLS_SRC"
    exit 1
fi

for skill in "${SKILL_ARGS[@]}"; do
    validate_skill_name "$skill" || exit 2
done

resolve_agent

printf '\n'
info "installing into $TARGET_DIR ($INSTALL_MODE)"
printf '\n'

for skill in "${SKILL_ARGS[@]}"; do
    install_skill "$skill" "$TARGET_DIR" || FAILURES=$((FAILURES + 1))
done

printf '\n'
if [ "$FAILURES" -gt 0 ]; then
    err "$FAILURES skill(s) could not be installed"
    exit 1
fi

ok "done"
