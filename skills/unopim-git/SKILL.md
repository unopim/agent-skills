---
name: unopim-git
description: Use when creating an UnoPim branch, writing a commit message, or opening a pull request against the UnoPim repository. Trigger phrases include "branch", "commit", "commit message", "PR", "pull request", "changelog".
requires: unopim-verify
---

# UnoPim Git Workflow

Branching, commits, and pull requests for the UnoPim repository. The authoritative
sources are `.github/CONTRIBUTING.md` and `.github/PULL_REQUEST_TEMPLATE.md` in the
UnoPim checkout ($UNOPIM) — when this skill and those files disagree, the repo files win.

## Branches

- Target `master`, unless a maintainer requests a backport to a version branch (e.g. `2.1`).
- One fix per branch, named with the issue ID: `issue-1234`.
- Lowercase with hyphens. When there is no issue, prefix by intent:
  `feature/short-description`, `refactor/short-description`, `test/short-description`.

## Commit Messages — Conventional Commits (MANDATORY)

`.github/CONTRIBUTING.md` mandates the Conventional Commits format, referencing the
issue in parentheses at the end of the subject:

```
type(scope): imperative description (#1234)
```

- `type`: feat, fix, refactor, perf, test, ci, chore, docs.
- `scope`: the package or area touched — admin, product, attribute, datagrid, core.
- Subject: imperative mood, lowercase, no trailing period, 72 characters or fewer.
- Optional body after a blank line explains why, not what.

Good (taken from real history):

```
fix(admin): prevent duplicate SKU on product creation (#1234)
feat(product): configurable association types with per-link fields (#570)
fix(attribute): copy a cloned family's attribute mappings in the database
```

Bad — NEVER write commits in these shapes:

```
Fixed #1234 - Prevent duplicate SKU     <- legacy format; not the repo convention
Update ProductController.php            <- no type(scope), describes the file not the change
fix: stuff                              <- no scope, vague
```

## Pull Requests

PR titles use the same conventional `type(scope): description` shape as commits.
The closing keyword (`Fixes #123`) belongs in the body's Issue Reference section,
NEVER in the title.

The PR body MUST contain all SIX sections of `.github/PULL_REQUEST_TEMPLATE.md`, in
order: **Issue Reference, Description, How To Test This?, Screenshots, Checklist,
Documentation**. Do not omit a section and do not rename "How To Test This?".

```bash
gh pr create --title "fix(admin): prevent duplicate SKU on product creation (#1234)" --body "$(cat <<'EOF'
## Issue Reference
Fixes #1234

## Description
Adds a unique-SKU guard to the product store flow so a double submit no longer
creates two products with the same SKU.

## How To Test This?
1. Open Catalog > Products and create a product with SKU `test-sku`.
2. Submit the create form twice in quick succession.
3. Only one product exists; the second submit returns a validation error.

## Screenshots
N/A — no UI change.

## Checklist
- [x] `vendor/bin/pest` passes locally
- [x] `vendor/bin/pint --test` reports no style issues
- [x] Tailwind classes are reordered
- [x] New user-facing strings use translation keys (all 33 locales)
- [x] Target branch is `master` (unless a maintainer requested a backport)

## Documentation
- [ ] My pull request requires an update on the documentation repository.
EOF
)"
```

- UI changes: replace the Screenshots placeholder with before/after images or a
  short recording. Otherwise the template allows removing that section's content,
  but keep the heading with `N/A`.
- Tick the Documentation box and describe what must change when docs are affected.
- Only tick a Checklist box after actually running the command it names.

## CI Gates — SIX gates on every push and PR

GitHub Actions runs six gates; treat every one as blocking before you push:

1. `vendor/bin/pint --test` — code style (linting_tests.yml)
2. Pest suite on MySQL AND PostgreSQL — `composer test` (pest_tests.yml, pest_tests_pgsql.yml)
3. Playwright E2E — `cd tests/e2e-pw && npx playwright test` (playwright_test.yml)
4. Larastan — `composer phpstan` (static_analysis.yml). NEVER add ignoreErrors to pass.
5. Rector — `composer rector-dry` (static_analysis.yml; dry-run job is advisory in CI —
   fix its findings anyway, NEVER extend withSkip).
6. `php artisan unopim:translations:check` — all 33 locales complete (translation_tests.yml)

**REQUIRED SUB-SKILL:** Use unopim-verify before pushing any branch or opening a PR —
it runs these same gates locally, in order, with workspace-correct commands. NEVER
push with a failing gate and NEVER claim a PR is ready without the verify pass.

## Contributing Process

- Security vulnerabilities: NEVER open a public GitHub issue — follow `SECURITY.md`.
- Bug fixes: search existing issues first; fork, branch per issue, PR to `master`.
- Features: open a feature request issue before implementing.
