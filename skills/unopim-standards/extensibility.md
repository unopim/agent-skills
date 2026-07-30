# Extensibility and reuse

Favor extensible, config-driven, additive design. Before writing any new
class, helper or query, check that core already provides it — extend or
inject, never re-implement, never copy-paste.

## Reuse-first table

| Need | Reuse — never re-implement |
|---|---|
| Data access | Extend `packages/Webkul/Core/src/Eloquent/Repository.php` — CRUD, criteria and caching inherited |
| Channels / locales / currencies | `core()->getAllChannels()` / `getAllLocales()` / `getAllActiveLocales()` / `getAllCurrencies()` (`packages/Webkul/Core/src/Http/helpers.php`) |
| Permissions | `bouncer()->hasPermission()` (`packages/Webkul/User/src/Http/helpers.php`) |
| Audit history | `packages/Webkul/HistoryControl/src/Traits/HistoryTrait.php` + `PresentableHistoryInterface` — never custom history tables |
| Admin listings | Extend `packages/Webkul/DataGrid/src/DataGrid.php` — implement only `prepareQueryBuilder()` + `prepareColumns()`; search/filter/sort/pagination inherited |
| Import / export | Extend `packages/Webkul/DataTransfer/src/Helpers/Importers/AbstractImporter.php` / `packages/Webkul/DataTransfer/src/Helpers/Exporters/AbstractExporter.php` — batching and job tracking inherited |
| Mass-action validation | Reuse `packages/Webkul/Admin/src/Http/Requests/MassDestroyRequest.php` / `MassUpdateRequest.php` |
| REST API validation | Extend `packages/Webkul/AdminApi/src/Http/Requests/ApiFormRequest.php` |
| Translatable models | Extend `packages/Webkul/Core/src/Eloquent/TranslatableModel.php` |

**Bad:** `DB::table('locales')->where('status', 1)->pluck('code')` —
re-implements a core helper. **Good:**
`core()->getAllActiveLocales()->pluck('code')`.

## Rule of two

The same statement block appearing in 2+ classes MUST be extracted: API and
credential logic into the module service, query logic into a repository
method, cross-cutting model behavior into a trait. Controllers, exporters,
importers and webhooks share logic through the service — never through paste.
One responsibility per class: controller = HTTP, service = business/API,
repository = persistence.

## Events and proxies are THE extension points

Core wraps every write in `{domain}.{entity}.{action}.{before|after}`
dispatches — exemplar
`packages/Webkul/Admin/src/Http/Controllers/Catalog/ProductController.php`
(`catalog.product.create.before` / `catalog.product.create.after`). To change
core behavior, add a listener; NEVER fork, copy or edit a core class. New
write paths in your own modules dispatch the same event pairs so others can
extend you.

Concord proxy models are the model-swap mechanism: a one-line proxy per model
(`packages/Webkul/Product/src/Models/ProductProxy.php`), a `Contracts`
interface, and all cross-package references via the proxy/contract — never a
hardcoded concrete class.

## Backward compatibility

Change is additive. Preserve existing extension points: never rename an event,
narrow a public method signature, or remove a config key another package may
read. Schema and data changes always go through migrations:

- Core packages keep migrations in `src/Database/Migrations/` (plural, under
  `src/`) — providers `loadMigrationsFrom` that path.
- Plugin-style packages (exemplar AiAgent) use root-level `Database/Migration/`
  (singular): `packages/Webkul/AiAgent/Database/Migration`.

Match the package you are editing; a migration in the wrong folder never loads.
Data backfills stream — see [scale.md](scale.md).

Config-driven behavior beats hardcoded behavior: new types, columns and menu
entries register through package config merged in the provider (menu config
merges under the key `'menu.admin'` — the admin sidebar reads only
`config('menu.admin')`, never `'menu'`).

## Octane safety

No request state in singletons or statics — bind request-stateful services
`scoped()`; the full decision table and exemplars are in
[performance.md](performance.md). Design every feature for queues and
horizontal scaling: no filesystem session assumptions, no in-process locks for
cross-request coordination.
