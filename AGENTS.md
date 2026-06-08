<unopim-guidelines>
=== foundation rules ===

# UnoPim Guidelines

UnoPim is a Laravel-based open-source Product Information Management (PIM) system. These guidelines are curated for developing with UnoPim and its modular Concord package architecture.

## Foundational Context

This application is an **UnoPim** PIM platform built on Laravel 12 with a modular Concord architecture. You must be familiar with both Laravel and UnoPim's package structure.

### Technology Stack

- **PHP**: 8.3+
- **Laravel**: v12
- **Concord**: modular package architecture (Konekt Concord)
- **Vue.js**: v3 — admin panel interactivity
- **Tailwind CSS**: v3 — styling
- **Vite**: v6
- **Elasticsearch**: v8.17+ — search indexing
- **Laravel Passport**: v12.2 — REST API OAuth
- **Laravel Sanctum**: v4
- **Laravel Octane**: v2.3
- **Laravel Boost**: v2
- **Laravel Pint**: v1.19 — code style (preset: laravel)
- **Pest**: v3 — testing
- **Playwright**: v1.52 — E2E testing

### UnoPim Core Packages

UnoPim uses a modular package structure in `packages/Webkul/`:

| Package | Purpose |
|---------|---------|
| **Admin** | Admin panel UI, controllers, DataGrids, config |
| **AdminApi** | REST API v1, OAuth |
| **Attribute** | Product attribute system |
| **Category** | Category tree (nested-set) |
| **Completeness** | Product data quality scoring |
| **Core** | Foundation: models, repositories, helpers |
| **DataGrid** | Abstract DataGrid engine |
| **DataTransfer** | Import/export pipeline |
| **ElasticSearch** | Search indexing |
| **HistoryControl** | Audit trail |
| **Installer** | Installation wizard |
| **Inventory** | Stock/inventory management |
| **Product** | Product domain (Simple/Configurable) |
| **User** | Admin users, roles, ACL |
| **Webhook** | Outgoing webhooks |

## Critical Conventions

These conventions differ from generic Laravel / Bagisto and MUST be followed:

- **Table prefix** — all tables use the `wk_` prefix (e.g. `wk_products`). The prefix is added automatically by Laravel config; reference unprefixed names in `DB::table()`.
- **Migration folder** — package migrations live in `Database/Migration/` (singular, no `s`).
- **Route middleware** — use `['admin']` only, never `['web', 'admin']`.
- **Models with history** — implement `PresentableHistoryInterface` and use `HistoryTrait` for audit tracking.
- **Controllers return JSON** — store/update/delete return `JsonResponse` with `redirect_url` and `message`.
- **FormRequest validation** — always type-hint FormRequest classes; never inline `$request->validate()`.
- **Repository pattern** — all DB queries go through `*Repository` classes, not direct Eloquent in controllers.
- **Proxy models** — Concord uses proxy models for extensibility (`ProductProxy`, `UserProxy`).
- **Connectors use cURL** — native cURL, not Guzzle or Laravel HTTP.
- **Sensitive fields** — go in `$auditExclude`, not `Crypt::encryptString()`.
- **ACL config** — flat arrays, no nested `children`.
- **No hardcoded strings** — all user-facing text via `trans('package::file.key')`; propagate keys to all supported locales.

## Skills Activation

This project has domain-specific skills available. You MUST activate the relevant skill whenever you work in that domain — don't wait until you're stuck.

- `unopim-plugin-development` — Plugin, package, and connector development — the comprehensive module-building skill. Activates when creating modules/packages, service providers, models, repositories, controllers, routes, ACL, menus, migrations, credentials, cURL HTTP clients, attribute mapping, or scaffolding a third-party connector. Reference sections: `@quickstart` (day-1 checklist), `@core` (package structure, service providers, config), `@backend` (PHP classes, models, repositories, events), `@credentials` (credential storage, connection testing, history), `@http` (cURL ApiClient, BasicAuth/OAuth), `@mapping` (attribute mapping + history).

- `unopim-datagrid` — Implement DataGrid classes for admin listings with search, filter, sort, actions, and mass actions.

- `unopim-data-transfer` — Import/export pipeline and connector export/import workflow. Activates when configuring imports/exports, debugging job pipelines, creating data transfer profiles, or building connector export jobs (`@export-workflow` section: exporters.php, quick_exporters.php, importers.php, Exporter classes, Validators, queue jobs).

- `unopim-code-review` — Code review. Activates when reviewing changes, checking standards compliance, flagging violations, or performing PR reviews.

- `unopim-git` — Git and GitHub operations (branches, commit messages, pull requests, changelog).

- `unopim-dev-cycle` — Development workflow (tests, lint, Pint, build, Pest, coverage).

## Mandatory Development Pipeline

Every task MUST follow this pipeline before completion:

1. **Write Pest tests** — unit/feature tests for code being developed; tests must pass.
2. **Run Laravel Pint** — `vendor/bin/pint` after every change, then `vendor/bin/pint --test` (zero issues required).
3. **Run Playwright E2E** — for UI/admin flows, `cd tests/e2e-pw && npx playwright test`.
4. **Verify translations** — `php artisan unopim:translations:check` must pass with zero errors.

Never skip any step. Never commit code that fails tests or has formatting issues.
</unopim-guidelines>
