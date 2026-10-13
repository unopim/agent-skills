# Migrations that land on existing installs

Every migration ships twice: on a fresh install it runs against empty tables
(`migrate:fresh`), on an upgrade it runs against a live catalog that may hold
millions of `products`, `product_completeness` and `audits` rows, inside a
maintenance window the operator booked from the phase 3 estimate. Write for the
second case. General scale and driver rules: unopim-standards scale.md.

## 1. Where the file goes

The folder the owning package's provider passes to `loadMigrationsFrom()`:

| Package style | Folder | Exemplar provider |
|---|---|---|
| Core (`packages/Webkul/*/src`) | `src/Database/Migrations/` | `packages/Webkul/Product/src/Providers/ProductServiceProvider.php` |
| Plugin-style | root `Database/Migration/` | `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php` |

Not `database/migrations/` for package data — that directory is the
application's, and a package's migrations belong with the package so they ship
and roll back with it. Name with the release date prefix; the name (without
`.php`) is what `irreversible_migrations` and the sentinel reference.

## 2. Split by kind

| Kind | Contains | `down()` | Idempotent by |
|---|---|---|---|
| Schema | `Schema::create` / add nullable or defaulted column | Reverses it | `Schema::hasColumn` / `hasTable` guard when re-runs are plausible |
| Index | `$table->index([...], 'explicit_name')` | Drops it | `Schema::hasIndex('table', 'name')` — exemplar `packages/Webkul/Product/src/Database/Migrations/2026_08_05_120000_add_dashboard_aggregate_indexes_to_products_table.php` |
| Data | Backfill, rewrite, scrub, repair | No-op when the forward step destroys information | Insert-or-ignore, guarded update, or an early return when already consistent — exemplar `packages/Webkul/Category/src/Database/Migrations/2026_07_30_150000_repair_category_nested_set_bounds.php` |

One file per kind. If the data step fails, the schema step is already recorded
and a retry resumes at the data step instead of failing on "column exists".

## 3. Data migration rules (millions of rows)

Exemplar for the technique: `packages/Webkul/Product/src/Database/Migrations/2026_07_11_100002_backfill_product_associations.php`.
Copy its structure, not its inline comments — the comment rules in
unopim-standards comments.md apply to migrations too.

- Stream with `DB::table('products')->select([...only what you need])->chunkById(N, ...)`.
  `->get()`, `->all()` and `Model::all()` are unbounded.
- Query builder, not Eloquent: no hydration, no observers. Use a model only when
  the algorithm lives on it (the nested-set repair calls `Category::fixTree()`),
  and then expect observer side effects.
- Preload small lookup tables once (`pluck('id', 'code')`); resolve per-chunk
  foreign keys with one `whereIn` per chunk, never per row.
- Write once per chunk: `insertOrIgnore()` for missing rows, `upsert()` with an
  explicit unique key, or group ids by target value and `whereIn('id', $ids)->update()`.
  A per-row `update()` inside the loop (as in the older
  `packages/Webkul/Product/src/Database/Migrations/2024_11_28_174850_migrate_status_value_from_values_column_to_status_column.php`)
  is N round trips — acceptable at 10k rows, hours at 10M.
- Read JSON portably: decode `values` in PHP, or use the builder's JSON path
  (`->whereNotNull('values->common->brand')`). No `JSON_EXTRACT`, `->>`,
  `JSON_UNQUOTE` in raw SQL.
- Keep migrations self-contained: hardcode the codes and constants they need
  (the associations backfill copies `ASSOCIATION_SECTIONS`) so a later refactor
  of application code cannot change what an old migration does.
- Make a second run a no-op. The upgrade can fail mid-way and be re-run after a
  restore or a fix; Docker re-runs `migrate` on every app-container start.
- Tables bare, raw fragments prefixed with `DB::getTablePrefix()`.

