#!/usr/bin/env bash
# Covers the hooks that are not the grep ratchet — pint, i18n, verify, the
# session card — plus the settings registration, the git pre-commit bridge
# and bin/install-hooks.sh. Sourced by run-tests.sh; REPO_ROOT is exported
# there and every path below is derived from it.

HI_TMP="$(mktemp -d)"

hi_payload() { printf '{"tool_input":{"file_path":"%s"}}' "$1"; }

hi_pint() { hi_payload "$1" | "$REPO_ROOT/hooks/pint-gate.sh"; }
hi_pint_garbage() { printf 'not json at all' | "$REPO_ROOT/hooks/pint-gate.sh"; }
hi_pint_empty() { printf '' | "$REPO_ROOT/hooks/pint-gate.sh"; }
hi_i18n() { hi_payload "$1" | "$REPO_ROOT/hooks/i18n-gate.sh"; }
# verify-gate baselines what was already dirty on its first run, so a test that
# wants a verdict has to establish that baseline first — the same two steps a
# real session takes at SessionStart and then at Stop.
hi_verify() {
    printf '{"session_id":"hooksinstall","stop_hook_active":false}' \
        | CLAUDE_PROJECT_DIR="$1" "$REPO_ROOT/hooks/verify-gate.sh" --baseline >/dev/null 2>&1
    printf '{"session_id":"hooksinstall","stop_hook_active":false}' \
        | CLAUDE_PROJECT_DIR="$1" "$REPO_ROOT/hooks/verify-gate.sh"
}

