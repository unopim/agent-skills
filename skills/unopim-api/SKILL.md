---
name: unopim-api
description: Use when adding or changing an UnoPim REST API v1 endpoint under /api/v1/rest — AdminApi routes, api-acl.php permissions, an ApiDataSource listing with filters and pagination, ApiFormRequest validation, OAuth tokens, integrations and API keys, the unopim:passport:keys or unopim:passport:client commands, or Pest tests on ApiTestCase — including a plugin package that exposes its own REST endpoints. Trigger phrases include "REST API", "api endpoint", "v1/rest", "api-acl", "ApiDataSource", "passport", "oauth token", "API key", "integration", "This action is unauthorized".
requires: unopim-standards, unopim-exec, unopim-verify
---

# UnoPim REST API (AdminApi v1)

The REST API is `packages/Webkul/AdminApi`: Passport password-grant tokens issued to admin users, a per-key permission tree in `api-acl`, and a list engine (`ApiDataSource`) that owns pagination, filters and the response envelope. It is NOT a Laravel `routes/api.php` + `apiResource` + `JsonResource::collection` API. Copy the shape of an existing endpoint before writing a line.

**REQUIRED BACKGROUND:** unopim-standards for idiom, security, scale, localization and comments. unopim-exec before any artisan, pest or composer command. unopim-verify before calling anything done. A new package or connector scaffold: unopim-plugin-development.

## Reference files

| File | Read when |
|---|---|
| [endpoint-recipe.md](endpoint-recipe.md) | Adding an endpoint end to end: route, `api-acl` entry, DataSource, controller, FormRequest, translations, permission backfill |
| [auth-acl.md](auth-acl.md) | Tokens, integrations, `api.scope` semantics, the two passport commands, rate limits, a 401/403/406 you cannot explain |
| [contract.md](contract.md) | Response envelopes, pagination (page and `search_after`), the `filters` JSON grammar, error codes, structure cache and ETag |
| [testing.md](testing.md) | Pest tests with `ApiTestCase` / `ApiHelperTrait`, ACL tests, what every endpoint test must cover |

## Exemplars

| Concern | Copy from |
|---|---|
| Route group and middleware stack | `packages/Webkul/AdminApi/src/Routes/admin-api.php` |
| Resource routes, naming | `packages/Webkul/AdminApi/src/Routes/V1/settings-routes.php`, `packages/Webkul/AdminApi/src/Routes/V1/catalog-routes.php` |
| Permission entries | `packages/Webkul/AdminApi/src/Config/api-acl.php` |
| Simplest full CRUD controller | `packages/Webkul/AdminApi/src/Http/Controllers/API/Settings/LocaleController.php` |
| Controller that fires admin events | `packages/Webkul/AdminApi/src/Http/Controllers/API/Catalog/AttributeGroupController.php` |
| List engine | `packages/Webkul/AdminApi/src/ApiDataSource.php`; leaf: `packages/Webkul/AdminApi/src/ApiDataSource/Catalog/AttributeGroupDataSource.php` |
| Validation base | `packages/Webkul/AdminApi/src/Http/Requests/ApiFormRequest.php`; leaf: `packages/Webkul/AdminApi/src/Http/Requests/Settings/StoreLocaleRequest.php` |
| Response helpers | `packages/Webkul/AdminApi/src/Traits/ApiResponse.php` |
| Plugin package exposing REST routes + ACL | `packages/Webkul/Measurement/src/Routes/api.php`, `packages/Webkul/Measurement/src/Config/api-acl.php`, `packages/Webkul/Measurement/src/Providers/MeasurementServiceProvider.php` |
| Permission backfill migration | `packages/Webkul/Measurement/src/Database/Migrations/2026_07_29_120000_add_api_measurement_unit_permissions.php` |
| Tests | `packages/Webkul/AdminApi/tests/Feature/Settings/ApiLocaleTest.php`, `packages/Webkul/AdminApi/tests/Feature/Acl/ApiAclTest.php` |

The Measurement API is the exemplar for *wiring* only. Its controllers predate the conventions (`$request->validate()`, an unbounded `$this->repository->all()` list) — do not copy their bodies.

## Decision procedure

