# grep-gate: the ratchet.
# Proves the gate blocks a violation on a line the edit ADDED, and stays
# silent on the identical violation once it is committed. Fixtures are a
# real throwaway git repo, so the added-line computation is exercised for
# real rather than mocked.

GG_GATE="$REPO_ROOT/hooks/grep-gate.sh"
GG_PAYLOAD="$REPO_ROOT/hooks/lib/payload.sh"
GG_ADDED="$REPO_ROOT/hooks/lib/added-lines.sh"

GG_TMP="$(mktemp -d)"
GG_NOREPO="$(mktemp -d)"
GG_VIEWS="$GG_TMP/packages/Webkul/Admin/src/Resources/views/catalog"
GG_CSS="$GG_TMP/packages/Webkul/Admin/src/Resources/assets/css"
GG_HTTP="$GG_TMP/packages/Webkul/Admin/src/Http/Controllers"
GG_GRID="$GG_TMP/packages/Webkul/Admin/src/DataGrids/Catalog"
GG_MODEL="$GG_TMP/packages/Webkul/Foo/src/Models"
GG_REQ="$GG_TMP/packages/Webkul/Foo/src/Http/Requests"
GG_REPO="$GG_TMP/packages/Webkul/Foo/src/Repositories"
mkdir -p "$GG_VIEWS" "$GG_CSS" "$GG_HTTP" "$GG_GRID" "$GG_MODEL" "$GG_REQ" \
    "$GG_REPO" "$GG_NOREPO/Resources/views"

GG_BAD='<div style="color:#ff0000" class="bg-violet-500"><input name="sku"></div>'
GG_OK='<x-admin::form.control-group.control type="text" name="sku" />'

git -C "$GG_TMP" init -q
git -C "$GG_TMP" config user.email tester@example.test
git -C "$GG_TMP" config user.name tester

printf '%s\n' "$GG_OK"  > "$GG_VIEWS/untouched.blade.php"
printf '%s\n%s\n' "$GG_OK" "$GG_BAD" > "$GG_VIEWS/deletions.blade.php"
printf '%s\n' "$GG_BAD" > "$GG_VIEWS/legacy.blade.php"
printf '%s\n' "$GG_BAD" > "$GG_VIEWS/legacy-appended.blade.php"
printf '%s\n' "$GG_OK"  > "$GG_VIEWS/edited.blade.php"
printf '%s\n' "$GG_OK"  > "$GG_VIEWS/staged.blade.php"

# One committed carrier per NEW rule, holding that rule's violation. Each is
# asserted to stay silent, which is the half of the contract a fixture written
# only as a new file cannot prove: the rule must judge the edit, not the file.
GG_V_OVERLAY='<div class="fixed inset-0 z-50 flex items-center justify-center">'
GG_V_LISTING='<a href="{{ $rows->previousPageUrl() }}">prev</a>'
GG_V_SHORTHEX='<path fill="#333" d="M0 0" />'
GG_V_ARBRGB='<div class="bg-[rgb(124,58,237)] px-4">x</div>'
GG_V_YELLOW='<span class="bg-yellow-100 text-yellow-800">pending</span>'
GG_V_PHPCOLOR="        return '<span class=\"text-green-700\">ok</span>';"
GG_V_CSS='.credential-card { background-color: #F5F3FF; }'
GG_V_VALIDATOR='        $v = Validator::make($request->all(), []);'
GG_V_MODELPROP="    protected \$fillable = ['code'];"
GG_V_RAWSQL='        $q->whereRaw("name LIKE '"'"'%$search%'"'"'");'
GG_V_SVG="            'logo' => ['required', 'mimes:png,jpg,svg'],"
GG_V_UPLOAD="            'file' => ['required', 'file'],"
GG_V_REPOALL='        $rows = $this->productRepository->all();'
GG_V_SELECTSTAR="        \$q->select('*');"

