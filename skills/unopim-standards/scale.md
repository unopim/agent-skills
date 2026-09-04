# Scale

Assume millions of product rows, 50k-attribute datasets and 10k-node category
trees. Code that hydrates a catalog table whole is a bug even when the demo
database is small.

## Contents

- The rules
- Eager loading is a scale rule, not a micro-optimisation
- Portability

## The rules

- **No unbounded reads.** Never `->all()`, `->get()` or `->pluck()` on
  products, product values or any unbounded set without a `limit`/`whereIn`.
  `Model::all()` and `$someRepository->all()` are hook-blocked; the small
  config-shaped entities below (channels, locales, currencies, roles, attribute
  families and groups) are exempt from that block because this file permits
  them. An unbounded `->get()` at the end of a fluent chain is NOT hook-blocked
  and cannot be — the terminating `->get();` sits on its own line and no
  single-line regex can tie it to the table named four lines up. That one is
  yours to catch, and it is the commonest way a million-row table gets loaded.
- **Batch scans use keyset pagination.** `chunkById()` or `lazyById()` on an
  ordered id — exemplar
  `packages/Webkul/Completeness/src/Jobs/BulkProductCompletenessJob.php`:

```php
$this->productRepository
    ->select('id')
    ->where('attribute_family_id', $this->familyId)
    ->orderBy('id')
    ->chunkById(self::BATCH_SIZE, function ($products) use (&$allIds): void {
        foreach ($products as $product) {
            $allIds[] = $product->id;
        }
    });
```

- **Export sources stream.** A custom exporter `getResults()` returns an
  id-cursor (`where('id', '>', $lastId)->orderBy('id')->limit($batchSize)`) —
  exemplar `packages/Webkul/DataTransfer/src/Helpers/Sources/Export/ProductCursor.php`.
  The `packages/Webkul/DataTransfer/src/Helpers/Exporters/AbstractExporter.php`
  default (`$this->source->all()`) is acceptable ONLY for small entities
  (attributes, categories, families) — never products or values.
- **Chunk bulk lookups.** `array_chunk($keys, 1000)` + `whereIn`, never one
  giant `IN ()` and never a per-row query — exemplar
  `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/SKUStorage.php`.
- **Queue heavy work.** Any operation spanning more than one batch is a
  `ShouldQueue` job (`packages/Webkul/DataTransfer/src/Jobs/Export/ExportBatch.php`,
  `BulkProductCompletenessJob`), never inline controller work. The worker runs
  `--queue=webhooks,default,system,completeness,publication`; put a new job
  family on its own queue when it can flood the default one.
- **Data migrations stream too.** Backfills use `cursor()` or `chunkById()` —
  exemplar `packages/Webkul/Product/src/Database/Migrations/2024_11_28_174850_migrate_status_value_from_values_column_to_status_column.php` —
  never a whole-table UPDATE-from-SELECT in PHP.
- **Index what you query.** Every column a DataGrid filters or sorts on, every
  FK, every `where`/`orderBy` column of a bulk scan; composite indexes for hot
  pairs — exemplar migration in
  `packages/Webkul/Completeness/src/Database/Migrations/`.
- **Search is Elasticsearch, not `LIKE`.** Product search goes through the
  query-builder factory (below), never a `LIKE '%term%'` scan.
- **Paginate everything user-facing.** Prefer `withCount()` over loading a
  relation to count it.

## Eager loading is a scale rule, not a micro-optimisation

The rule and its exemplars live in [performance.md](performance.md); what
belongs here is the consequence. An N+1 is invisible on a demo database and
linear on a real one: one extra query per row is 40 queries on a seeded catalog
and 40,000 on a real page of it. Eager-load every relation the code path
traverses, nested where the traversal is nested — exemplar
`packages/Webkul/Product/src/Repositories/ProductAssociationRepository.php`,
whose `getLinksForProduct()` loads `relatedProduct.attribute_family` precisely
so `normalizeWithImage()` cannot lazy-load once per link.

