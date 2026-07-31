---
name: unopim-verify
description: Use when a change is about to be called done, or when asked to run the UnoPim verification gates — formatting, tests, static analysis, refactoring checks, end-to-end tests and translation completeness. Trigger phrases include "verify", "is this done", "run the gates", "pint", "pest", "larastan", "rector", "playwright", "translations check".
requires: unopim-exec
---

# UnoPim Verify

The completion gate. No change is "done" until all six gates pass, in this order. Resolve every command through unopim-exec first (container-versus-host wrapper, ports, database and Elasticsearch overrides).

## The six gates

1. **Pint** — `vendor/bin/pint --test` (preset laravel). Zero issues. Run `vendor/bin/pint` first to auto-fix.
2. **Pest** — `composer test`. All tests pass. CI also runs the suite on PostgreSQL (`phpunit.pgsql.xml`); DB-touching changes must not use MySQL-only SQL.
3. **Larastan** — `composer phpstan`. Zero errors.
4. **Rector** — `composer rector-dry`. Zero pending refactorings; apply with `composer rector` when it reports any.
5. **Playwright** — `cd tests/e2e-pw && npx playwright test`, REQUIRED when views, JS, or translations changed. Otherwise state the skip explicitly ("no view/JS/translation changes — Playwright skipped"); never skip silently.
6. **Translations** — `php artisan unopim:translations:check`. All 33 locales complete, zero errors.

## Usage

`verify.sh` runs all six in that order, skipping the ones the change does not
reach, and reports every gate's result in a summary:

```bash
mapfile -t CHANGED < <(git -C "$PROJECT_ROOT" diff --name-only HEAD)
skills/unopim-verify/verify.sh "$PROJECT_ROOT" --changed "${CHANGED[@]}"
```

It calls the binaries the composer scripts wrap — `vendor/bin/pest` and
`vendor/bin/phpstan analyse --memory-limit=2G` — so the `PEST_ENV` overrides can
be applied per invocation; rector still goes through `composer rector-dry`.

Quote the expansion — a path containing a space is one path, not two. With no
`--changed` list every gate applies. Exit 0 means every applicable gate passed;
it then writes `$PROJECT_ROOT/.verify-stamp` (unix seconds), which the Stop hook
reads to tell a fresh verification from a stale one. Rector is the one advisory
gate in the runner: a repo-wide dry run reports pre-existing debt this change did
not add, so it is reported loudly but does not set the exit status — a non-empty
rector report still has to be cleared before merge.

## Rules

- Two requirements have no diff-level check and are enforced differently — see [strict-mode.md](strict-mode.md): N+1 via `Model::preventLazyLoading()` in the test environment, and explicit types via a per-package Larastan level and ignore-list ratchet.
- Fix the root cause of every failure. NEVER suppress: no `ignoreErrors` or baseline entries in `phpstan.neon`, no `withSkip()` additions in `rector.php`, no inline `@phpstan-ignore`, no skipped or deleted tests to force green.
- Report each gate's result explicitly. A gate you did not run is a gate that failed.
- Never write `.verify-stamp` yourself. `verify.sh` writes it, and only after every applicable gate returned 0. Hand-writing it turns the Stop hook green with nothing behind it — that is falsifying the verification record, not passing it.
- Rector is advisory in the runner and blocking in this list, and the divergence is real: `composer rector-dry` is repo-wide, and scoping it to changed files would not fix that, because Rector reports per FILE — one line added to a legacy file fails on debt the change did not introduce. So promotion and return types in `packages/Webkul/Admin` and `packages/Webkul/AdminApi` (both skipped in `rector.php`) are review-only. Clear the rector report before merge yourself.
- If unopim-exec is unavailable, inspect `.env` and `docker-compose.yml` yourself, state which wrapper you chose, and continue — never skip a gate because the resolver skill is missing.
