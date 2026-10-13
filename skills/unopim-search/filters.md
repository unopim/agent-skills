# Filters and sorts on both branches

How a product grid, API or export filter reaches the database or Elasticsearch, and the exact steps to add one. Read `packages/Webkul/Product/src/Filter/FilterManager.php` and `packages/Webkul/Product/src/Traits/ProductQueryFilter.php` once before starting — together they are about 150 lines and they are the whole dispatch.

## How dispatch works

1. `ProductQueryBuilderFactory::make()` resolves `ElasticProductQueryBuilder` or `DatabaseProductQueryBuilder` from `config('elasticsearch.enabled')`.
2. `applyFilter($property, FilterOperators $operator, $value, $context)` asks `FilterManager` for a **property** filter first (`supportsProperty()`), then — if none and an attribute with that code exists — an **attribute** filter (`supportsAttribute()`, matched on attribute type).
3. `FilterManager` is built from tagged services, one tag set per branch:

| Branch | Property tag | Attribute tag |
|---|---|---|
| Database | `unopim.database.product.property.filters` | `unopim.database.attribute.filters` |
| Elasticsearch | `unopim.elasticsearch.product.property.filters` | `unopim.elasticsearch.attribute.filters` |

4. First match wins, in tag order. No match → `Exception: No matching filter found for property: …`. On the ES listing path that exception is caught and the grid silently falls back to the database, logging "Elasticsearch unavailable" — a missing ES filter looks like an outage, not a bug.
5. The free-text "all" box goes through `getSkuOrUnfilteredFilter()`, a separate pair (`SkuOrUniversalFilter` in each namespace).

Branch coverage is per **tag**, not per class: Database `TextFilter` covers text, textarea, select, multiselect, checkbox, image, file and gallery; Elasticsearch splits those across `TextFilter`, `OptionFilter` and `DefaultFilter`. When adding a type, check that BOTH attribute tags now have a filter whose `supportsAttribute()` accepts it.

## Base classes and contracts

| Kind | Database | Elasticsearch |
|---|---|---|
| Property | extend `Webkul\Product\Filter\AbstractPropertyFilter` | same class |
| Attribute | extend `Webkul\Product\Filter\Database\AbstractDatabaseAttributeFilter` | extend `Webkul\Product\Filter\ElasticSearch\AbstractElasticSearchAttributeFilter` |

- Property filter method: `applyPropertyFilter($property, $operator, $value, $locale = null, $channel = null, $options = []): static`.
- Attribute filter method: `addAttributeFilter($attribute, $operator, $value, ?string $locale = null, ?string $channel = null, $options = []): static`.
- Declare operators in the constructor's `$allowedOperators` (`Webkul\ElasticSearch\Enums\FilterOperators` cases). The builders reject any other operator before your method runs.
- `$this->queryBuilder` is a Laravel query builder on the Database branch and an `ElasticSearchQuery` on the ES branch (`where()` → `bool.filter`, `whereNot()` → `bool.must_not`, `must()` → `bool.must`, `orWhere()` → `bool.should` with `minimum_should_match: 1`, all under `query.constant_score.filter`). `setQueryManager()` refuses anything else when ES is enabled.
- Scoped paths: `getScopedAttributePath()` — `values.<scope>.<code>-<type>` on ES, an exploded JSON path on the database. Never hand-build either.
- Filter values arrive as a list even for single-value operators; use `scalarValue()`.

## Adding a filterable product property (a `products` column)

Example shape: core's completeness pair.

1. **Index it.** Confirm the column is in the indexed document and mapped with the right type — see [indexing.md](indexing.md) "Changing what is indexed". A property the index does not hold cannot be filtered on ES.
2. **Database filter** — copy `packages/Webkul/Product/src/Filter/Database/Property/CompletenessFilter.php`: qualify the column through `getSearchTablePath($options)`, prefix any raw fragment with `DB::getTablePrefix()`, bind values, no driver-specific SQL.
3. **Elasticsearch filter** — copy `packages/Webkul/Product/src/Filter/ElasticSearch/Property/CompletenessFilter.php`: same `supportedProperties`, same `allowedOperators`, same semantics. Map each operator deliberately:
   - `IS_EMPTY` on the DB side is `IS NULL`; on ES it is `whereNot(['exists' => ['field' => …]])`. An empty string is indexed as a value — decide whether it counts as empty on both sides and make them agree.
   - `RANGE` is inclusive on both sides (`BETWEEN` / `gte`+`lte`).
   - Booleans: `filter_var($v, FILTER_VALIDATE_BOOLEAN)` before an ES `terms`; on the DB side never compare with `=== 1` (PostgreSQL returns `true`).
   - Dates: ES `date` fields expect the mapping's format; reuse `getFormattedDateTime()` inherited from `Webkul\ElasticSearch\Filter\AbstractFilter`.