No hook can see this. `grep-gate` matches single added lines with no block or
scope awareness, so `$row->relation->name` inside a `foreach` is
indistinguishable from the same expression on an eager-loaded row. Eager loading
is caught by review and by tests, never by an exit code.

**Prove it with a query budget.** The mechanism this codebase already uses for
exactly this: count queries while exercising the path, then assert the count
does not scale with the row count — exemplars
`packages/Webkul/Admin/tests/Feature/ProductEditQueryCountTest.php` and
`packages/Webkul/Product/tests/Unit/Type/ConfigurableUpdateVariantQueryBudgetTest.php`.

```php
$queries = 0;

DB::listen(function () use (&$queries): void {
    $queries++;
});

get(route('admin.catalog.products.edit', ['id' => $product->id]))->assertOk();
```

Build the fixture twice at two sizes and assert the delta is bounded. A test
that only asserts a 200 response proves nothing about N+1. Any new listing,
edit page, exporter or API resource that traverses a relation ships with one of
these.

## Portability

UnoPim runs on MySQL 8 AND PostgreSQL 14+, with a configurable table prefix,
with Elasticsearch optional, behind Apache or Nginx, bare or in Docker. Code
that works in only one configuration is a bug.

### Table prefix in raw SQL

There is no fixed prefix: tables are bare (`products`, `ai_agent_credentials`)
and the prefix comes from `env('DB_PREFIX', '')`, default empty. `DB::table()`
and the schema builder prefix automatically; raw fragments (`DB::raw`,
`selectRaw`, `whereRaw`, `orderByRaw`) do NOT. Prepend `DB::getTablePrefix()`
there, captured once at the top of the method — exemplars
`packages/Webkul/Measurement/src/DataGrids/UnitDataGrid.php`,
`packages/Webkul/Admin/src/Helpers/Dashboard.php`. Never hardcode `wk_` or any
other prefix.

### No MySQL-only SQL

Never `GROUP_CONCAT`, `FIELD()`, backtick quoting, `DATE_FORMAT`, `CAST AS
SIGNED` or `JSON_EXTRACT('$..')` in raw fragments. Use the core macro
`DB::rawQueryGrammar()` — it resolves
`packages/Webkul/Core/src/Helpers/Database/Grammars/MySQLGrammar.php` or
`packages/Webkul/Core/src/Helpers/Database/Grammars/PostgresGrammar.php` by
driver and exposes `groupConcat()`, `concat()`, `coalesce()`, `length()`,
`castToText()`, `jsonExtract()`, `jsonContains()`, `orderByField()`,
`getRegexOperator()`, `getBooleanValue()`. Usage exemplar:
`packages/Webkul/Admin/src/DataGrids/Catalog/ProductDataGrid.php`.

```php
$prefix = DB::getTablePrefix();

$query->selectRaw(DB::rawQueryGrammar()->groupConcat($prefix.'ao.code', 'options'));
```

A driver difference the grammar does not cover gets an explicit
`DB::getDriverName() === 'pgsql'` branch — never an assumed driver. PostgreSQL
is a first-class CI target: run `vendor/bin/pest -c phpunit.pgsql.xml` after
DB-touching work (via unopim-verify).

### Three drivers, not two

`config/database.php` ships `mysql`, `mariadb` and `pgsql`. Laravel reports
MariaDB under its own driver name, so `DB::getDriverName()` returns the literal
`mariadb` and never `mysql`. MariaDB has no CI matrix, so a branch that forgets
it fails in production rather than in the suite.

```php
match ($driver) { 'mysql' => …, 'pgsql' => … }   // UnhandledMatchError on mariadb
$driver === 'mysql' ? $a : $b                     // sends mariadb down the pgsql path
in_array($driver, ['mysql', 'pgsql'], true)       // rejects mariadb
```

