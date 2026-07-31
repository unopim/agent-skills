# detect-env: which php actually runs the command.
# A machine may have BOTH a host php and a running compose stack. Picking the
# host binary there is the failure this skill exists to prevent, so the cases
# below pin the precedence: running container > host php > stopped container.
# PATH is rebuilt from symlinks per case, which is the only way to model "no
# host php" without touching the machine.

DE_BASH="$(command -v bash)"
DE_SCRIPT="$REPO_ROOT/skills/unopim-exec/detect-env.sh"
DE_TMP="$(mktemp -d)"

mkdir -p "$DE_TMP/project"
cat > "$DE_TMP/project/docker-compose.yml" <<'YAML'
services:
  php:
    image: php:8.4-fpm
  db:
    image: mysql:8
YAML

mkdir -p "$DE_TMP/bare"

# Two docker stand-ins. `ps -q` printing an id means the stack is up; printing
# nothing is a declared-but-stopped stack.
de_docker_shim() {
    local dir="$1" id="$2"
    mkdir -p "$dir"
    {
        printf '#!%s\n' "$DE_BASH"
        printf 'if [ "${1:-}" = compose ]; then printf %%s "%s"; fi\n' "$id"
        printf 'exit 0\n'
    } > "$dir/docker"
    chmod +x "$dir/docker"
}

de_docker_shim "$DE_TMP/bin-up" "abc123def456"
de_docker_shim "$DE_TMP/bin-down" ""

# A PATH holding only what detect-env.sh actually calls, so `php` can be left out.
de_path() {
    local dir="$DE_TMP/path-$1" with_php="$2" tool src
    mkdir -p "$dir"
    for tool in awk sed tr getent python3; do
        src="$(command -v "$tool" 2>/dev/null)" || continue
        [ -n "$src" ] && ln -sf "$src" "$dir/$tool"
    done
    if [ "$with_php" = yes ]; then
        printf '#!%s\nexit 0\n' "$DE_BASH" > "$dir/php"
        chmod +x "$dir/php"
    fi
    printf '%s' "$dir"
}

DE_WITH_PHP="$(de_path with yes)"
DE_NO_PHP="$(de_path without no)"

# The interpreter is addressed absolutely: the cases below hand the script a
# PATH that deliberately omits things, and bash must not be one of them.
de_wrapper() {
    local shims="$1" base="$2" root="$3"
    PATH="$shims:$base" "$DE_BASH" "$DE_SCRIPT" "$root" | sed -n 's/^WRAPPER=//p'
}

de_expect() {
    local label="$1" want="$2" got="$3"
    if [ "$got" = "$want" ]; then
        echo "  ok   : $label"
    else
        echo "  FAIL : $label"
        echo "         want: $want"
        echo "         got : $got"
        FAILED=1
    fi
}

# The regression: host php present, container up. The container must win.
de_expect "a running container beats an installed host php" \
    "docker compose exec -T php php" \
    "$(de_wrapper "$DE_TMP/bin-up" "$DE_WITH_PHP" "$DE_TMP/project")"

de_expect "a stopped stack falls back to host php" \
    "php" \
    "$(de_wrapper "$DE_TMP/bin-down" "$DE_WITH_PHP" "$DE_TMP/project")"

de_expect "no host php and a stopped stack still targets the container" \
    "docker compose exec -T php php" \
    "$(de_wrapper "$DE_TMP/bin-down" "$DE_NO_PHP" "$DE_TMP/project")"

de_expect "a checkout with no compose file uses host php" \
    "php" \
    "$(de_wrapper "$DE_TMP/bin-up" "$DE_WITH_PHP" "$DE_TMP/bare")"

# The five-line stdout contract the verify script and session card parse.
assert_output_contains "PEST_ENV=" bash "$DE_SCRIPT" "$DE_TMP/bare"

rm -rf "$DE_TMP"
