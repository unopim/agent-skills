---
name: unopim-search
description: Use when touching UnoPim product or category search — Elasticsearch indexing, the unopim:product:index, unopim:category:index or unopim:elastic:clear commands, config/elasticsearch.php, the ElasticSearch observers, a product filter or sort that must work with Elasticsearch on and off, or a product that saves but does not show up in the grid. Trigger phrases include "elasticsearch", "reindex", "index products", "unopim:product:index", "elastic:clear", "search not updating", "add a filter", "filterable field", "ES enabled", "ES disabled".
requires: unopim-standards, unopim-exec, unopim-verify
---

# UnoPim Search

Elasticsearch is an optional, derived index over the database. Every product filter exists twice — a Database class and an ElasticSearch class — selected at runtime by `config('elasticsearch.enabled')`. A change that touches one branch and not the other ships a grid that answers differently depending on `.env`.

**REQUIRED BACKGROUND:** unopim-standards (the "Elasticsearch is optional" rule lives in its scale.md — this skill is the how, not the rule), unopim-exec before any artisan or pest command (`ES_OVERRIDE`), unopim-verify before calling anything done. Listing-page columns and mass actions: unopim-datagrid. Importer indexing internals: unopim-data-transfer.

## Reference files

| File | Read when |
|---|---|
| [indexing.md](indexing.md) | Commands and flags, config keys, observers, mapping, the import path, why a write is not searchable yet, operating a reindex |
| [filters.md](filters.md) | Adding or changing a filterable/sortable product field on both branches, registration tags, operators, tests |

## Exemplars — open these, do not paraphrase them

- Branch selection: `packages/Webkul/Product/src/Factories/ProductQueryBuilderFactory.php`, `packages/Webkul/Product/src/Filter/FilterManager.php`
- Filter pair (property): `packages/Webkul/Product/src/Filter/Database/Property/CompletenessFilter.php` + `packages/Webkul/Product/src/Filter/ElasticSearch/Property/CompletenessFilter.php`
- Filter registration: `registerTags()` in `packages/Webkul/Product/src/Providers/ProductServiceProvider.php`; from a plugin, `packages/Webkul/Measurement/src/Providers/MeasurementServiceProvider.php`
- Grid consumer (ES ids → DB rows, DB fallback): `processRequest()` and `setElasticSort()` in `packages/Webkul/Admin/src/DataGrids/Catalog/ProductDataGrid.php`
- Indexers: `packages/Webkul/ElasticSearch/src/Console/Command/ProductIndexer.php`, `packages/Webkul/ElasticSearch/src/Console/Command/CategoryIndexer.php`, `packages/Webkul/ElasticSearch/src/Console/Command/Reindexer.php`
- Write path: `packages/Webkul/ElasticSearch/src/Observers/Product.php`, `indexBatch()` in `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/Importer.php`
- Both-branch tests: `packages/Webkul/Admin/tests/Feature/Catalog/ProductMediaEmptinessFilterTest.php`, `packages/Webkul/Admin/tests/Feature/Catalog/ProductFilterWithElasticSearchTest.php`

## There is no Scout

UnoPim does not use Laravel Scout. NEVER add `Searchable`, `toSearchableArray()`, `scout:import`, `scout:flush` or a Scout config file; NEVER call `Product::search()`. The client is the `Webkul\Core\Facades\ElasticSearch` facade (`packages/Webkul/Core/src/ElasticSearch.php`), queries are built by `Webkul\ElasticSearch\ElasticSearchQuery`, and indexing is the three console commands plus two observers.

## Decision procedure

1. **Classify the request.**
   - Filter or sort by something new → [filters.md](filters.md). First check `registerTags()`: `created_at`/`updated_at`, `status`, `sku`, `type`, family, parent, completeness and categories already have both-branch filters. Reuse beats a third copy.
   - "Saved but not in the grid / stale in search" → [indexing.md](indexing.md) "Why a write is not visible".
   - New indexed field or mapping change → [indexing.md](indexing.md) "Changing what is indexed", then a `--fresh` reindex.
   - New entity in its own index → `packages/Webkul/ElasticSearch/Guide.md` plus [indexing.md](indexing.md); it needs its own indexer command, observer, clear step in `Reindexer`, and a DB fallback for every read.