gg_seed() { printf '%s\n' "${@:2}" > "$1"; }
gg_seed "$GG_VIEWS/legacy-overlay.blade.php"  "$GG_V_OVERLAY"
gg_seed "$GG_VIEWS/legacy-listing.blade.php"  "$GG_V_LISTING"
gg_seed "$GG_VIEWS/legacy-shorthex.blade.php" "$GG_V_SHORTHEX"
gg_seed "$GG_VIEWS/legacy-arbrgb.blade.php"   "$GG_V_ARBRGB"
gg_seed "$GG_VIEWS/legacy-yellow.blade.php"   "$GG_V_YELLOW"
gg_seed "$GG_GRID/LegacyDataGrid.php"   '<?php' "$GG_V_PHPCOLOR"
gg_seed "$GG_HTTP/LegacyValidator.php"  '<?php' "$GG_V_VALIDATOR"
gg_seed "$GG_MODEL/LegacyModel.php"     '<?php' "$GG_V_MODELPROP"
gg_seed "$GG_REPO/LegacySql.php"        '<?php' "$GG_V_RAWSQL"
gg_seed "$GG_REQ/LegacySvgForm.php"     '<?php' "$GG_V_SVG"
gg_seed "$GG_REQ/LegacyUploadForm.php"  '<?php' "$GG_V_UPLOAD"
gg_seed "$GG_REPO/LegacyRepoAll.php"    '<?php' "$GG_V_REPOALL"
gg_seed "$GG_REPO/LegacySelectStar.php" '<?php' "$GG_V_SELECTSTAR"
printf '.card { padding: 8px; }\n' > "$GG_CSS/theme.css"
printf '%s\n' '.legacy-card { background-color: #F5F3FF; }' > "$GG_CSS/legacy-theme.css"

git -C "$GG_TMP" add -A
git -C "$GG_TMP" commit -qm baseline

printf '%s\n' "$GG_BAD" >> "$GG_VIEWS/edited.blade.php"
printf '%s\n' "$GG_OK"  >> "$GG_VIEWS/legacy-appended.blade.php"
printf '%s\n' "$GG_BAD" >> "$GG_VIEWS/staged.blade.php"
git -C "$GG_TMP" add "$GG_VIEWS/staged.blade.php"

printf '%s\n' "$GG_OK"  > "$GG_VIEWS/deletions.blade.php"

mkdir -p "$GG_VIEWS/spaced dir"
printf '%s\n' "$GG_BAD" > "$GG_VIEWS/spaced dir/new file.blade.php"

printf '%s\n' "$GG_BAD" > "$GG_VIEWS/new-untracked.blade.php"
printf '%s\n' "$GG_OK"  > "$GG_VIEWS/new-clean.blade.php"
printf '%s\n' "$GG_BAD" > "$GG_NOREPO/Resources/views/orphan.blade.php"
printf 'body { color: #ffffff; }\n' > "$GG_CSS/custom.css"
printf 'body { color: #ffffff; }\n' > "$GG_CSS/app.css"
printf 'x\000\001\002 style="binary"\n' > "$GG_VIEWS/binary.blade.php"

{
    printf '<?php\n'
    printf '        $data = $request->validate([]);\n'
    printf '        // fetch every row\n'
    printf '        $rows = Product::all();\n'
} > "$GG_HTTP/DemoController.php"

# The same violations again as UNTRACKED files, which is how the gate sees new
# code: every line counts as added.
gg_seed "$GG_VIEWS/new-overlay.blade.php"  "$GG_V_OVERLAY"
gg_seed "$GG_VIEWS/new-listing.blade.php"  "$GG_V_LISTING"
gg_seed "$GG_VIEWS/new-shorthex.blade.php" "$GG_V_SHORTHEX"
gg_seed "$GG_VIEWS/new-arbrgb.blade.php"   "$GG_V_ARBRGB"
gg_seed "$GG_VIEWS/new-yellow.blade.php"   "$GG_V_YELLOW"
gg_seed "$GG_GRID/NewDataGrid.php"   '<?php' "$GG_V_PHPCOLOR"
gg_seed "$GG_HTTP/NewValidator.php"  '<?php' "$GG_V_VALIDATOR"
gg_seed "$GG_MODEL/NewModel.php"     '<?php' "$GG_V_MODELPROP"
gg_seed "$GG_REPO/NewSql.php"        '<?php' "$GG_V_RAWSQL"
gg_seed "$GG_REQ/NewSvgForm.php"     '<?php' "$GG_V_SVG"
gg_seed "$GG_REQ/NewUploadForm.php"  '<?php' "$GG_V_UPLOAD"
gg_seed "$GG_REPO/NewRepoAll.php"    '<?php' "$GG_V_REPOALL"
gg_seed "$GG_REPO/NewSelectStar.php" '<?php' "$GG_V_SELECTSTAR"

# A tracked stylesheet is past NEW_CSS_FILE, so the colour it grows afterwards
# is CSS_COLOR_LITERAL's job. A new .scss is NEW_CSS_FILE's.
printf '%s\n' "$GG_V_CSS" >> "$GG_CSS/theme.css"
printf '$brand: #7C3AED;\n' > "$GG_CSS/theme.scss"

