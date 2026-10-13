# Install

Source: `packages/Webkul/Installer/src/Console/Commands/Installer.php`, registered
by `packages/Webkul/Installer/src/Providers/InstallerServiceProvider.php`.
Resolve the command wrapper (host php or container) with unopim-exec first.

## `unopim:install` — the real signature

| Flag | Effect |
|---|---|
| `--skip-env-check` | Skip the interactive `.env` wizard; use the `.env` already on disk |
| `--skip-admin-creation` | Do not prompt for the admin user (CI / headless) |
| `--with-demo-data` | Seed the demo catalog after install |
| `--with-packages=` | Comma-separated optional add-ons (keys of `installer.optional_packages.packages`) |

Nothing else exists — no `--force`, no `--seed`, no `--database`. Headless
installs use the first two:

```bash
php artisan unopim:install --skip-env-check --skip-admin-creation
```

### What `handle()` does, in order

1. `.env` wizard (unless `--skip-env-check`), then `loadEnvConfigAtRuntime()`
   pushes the fresh values (including `DB_PREFIX`) into config.
2. `key:generate`, `unopim:passport:keys`.
3. If Elasticsearch is enabled: connection test, abort on failure.
4. **`migrate:fresh`** — drops every table. No installed-check guards the CLI path.
5. `Webkul\Installer\Database\Seeders\DatabaseSeeder` with the chosen locales and
   currencies.
6. `storage:link --relative`; if ES enabled: `unopim:elastic:clear`,
   `unopim:category:index`, `unopim:product:index`.
7. `optimize:clear`.
8. Resolve optional packages (prompt happens here, before demo seeding flips the
   console non-interactive).
9. Admin credentials (unless skipped), demo data (if flagged), optional packages
   (`composer require` + the add-on's own install command, each in a child
   process carrying the resolved DB env).
10. `markInstalled()` — writes the `core_config` row `installer.installed` and the
    `storage/installed` file, then dispatches `unopim.installed`.

Consequence: an agent must never suggest `unopim:install` to "fix" an existing
database, and must never run it against a `.env` pointing at shared data.

## Related commands

| Command | Signature source | Note |
|---|---|---|
| `unopim:user:create` | `packages/Webkul/Installer/src/Console/Commands/DefaultUser.php` | `--name --email --password --ui_locale --timezone --admin`; use after `--skip-admin-creation` |
| `unopim:install:demo-data` | `packages/Webkul/Installer/src/Console/Commands/SeedDemoData.php` | `--force` re-seeds and **deletes** products, categories, channels, attributes, families and core config; `--scale=large` pads to 2000 products |
| `unopim:images:purge-unused` | `packages/Webkul/Installer/src/Console/Commands/PurgeUnusedImages.php` | `--dry-run` first |

Non-interactive admin defaults come from `installer.admin.email` /
`installer.admin.password` (`INSTALLER_ADMIN_EMAIL`, `INSTALLER_ADMIN_PASSWORD`)
in `packages/Webkul/Installer/src/Config/installer.php`.

## Seeding

- Entry point: `database/seeders/DatabaseSeeder.php` delegates to
  `packages/Webkul/Installer/src/Database/Seeders/DatabaseSeeder.php`, which calls
  the per-domain seeders (Attribute, Category, Core, Measurement, User, MagicAI
  prompts, AiAgent config). `php artisan db:seed` (what Docker runs on first
  boot) therefore produces the same baseline as the CLI installer.
- Seeders receive a `parameters` array (locales, currencies). A new core seeder
  is added to that `run()` and must read those parameters rather than hardcode
  `en_US`/`USD`.
- Seeders must be idempotent — Docker and re-runs call them on populated tables.
  Exemplar test: `packages/Webkul/Installer/tests/Feature/RolesTableSeederIdempotencyTest.php`.
- Reference data that an **existing** install also needs (a new attribute type, a
  new ACL role permission, a new config row) is NOT a seeder change alone —
  seeders do not run on upgrade. Ship it as a data migration too
  ([migrations.md](migrations.md)).

## Web installer

- Routes: `packages/Webkul/Installer/src/Routes/web.php` — `web` +
  `installer_locale`, no admin auth, because no admin exists yet.
- Gates: `packages/Webkul/Installer/src/Http/Middleware/CanInstall.php` and the
  controller (`packages/Webkul/Installer/src/Http/Controllers/InstallerController.php`)
  check `packages/Webkul/Installer/src/Helpers/DatabaseManager.php`:
  `isInstalled()` (admins exist), `isMarkedInstalled()` (DB flag), and
  `canConfirmNotInstalled()` — fail-closed: true only when `core_config` is
  readable and the flag is absent. Every destructive endpoint uses the
  fail-closed one. Regression tests:
  `packages/Webkul/Installer/tests/Feature/InstallerDbStateGateTest.php`,
  `packages/Webkul/Installer/tests/Feature/InstallerSecurityTest.php`.
- Views are exempt from the admin design-system hook rules (they render before
  the theme exists) but still use `installer::` translation keys.

## Registering a new package so install and upgrade pick it up

Scaffolding detail lives in unopim-plugin-development (package-structure.md).
The install/upgrade-relevant points:

1. PSR-4 mapping in the root `composer.json`, then `composer dump-autoload`.
2. Service provider added to `bootstrap/providers.php` — this is what makes
   `loadMigrationsFrom()` run, so `migrate` (install and upgrade alike) sees the
   package's migrations. A package missing here installs with no tables.
3. Concord `ModuleServiceProvider` (extends
   `packages/Webkul/Core/src/Providers/CoreModuleServiceProvider.php`) added to
   the `modules` array in `config/concord.php` for its models/proxies.
4. If the package needs baseline rows on a fresh install, add its seeder to the
   Installer `DatabaseSeeder::run()` (core) or to the package's own install
   command (add-ons — see the `install` key of each entry in
   `installer.optional_packages.packages`).
5. Existing installs get the package's tables and rows only through migrations
   on the next `unopim:upgrade` — never by asking the operator to re-install.