1. **Does it exist?** `git grep -n "admin.api.<entity>" -- packages` and read every `Routes/` file of the owning package. Measurement, for example, already ships `/measurement` and `/units`.
2. **Where does the route live?** Core entity: a `V1/*-routes.php` file required from `admin-api.php`. Plugin entity: the plugin's own `Routes/api.php` loaded under `Route::prefix('api')->middleware('api')`, with the full middleware stack copied from `admin-api.php` — never edit AdminApi from a plugin.
3. **Name the route** `admin.api.{entity}.{index|get|store|update|patch|delete}`. Use `get`, not `show`: `api.scope` resolves `*.get` to the `*.index` permission automatically; any other verb needs its own `api-acl` entry.
4. **Add the `api-acl` entry in the same change.** The API ACL is fail-closed — the inverse of the admin ACL. See [auth-acl.md](auth-acl.md).
5. **Listing → an `ApiDataSource` subclass.** Do not hand-roll `paginate()`, `count` or a `data` wrapper. See [contract.md](contract.md).
6. **Writes → a FormRequest extending `ApiFormRequest`**, a repository call, and the same `Event::dispatch('….before'/'….after')` pair the admin controller fires, so history, webhooks and indexing listeners still run.
7. **Responses → `ApiResponse` helpers** (`successResponse`, `modelNotFoundResponse`, `validateErrorResponse`, `storeExceptionLog`) with `trans()` messages.
8. **Test** with `ApiHelperTrait` headers, covering the permission-denied path. See [testing.md](testing.md).

## UnoPim-specific pitfalls

- **Unmapped route = 403 for every key**, including `permission_type = all`. `ScopeMiddleware` rejects a route before it checks the key type when no `api-acl` entry names it.
- **Splitting a permission strips access from existing keys.** Custom keys store permission keys as JSON. Moving a route to a new key needs a data migration that grants it to every key holding the old one — copy the Measurement backfill.
- **`api-acl` `name` values are translation keys** rendered as checkboxes on the integration edit page. Add them to `en_US` and all 33 locales.
- **The list engine owns the contract.** `limit` clamps to 1–100, sort is fixed to `$sortColumn`, `search_after` needs a monotonically increasing numeric `$primaryColumn`. Qualify both (`products.id`) once the query joins.
- **Legacy `=`/`IN`/`NOT IN` filters combine with `orWhere`; `>`/`<`/`BETWEEN` combine with AND.** Never assume two equality filters narrow each other. Datetime filters need the `'datetime'` type argument on `addFilter()`.
- **`$structureCacheGroup` caches list responses.** Set it only for slow-changing structure data AND wire invalidation (model `saved`/`deleted` → `StructureCache::bump()`), as `AdminApiServiceProvider::registerStructureCacheInvalidation()` does. Never on products or plugin data you cannot invalidate.
- **DataSources are stateful** (paginator, cursor, query). Resolve one per call with `app(XDataSource::class)`, never bind it as a singleton — Octane would leak one request's cursor into the next.
- **Elasticsearch is not on this path.** Product listings read the database through `ProductRepository::queryBuilderFromDatabase()`, so every endpoint behaves identically with `elasticsearch.enabled` on or off. Do not add an index branch: indexing is asynchronous, so a client would not see its own write in the next list call.
- **Rules name bare tables** (`unique:locales,code`). Laravel applies `DB_PREFIX`. Raw fragments follow unopim-standards scale.md.
- **`labels` keyed by locale code are validated for free** by the `request.locale` middleware against active locales. Keep that payload shape and you need no locale rule of your own.
- **An `Accept` header that excludes JSON** (`text/html`) gets 406 from `accept.json` before auth runs — check it first when a client reports 406.

## Verification

unopim-verify gates 1–4 and 6 always: a new `api-acl` name or message adds translation keys. Run the API suite through unopim-exec: `vendor/bin/pest packages/Webkul/AdminApi/tests` plus the owning package's tests, on MySQL and PostgreSQL. Gate 5 (Playwright) applies only if the integrations pages under `packages/Webkul/AdminApi/src/Resources/views/integrations` changed; otherwise state the skip.

Code review of an API change: unopim-code-review, plus the checklist at the end of [endpoint-recipe.md](endpoint-recipe.md).
