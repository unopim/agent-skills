# Tests for bin/install-skills.sh.
# Contract under test: --list works, skill names containing '/' or '..' are rejected
# before anything is written, `requires:` resolves transitively, symlink is the default
# with --copy as the container fallback, and an unrelated existing file is never
# overwritten. The installer must never prompt when an agent is named and its
# dot-directory already exists, so every case here is non-interactive.

INSTALLER="$REPO_ROOT/bin/install-skills.sh"

_inst_expect() {
    if [ "$2" -eq 0 ]; then
        echo "  ok   : $1"
    else
        echo "  FAIL : $1"
        FAILED=1
    fi
}

_inst_workspace() {
    local ws
    ws="$(mktemp -d "${TMPDIR:-/tmp}/unopim-install.XXXXXX")"
    mkdir -p "$ws/.claude"
    printf '%s' "$ws"
}

_inst_run() {
    local ws="$1"; shift
    ( cd "$ws" && bash "$INSTALLER" "$@" ) </dev/null 2>&1
}

_inst_installed() {
    [ -e "$1/.claude/skills/$2" ]
}

# --list enumerates the skills without touching the filesystem
_inst_ws="$(_inst_workspace)"
_inst_out="$(_inst_run "$_inst_ws" --list)"; _inst_status=$?
_inst_expect "--list exits 0" "$_inst_status"
printf '%s\n' "$_inst_out" | grep -qx 'unopim-plugin-development'
_inst_expect "--list names unopim-plugin-development" "$?"
[ ! -d "$_inst_ws/.claude/skills" ]
_inst_expect "--list installs nothing" "$?"

# path traversal is rejected before any agent resolution or write
for _inst_evil in '../../etc' 'unopim/../../etc' '..'; do
    _inst_out="$(_inst_run "$_inst_ws" -a claude "$_inst_evil")"; _inst_status=$?
    [ "$_inst_status" -ne 0 ]
    _inst_expect "rejects skill name '$_inst_evil'" "$?"
    printf '%s' "$_inst_out" | grep -qF "must not contain"
    _inst_expect "explains why '$_inst_evil' was rejected" "$?"
done
[ ! -d "$_inst_ws/.claude/skills" ]
_inst_expect "rejected names write nothing" "$?"
rm -rf "$_inst_ws"

# an unknown skill fails loudly
_inst_ws="$(_inst_workspace)"
_inst_out="$(_inst_run "$_inst_ws" -a claude unopim-does-not-exist)"; _inst_status=$?
[ "$_inst_status" -ne 0 ]
_inst_expect "unknown skill exits non-zero" "$?"
printf '%s' "$_inst_out" | grep -qF "unopim-does-not-exist"
_inst_expect "unknown skill is named in the error" "$?"
rm -rf "$_inst_ws"

# declared dependencies of unopim-plugin-development all arrive
_inst_ws="$(_inst_workspace)"
_inst_out="$(_inst_run "$_inst_ws" -a claude unopim-plugin-development)"; _inst_status=$?
_inst_expect "installing unopim-plugin-development exits 0" "$_inst_status"
for _inst_dep in unopim-plugin-development unopim-standards unopim-datagrid \
                 unopim-data-transfer unopim-exec unopim-verify; do
    _inst_installed "$_inst_ws" "$_inst_dep"
    _inst_expect "unopim-plugin-development pulls in $_inst_dep" "$?"
done
[ -L "$_inst_ws/.claude/skills/unopim-exec" ]
_inst_expect "symlink is the default install mode" "$?"
[ -f "$_inst_ws/.claude/skills/unopim-exec/SKILL.md" ]
_inst_expect "the symlink resolves to a real SKILL.md" "$?"
rm -rf "$_inst_ws"

# the requires: chain is followed transitively, not one level deep:
# unopim-git -> unopim-verify -> unopim-exec
_inst_ws="$(_inst_workspace)"
_inst_out="$(_inst_run "$_inst_ws" -a claude unopim-git)"; _inst_status=$?
_inst_expect "installing unopim-git exits 0" "$_inst_status"
_inst_installed "$_inst_ws" unopim-verify
_inst_expect "unopim-git pulls in its direct dependency unopim-verify" "$?"
_inst_installed "$_inst_ws" unopim-exec
_inst_expect "unopim-git pulls in the transitive dependency unopim-exec" "$?"

# re-running is idempotent and still exits 0
_inst_out="$(_inst_run "$_inst_ws" -a claude unopim-git)"; _inst_status=$?
_inst_expect "re-installing over an existing symlink exits 0" "$_inst_status"
rm -rf "$_inst_ws"

# --copy writes real directories for containers where symlinks are unusable
_inst_ws="$(_inst_workspace)"
_inst_out="$(_inst_run "$_inst_ws" --copy -a claude unopim-verify)"; _inst_status=$?
_inst_expect "--copy exits 0" "$_inst_status"
[ -d "$_inst_ws/.claude/skills/unopim-verify" ] && [ ! -L "$_inst_ws/.claude/skills/unopim-verify" ]
_inst_expect "--copy installs a real directory, not a symlink" "$?"
[ -f "$_inst_ws/.claude/skills/unopim-exec/SKILL.md" ]
_inst_expect "--copy copies dependencies too" "$?"
rm -rf "$_inst_ws"

