---
name: unopim-standards
description: Use when writing or changing any UnoPim code — the canonical rules for Laravel 13 and PHP 8.4 idiom, security, performance, scale, extensibility, localization and comments. Trigger phrases include "best practice", "standards", "laravel 13", "security", "performance", "scalable", "localization", "comments".
---

# UnoPim Standards

The canonical, judgment-level rules for all UnoPim code. Every rule cites a real
file under `packages/Webkul/` in the UnoPim checkout (`$UNOPIM`) as the pattern to
copy — follow the exemplar, never invent a generic-Laravel alternative. Mechanical
rules (anything a regex can catch) are enforced by hooks and by unopim-verify;
these files spend their words on the calls that need a model's judgment.

The installed checkout outranks these files: when the code in `$UNOPIM` disagrees
with a reference file, follow the checkout and report the drift so the skill can be
regenerated — these documents are a fallback snapshot, not the source of truth.

## Consistency first

Before applying any rule below, read what the surrounding code already does —
the sibling controller, the neighbouring DataGrid, the package's other
repositories. UnoPim offers more than one valid way to do most things, and the
right one is the one this package already uses. A second pattern for the same
job costs more than a suboptimal first one. These rules are the default when no
pattern exists yet, not a licence to convert code you happen to be editing.

## How to apply

1. Map the change to the reference files below, and read each mapped file before editing. Skip the unrelated ones.
2. Read the sibling files and the exemplar each rule cites. Follow the exemplar, not a generic-Laravel alternative.
3. Verify anything version-sensitive — a signature, a column, a component, a driver, a config key — against the checkout rather than recalling it (see below).
4. Make the smallest coherent change. Additive and backward compatible; no drive-by refactors of untouched lines.
5. Run the narrowest tests that cover the change, then the gates (unopim-verify).
6. Re-read the diff against every rule you mapped in step 1.

## Verify, do not recall

These files are a snapshot; the checkout is the truth. Anything countable or
version-bound — how many components exist, which drivers ship, which branch is
the release line, what a base class's signature is — must be read, not
remembered. Use the highest tier available and say which one you used; every
tier is optional and the last one always works.

| Tier | Available when | Use |
|---|---|---|
| UnoPim MCP | `unopim/mcp` is installed | `get_catalog_schema`, `get_database_schema`, `get_app_info`, `search_jobs` |
| Laravel Boost | `laravel/boost` is installed | `search-docs`, `database-schema`, `application-info` |
| Shell | always | `php artisan about`, `composer show --direct`, `git grep`, reading the file |

Never make a tool a precondition. A rule that only works with an MCP server
installed is a rule that does not work.

When the checkout disagrees with a reference file, follow the checkout and
report the drift so the skill can be regenerated.

## Comments

No comments inside method bodies, object/array literals, or Blade markup — not even a one-line "why". A genuinely non-obvious rationale belongs in the class or method PHPDoc, or in the commit message. No narration, no section dividers, no banners. Laravel framework internals do use narrative inline comments; that is framework style, not app/package style, and not this codebase's.

## Reference files

| File | Covers |
|---|---|
| [laravel13.md](laravel13.md) | Laravel 13 / PHP 8.4 idiom: promoted constructors, explicit types, attribute-based models + `casts()`, enums in `src/Enums/`, FormRequest, API Resources, named routes, `match()`, first-party over custom |
| [security.md](security.md) | Fail-open ACL and how to close it, `also_authorizes`, in-controller `bouncer()`, FormRequest `authorize()`, upload allowlists, DataGrid XSS, mass assignment, SSRF, CSV formula injection, secrets at rest, CSRF |
| [performance.md](performance.md) | Eager loading, no query in loops or Blade, `Cache::remember`, `RequestMemo`, the `scoped()` / `singleton()` / `bind()` decision table for Octane |
| [scale.md](scale.md) | Millions-of-rows discipline: `chunkById`/`lazyById`, keyset cursors, chunked `whereIn`, queued jobs, streaming migrations, indexes, pagination — plus portability: DB prefix in raw SQL, MySQL+PostgreSQL, optional Elasticsearch, server-agnostic code |
| [extensibility.md](extensibility.md) | Reuse-first: base classes, `core()`/`bouncer()`, events + proxy models as the extension mechanism, rule-of-two extraction, BC-preserving additive change, migration folders |
| [localization.md](localization.md) | `en_US` canonical, 33 locales, natural translations, `:placeholder` preservation, `unopim:translations:check` |
| [comments.md](comments.md) | The absolute comment bar, the PHPDoc contract, and the measured core baseline |

**REQUIRED SUB-SKILL:** Use unopim-verify before claiming any change is complete.
