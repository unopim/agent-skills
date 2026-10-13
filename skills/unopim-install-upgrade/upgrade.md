# Upgrade

Source: `packages/Webkul/Installer/src/Console/Commands/Upgrade.php`. Operator
guide: `UPGRADE.md` (release-archive, git-worktree and Docker tracks). The
command runs from the **new** release directory while the old one still serves.

## `unopim:upgrade` — the real signature

| Flag | Effect |
|---|---|
| `--from=PATH` | Previous release directory; enables the full drift report (old `.env`, `config/*.php`, `composer.json` require list) |
| `--dry-run` | Phases 1–3 only; changes nothing |
| `--with-reindex` | Rebuild ES inline after cutover — refused above `upgrade.inline_reindex_product_limit` products |
| `--skip-backup` | No dump. Only where infrastructure already snapshots the DB |
| `--force` | Downgrade the source-version check from failure to warning |

Interactive runs ask for confirmation before phase 4; non-interactive runs
(`--no-interaction`, CI, `docker compose run` without a TTY) proceed.

## Phases

| # | Phase | Class | Mutates |
|---|---|---|---|
| 1 | Preflight | `packages/Webkul/Installer/src/Helpers/Upgrade/PreflightChecker.php` | no |
| 2 | Drift | `packages/Webkul/Installer/src/Helpers/Upgrade/DriftReporter.php` | no — reports only |
| 3 | Sizing | `packages/Webkul/Installer/src/Helpers/Upgrade/MigrationSizer.php` | no |
| 4 | Execute | `Upgrade::runUpgrade()` | yes |
| 5 | Verify | `packages/Webkul/Installer/src/Helpers/Upgrade/PostUpgradeVerifier.php` | no |

Pending migrations are read by
`packages/Webkul/Installer/src/Helpers/Upgrade/MigrationInspector.php`, which adds
`database_path('migrations')` to the migrator's package paths — so every
package's `loadMigrationsFrom()` directory is counted.

Preflight checks: PHP ≥ `minimum_php`; `required_extensions`; DB connection
(prints driver, database, prefix); source version via the sentinel migration;
pending migrations exist (warning if none); no active data-transfer job;
`writable_paths`; free disk ≥ estimated DB size + `disk_headroom_bytes`.

Phase 4, in order — each step through `runStep()`, which throws on a non-zero exit:

1. `BackupManager::dump()` unless `--skip-backup` — failure aborts before downtime.
2. `down --render=errors::503`.
3. `unopim:passport:keys` → `migrate --force` → `storage:link --relative` →
   `optimize:clear` → `queue:restart`.
4. Any failure: restore recipe printed, **site left in maintenance**.
5. Phase 5 verification; failure also leaves maintenance on.
6. `up`, then the reindex report.

Never recommend bare `php artisan migrate --force` as "the upgrade": it skips
the job check, the dump, maintenance mode, key generation, worker restart and
verification.

## `upgrade.*` config keys

All in `packages/Webkul/Installer/src/Config/upgrade.php`, merged under `upgrade`:

| Key | Used by | Change it when |
|---|---|---|
| `minimum_php` | preflight | The release raises the PHP floor |
| `minimum_source_version` + `source_version_sentinel` | preflight | The supported upgrade floor moves; the sentinel must be a migration every install at that floor has run |
| `required_extensions` | preflight | A new PHP extension becomes mandatory |
| `active_job_states`, `stale_job_minutes` | preflight | DataTransfer gains a new in-flight state — spelled out as strings on purpose (no cross-package class at `register()` time) |
| `disk_headroom_bytes`, `writable_paths` | preflight | Rarely |
| `removed_env_keys` | drift | The release retires an `.env` key |
| `sizing_tables` | sizing | A pending migration rewrites a large table not listed; value = conservative rows/second |
| `irreversible_migrations` | sizing | Every data migration with a no-op or lossy `down()` |
| `inline_reindex_product_limit` | reindex report | Rarely |

