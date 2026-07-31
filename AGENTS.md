# UnoPim Guidelines

UnoPim is a Laravel-based open-source Product Information Management (PIM) system built on a modular Concord package architecture. This file is a router: it states only the facts every task needs, then points at the skill that owns the depth. Standards questions (idiom, security, performance, scale, extensibility, localization, comments) are answered by `skills/unopim-standards` — do not restate or improvise rules here.

## Technology Stack

- **PHP**: 8.4+
- **Laravel**: v13
- **Concord**: modular package architecture (Konekt Concord)
- **Vue.js**: v3 — admin panel interactivity
- **Tailwind CSS**: v3 — semantic design tokens only
- **Vite**: v6
- **Elasticsearch**: v8.17+ — OPTIONAL search indexing, off by default
- **Laravel Passport**: v13.7 — REST API OAuth
- **Laravel Sanctum**: v4
- **Laravel Octane**: v2.3
- **Laravel Pint**: v1.29 — code style (preset: laravel)
- **Pest**: v5 — testing (MySQL and PostgreSQL suites in CI)
- **Playwright**: v1.58+ — E2E testing

## Core Packages (`packages/Webkul/`)

| Package | Purpose |
|---------|---------|
| **Admin** | Admin panel UI, controllers, DataGrids, config |
| **AdminApi** | REST API v1, OAuth |
| **AiAgent** | AI agent chat, credentials, tools (plugin-style package) |
| **AppUrlGuard** | Application URL guard middleware |
| **Attribute** | Product attribute system |
| **Category** | Category tree (nested-set) |
| **Completeness** | Product data quality scoring |
| **Core** | Foundation: models, repositories, helpers |
| **DataGrid** | Abstract DataGrid engine |
| **DataTransfer** | Import/export pipeline |
| **DebugBar** | Debug bar integration |
| **ElasticSearch** | Search indexing (optional) |
| **HistoryControl** | Audit trail |
| **Installer** | Installation wizard |
| **MagicAI** | AI content generation |
| **Measurement** | Measurement families and units |
| **Notification** | Event-driven notifications |
| **Product** | Product domain (Simple/Configurable) |
| **ProductPassport** | Digital product passport pages |
| **Publication** | Product publication workflow |
| **Resource** | Shared HTTP resource/routing support |
| **Theme** | Theme engine, view resolution |
| **User** | Admin users, roles, ACL |
| **Webhook** | Outgoing webhooks |

## Critical Conventions

- **Table names are bare** — migrations create `products`, `ai_agent_credentials`, not `wk_*`. The prefix comes from `env('DB_PREFIX', '')` and defaults to EMPTY; `DB::table()` and the schema builder apply it automatically. Raw SQL fragments (`DB::raw`, `selectRaw`, `whereRaw`, `orderByRaw`) MUST prepend `DB::getTablePrefix()` (see `packages/Webkul/Measurement/src/DataGrids/UnitDataGrid.php`).
- **Migration folder depends on the package style** — core packages keep migrations in `src/Database/Migrations/` (plural, loaded by their providers); plugin-style packages such as `packages/Webkul/AiAgent` use root-level `Database/Migration/` (singular). Match the package you are editing — a file in the wrong folder never loads.
- **Route middleware** — use `['admin']` only, never `['web', 'admin']`.
- **ACL is fail-open by route name** — routes absent from every `acl.php` are reachable by ALL logged-in admins. Every write route (store/update/mass_*/test-connection) must be ACL-covered. ACL config is flat arrays, no nested `children`; mass-action keys are snake_case.
- **Models with history** — implement `PresentableHistoryInterface` (with `getPresenters()`), use `HistoryTrait`, define `$historyTags`, and put secrets in `$auditExclude`.
- **Secrets at rest** — `'encrypted'` Eloquent cast + `#[Hidden]` + `$auditExclude` TOGETHER; `$auditExclude` alone is not encryption (see `packages/Webkul/AiAgent/src/Models/Credential.php`).
- **Controllers return JSON** — store/update/delete return `JsonResponse` with `redirect_url` and `message`.
- **FormRequest validation** — the standard for all NEW code: type-hint a FormRequest, never inline `$request->validate()`. Legacy inline calls exist in core; never add another.
- **Repository pattern** — all DB queries go through `*Repository` classes, not direct Eloquent in controllers.
- **Proxy models** — Concord uses proxy models for extensibility (`ProductProxy`, `AdminProxy`). The admin-user model is `Admin`, not `User` — there is no `UserProxy`.
- **Connectors use cURL** — native cURL, not Guzzle or Laravel HTTP.
- **No hardcoded strings** — all user-facing text via `trans('package::file.key')`; `en_US` is canonical, propagate to all 33 locales (there is no bare `en` directory).
- **Comments** — ZERO comments inside method bodies, array literals, or Blade markup. The core baseline: `packages/Webkul/Product/src/Repositories/ProductRepository.php` (18 methods, 0 inline comments) and `packages/Webkul/Product/src/Type/AbstractType.php` (988 lines, 0 inline comments). One-line imperative PHPDoc summaries; a non-obvious "why" goes in the class/method PHPDoc or the commit message, never inline.
- **Portability** — MySQL AND PostgreSQL are both supported: no MySQL-only SQL (`GROUP_CONCAT`, backticks, `FIELD()`); use `DB::rawQueryGrammar()` (see `packages/Webkul/Core/src/Helpers/Database/Grammars/MySQLGrammar.php` and `PostgresGrammar.php`) or branch on `DB::getDriverName()`. Elasticsearch is optional — gate on `config('elasticsearch.enabled')` with a database fallback (see `packages/Webkul/Product/src/Factories/ProductQueryBuilderFactory.php`). Package code is web-server-agnostic (Apache, Nginx, Docker).

## Skills Activation

Activate the relevant skill whenever you work in its domain — do not wait until you are stuck.

- `unopim-standards` — the canonical rules for all UnoPim code: Laravel 13 / PHP 8.4 idiom, security, performance, scale, extensibility, localization, comments.
- `unopim-exec` — resolve the workspace environment (container vs host, ports, DB/Elasticsearch overrides) before running any shell command.
- `unopim-verify` — the completion gate; see below.
- `unopim-plugin-development` — new packages, modules, and third-party connectors.
- `unopim-datagrid` — admin listing pages (DataGrid classes and their Blade views).
- `unopim-data-transfer` — import/export pipeline, exporters, importers, validators.
- `unopim-code-review` — reviewing changes against the standards.
- `unopim-git` — branches, commit messages, pull requests.

## Verification

**REQUIRED SUB-SKILL:** unopim-verify — six gates, all must pass before any change is called done:

1. `vendor/bin/pint --test`
2. `composer test` (CI also runs the PostgreSQL suite)
3. `composer phpstan`
4. `composer rector-dry`
5. `cd tests/e2e-pw && npx playwright test` when views, JS, or translations changed — otherwise state the skip explicitly
6. `php artisan unopim:translations:check`
