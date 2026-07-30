assert_passes  "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/good"
assert_fails   "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/bad"
assert_output_contains "DESCRIPTION_PREFIX" \
    "$REPO_ROOT/bin/lint-skills.sh" --skills "$FIXTURES/bad"