# MODEL_ALL must NOT fire on the small config-shaped entities scale.md permits,
# even written fresh: this is the false positive the veto list exists to stop.
gg_seed "$GG_REPO/SmallEntity.php" '<?php' '        $c = Channel::all();' \
    '        $l = Locale::all();'

gg_code() {
    printf '{"tool_input":{"file_path":"%s"}}' "$1" | "$GG_GATE" >/dev/null 2>&1
    echo "$?"
}
gg_blocks() { [ "$(gg_code "$1")" = "2" ]; }
gg_allows() { [ "$(gg_code "$1")" = "0" ]; }
gg_out()    { printf '{"tool_input":{"file_path":"%s"}}' "$1" | "$GG_GATE" 2>&1; }
gg_added()  { bash "$GG_ADDED" "$1"; }
gg_payload_out() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$GG_PAYLOAD"; }

gg_payload_empty()   { printf '' | bash "$GG_PAYLOAD"; }
gg_empty_payload()   { printf '' | "$GG_GATE"; }
gg_garbage_payload() { printf 'not json at all' | "$GG_GATE"; }
gg_closed_stdin()    { "$GG_GATE" < /dev/null; }
gg_added_hides_committed() {
    local out
    out="$(gg_added "$GG_VIEWS/legacy-appended.blade.php")"
    [ -n "$out" ] || return 1
    ! printf '%s\n' "$out" | grep -q 'violet'
}

gg_no_comment_rule() {
    local out
    out="$(gg_out "$GG_VIEWS/edited.blade.php")"
    printf '%s\n' "$out" | grep -q 'INLINE_STYLE' || return 1
    ! printf '%s\n' "$out" | grep -q '^#'
}

# payload.sh must actually see the piped JSON (the python -c contract).
# A substring match is not enough: an implementation that echoed its stdin back
# would satisfy it. The contract is exactly one line, the path and nothing else.
gg_payload_exact() {
    local got
    got="$(gg_payload_out "$1")"
    [ "$got" = "$1" ]
}
assert_output_contains "edited.blade.php" gg_payload_out "$GG_VIEWS/edited.blade.php"
assert_passes gg_payload_exact "$GG_VIEWS/edited.blade.php"
assert_passes gg_payload_exact "$GG_VIEWS/spaced dir/new file.blade.php"
assert_passes bash -c 'printf "{\"tool_input\":{\"file_path\":\"%s\"}}" "$2" | bash "$1" | grep -c "" | grep -qx 1' \
    _ "$GG_PAYLOAD" "$GG_VIEWS/edited.blade.php"
assert_passes gg_payload_empty

# added-lines.sh: only additions for a tracked file, whole file otherwise
assert_output_contains "violet" gg_added "$GG_VIEWS/edited.blade.php"
assert_output_contains "control-group" gg_added "$GG_VIEWS/legacy-appended.blade.php"
assert_passes gg_added_hides_committed
assert_output_contains "violet" gg_added "$GG_VIEWS/new-untracked.blade.php"
assert_output_contains "violet" gg_added "$GG_NOREPO/Resources/views/orphan.blade.php"

# blocks on an added line, exit code 2, rule ids named
assert_passes gg_blocks "$GG_VIEWS/edited.blade.php"
assert_output_contains "INLINE_STYLE"     gg_out "$GG_VIEWS/edited.blade.php"
assert_output_contains "HEX_COLOR"        gg_out "$GG_VIEWS/edited.blade.php"
assert_output_contains "TAILWIND_INTENT"  gg_out "$GG_VIEWS/edited.blade.php"
assert_output_contains "RAW_FORM_CONTROL" gg_out "$GG_VIEWS/edited.blade.php"
assert_output_contains "pre-existing violations elsewhere are not your problem" \
    gg_out "$GG_VIEWS/edited.blade.php"
assert_passes gg_no_comment_rule

# the ratchet: identical violation, already committed, stays silent
assert_passes gg_allows "$GG_VIEWS/legacy.blade.php"
assert_passes gg_allows "$GG_VIEWS/legacy-appended.blade.php"
assert_passes gg_allows "$GG_VIEWS/untouched.blade.php"
assert_passes gg_allows "$GG_VIEWS/new-clean.blade.php"

# a staged edit is still an added line
assert_passes gg_blocks "$GG_VIEWS/staged.blade.php"

# removing a violating line adds nothing, so nothing is judged
assert_passes gg_allows "$GG_VIEWS/deletions.blade.php"