An install can override them with its own `upgrade.php` in the app config directory (not shipped on master); the merge is
shallow, so an overridden list replaces the shipped one.

## BackupManager

`packages/Webkul/Installer/src/Helpers/Upgrade/BackupManager.php` writes
`storage/app/upgrade-backups/<database>-<timestamp>.sql` and verifies it is at
least 1 KB. Already correct for all three engines — reuse it, never hand-roll a
dump in a script or doc:

- `mysql` / `mariadb`: `--single-transaction --routines`; `--no-tablespaces`
  for `mysql` only (MariaDB rejects it); prefers `mariadb-dump` on MariaDB via
  `ExecutableFinder`, falls back to `mysqldump`.
- `pgsql`: `pg_dump --file=`.
- Credentials via `MYSQL_PWD` / `PGPASSWORD` env, never argv.
- Unknown driver throws — deliberate: an upgrade with no restore point stops.

The client binary must exist where the command runs. On Docker that is the app
image, not the DB container; a missing binary fails phase 4 before `down`.

## Docker vs host

Resolve with unopim-exec, then:

| Workspace | Upgrade invocation |
|---|---|
| Host / release directories | `php artisan unopim:upgrade --dry-run --from=<old release>` then without `--dry-run` |
| Docker image stack | `docker compose pull`, `docker compose run --rm app php artisan unopim:upgrade --dry-run`, the same without `--dry-run`, then `docker compose up -d` |

`dockerfiles/lib/setup-app.sh` runs on app-container start: always
`unopim:passport:keys`, then `migrate --force` (plus `db:seed` on first boot)
unless `UNOPIM_SKIP_MIGRATIONS=true`. On a scaled deployment set that flag on
replicas and run `unopim:upgrade` once, or replicas race the migration and skip
the backup. Docker has no previous tree on disk, so drift degrades to `.env`
against `.env.example` — config and composer drift are not compared.

## Post-upgrade steps

| Step | Who does it | Command |
|---|---|---|
| Clear caches | upgrade (phase 4) | `optimize:clear` — it does not re-cache |
| Re-cache for production | operator | `config:cache`, `route:cache`, `view:cache` |
| Restart queue workers | upgrade | `queue:restart`; Supervisor-managed workers pick it up |
| Reload Octane workers | operator | `octane:reload` when served by Octane |
| Reindex ES (enabled only) | operator, after `up` | `unopim:elastic:clear`, `unopim:category:index`, `unopim:product:index` — see unopim-search indexing.md for `--fresh` / `--workers` |
| Completeness after a scoring change | operator | `unopim:completeness:recalculate` |
| Merge drift | operator | Re-apply what phase 2 listed; nothing is auto-merged |
| Translations | developer, before release | `unopim:translations:check` — never at upgrade time |

ES is optional: with `elasticsearch.enabled` false the reindex report prints
nothing and search reads the database. A release note must not make the reindex
sound mandatory for DB-only installs.

## Testing upgrade-path changes

Follow the existing feature tests:

- `packages/Webkul/Installer/tests/Feature/UpgradeCommandTest.php` — command
  contract (dry run never mutates, preflight failure aborts, `runStep` fails closed).
- `packages/Webkul/Installer/tests/Feature/UpgradePreflightTest.php`,
  `packages/Webkul/Installer/tests/Feature/UpgradeSizerTest.php`,
  `packages/Webkul/Installer/tests/Feature/UpgradeDriftReporterTest.php`,
  `packages/Webkul/Installer/tests/Feature/UpgradeBackupTest.php`,
  `packages/Webkul/Installer/tests/Feature/UpgradeVerifierTest.php`.

Override `upgrade.*` with `config([...])` inside the test to isolate the gate
under test (see how `UpgradeCommandTest` neutralises `active_job_states`). Never
let a test actually run `down` against the shared test app without restoring.