2. **Write both branches in the same change.** Database class and ElasticSearch class, same `supportedProperties`/`supportedAttributeTypes`, same `allowedOperators`, same semantics for empty, range bounds and booleans.
3. **Register both** under the matching tag pair. Order is first-match: `FilterManager` returns the first tagged filter whose `supportsProperty()`/`supportsAttribute()` says yes.
4. **Keep the read contract.** Same rows, same order, same total, same pagination on both branches (see "Same shape" below).
5. **Test both branches** — DB with real rows, ES by asserting the emitted query body against the mocked facade. A test for one branch is half a test.
6. **Ship the operational step.** If what is indexed changed, the PR description states the reindex command operators must run.

## Same shape, both branches

- The ES branch only answers *which ids, in what order, how many*. `ProductDataGrid::processRequest()` takes ids from `ResultCursorFactory`, then loads rows from the database with `whereIn('products.id', $ids)` ordered by `DB::rawQueryGrammar()->orderByField(...)`. Copy that; never render rows straight from `_source` — the index may lag the database.
- Sort: a new sortable system column needs an entry in the `$sortMapping` of `setElasticSort()`; an unmapped name falls through to the attribute-path lookup and sorts on nothing. The DB side sorts in `processRequestedSorting()`.
- ES paginates with `from`/`size` and `track_total_hits`; the DB side uses the DataGrid paginator. Both must report the same `total` for the same filters.
- Listing reads fall back to the database when the ES call throws. Mass-action id collection (`getMatchingIds()`) deliberately does NOT fall back — a fallback that drops ES-built filters would widen a delete to every product. Keep that asymmetry.

## UnoPim-specific pitfalls

| Pitfall | Consequence | Do instead |
|---|---|---|
| Writing products with `DB::table('products')->update()` or a raw `UPDATE` | Observer never fires; ES keeps the old document | Save through the repository/model, or reindex the affected ids; see [indexing.md](indexing.md) |
| Changing an indexed column without bumping `updated_at` | Incremental `unopim:product:index` compares only `updated_at` and skips the row | Run `unopim:product:index --fresh` |
| Asserting a just-saved product is searchable in the same request/test | ES is near-real-time; nothing in core forces a refresh | Assert the indexed payload or the query body, not search results |
| Using the `elastic-search-query` container singleton or facade to build a query | Clauses accumulate across requests under Octane/queue workers until ES rejects `maxClauseCount` (unopim#559) | Use the builder-owned `ElasticSearchQuery` — `packages/Webkul/Product/tests/Unit/Builders/ElasticProductQueryBuilderIsolationTest.php` |
| Calling `Observers\Product::disable()` without `finally` | The static flag outlives the job in a worker or Octane; indexing silently stops for every later save | try/finally exactly as the Importer does |
| Calling clause methods statically (`$this->queryBuilder::where(...)`) | PHP 8 Error: non-static method called statically | Instance calls, as in the core ElasticSearch filters. `packages/Webkul/Measurement/src/Filter/ElasticSearch/MeasurementFilter.php` currently does this — copy its registration, not its clause calls |
| Deriving index names from `DB::getTablePrefix()` | Two unrelated prefixes conflated | Index name is `strtolower(config('elasticsearch.prefix').'_products')` |
| Raw SQL in a Database filter without the table prefix | Breaks under `DB_PREFIX` | `DB::getTablePrefix()` as in the Database `CompletenessFilter` |
| Feeding `"1"`/`"0"` to a boolean ES field | ES 8 rejects the query | Coerce with `filter_var(..., FILTER_VALIDATE_BOOLEAN)` as the ES `StatusFilter` does |

Portability, prefix-safe SQL and comment rules for the Database branch come from unopim-standards; they are not repeated here. Search adds no routes on its own — if you add one (a reindex button, an async option endpoint), it is ACL-fail-open until covered; see unopim-plugin-development.

## Verification

unopim-verify, all gates. Specifically for search changes:

- Pest runs with `ES_OVERRIDE` from unopim-exec when no cluster resolves; the ES-branch tests mock the facade and do not need a cluster.
- New operator labels or grid strings → translations gate (33 locales) and Playwright.
- A mapping or indexed-payload change is not verified until `unopim:product:index --fresh` has run against a real cluster, or the PR states that it has not.
