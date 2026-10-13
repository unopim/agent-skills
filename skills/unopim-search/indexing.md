# Indexing

How documents get into Elasticsearch, how to rebuild them, and why a save is not searchable yet. Every command below goes through the unopim-exec wrapper.

## Configuration — `config/elasticsearch.php`

| Key | Env | Notes |
|---|---|---|
| `enabled` | `ELASTICSEARCH_ENABLED` | Default `false`. Every read, write and command checks it. The client itself throws `ElasticSearch is disabled in the env file.` when called while disabled, so an unguarded facade call is a 500 on a default install. |
| `connection` | `ELASTICSEARCH_CONNECTION` | `default` (hosts + user/pass), `api` (hosts + `ELASTICSEARCH_API_KEY`) or `cloud` (`ELASTICSEARCH_CLOUD_ID`). |
| `prefix` | `ELASTICSEARCH_INDEX_PREFIX`, else `APP_NAME` | Index names are `strtolower(prefix.'_products')` and `strtolower(prefix.'_categories')`. Two installs on one cluster with the same `APP_NAME` share an index unless the prefix is set. Unrelated to `DB_PREFIX`. |
| `total_fields_limit` | `ELASTICSEARCH_TOTAL_FIELDS_LIMIT` | Default 3000, floor 1000. Each localisable/channel attribute expands into its own field; a wide catalogue exhausts ES's default 1000 and documents are rejected. Applied on index create and re-applied by `ensureFieldLimit()` on every indexer run. |
| `debug_payload` | `ELASTICSEARCH_DEBUG_PAYLOAD` | Logs the full payload and empty-key paths of every rejected document. Turn on to diagnose, off afterwards. |
| `connections.*`, `caBundle`, `retries` | `ELASTICSEARCH_HOST`, `_USER`, `_PASS` | Read by `packages/Webkul/Core/src/ElasticSearch.php`. |

Failures log to the `elasticsearch` channel (`storage/logs/elasticsearch.log`), not `laravel.log`. Look there first.

Never add a config key for a behaviour core already reads from another file: import-time indexing is switched by `import.deferred_indexing` (`IMPORT_DEFERRED_INDEXING`) in `config/import.php`.

## The three commands

Registered in `packages/Webkul/ElasticSearch/src/Providers/ElasticSearchServiceProvider.php` (console only). All print `ELASTICSEARCH IS DISABLED.` (or `NOT ENABLED`) and exit 0 when the flag is off — a green exit is not proof anything was indexed.

### `unopim:product:index [--fresh] [--workers=N]`

`packages/Webkul/ElasticSearch/src/Console/Command/ProductIndexer.php`.

- Creates the index with settings and mappings if it does not exist; otherwise only raises the field limit.
- Walks `products` by id keyset in `BATCH_SIZE` (10000) rows and sends bulk requests of `BULK_DOCUMENTS` (500) — larger bulks trip ES indexing pressure (429).
- **Incremental by default:** fetches the indexed `updated_at` per id and re-sends only rows whose `updated_at` differs or that are missing. A row changed without touching `updated_at` is skipped.
- After an incremental run, `pruneStaleDocuments()` deletes documents whose product no longer exists (point-in-time + `search_after`).
- `--fresh` drops and recreates the index, sends every row and skips the comparison and prune. Use it after any mapping change, after a raw SQL bulk update, or when the index is suspect.
- `--workers=N` forks N processes over disjoint id ranges. Needs `pcntl`; without it the command warns and runs single-process.
- Zero products: deletes the index and recreates it empty.
- Failed ids are printed and logged; the run continues.

### `unopim:category:index`

`packages/Webkul/ElasticSearch/src/Console/Command/CategoryIndexer.php`. Same incremental `updated_at` comparison and stale-delete against `<prefix>_categories`. No `--fresh`; to rebuild, clear then index.

### `unopim:elastic:clear`

`packages/Webkul/ElasticSearch/src/Console/Command/Reindexer.php`. Deletes both the products and categories index for this prefix. It **asks for confirmation, default no** — run with `-n` (CI, deploy script) and it prints `Action canceled.` and deletes nothing. It does not rebuild; follow with both index commands.

### Runbook

| Situation | Run |
|---|---|
| First enable on an existing catalogue | `unopim:product:index` then `unopim:category:index` |
| Mapping or indexed-payload change shipped | `unopim:product:index --fresh` |
| Import ran with `IMPORT_DEFERRED_INDEXING=true` | `unopim:product:index` |
| Raw SQL / `DB::table()` bulk update of products | `unopim:product:index --fresh` (or the incremental run if the update also set `updated_at`) |
| Prefix changed, or index corrupt | `unopim:elastic:clear` (answer yes), then both index commands |
| Large catalogue, slow rebuild | `unopim:product:index --fresh --workers=4` |

## The write path

### Observers

`packages/Webkul/ElasticSearch/src/Observers/Product.php` and `packages/Webkul/ElasticSearch/src/Observers/Category.php`, attached in the provider's `boot()` to the concrete models.

