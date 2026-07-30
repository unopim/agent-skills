---
name: unopim-plugin-development
description: Use when creating a new UnoPim package, module or third-party connector — service providers, models, repositories, controllers, routes, ACL, menus, migrations, credential storage, cURL clients or attribute mapping. Trigger phrases include "new module", "new package", "connector", "scaffold module", "service provider", "credentials", "attribute mapping", "WooCommerce", "Shopify", "Shopware".
requires: unopim-standards, unopim-datagrid, unopim-data-transfer, unopim-exec, unopim-verify
license: MIT
---

# UnoPim Plugin Development

Build a self-contained Concord package under `packages/Webkul/{ModuleName}/` — a feature
module or a third-party connector (Shopify, Shopware, any REST API). The living connector
reference is `packages/Webkul/AiAgent`; when a template here and that package disagree,
the package wins.

## Reference files — load only what the current phase needs

| File | Load when |
|---|---|
| [quickstart.md](quickstart.md) | Starting a new module — the day-1 ordered checklist |
| [package-structure.md](package-structure.md) | Directory layout, composer.json, service providers, config merging, migrations |
| [backend.md](backend.md) | Models, contracts, repositories, events, Octane-safe bindings |
| [credentials.md](credentials.md) | Credential storage, encryption at rest, history/audit, test-connection endpoint |
| [http-client.md](http-client.md) | cURL ApiClient, auth strategies, SSRF guard, container binding |
| [admin-ui.md](admin-ui.md) | Blade views — components, theme tokens, CRUD summary |
| [crud-patterns.md](crud-patterns.md) | The admin CRUD envelope — save bar, modal create, breadcrumbs, page skeleton |
| [acl-security.md](acl-security.md) | ACL coverage, FormRequest authorization, uploads, CSRF, secrets |
| [mapping.md](mapping.md) | Attribute-mapping screens for a connector |

**REQUIRED SUB-SKILL:** Use unopim-datagrid for any admin listing page.
**REQUIRED SUB-SKILL:** Use unopim-data-transfer for Exporter, Importer and Validator classes.
**REQUIRED SUB-SKILL:** Use unopim-verify before claiming any change is complete.

## Critical conventions (details and exemplars in the reference files)

- Target Laravel 13 / PHP 8.4: promoted constructor properties, explicit return types,
  `#[Fillable]`/`#[Table]`/`#[Hidden]` attributes plus a `casts(): array` method on models.
- Providers register in `bootstrap/providers.php` — `config/app.php` has NO providers array.
- Menu config merges into the `'menu.admin'` key, NEVER `'menu'` — the admin sidebar reads
  only `config('menu.admin')`, so a module merged into `'menu'` never appears.
- Plugin packages keep migrations in root-level `Database/Migration/` (singular); core
  packages use `src/Database/Migrations/` (plural). Table names are written bare — the
  prefix comes from `env('DB_PREFIX', '')`, whose default is EMPTY.
- Route middleware is `['admin']` only. ACL enforcement is fail-open by route name: every
  write route (store, update, destroy, mass_*, test-connection) MUST appear in
  `Config/acl.php` or any logged-in admin can call it. See [acl-security.md](acl-security.md).
- A history/audit model MUST implement its module contract, `PresentableHistoryInterface`
  (with `getPresenters()`), and the OwenIt `Auditable` contract, use `HistoryTrait`, and
  define `$historyTags` — omitting any one is a fatal at class load or on first save.
- Secrets at rest need the `'encrypted'` cast + `#[Hidden]` + `$auditExclude` TOGETHER.
  `$auditExclude` alone stores plaintext.
- Connector HTTP is native cURL — never Guzzle, never the `Http` facade. Stateful clients
  bind `scoped()`, never `singleton()` (this stack runs Octane).
- Localization lives in `Resources/lang/{locale}/` with `en_US` canonical across 33
  locales — a bare `en/` directory never loads.
- NO comments inside method bodies, array literals, route groups or Blade markup. A
  method PHPDoc is a one-line imperative summary.
- NO hardcoded user-facing strings — `trans('{module}::app.…')` for every label, message
  and placeholder.