# The baseline is keyed on the session and the checkout, so a fixture reused
# across cases has to start from a clean one or the first case's snapshot
# decides the second's verdict.
hi_verify_reset() { rm -f "${TMPDIR:-/tmp}"/unopim-verify-hooksinstall-* 2>/dev/null; return 0; }
hi_verify_looping() {
    printf '{"stop_hook_active":true}' \
        | CLAUDE_PROJECT_DIR="$1" "$REPO_ROOT/hooks/verify-gate.sh"
}
hi_card() { "$REPO_ROOT/hooks/session-card.sh" "$1" </dev/null; }
hi_json_ok() { python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1"; }
hi_precommit() { (cd "$1" && "$REPO_ROOT/hooks/pre-commit" </dev/null); }

HI_ABS_RE="$(printf '/%s/[A-Za-z0-9._-]+/|/%s/[A-Za-z0-9._-]+/' home Users)"

hi_hygiene() {
    local f="$REPO_ROOT/$1"
    [ -x "$f" ] || return 1
    head -1 "$f" | grep -qx '#!/usr/bin/env bash' || return 1
    grep -qE '^set -(euo|uo) pipefail$' "$f" || return 1
    ! grep -qE "$HI_ABS_RE" "$f"
}

hi_git_init() {
    git -C "$1" init -q
    git -C "$1" config user.email t@t
    git -C "$1" config user.name t
}

# --- pint-gate: never blocks, whatever it is handed -------------------------
mkdir -p "$HI_TMP/plain"
printf '<?php\n' > "$HI_TMP/plain/x.php"

assert_passes hi_pint "$HI_TMP/plain/nonexistent.php"
assert_passes hi_pint "$HI_TMP/plain/x.php"
assert_passes hi_pint "$HI_TMP/plain/notes.md"
assert_passes hi_pint_garbage
assert_passes hi_pint_empty

# --- i18n-gate: silent without artisan, ignores non-lang paths --------------
mkdir -p "$HI_TMP/plain/src/Resources/lang/en_US"
printf "<?php return [];\n" > "$HI_TMP/plain/src/Resources/lang/en_US/app.php"

assert_passes hi_i18n "$HI_TMP/plain/src/Resources/lang/en_US/app.php"
assert_passes hi_i18n "$HI_TMP/plain/x.php"

# --- verify-gate: the Stop gate ---------------------------------------------
assert_passes hi_verify "$HI_TMP/plain"

HI_REPO="$HI_TMP/repo"
mkdir -p "$HI_REPO"
hi_git_init "$HI_REPO"
printf 'seed\n' > "$HI_REPO/README.md"
git -C "$HI_REPO" add -A
git -C "$HI_REPO" commit -qm init

assert_passes hi_verify "$HI_REPO"

printf 'docs only\n' >> "$HI_REPO/README.md"
assert_passes hi_verify "$HI_REPO"

printf '<?php\n' > "$HI_REPO/Widget.php"
assert_fails hi_verify "$HI_REPO"
assert_output_contains "verify-gate" hi_verify "$HI_REPO"
assert_output_contains "Widget.php" hi_verify "$HI_REPO"
assert_passes hi_verify_looping "$HI_REPO"

printf '4102444800\n' > "$HI_REPO/.verify-stamp"
assert_passes hi_verify "$HI_REPO"

printf '1\n' > "$HI_REPO/.verify-stamp"
assert_fails hi_verify "$HI_REPO"

printf 'not-a-number\n' > "$HI_REPO/.verify-stamp"
assert_fails hi_verify "$HI_REPO"

# A stamp that is not one bare integer must fail CLOSED. Stripping non-digits
# out of these instead would produce a number far in the future and the gate
# would silently stop blocking anything, forever.
printf '4102444800.123456\n' > "$HI_REPO/.verify-stamp"
assert_fails hi_verify "$HI_REPO"
printf '4102444800 4102444800\n' > "$HI_REPO/.verify-stamp"
assert_fails hi_verify "$HI_REPO"
printf '# written by verify.sh\n4102444800\n' > "$HI_REPO/.verify-stamp"
assert_fails hi_verify "$HI_REPO"
printf '41024448004102444800410244480041\n' > "$HI_REPO/.verify-stamp"
assert_fails hi_verify "$HI_REPO"
rm -f "$HI_REPO/.verify-stamp"

# verify.sh is the only writer of that stamp, so what it writes must be exactly
# what verify-gate.sh accepts. This is the contract, asserted end to end.
hi_stamp_roundtrip() {
    local root="$1"
    rm -f "$root/.verify-stamp"
    "$REPO_ROOT/skills/unopim-verify/verify.sh" "$root" --changed "README.md" >/dev/null 2>&1 || return 1
    [ -f "$root/.verify-stamp" ] || return 1
    CLAUDE_PROJECT_DIR="$root" "$REPO_ROOT/hooks/verify-gate.sh" </dev/null >/dev/null 2>&1
}
assert_passes hi_stamp_roundtrip "$HI_REPO"
rm -f "$HI_REPO/.verify-stamp"

# --- session-card ------------------------------------------------------------
assert_passes hi_card "$REPO_ROOT"
assert_output_contains "UnoPim workspace" hi_card "$REPO_ROOT"
assert_output_contains "php wrapper" hi_card "$HI_TMP/plain"
mkdir -p "$HI_TMP/noboost/packages/Webkul"
printf '<?php\n' > "$HI_TMP/noboost/artisan"
assert_output_contains "Laravel Boost is required" hi_card "$HI_TMP/noboost"
assert_output_contains "boost:install" hi_card "$HI_TMP/noboost"

# --- settings.json ------------------------------------------------------------
assert_passes hi_json_ok "$REPO_ROOT/hooks/settings.json"
for hi_needle in '"PostToolUse"' '"Stop"' '"SessionStart"' '"Edit|Write"' \
    '$CLAUDE_PROJECT_DIR/.claude/hooks/grep-gate.sh' \
    '$CLAUDE_PROJECT_DIR/.claude/hooks/pint-gate.sh' \
    '$CLAUDE_PROJECT_DIR/.claude/hooks/i18n-gate.sh' \
    '$CLAUDE_PROJECT_DIR/.claude/hooks/verify-gate.sh' \
    '$CLAUDE_PROJECT_DIR/.claude/hooks/session-card.sh'; do
    assert_output_contains "$hi_needle" cat "$REPO_ROOT/hooks/settings.json"
done

# --- script hygiene -----------------------------------------------------------
for hi_script in hooks/pint-gate.sh hooks/i18n-gate.sh hooks/verify-gate.sh \
    hooks/session-card.sh hooks/pre-commit bin/install-hooks.sh bin/doctor.sh; do
    assert_passes hi_hygiene "$hi_script"
done

# --- pre-commit ---------------------------------------------------------------
assert_passes hi_precommit "$HI_REPO"

# --- install-hooks ------------------------------------------------------------
assert_fails "$REPO_ROOT/bin/install-hooks.sh"
assert_output_contains "usage:" "$REPO_ROOT/bin/install-hooks.sh"
assert_fails "$REPO_ROOT/bin/install-hooks.sh" "$HI_TMP/plain"
assert_output_contains "UnoPim" "$REPO_ROOT/bin/install-hooks.sh" "$HI_TMP/plain"

HI_APP="$HI_TMP/app"
mkdir -p "$HI_APP/packages/Webkul"
printf '<?php\n' > "$HI_APP/artisan"
hi_git_init "$HI_APP"
mkdir -p "$HI_APP/.claude"
printf '{\n  "permissions": {\n    "allow": ["Bash(ls:*)"]\n  }\n}\n' > "$HI_APP/.claude/settings.json"

assert_passes "$REPO_ROOT/bin/install-hooks.sh" "$HI_APP" --with-git-hook --skip-tooling
assert_passes hi_json_ok "$HI_APP/.claude/settings.json"
assert_passes test -f "$HI_APP/.claude/hooks/pint-gate.sh"
assert_passes test -f "$HI_APP/.claude/hooks/i18n-gate.sh"
assert_passes test -f "$HI_APP/.claude/hooks/verify-gate.sh"
assert_passes test -f "$HI_APP/.claude/hooks/session-card.sh"
assert_passes test -x "$HI_APP/.claude/hooks/verify-gate.sh"
assert_passes test -x "$HI_APP/.git/hooks/pre-commit"
assert_output_contains "Bash(ls:*)" cat "$HI_APP/.claude/settings.json"
assert_output_contains "session-card.sh" cat "$HI_APP/.claude/settings.json"

hi_command_count() {
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
count = 0
for entries in data.get("hooks", {}).values():
    for entry in entries:
        for hook in entry.get("hooks", []):
            if sys.argv[2] in hook.get("command", ""):
                count += 1
print(count)
' "$1" "$2"
}

hi_installed_once() { [ "$(hi_command_count "$1" "$2")" = "1" ]; }
hi_installed_twice() { [ "$(hi_command_count "$1" "$2")" = "2" ]; }

assert_passes "$REPO_ROOT/bin/install-hooks.sh" "$HI_APP" --skip-tooling
assert_passes hi_json_ok "$HI_APP/.claude/settings.json"
# verify-gate is registered twice on purpose: --baseline at SessionStart and
# the verdict at Stop.
assert_passes hi_installed_twice "$HI_APP/.claude/settings.json" verify-gate.sh
assert_passes hi_installed_once "$HI_APP/.claude/settings.json" pint-gate.sh
assert_passes hi_installed_once "$HI_APP/.claude/settings.json" grep-gate.sh
assert_output_contains "Bash(ls:*)" cat "$HI_APP/.claude/settings.json"

# --- end to end ---------------------------------------------------------------
# Unconditional on purpose. This block used to be guarded by "if grep-gate.sh
# exists", which meant a deleted or unreadable ratchet turned the whole end-to-end
# case into a silent skip and the suite still went green.
assert_passes test -x "$REPO_ROOT/hooks/grep-gate.sh"
assert_passes test -f "$REPO_ROOT/hooks/lib/payload.sh"
assert_passes test -f "$REPO_ROOT/hooks/lib/added-lines.sh"
assert_passes test -f "$REPO_ROOT/hooks/rules.txt"

HI_VIEW="$HI_APP/packages/Webkul/Admin/src/Resources/views/catalog"
mkdir -p "$HI_VIEW"
printf '<x-admin::form.control-group.control type="text" name="sku" />\n' \
    > "$HI_VIEW/clean.blade.php"
git -C "$HI_APP" add -A
git -C "$HI_APP" commit -qm seed --no-verify
printf '<div style="color:#ff0000"><input name="sku"></div>\n' > "$HI_VIEW/dirty.blade.php"
git -C "$HI_APP" add "$HI_VIEW/dirty.blade.php"
assert_fails hi_precommit "$HI_APP"
assert_output_contains "grep-gate" hi_precommit "$HI_APP"
assert_output_contains "INLINE_STYLE" hi_precommit "$HI_APP"
git -C "$HI_APP" rm -q --cached "$HI_VIEW/dirty.blade.php"
rm -f "$HI_VIEW/dirty.blade.php"
assert_passes hi_precommit "$HI_APP"

# The installed hook must reach its own lib/ and rule table, not the ones in
# this repository: the copy under .claude/hooks is what actually runs.
hi_installed_gate_blocks() {
    printf '<div style="color:#ff0000"><input name="sku"></div>\n' > "$HI_VIEW/added.blade.php"
    printf '{"tool_input":{"file_path":"%s"}}' "$HI_VIEW/added.blade.php" \
        | "$HI_APP/.claude/hooks/grep-gate.sh" 2>&1
    local code=$?
    rm -f "$HI_VIEW/added.blade.php"
    [ "$code" -eq 2 ]
}
assert_passes hi_installed_gate_blocks
assert_output_contains "RAW_FORM_CONTROL" hi_installed_gate_blocks

# Every skill path a block message points at has to exist, or the fix it names
# cannot be read. grep-gate.sh signed off telling the model to consult
# skills/unopim-admin-ui, which has never been a directory in this repository.
hi_cited_skills_exist() {
    local cited missing=0
    while read -r cited; do
        [ -n "$cited" ] || continue
        cited="${cited%.}"
        if [ ! -e "$REPO_ROOT/$cited" ]; then
            echo "dangling citation: $cited"
            missing=1
        fi
    done < <(grep -ohE 'skills/unopim-[A-Za-z0-9._/-]+' \
        "$REPO_ROOT/hooks/grep-gate.sh" "$REPO_ROOT/hooks/rules.txt" | sort -u)
    [ "$missing" -eq 0 ]
}
assert_passes hi_cited_skills_exist

# Re-running the installer must not register a command twice: Stop and
# SessionStart entries carry no matcher, so a second run can land the same
# command in a different slot and the hook fires twice per event.
assert_passes "$REPO_ROOT/bin/install-hooks.sh" "$HI_APP" --skip-tooling
assert_passes hi_installed_twice "$HI_APP/.claude/settings.json" verify-gate.sh
assert_passes hi_installed_twice "$HI_APP/.claude/settings.json" sweep-gate.sh
assert_passes hi_installed_once "$HI_APP/.claude/settings.json" session-card.sh
assert_passes hi_installed_once "$HI_APP/.claude/settings.json" grep-gate.sh

# Without --skip-tooling the installer ships doctor.sh and runs it with --fix
hi_tool_bin="$HI_TMP/toolbin"
mkdir -p "$hi_tool_bin"
printf '#!/usr/bin/env bash\nprintf "composer %%s\\n" "$*" >> calls.log\nprintf %%s "{\\"packages-dev\\":[{\\"name\\":\\"laravel/boost\\"}]}" > composer.lock\n' > "$hi_tool_bin/composer"
printf '#!/usr/bin/env bash\nprintf "php %%s\\n" "$*" >> calls.log\nprintf %%s "{\\"mcpServers\\":{\\"laravel-boost\\":{\\"command\\":\\"php\\",\\"args\\":[\\"artisan\\",\\"boost:mcp\\"]}}}" > .mcp.json\n' > "$hi_tool_bin/php"
chmod +x "$hi_tool_bin/composer" "$hi_tool_bin/php"
hi_tool_app="$HI_TMP/toolapp"
mkdir -p "$hi_tool_app/packages/Webkul"
printf '<?php\n' > "$hi_tool_app/artisan"
hi_install_tooling() { PATH="$hi_tool_bin:$PATH" "$REPO_ROOT/bin/install-hooks.sh" "$1" </dev/null; }
assert_passes hi_install_tooling "$hi_tool_app"
assert_passes test -x "$hi_tool_app/.claude/hooks/doctor.sh"
assert_passes grep -qF "artisan boost:install --mcp --guidelines --skills --no-interaction" "$hi_tool_app/calls.log"

rm -rf "$HI_TMP"