# an unrelated file already occupying the target name is never clobbered
_inst_ws="$(_inst_workspace)"
mkdir -p "$_inst_ws/.claude/skills"
printf 'hand written\n' > "$_inst_ws/.claude/skills/unopim-git"
_inst_out="$(_inst_run "$_inst_ws" -a claude unopim-git)"; _inst_status=$?
[ "$_inst_status" -ne 0 ]
_inst_expect "refuses to overwrite an unrelated existing path" "$?"
grep -qx 'hand written' "$_inst_ws/.claude/skills/unopim-git"
_inst_expect "the unrelated file is left untouched" "$?"
[ ! -L "$_inst_ws/.claude/skills/unopim-git" ]
_inst_expect "no symlink replaced the unrelated file" "$?"
rm -rf "$_inst_ws"

# a link left dangling by a moved checkout is a previous install, not a stranger's file
_inst_ws="$(_inst_workspace)"
mkdir -p "$_inst_ws/.claude/skills"
ln -s "$_inst_ws/gone/unopim-exec" "$_inst_ws/.claude/skills/unopim-exec"
_inst_out="$(_inst_run "$_inst_ws" -a claude unopim-exec)"; _inst_status=$?
_inst_expect "replaces a dangling symlink from an earlier install" "$_inst_status"
[ -f "$_inst_ws/.claude/skills/unopim-exec/SKILL.md" ]
_inst_expect "the replaced symlink resolves again" "$?"
rm -rf "$_inst_ws"

# a copied install can be switched back to a symlink without a manual cleanup
_inst_ws="$(_inst_workspace)"
_inst_out="$(_inst_run "$_inst_ws" --copy -a claude unopim-exec)"; _inst_status=$?
_inst_expect "seeding a copy install exits 0" "$_inst_status"
_inst_out="$(_inst_run "$_inst_ws" -a claude unopim-exec)"; _inst_status=$?
_inst_expect "re-installing over a copy exits 0" "$_inst_status"
[ -L "$_inst_ws/.claude/skills/unopim-exec" ]
_inst_expect "the copy was converted to a symlink" "$?"
rm -rf "$_inst_ws"

# the agent argument selects the dot-directory, and an unknown agent is refused
_inst_ws="$(mktemp -d "${TMPDIR:-/tmp}/unopim-install.XXXXXX")"
mkdir -p "$_inst_ws/.cursor"
_inst_out="$(_inst_run "$_inst_ws" -a cursor unopim-exec)"; _inst_status=$?
_inst_expect "-a cursor exits 0" "$_inst_status"
[ -e "$_inst_ws/.cursor/skills/unopim-exec" ]
_inst_expect "-a cursor installs into .cursor/skills" "$?"
# a named agent whose dot-directory does not exist yet must not block on a prompt
_inst_out="$(_inst_run "$_inst_ws" -a copilot unopim-exec)"; _inst_status=$?
_inst_expect "-a copilot exits 0 with no .github present" "$_inst_status"
[ -e "$_inst_ws/.github/skills/unopim-exec" ]
_inst_expect "-a copilot maps to .github/skills" "$?"
_inst_out="$(_inst_run "$_inst_ws" -a gemini --local unopim-exec)"; _inst_status=$?
_inst_expect "--local exits 0" "$_inst_status"
[ -e "$_inst_ws/.gemini/skills/unopim-exec" ]
_inst_expect "--local installs beside the project" "$?"
_inst_out="$(_inst_run "$_inst_ws" -a notanagent unopim-exec)"; _inst_status=$?
[ "$_inst_status" -ne 0 ]
_inst_expect "an unknown agent exits non-zero" "$?"
rm -rf "$_inst_ws"

# UNOPIM_SKILLS_AGENT is consulted when no -a is given
_inst_ws="$(_inst_workspace)"
_inst_out="$( cd "$_inst_ws" && UNOPIM_SKILLS_AGENT=claude bash "$INSTALLER" unopim-exec </dev/null 2>&1 )"
_inst_status=$?
_inst_expect "UNOPIM_SKILLS_AGENT drives the install" "$_inst_status"
_inst_installed "$_inst_ws" unopim-exec
_inst_expect "UNOPIM_SKILLS_AGENT lands in .claude/skills" "$?"
rm -rf "$_inst_ws"

# with no skill named, every skill in the repo is installed
_inst_ws="$(_inst_workspace)"
_inst_out="$(_inst_run "$_inst_ws" -a claude --all)"; _inst_status=$?
_inst_expect "--all exits 0" "$_inst_status"
_inst_count="$(find "$_inst_ws/.claude/skills" -mindepth 1 -maxdepth 1 | grep -c '' || true)"
_inst_available="$(find "$REPO_ROOT/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | grep -c '' || true)"
[ "$_inst_count" -eq "$_inst_available" ]
_inst_expect "--all installs every skill ($_inst_count of $_inst_available)" "$?"
rm -rf "$_inst_ws"

unset INSTALLER _inst_ws _inst_out _inst_status _inst_evil _inst_dep _inst_count _inst_available
unset -f _inst_expect _inst_workspace _inst_run _inst_installed
