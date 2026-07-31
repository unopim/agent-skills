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