4. **Register** both in the four-tag scheme above — core in `registerTags()` of `packages/Webkul/Product/src/Providers/ProductServiceProvider.php`; a plugin in its own provider's `register()` as `packages/Webkul/Measurement/src/Providers/MeasurementServiceProvider.php` does.
5. **Expose it in the grid.** System-column filters for the product grid are defined once in `packages/Webkul/Admin/src/Filters/ProductPropertyFilters.php` (picker and grid share it) with `operators` from `ProductFilterOperators::optionsForType()`. Column keys and flags follow unopim-datagrid.
6. **Sort** — if `sortable`, add the property to `$sortMapping` in `setElasticSort()` of `packages/Webkul/Admin/src/DataGrids/Catalog/ProductDataGrid.php` (ES field name, `.keyword` for text). The DB side sorts by column name in `processRequestedSorting()`.
7. **Labels** — every label is a `trans()` key in all 33 locales (unopim-standards localization.md).

## Adding a filter for a new attribute type

Example shape: the Measurement package (a plugin adding the `measurement` type).

1. Database class extending `AbstractDatabaseAttributeFilter` and ES class extending `AbstractElasticSearchAttributeFilter`, both with `$supportedAttributeTypes = ['<type>']` — `packages/Webkul/Measurement/src/Filter/Database/MeasurementFilter.php` and its ES twin. Write ES clauses as instance calls (`$this->queryBuilder->where([...])`); the Measurement ES class's `::` calls are a defect, not a pattern.
2. Tag each into its branch's attribute tag from the plugin provider.
3. Operator group for the UI: a `product_filter_operators` config file with `types`, `control`, optional `range_control`, and `operators` (`['operator' => FilterOperators::X->value, 'label' => '<key>']`), merged recursively by the provider — `packages/Webkul/Measurement/src/Config/product_filter_operators.php`. Read by `packages/Webkul/Admin/src/Filters/ProductFilterOperators.php`.
4. Operator `label` values are keys under `admin::app.settings.data-transfer.exports.create.operators.*`. Reuse an existing key; a new one needs all 33 locales.
5. If the type needs a non-keyword ES mapping (numbers, dates, nested objects), add its suffix rule in `dynamicAttributeMappings()` and ship a `--fresh` reindex note — see [indexing.md](indexing.md).

## Read contract checklist

- [ ] Same `supportedProperties`/`supportedAttributeTypes` and `allowedOperators` on both classes
- [ ] Same row set for the same input, including empty, null, range bounds, booleans, multi-value
- [ ] ES returns ids only; rows are loaded from the database in ES id order (`orderByField`) — no rendering from `_source`
- [ ] Sortable → present in `setElasticSort()` mapping and sortable on the DB side
- [ ] Same `total` on both branches; pagination params honoured (`from`/`size` on ES)
- [ ] Mass-action id collection uses the ES filters with no DB fallback (`getMatchingIds()`)
- [ ] No per-request state in a singleton: the query lives on the builder (`packages/Webkul/Product/tests/Unit/Filter/ElasticSearch/QueryStateLeakTest.php`)

## Tests — both branches, every time

Database branch — real rows, assert results:

- Unit-level operator coverage: `packages/Webkul/Product/tests/Unit/Filter/Database/PropertyFilterOperatorsTest.php`, `packages/Webkul/Product/tests/Unit/Filter/Database/AttributeFilterOperatorsTest.php`.
- Through the grid: `config(['elasticsearch.enabled' => false])`, create products, `->json('GET', route('admin.catalog.products.index'), [...filters...])`, assert the returned records.

Elasticsearch branch — no cluster, assert the query body:

- Setup as in `packages/Webkul/Admin/tests/Feature/Catalog/ProductFilterWithElasticSearchTest.php`: enable ES, fake host, `ElasticSearch::shouldReceive('makeConnection')->andReturn(Mockery::mock('Webkul\ElasticSearch\Client\Fake\FakeElasticClient'))`, log in.
- Create fixtures with ES disabled, then re-enable — otherwise the observer calls the mock.
- `ElasticSearch::shouldReceive('search')->once()->withArgs(fn ($args) => …)` and assert the clause under `body.query.constant_score.filter.bool` (`filter` / `must_not`), then `->andReturn(['hits' => ['hits' => [], 'total' => ['value' => 0]]])`.
- `->once()` matters: a missing ES filter makes the grid fall back to the database and the ES assertion never runs. Without `once()` the test passes on the bug.
- Unit operator coverage: `packages/Webkul/Product/tests/Unit/Filter/ElasticSearch/AttributeFilterOperatorsTest.php`, `packages/Webkul/Product/tests/Unit/Filter/ElasticSearch/Property/StatusFilterTest.php`.

Pair them in one file with `describe('elasticsearch', …)` / `describe('database', …)` over the same `->with([...])` dataset, as `packages/Webkul/Admin/tests/Feature/Catalog/ProductMediaEmptinessFilterTest.php` does — one dataset guarantees both branches are asked the same questions.
