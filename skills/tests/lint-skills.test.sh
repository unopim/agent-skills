assert_passes  "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/good"
assert_fails   "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/bad"
assert_output_contains "DESCRIPTION_PREFIX" \
    "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/bad"
assert_output_contains "DANGLING_LINK" \
    "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/bad"
assert_output_contains "REQUIRES_UNRESOLVED" \
    "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/bad"
assert_output_contains "EXEMPLAR_MISSING" \
    "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/bad" --unopim "$FIXTURES/fake-unopim"
assert_output_contains "ABSOLUTE_PATH" \
    "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/bad"