Group the family instead — `'mysql', 'mariadb' => …`, or
`in_array($driver, ['mysql', 'mariadb'], true)`. Exemplars:
`packages/Webkul/Core/src/Helpers/Database/GrammarQueryManager.php` (grammar
selection), `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/Importer.php`
(bulk-mode session vars). When only PostgreSQL is special, test for that one and
let the rest fall through: `=== 'pgsql'` is safe, `=== 'mysql'` is not.

Singling out `mysql` is legitimate only once the family is already handled —
`packages/Webkul/Installer/src/Helpers/Upgrade/BackupManager.php` passes
`--no-tablespaces` to mysqldump alone, because MariaDB has no tablespace
metadata and exits non-zero on the flag. That file also shows the two other
client-level traps: MariaDB 11 renamed its binaries, so probe with
`Symfony\Component\Process\ExecutableFinder` for `mariadb-dump` before falling
back to the `mysqldump` shim, and pass credentials through the environment
(`MYSQL_PWD`, `PGPASSWORD`) rather than argv, which is world-readable.

`packages/Webkul/Core/tests/Unit/DatabaseDriverCoverageTest.php` fails any
package file that branches on `'mysql'` without naming `mariadb`, so this is a
suite failure and not only a review finding.

### Elasticsearch is optional

`config('elasticsearch.enabled')` defaults to false. Every ES read needs a DB
fallback and every ES write a guard — exemplars
`packages/Webkul/Product/src/Factories/ProductQueryBuilderFactory.php` and
`packages/Webkul/ElasticSearch/src/Observers/Product.php`:

```php
public static function make()
{
    return config('elasticsearch.enabled')
        ? resolve(ElasticProductQueryBuilder::class)
        : resolve(DatabaseProductQueryBuilder::class);
}
```

Never hard-depend on a reachable ES cluster.

### Apache, Nginx and Docker are all supported targets

The app deploys behind Apache (`public/.htaccess`), behind Nginx
(`dockerfiles/nginx.conf`), and in Docker under either (`docker-compose.yml`,
`docker-compose.apache.yml`). These are three different config files that no
build step keeps in sync, so **a feature that needs a web-server rule to work is
broken on two of the three targets.**

- **Serve through a route, never through a server rule.** The image cache is the
  model: it is a Laravel route registered from `config('imagecache.route')` in
  `packages/Webkul/Core/src/Providers/CoreServiceProvider.php`, and the Nginx
  `location ^~ /cache/` block only short-circuits to a cached file before
  falling through to that same route. The feature works with the block, without
  it, and under Apache. Adding a `location` or `RewriteRule` that the feature
  cannot run without is a blocker.
- **Never write outside a configured disk.** All file writes go through the
  Storage facade and a disk name — exemplar
  `packages/Webkul/Core/src/Filesystem/FileStorer.php`. No `public_path()`
  writes, no absolute paths, no assumption that `storage/app/public` is
  symlinked into the docroot on this host.
- **Never derive the base URL from the request.** It comes from
  `config('app.url')`; the mismatch between that and the actual host is a real
  enough deployment failure that a middleware exists for it —
  `packages/Webkul/AppUrlGuard/src/Http/Middleware/VerifyAppUrlMatches.php`.
  Build links with `route()`/`url()`/`asset()`, never by concatenating
  `$_SERVER` values.
- **A server rule is never the only enforcement.** Both configs block script
  execution under `/storage` (the `.htaccess` `RewriteRule ^storage/...` and the
  Nginx `location ~* ^/storage/...`), and neither is a substitute for the upload
  allowlist in [security.md](security.md) — a third deployment has neither
  block. Likewise upload size: Nginx sets `client_max_body_size 200M` and
  Apache sets nothing, so the `max:` rule in the FormRequest is the only limit
  that exists everywhere.
- **The queue worker and the scheduler are separate processes.** In Docker they
  are separate containers (`unopim-q`, `unopim-scheduler`), started from their
  own entrypoints. A queued job therefore cannot reach the web process's memory,
  its session, its uploaded temp file, or anything a request-scoped binding
  held. Pass ids and read state from the database or a shared disk — never
  serialize a model's loaded relations or a file handle into a job payload.
