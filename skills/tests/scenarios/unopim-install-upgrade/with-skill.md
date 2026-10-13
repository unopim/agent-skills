# unopim-install-upgrade — with the skill

Same task as [baseline.md](baseline.md). Desk-run against UnoPim master,
following SKILL.md's decision procedure; not a captured live session.

## Task

"Products get a new `brand_code` column, backfilled from the brand value
inside the `values` JSON. It has to land on existing installs through the next
upgrade. Write the migration, hook it into the upgrade, and give ops the steps."

## Run

1. **Which command** (step 1): existing data → `unopim:upgrade`. The answer
   never mentions `unopim:install`; install.md records that it runs
   `migrate:fresh`.
2. **Environment** (step 2): unopim-exec resolved a container wrapper, so every
   command below was run as `docker compose run --rm app php artisan …` in the
   rehearsal and written as plain `php artisan …` in the ops note, with the
   Docker variant beside it.
3. **Split** (step 3), all in `packages/Webkul/Product/src/Database/Migrations/`
   (the folder `ProductServiceProvider` loads):
   - `…_add_brand_code_to_products_table.php` — nullable `string`, guarded by
     `Schema::hasColumn`, `down()` drops it.
   - `…_add_brand_code_index_to_products_table.php` — named index behind
     `Schema::hasIndex`, copied from the 2026_08_05 dashboard-index migration.
   - `…_backfill_products_brand_code.php` — the migrations.md skeleton:
     `DB::table('products')->select(['id','values'])->whereNull('brand_code')->chunkById(500, …)`,
     brand decoded in PHP (no `JSON_EXTRACT`), one `whereIn('id', …)->update()`
     per distinct brand per chunk, empty `down()` with a one-line why.
4. **Upgrade registration** (step 5): appended the backfill's name to
   `irreversible_migrations` in `packages/Webkul/Installer/src/Config/upgrade.php`.
   `products` is already in `sizing_tables`, so no new entry. No invented
   `UpgradeStep` API.
5. **Silent outcome** (migrations.md §6): added `verifyBrandCodes()` to
   `PostUpgradeVerifier` — warning when the column is missing; failure when
   products with a non-empty brand in the common values still have a null
   `brand_code`, counted with the builder JSON path; added to `run()`.
   `installer::app.upgrade.verify.brand-codes*` keys added to all 35 locale
   directories under the Installer package's `Resources/lang/`, translated.
6. **Search** (step 6): `brand_code` feeds a product filter, so the release
   note says reindex is required when Elasticsearch is enabled and nothing
   extra when it is not.
7. **Tests**:
   - `packages/Webkul/Product/tests/…/BackfillBrandCodeMigrationTest.php` —
     seeds three products (brand, empty brand, no common values), runs the
     migration's `up()` twice, asserts one populated row and no change on the
     second run.
   - Two cases in `packages/Webkul/Installer/tests/Feature/UpgradeVerifierTest.php`
     — fail on an unmigrated row, pass after backfill.
   - Suite run on MySQL and on `phpunit.pgsql.xml`; the driver-family check was
     done by reading (no MariaDB CI).
8. **Rehearsal** (step 8): `unopim:upgrade --dry-run` on a copy of a 1.2M-product
   database listed the three pending migrations, named the backfill as
   irreversible, and gave a window estimate that went into the ops note.

## Ops note produced

```bash
# host, from the new release directory
php artisan unopim:upgrade --dry-run --from=../<previous-release>
php artisan unopim:upgrade --from=../<previous-release>

# docker
docker compose pull
docker compose run --rm app php artisan unopim:upgrade --dry-run
docker compose run --rm app php artisan unopim:upgrade
docker compose up -d

# after cutover, only when ELASTICSEARCH_ENABLED=true
php artisan unopim:elastic:clear
php artisan unopim:category:index
php artisan unopim:product:index
```

Plus: re-cache config/routes/views if the deployment caches them;
`octane:reload` when served by Octane; the backup is written by the upgrade
itself (no hand-rolled `mysqldump`); rollback = previous release + restore the
dump in `storage/app/upgrade-backups/`, because the backfill is irreversible.

## Gates

pint, Pest (MySQL + PostgreSQL), phpstan on changed files, rector dry-run,
`unopim:translations:check --package=Installer`. Playwright skipped — no view
or JS change.

## Delta vs baseline

All twelve baseline findings addressed: right folder, streamed and portable
backfill, split idempotent files, irreversible listed, no invented API, the
upgrade command instead of bare `migrate`, no `unopim:install` advice, backup
via BackupManager, reindex conditional on ES, Docker path, verifier check with
tests.
