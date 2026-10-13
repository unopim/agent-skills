# unopim-install-upgrade — baseline (without the skill)

Desk-run, not a captured live session. The "agent" column was written from
generic Laravel 13 knowledge before the Installer package was read; the
"against master" column was filled in afterwards by reading UnoPim master.

## Task

"Products get a new `brand_code` column, backfilled from the brand value
inside the `values` JSON. It has to land on existing installs (some with
millions of products, on MySQL, MariaDB and PostgreSQL) through the next
upgrade. Write the migration, hook it into the upgrade, and give ops the
upgrade steps."

## What the agent produced from generic knowledge

1. One migration in `database/migrations/` that adds the column, adds an
   index, and backfills in the same `up()`:
   `Product::all()->each(fn ($p) => $p->update(['brand_code' => ...]))`.
2. Alternatively a single statement:
   `DB::statement("UPDATE products SET brand_code = JSON_UNQUOTE(JSON_EXTRACT(values, '$.common.brand'))")`.
3. `down()` drops the column.
4. "Hook into the upgrade" by inventing an `UpgradeStep` contract and a
   `registerUpgradeSteps()` method on the package's service provider.
5. Ops instructions:
   ```bash
   git pull && composer install
   php artisan migrate --force
   php artisan optimize:clear
   ```
   with an optional "re-run `php artisan unopim:install` if something breaks".
6. Backup advice: `mysqldump -u root -pSECRET unopim > backup.sql`.
7. No mention of Elasticsearch, queue workers, or the running import jobs.

## What was wrong against UnoPim master

| # | Baseline output | Reality on master |
|---|---|---|
| 1 | Migration in `database/migrations/` | Core package migrations live in the owning package's `src/Database/Migrations/`, loaded by its provider's `loadMigrationsFrom()` (e.g. `packages/Webkul/Product/src/Providers/ProductServiceProvider.php`). |
| 2 | `Product::all()->each(...)` | Hydrates the whole catalog; Eloquent saves fire observers (ES indexing, history) per row. Master streams with `DB::table()->chunkById()` and bulk-writes per chunk — `packages/Webkul/Product/src/Database/Migrations/2026_07_11_100002_backfill_product_associations.php`. |
| 3 | `JSON_UNQUOTE(JSON_EXTRACT(...))` raw SQL | MySQL-only; breaks on PostgreSQL and names a bare table under `DB_PREFIX`. |
| 4 | Schema change + index + backfill in one migration | One failure leaves a half-applied schema with no clean retry; master keeps schema, index and data migrations separate and makes each idempotent (`Schema::hasIndex` guards in `packages/Webkul/Product/src/Database/Migrations/2026_08_05_120000_add_dashboard_aggregate_indexes_to_products_table.php`). |
| 5 | `down()` drops the column | Fine for the schema migration; the data migration must be a deliberate no-op `down()` and be named in `irreversible_migrations` so phase 3 of the upgrade warns before downtime is booked. |
| 6 | Invented `UpgradeStep` / `registerUpgradeSteps()` | Does not exist. `unopim:upgrade` runs `migrate --force`; a package's upgrade step IS a migration. Release metadata lives in `packages/Webkul/Installer/src/Config/upgrade.php` (`irreversible_migrations`, `sizing_tables`); silent-failure checks go in `packages/Webkul/Installer/src/Helpers/Upgrade/PostUpgradeVerifier.php`. |
| 7 | `php artisan migrate --force` by hand | Skips preflight (active jobs, PHP floor, disk for the dump), the verified backup, maintenance mode, `unopim:passport:keys`, `queue:restart` and post-upgrade verification — all in `packages/Webkul/Installer/src/Console/Commands/Upgrade.php`. |
| 8 | "Re-run `unopim:install`" | `unopim:install` calls `migrate:fresh` — it drops every table. Never on an installed database. |
| 9 | `mysqldump -pSECRET` | Password in argv (process table); `mysqldump` is a deprecated shim on MariaDB 11; `--no-tablespaces` matters on MySQL 8. `packages/Webkul/Installer/src/Helpers/Upgrade/BackupManager.php` already does this right and runs inside the upgrade. |
| 10 | No reindex step | A `DB::table()` backfill bypasses the model observers, so ES documents never see `brand_code`. Upgrade defers reindex by design and prints the three commands; `--with-reindex` is capped by `inline_reindex_product_limit`. |
| 11 | No Docker path | Docker installs run the upgrade in a one-off container (`docker compose run --rm app php artisan unopim:upgrade`); `dockerfiles/lib/setup-app.sh` otherwise auto-migrates on start unless `UNOPIM_SKIP_MIGRATIONS=true`. |
| 12 | No test | Master tests every upgrade helper (`packages/Webkul/Installer/tests/Feature/UpgradeVerifierTest.php`); a new verifier check without a test is unproven. |

## Failure the skill must prevent

Shipping a data change for existing installs as an unbounded, MySQL-only,
non-idempotent migration run outside `unopim:upgrade`, with no backup, no
verification, and a stale search index — and suggesting `unopim:install`
(a full wipe) as the recovery path.