### Skeleton

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    private const CHUNK_SIZE = 500;

    /**
     * Backfill products.brand_code from the common brand value.
     */
    public function up(): void
    {
        DB::table('products')
            ->select(['id', 'values'])
            ->whereNull('brand_code')
            ->chunkById(self::CHUNK_SIZE, fn (Collection $products) => $this->backfill($products));
    }

    /**
     * The source value stays in the values JSON, so there is nothing to undo.
     */
    public function down(): void {}

    private function backfill(Collection $products): void
    {
        $idsByBrand = [];

        foreach ($products as $product) {
            $brand = json_decode((string) $product->values, true)['common']['brand'] ?? null;

            if (is_string($brand) && $brand !== '') {
                $idsByBrand[$brand][] = $product->id;
            }
        }

        foreach ($idsByBrand as $brand => $ids) {
            DB::table('products')->whereIn('id', $ids)->update(['brand_code' => $brand]);
        }
    }
};
```

`chunkById` plus a `whereNull` filter on the column being written is safe: it
pages by id, not by offset, so rows leaving the filter do not shift the window.

## 4. Engine behaviour that changes the window

- **PostgreSQL runs each migration in a transaction.** A failure rolls the whole
  file back (good for schema), and a 10M-row backfill is one long transaction
  (bloat, locks held to the end). Laravel's `$withinTransaction = false` on the
  migration opts out; master has no exemplar, so justify it in the docblock and
  rely on idempotence for retry. Also: a failing statement aborts the rest of a
  PG transaction — wrap expected failures in a savepoint, never `try/catch` and
  carry on.
- **MySQL / MariaDB DDL is not transactional.** A half-run multi-statement
  migration leaves partial schema; this is why each kind gets its own file with
  `has*` guards.
- **Index builds on large tables** hold locks for minutes (`UPGRADE.md` "How long
  will it take?"). They run inside the maintenance window — do not reach for
  `CONCURRENTLY` / `ALGORITHM=INPLACE` raw SQL: it is engine-specific, cannot run
  inside the PG migration transaction, and master uses the plain builder.
- **Column adds**: nullable or with a constant default (instant on MySQL 8 and
  PG 11+). Avoid `->change()` on `products` and `audits`; add a new column,
  backfill, switch reads, drop later.
- **Booleans** come back `true/false` on PG and `1/0` on MySQL — compare
  loosely or cast in PHP.

## 5. Register the migration with the upgrade

- Data migration with a no-op or lossy `down()` → append its name to
  `irreversible_migrations` in `packages/Webkul/Installer/src/Config/upgrade.php`.
- It scans a large table not already in `sizing_tables` → add the table with a
  conservative rows/second figure.
- Raises the supported floor → move `minimum_source_version` and
  `source_version_sentinel` together.
- Plugin packages cannot append to these lists (shallow config merge, no hook on
  master); document the window and irreversibility in the plugin's own upgrade
  notes.

## 6. Verify silent outcomes

`migrate` exiting 0 proves only that nothing threw. When the failure mode is
"the backfill wrote nothing", add a check to
`packages/Webkul/Installer/src/Helpers/Upgrade/PostUpgradeVerifier.php`:

1. A protected method returning `CheckResult::passed($name, $detail)`,
   `CheckResult::warning($name, $detail, $remedy)` or
   `CheckResult::failed($name, $detail, $remedy)`
   (`packages/Webkul/Installer/src/Helpers/Upgrade/CheckResult.php`).
2. Guard with `Schema::hasTable` / `hasColumn` → warning, so an install without
   the optional table does not fail forever.
3. Assert a bounded aggregate (`count()` on an indexed predicate), never a
   row-by-row comparison.
4. Add it to `run()`; add `installer::app.upgrade.verify.*` keys to every
   locale under `packages/Webkul/Installer/src/Resources/lang/`.
5. Test it in `packages/Webkul/Installer/tests/Feature/UpgradeVerifierTest.php`:
   seed the bad state, expect failure; seed the good state, expect pass.

## 7. Search and derived data

Query-builder writes skip the product and category observers, so Elasticsearch
documents and history are not updated. If the column is indexed or shown in
search, say "reindex required" in the release note; the upgrade already prints
the reindex commands when ES is enabled. Completeness scores derived from
changed values need `unopim:completeness:recalculate`. With ES disabled nothing
extra is needed — the database is authoritative.

## 8. Baseline rows existing installs need

Seeders run only on install (and Docker's first boot). A new config row, ACL
default or reference record that existing installs also need ships as a data
migration using `updateOrInsert` on its natural key, exactly like
`packages/Webkul/Core/src/Database/Migrations/2026_07_01_000000_backfill_installer_installed_flag.php`,
and the seeder is updated for fresh installs in the same change.
