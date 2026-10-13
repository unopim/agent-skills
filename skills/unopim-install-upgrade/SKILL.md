---
name: unopim-install-upgrade
description: Use when installing UnoPim, running or changing unopim:install or unopim:upgrade, writing a migration that must land on existing installs (schema change, data backfill, index on a large table), editing the Installer package's upgrade config, seeders or BackupManager, registering a new package so its migrations and seeders run, or planning post-upgrade steps on host or Docker. Trigger phrases include "install", "unopim:install", "upgrade", "unopim:upgrade", "migration", "data migration", "backfill", "seeder", "backup", "maintenance window", "irreversible", "release upgrade", "migrate --force".
requires: unopim-standards, unopim-exec, unopim-verify
---

# UnoPim Install & Upgrade

`unopim:install` builds an empty database from nothing; `unopim:upgrade` moves a
live one forward. Both live in `packages/Webkul/Installer`. There is no plugin
"upgrade step" API: what an upgrade runs is `migrate --force`, so **a package's
upgrade step is a migration** in that package, plus release metadata in
`packages/Webkul/Installer/src/Config/upgrade.php`.

**REQUIRED BACKGROUND:** unopim-standards (scale.md for streaming and driver
families, security.md for credentials), unopim-exec before any command,
unopim-verify before calling it done. Package scaffolding (provider, composer
autoload, Concord module) is unopim-plugin-development; reindex choice is
unopim-search indexing.md.

## Reference files

| File | Read when |
|---|---|
| [install.md](install.md) | `unopim:install` flags and step order, seeders, web installer, installed flags, demo data, registering a new package |
| [upgrade.md](upgrade.md) | The five upgrade phases, every flag, every `upgrade.*` config key, BackupManager, Docker vs host, post-upgrade steps |
| [migrations.md](migrations.md) | Writing schema vs data migrations that survive millions of rows on MySQL, MariaDB and PostgreSQL; marking them irreversible; adding a verifier check |

## Exemplars

- Upgrade command: `packages/Webkul/Installer/src/Console/Commands/Upgrade.php`
- Install command: `packages/Webkul/Installer/src/Console/Commands/Installer.php`
- Release metadata: `packages/Webkul/Installer/src/Config/upgrade.php`
- Dump: `packages/Webkul/Installer/src/Helpers/Upgrade/BackupManager.php`
- Silent-failure checks: `packages/Webkul/Installer/src/Helpers/Upgrade/PostUpgradeVerifier.php`
- Chunked data backfill: `packages/Webkul/Product/src/Database/Migrations/2026_07_11_100002_backfill_product_associations.php`
- Idempotent index on `products`: `packages/Webkul/Product/src/Database/Migrations/2026_08_05_120000_add_dashboard_aggregate_indexes_to_products_table.php`
- Operator guide: `UPGRADE.md`

## Decision procedure

1. **Which command?** Empty database → `unopim:install`. Anything with data →
   `unopim:upgrade`. `unopim:install` runs `migrate:fresh` with no installed-check
   in the CLI path — it drops every table. Never prescribe it as a repair.
2. **Resolve the environment** with unopim-exec. On Docker the upgrade runs in a
   one-off container (`docker compose run --rm app php artisan unopim:upgrade`);
   the app container's `dockerfiles/lib/setup-app.sh` otherwise migrates on boot
   unless `UNOPIM_SKIP_MIGRATIONS=true`.
3. **Shipping a DB change?** Split it — see [migrations.md](migrations.md):
   - schema migration (column, nullable or defaulted) — reversible `down()`;
   - index migration — guarded by `Schema::hasIndex`, separate file;
   - data migration — `DB::table()->chunkById()`, bulk write per chunk,
     idempotent, no-op `down()`.
4. **Put each file in the owning package's migration folder** — the folder its
   provider passes to `loadMigrationsFrom()`. A file anywhere else never runs on
   upgrade.
5. **Irreversible or slow?** Core release: add the migration name to
   `irreversible_migrations` and any newly heavy table to `sizing_tables` in
   `packages/Webkul/Installer/src/Config/upgrade.php`. Silent data migration:
   add a check method to `PostUpgradeVerifier` and its test.
6. **Touches indexed product or category fields?** `DB::table()` writes bypass
   the model observers — state the reindex in the release note; the upgrade
   prints it after cutover (see [upgrade.md](upgrade.md)).
7. **New user-facing string** in the installer or upgrade output → `installer::`
   key in every locale directory under
   `packages/Webkul/Installer/src/Resources/lang/` (35 there, not 33 —
   `en_CA` and `fr_CA` exist).
8. **Rehearse**: `unopim:upgrade --dry-run` against a copy of real data; read the
   sizing table and the irreversible list before claiming a maintenance window.

## UnoPim-specific pitfalls

- **Installer routes are not admin routes.** `packages/Webkul/Installer/src/Routes/web.php`
  is unauthenticated by design and gated in the controller by
  `DatabaseManager::canConfirmNotInstalled()` / `isInstalled()` (fail closed).
  Any new destructive installer endpoint copies that gate — the `['admin']`
  middleware and ACL rules do not apply before an admin exists.
- **Two installed markers.** `storage/installed` (ephemeral) and the
  `core_config` row `installer.installed` (persistent). Install writes both
  (`markInstalled()`); Docker's `setup-app.sh` writes only the file, the
  `2026_07_01_000000_backfill_installer_installed_flag` migration seals the DB.
- **Driver families.** Three driver names: `mysql`, `mariadb`, `pgsql`. A
  `match` on the driver groups `'mysql', 'mariadb'`. Backup is the one place
  that throws on an unknown driver, on purpose: no dump, no upgrade.
- **`DB_PREFIX`.** Migrations name tables bare; raw fragments prepend
  `DB::getTablePrefix()` (unopim-standards scale.md).
- **Config overrides are shallow.** `mergeConfigFrom(..., 'upgrade')` merges top
  level keys only. An `upgrade.php` an operator adds to the app config directory (none ships on master; `UPGRADE.md` invites it) replaces a whole
  list (e.g. `irreversible_migrations`) rather than appending to it — copy the
  full shipped list when overriding one.
- **No plugin hook into `upgrade.*`.** No package outside Installer touches that
  config on master. A plugin's migrations still run (they are on the migrator's
  path), but appear in sizing as reversible; say so in the plugin's own notes
  instead of inventing an API.
- **Octane / workers.** Upgrade runs `queue:restart`; long-lived Octane workers
  also need `octane:reload` after cutover — the command does not do it.
- **Active jobs block preflight.** States in `active_job_states` with a fresh
  heartbeat fail phase 1. Stalled ones: `unopim:data-transfer:reap-stalled`,
  never a manual `UPDATE job_track`.

## Verification

- Pest: add or extend tests beside
  `packages/Webkul/Installer/tests/Feature/UpgradeCommandTest.php`,
  `UpgradeVerifierTest.php`, `UpgradeBackupTest.php`; a data migration gets a
  test that seeds legacy rows, runs it twice, and asserts the result.
- Run the suite on MySQL **and** PostgreSQL (`phpunit.pgsql.xml`); there is no
  MariaDB matrix, so review every driver branch for the family by hand.
- `php artisan unopim:translations:check --package=Installer` after any
  `installer::` string change.
- Then the full unopim-verify gate set; Playwright only if the web installer
  view changed.
