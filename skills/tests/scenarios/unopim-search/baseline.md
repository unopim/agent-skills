# Baseline — unopim-search, without the skill

**Nature of this record:** a desk-run, not a live agent session. The plan below was written down from generic Laravel knowledge before the UnoPim search code was read, then checked line by line against UnoPim `origin/master`. The findings are what that check turned up.

## Task

> "Product grid: let admins filter products by an *Updated at* date range, and it has to work with Elasticsearch on. Also, our nightly price sync updates `products` with SQL — those products must show up correctly in search the next morning."

## Plan produced from generic Laravel knowledge

1. `composer require laravel/scout` plus an Elasticsearch Scout driver; add `use Searchable` to `Webkul\Product\Models\Product`; implement `toSearchableArray()` returning `sku`, `status`, `updated_at`.
2. `config/scout.php` with `driver => elastic`; `SCOUT_DRIVER=elastic` in `.env`.
3. In the product DataGrid: `if (config('scout.driver') === 'elastic')` → `Product::search($term)->where('updated_at', ...)->paginate()`, render the hits; else `whereBetween('updated_at', ...)` on Eloquent.
4. New `UpdatedAtFilter` class in `app/Filters`, wired in the grid.
5. After the nightly sync: `php artisan scout:import "Webkul\Product\Models\Product"`.
6. To reset: `php artisan scout:flush`.
7. Test: `Product::factory()->create()`, then `expect(Product::search($sku)->get())->toHaveCount(1)` in the same test, against a running cluster.

## What was wrong, checked against UnoPim master

| # | Generic plan | UnoPim reality | Severity |
|---|---|---|---|
| 1 | Install Scout, `Searchable` on Product | UnoPim has no Scout. Indexing is `packages/Webkul/ElasticSearch/src/Observers/Product.php` plus three console commands. Adding Scout creates a second, competing index of differently shaped documents that no filter reads | Wrong architecture, new dependency |
| 2 | Branch on `config('scout.driver')` | The switch is `config('elasticsearch.enabled')`, read by `packages/Webkul/Product/src/Factories/ProductQueryBuilderFactory.php` and `packages/Webkul/Product/src/Filter/FilterManager.php` | Grid ignores the real flag |
| 3 | Write a new `UpdatedAtFilter` | Already exists on both branches: `packages/Webkul/Product/src/Filter/Database/Property/DateTimeFilter.php` and `packages/Webkul/Product/src/Filter/ElasticSearch/Property/DateTimeFilter.php` (`created_at`, `updated_at`; `IN`, `RANGE`, `LESS_THAN`, `GREATER_THAN`), exposed in the grid by `packages/Webkul/Admin/src/Filters/ProductPropertyFilters.php` | Duplicated logic — a DRY defect |
| 4 | `app/Filters`, wired directly in the grid | Filters are tagged services (`unopim.{database,elasticsearch}.product.property.filters`) registered in `packages/Webkul/Product/src/Providers/ProductServiceProvider.php`; nothing in `app/` is ever resolved by `FilterManager` | Dead code |
| 5 | Render rows from search hits | `ProductDataGrid::processRequest()` takes only ids and total from ES, then loads rows from the database in ES order via `DB::rawQueryGrammar()->orderByField()` | Stale data shown; different shape per branch |
| 6 | No DB fallback on ES failure | The listing falls back to the database on an ES exception; mass-action id collection deliberately does not | Outage = broken grid |
| 7 | `scout:import` after the SQL sync | The command is `unopim:product:index`. It is incremental on `updated_at`: an SQL sync that does not set `updated_at` is skipped entirely. And the SQL write never fired the observer in the first place | The actual bug the user reported stays unfixed |
| 8 | `scout:flush` | `unopim:elastic:clear` — asks for confirmation, default no; with `-n` it deletes nothing. It does not rebuild | Script silently no-ops |
| 9 | Assert `search()` finds the product in the same test | No `refresh` anywhere in core; a write is searchable only after ES's refresh interval. Core tests never hit a cluster: they mock `Webkul\Core\Facades\ElasticSearch` with `Webkul\ElasticSearch\Client\Fake\FakeElasticClient` and assert the query body | Flaky test needing infrastructure CI lacks |
| 10 | One test, ES-on only | Core pairs `describe('elasticsearch')` / `describe('database')` over one dataset (`packages/Webkul/Admin/tests/Feature/Catalog/ProductMediaEmptinessFilterTest.php`) | Half the contract untested |
| 11 | — | Fixtures must be created with ES disabled and then re-enabled, or the observer calls the mock with no expectation | Test errors unrelated to the change |

## Failure the skill must prevent

Building a parallel search stack (Scout) and a duplicate filter for a field UnoPim already filters on both branches, while the reported bug — SQL writes that are invisible to the observer and to the incremental indexer — goes undiagnosed.