# untracked files count entirely as added, inside a repo or outside one
assert_passes gg_blocks "$GG_VIEWS/new-untracked.blade.php"
assert_passes gg_blocks "$GG_NOREPO/Resources/views/orphan.blade.php"
assert_passes gg_blocks "$GG_VIEWS/spaced dir/new file.blade.php"

# non-view rule groups
assert_passes gg_blocks "$GG_HTTP/DemoController.php"
assert_output_contains "INLINE_VALIDATE" gg_out "$GG_HTTP/DemoController.php"
assert_output_contains "INLINE_COMMENT"  gg_out "$GG_HTTP/DemoController.php"
assert_output_contains "MODEL_ALL"       gg_out "$GG_HTTP/DemoController.php"

# a new stylesheet is a path rule; the token file itself is exempt
assert_passes gg_blocks "$GG_CSS/custom.css"
assert_output_contains "NEW_CSS_FILE" gg_out "$GG_CSS/custom.css"
assert_passes gg_allows "$GG_CSS/app.css"
assert_output_contains "NEW_CSS_FILE" gg_out "$GG_CSS/theme.scss"

# Each new rule, both directions: it names itself on the line the edit added,
# and it says nothing about the identical line once that line is committed.
assert_output_contains "RAW_OVERLAY"           gg_out "$GG_VIEWS/new-overlay.blade.php"
assert_passes gg_allows                                "$GG_VIEWS/legacy-overlay.blade.php"
assert_output_contains "RAW_LISTING"           gg_out "$GG_VIEWS/new-listing.blade.php"
assert_passes gg_allows                                "$GG_VIEWS/legacy-listing.blade.php"
assert_output_contains "SHORT_HEX"             gg_out "$GG_VIEWS/new-shorthex.blade.php"
assert_passes gg_allows                                "$GG_VIEWS/legacy-shorthex.blade.php"
assert_output_contains "ARBITRARY_RGB"         gg_out "$GG_VIEWS/new-arbrgb.blade.php"
assert_passes gg_allows                                "$GG_VIEWS/legacy-arbrgb.blade.php"
assert_output_contains "TAILWIND_INTENT"       gg_out "$GG_VIEWS/new-yellow.blade.php"
assert_passes gg_allows                                "$GG_VIEWS/legacy-yellow.blade.php"
assert_output_contains "PHP_MARKUP_COLOR"      gg_out "$GG_GRID/NewDataGrid.php"
assert_passes gg_allows                                "$GG_GRID/LegacyDataGrid.php"
assert_output_contains "CSS_COLOR_LITERAL"     gg_out "$GG_CSS/theme.css"
assert_passes gg_allows                                "$GG_CSS/legacy-theme.css"
assert_output_contains "INLINE_VALIDATOR_MAKE" gg_out "$GG_HTTP/NewValidator.php"
assert_passes gg_allows                                "$GG_HTTP/LegacyValidator.php"
assert_output_contains "LEGACY_MODEL_PROPERTY" gg_out "$GG_MODEL/NewModel.php"
assert_passes gg_allows                                "$GG_MODEL/LegacyModel.php"
assert_output_contains "RAW_SQL_INTERPOLATION" gg_out "$GG_REPO/NewSql.php"
assert_passes gg_allows                                "$GG_REPO/LegacySql.php"
assert_output_contains "UPLOAD_SCRIPT_CARRIER" gg_out "$GG_REQ/NewSvgForm.php"
assert_passes gg_allows                                "$GG_REQ/LegacySvgForm.php"
assert_output_contains "UPLOAD_UNRESTRICTED"   gg_out "$GG_REQ/NewUploadForm.php"
assert_passes gg_allows                                "$GG_REQ/LegacyUploadForm.php"
assert_output_contains "REPO_ALL"              gg_out "$GG_REPO/NewRepoAll.php"
assert_passes gg_allows                                "$GG_REPO/LegacyRepoAll.php"
assert_output_contains "SELECT_STAR"           gg_out "$GG_REPO/NewSelectStar.php"
assert_passes gg_allows                                "$GG_REPO/LegacySelectStar.php"

# calibration, not coverage: the small-entity lookup scale.md permits must pass
# even when every line of it is new
assert_passes gg_allows "$GG_REPO/SmallEntity.php"

# degenerate inputs never block and never crash
assert_passes gg_empty_payload
assert_passes gg_garbage_payload
assert_passes gg_closed_stdin
assert_passes gg_allows "$GG_TMP/does-not-exist.blade.php"
assert_passes gg_allows "$GG_VIEWS/binary.blade.php"

rm -rf "$GG_TMP" "$GG_NOREPO"