- They fire on Eloquent `created`/`updated`/`deleted` only. `DB::table('products')->update()`, `upsert()`, `insert()` and raw statements never reach them — exactly what `packages/Webkul/Completeness/src/Jobs/ProductCompletenessJob.php` does when it writes `avg_completeness_score`, so that field in the index is only as fresh as the last product save or reindex.
- The product observer implements `ShouldHandleEventsAfterCommit`: inside a transaction nothing is sent until commit, and nothing on rollback. The category observer does not.
- Indexing is a synchronous call inside the request, with no `refresh` parameter anywhere in core. ES makes the document searchable after its refresh interval, so the same request — and usually the very next one — will not find it. Design responses from the database, not from a search.
- Variants are indexed with `resolvedValues()` so inherited parent values are filterable.
- `status` is cast to a real boolean before indexing (`sanitizeProductArray()`); the mapping is `boolean` and ES 8 rejects `0`/`1` strings.
- ES exceptions are caught and logged; a failed index never fails the save. That is intended — the database is authoritative.

### Disabling the product observer

`Observers\Product::disable()` / `enable()` toggle a **static** flag. It survives across jobs in a queue worker and across requests under Octane. The only correct shape is the one in `importBatch()` of `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/Importer.php`:

```php
ElasticProductObserver::disable();

try {
    $this->saveProductsData($batch);
} finally {
    ElasticProductObserver::enable();
}
```

Then index the affected rows yourself in bulk — never leave them unindexed.

### Imports

The product importer disables the observer per batch and indexes the batch afterwards in one bulk request (`indexBatch()`), unless the action is delete or `import.deferred_indexing` is on. `indexBatch()` selects a fixed column list (`id, sku, type, parent_id, attribute_family_id, values, status, created_at, updated_at`). A new `products` column you want filterable must be added there too, or imported products are indexed without it while UI-saved ones have it. Pipeline mechanics: unopim-data-transfer.

### Cost of a facade call

`Webkul\Core\ElasticSearch::__call()` builds a fresh client on every call and first attempts a `max_result_window` settings update. One facade call per product in a loop is two HTTP round-trips per row. Collect a `bulk` body and send it in chunks, as `ProductIndexer::bulkInChunks()` does.

## The document and its mapping

The indexer sends the raw `products` row (all columns) with `values` normalised by `packages/Webkul/ElasticSearch/src/Indexing/Normalizer/ProductNormalizer.php`; the observer sends `$product->toArray()`.

- Static mapping (`getUnopimProductMapping()`): `id`, `sku` (keyword with `sku_normalizer`), `status` (boolean), `type`, `attribute_family_id`, `attribute_family.*`, `created_at`, `updated_at`.
- Attribute values live under `values.common`, `values.locale_specific.<locale>`, `values.channel_specific.<channel>`, `values.channel_locale_specific.<channel>.<locale>`, each key suffixed with the attribute type by the normaliser: `name-text`, `price-price`, `release-date`. Dynamic templates map the suffix: `text`/`textarea` → text + `.keyword`, `price` → float, `date` → `yyyy-MM-dd`, `datetime` → `yyyy-MM-dd HH:mm:ss`, everything else → keyword. Option values (`select`, `multiselect`, `checkbox`) are forced to strings by the normaliser so a numeric-looking option code cannot map the field as a number.
- An ES filter must target that exact path. Build it with the base filter's `getScopedAttributePath()` rather than by hand.

### Changing what is indexed

1. A new attribute type: add its suffix rule to `dynamicAttributeMappings()` only if keyword is wrong for it (numbers, dates).
2. A new `products` column: add it to the static mapping with an explicit type (otherwise ES guesses the type from the first document it sees and later documents of another shape are rejected), and to the `indexBatch()` select list.
3. Both mapping methods are `private`/`protected` in core — a plugin cannot extend them; the change belongs in core.
4. Mappings apply only when the index is created. Existing installs keep the old mapping until `unopim:product:index --fresh`. Say so in the PR.
5. Update the expected mapping in `packages/Webkul/ElasticSearch/tests/Feature/ProductIndexTest.php`.

## Testing the indexing side

Copy the setup of `packages/Webkul/ElasticSearch/tests/Feature/ProductIndexTest.php`:

- `config([...])` with `elasticsearch.enabled` true, `prefix` `testing`, a fake host.
- `ElasticSearch::shouldReceive('makeConnection')->andReturn(Mockery::mock('Webkul\ElasticSearch\Client\Fake\FakeElasticClient'))` — the real client class is final; the fake exists for this.
- Create fixtures with ES **disabled**, then enable it — otherwise the observer fires against the mock with no expectation set.
- Assert on the bulk/index payload (`shouldReceive('bulk')->withArgs(...)`), not on a later search result.
- Field-limit and boolean regressions have their own tests: `packages/Webkul/ElasticSearch/tests/Feature/ProductIndexFieldLimitTest.php`, `packages/Webkul/ElasticSearch/tests/Feature/ProductBooleanStatusTest.php`.
