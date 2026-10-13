# Response contract, pagination and filters

API clients — connectors, ERPs, the docs site behind `UNOPIM_API_DOCS_URL` — are coded against these shapes. Changing one on a shipped endpoint is a breaking change: call it out in the PR and the changelog (unopim-git), or add a new route. Never quietly "tidy" an envelope.

## Envelopes

| Response | Shape | Produced by |
|---|---|---|
| List, page mode | `{data: [...], current_page, last_page, total, links: {first, last, next, prev}}` | `ApiDataSource::responseFormatData()` |
| List, cursor mode | `{data: [...], search_after: <int\|null>, links: {next}}` | `ApiDataSource::responseFormatCursorData()` |
| Single record | the bare object, no wrapper | `response()->json($dataSource->getByCode($code))` |
| Write success | `{success: true, message}` plus optional `data`; 201 on create | `ApiResponse::successResponse()` |
| Not found | `{success: false, message}` 404 | `ApiResponse::modelNotFoundResponse()` |
| Validation / domain refusal | `{success: false, message, errors: {field: [..]}}` 422 | `ApiFormRequest::failedValidation()`, `ApiResponse::validateErrorResponse()` |
| Uncaught exception | `{success: false, message: "Internal Server Error"}` 500, logged | `ApiResponse::storeExceptionLog()` |
| Scope refusal | `{error: "This action is unauthorized"}` 403 | `ScopeMiddleware` |

All helpers are in `packages/Webkul/AdminApi/src/Traits/ApiResponse.php`.

### Where JsonResource fits

unopim-standards laravel13.md says API payloads go through Eloquent API Resources. Inside AdminApi, the list engine predates that rule: core DataSources shape rows in `formatData()`. Apply it like this:

- Endpoint backed by an `ApiDataSource` → keep the DataSource envelope. Shaping rows in `formatData()` is the house pattern there; do not flag it in review.
- Endpoint that does not fit the DataSource model (a relation-heavy read, an action result) → a `JsonResource`, as `packages/Webkul/AdminApi/src/Http/Resources/PublicationResource.php` is used by `packages/Webkul/AdminApi/src/Http/Controllers/API/Catalog/PassportController.php`. Its collection uses Laravel's own `{data, links, meta}` paginator shape. Document that it differs from the DataSource shape; do not mix the two within one resource family.

## Pagination

Query parameters read by `ApiDataSource::processRequest()`: `filters`, `limit`, `page`, `pagination_type`, `search_after`. Nothing else is read — a `sort` parameter is accepted and ignored.

| Parameter | Rule |
|---|---|
| `limit` | Default `$itemsPerPage` (10), clamped to 1..`$maxItemsPerPage` (100). Non-numeric falls back to the default. |
| `page` | Offset paging, runs a `COUNT(*)` for `total`/`last_page` |
| `pagination_type` | `page` or `search_after`; anything else is a 422 |
| `search_after` | Non-negative integer cursor; switches to keyset mode with `simplePaginate` (no count) |

- Order is always `$sortColumn ?: $primaryColumn`, `$sortOrder` (default `asc`). Keyset mode adds `where <cursor column> > search_after`, so the cursor column must be unique, numeric and match the sort. Override `cursorColumn()` only together with the sort.
- Use cursor mode for anything that can reach catalogue scale. Offset paging degrades linearly with depth (unopim-standards scale.md). Covered by `packages/Webkul/AdminApi/tests/Feature/ProductDeltaFilterAndCursorTest.php` and `packages/Webkul/AdminApi/tests/Feature/ApiDataSourceClampTest.php`.
- Raise `$maxItemsPerPage` only with a measured reason. Every row runs `formatData()` work.

## The `filters` grammar

`filters` is a JSON string, parsed by `packages/Webkul/AdminApi/src/Checker/QueryParametersChecker.php`:

```text
?filters={"status":[{"operator":"=","value":"1"}],"updated_at":[{"operator":">","value":"2026-01-31 00:00:00"}]}
```

| Operator | Value | Combines with the rest of the query as |
|---|---|---|
| `=` | scalar | `orWhere` |
| `IN`, `NOT IN` | array | `orWhereIn`, `orWhereNotIn` |
| `>`, `>=`, `<`, `<=` | scalar | `where` (AND) |
| `BETWEEN` | list of exactly two | `whereBetween` (AND) |

- A field or operator not registered with `addFilter()` is a 422 naming the property. Malformed JSON is a 400. Register only what the index supports.
- `addFilter($column, $operators, $filterTable = null, $type = null)` — pass `'datetime'` as the type to get date parsing and a 422 on a bad date.
- The OR semantics of the legacy operators are part of the shipped contract. Two equality filters widen the result, they do not narrow it. A new filter that must narrow uses the comparison operators, or a `setDefaultFilters()` constraint. Do not change `operatorByFilter()` for existing entities — clients depend on the current behaviour.
- The filter column is passed to the builder as a column name. Register only real, safe column names; never let a client-supplied key reach `addFilter()`.
- `processRequest()` reads `request()` once into a local array. Override the `process*` hooks, not `request()` reads scattered through the class.

## Structure cache and ETag

`packages/Webkul/AdminApi/src/Cache/StructureCache.php` caches whole list responses for entities whose class sets `$structureCacheGroup`. Keys are versioned per group, and a write bumps the version instead of deleting keys, so it works on any cache store and under Octane.

- Core groups: `StructureCache::GROUPS`. Each is bumped by model `saved`/`deleted` hooks in `AdminApiServiceProvider::registerStructureCacheInvalidation()`, and all of them after any import (`data_transfer.imports.completed`).
- A plugin DataSource that sets a group must bump it itself from its own model events or listeners: `app(StructureCache::class)->bump('<group>')`. Without that, clients read stale lists for up to `UNOPIM_API_STRUCTURE_CACHE_TTL` seconds. If there is no reliable write hook — raw `DB::table()` writes, imports below the model layer — leave the group null.
- Never cache products or anything per-user. The cache key is built from the query parameters only, not from the caller.
- `cache.headers:private;etag` adds an ETag over the response body and answers a matching `If-None-Match` with 304 (`packages/Webkul/AdminApi/tests/Feature/StructureCacheAndEtagTest.php`).

## Localized payloads

- Labels travel as `{"labels": {"en_US": "Size", "de_DE": "Größe"}}`. `ApiController::setLabels()` maps them into the repository's translation input; `ApiDataSource::getTranslations()` maps them back on read. Use both, so a round trip is lossless.
- Locale codes in `labels` / `locale_specific` are checked against the active locales by `LocaleMiddleware` before the controller runs.
- Server messages are `trans()` keys, resolved in the app locale. Field names in `errors` are never translated — clients key on them.
