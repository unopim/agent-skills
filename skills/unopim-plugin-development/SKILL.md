---
name: unopim-plugin-development
description: "Plugin and package development for UnoPim. Activates when creating modules/packages, service providers, models, repositories, controllers, routes, ACL, menus, migrations, credentials, cURL HTTP clients, attribute mapping, or scaffolding a third-party connector (WooCommerce, Shopify, Shopware, REST API). Use references: @quickstart (day-1 connector checklist), @core (package structure, service providers, config), @backend (PHP classes, models, repositories, events), @credentials (credential storage, connection testing, history), @http (cURL ApiClient, BasicAuth/OAuth), @mapping (attribute mapping + history)."
license: MIT
metadata:
  author: unopim
  references:
    - quickstart: Day-1 ordered checklist to ship a complete connector
    - core: Package structure, service providers, ACL, menu, migrations, config
    - backend: PHP classes, models, repositories, events, listeners
    - credentials: Credential storage, connection testing, history, CRUD
    - http: cURL ApiClient with retry, BasicAuth/OAuth strategies
    - mapping: Module attribute mapping and mapping history
---

# Plugin Development in UnoPim

## Overview

A plugin (module/package) is a self-contained Concord module that adds features to UnoPim. This comprehensive skill covers the full lifecycle of building an UnoPim module or third-party connector — from day-1 scaffold to credentials, HTTP client, and attribute mapping.

## When to Apply

Activate this skill when:
- Scaffolding a new UnoPim module or connector (WooCommerce, Shopify, Shopware, any REST API)
- Creating service providers, routes, controllers, repositories, models
- Writing migrations (`Database/Migration/` singular, `wk_`/`DB_PREFIX` tables)
- Configuring ACL (flat arrays), admin menus, and system config
- Building credential storage with connection testing and history
- Writing a cURL-based `ApiClient` (NOT Guzzle / Laravel HTTP)
- Implementing attribute export mapping and mapping history

## Critical Conventions (apply throughout)

- Table prefix via `DB_PREFIX` in `.env` (default `wk_`); use unprefixed names in `DB::table()`.
- Migrations in `Database/Migration/` (singular).
- Route middleware `['admin']` only — never `['web', 'admin']`.
- Models use `HistoryTrait` + implement `PresentableHistoryInterface`.
- Controllers return `JsonResponse` with `redirect_url` + `message`.
- Sensitive fields go in `$auditExclude` — never `Crypt::encryptString()`.
- Connectors use native cURL — not Guzzle, not the Laravel Http facade.
- ACL config = flat arrays (no nested `children`).
- No hardcoded user-facing strings — use `trans('package::file.key')`.


---

# @quickstart: Day-1 Connector Quickstart

## Reference Implementation

All patterns in this guide are verified against the production WooCommerce
connector: `packages/Webkul/WooCommerce/`. When in doubt, refer to that
package's source code.

---

## Prerequisites (15 min)

## Admin UI Rule (CRITICAL)

For all admin Blade forms in connector modules, use UnoPim Blade components first.

- Use `x-admin::form.control-group` wrappers.
- Use `x-admin::form.control-group.label` and `x-admin::form.control-group.error`.
- Use `x-admin::form.control-group.control` for inputs/selects/textareas.
- Do not generate raw `<select>`, `<input>`, `<textarea>`, or `<label>` markup when component equivalents are available.
- Use translations for all labels/placeholders/messages.

For select fields, use component select (`type="select"`) with `:options="json_encode(...)"`, `track-by`, `label-by`, and Vue `@input` binding.

Before coding:
1. Confirm the external API authentication type (Basic Auth / Bearer Token / OAuth)
2. Note the API base URL pattern (e.g. `/wp-json/wc/v3/`, `/api/v1/`, etc.)
3. Decide what entities to sync: Products, Categories, Attributes, Customers, Orders
4. List which direction: export only / import only / bidirectional

---

## Phase 1 — Scaffolding (1–2 hours)

### Step 1: Create directory structure

```
packages/Webkul/{ModuleName}/
├── Config/
├── Routes/
├── Database/
│   ├── Migration/              ← NOT "Migrations" (singular)
│   └── Factories/
├── Resources/
│   ├── lang/en/
│   └── views/
└── src/
    ├── Providers/
    ├── Models/
    ├── Contracts/
    ├── Repositories/
    ├── Http/
    │   ├── Controllers/
    │   ├── Requests/
    │   └── Client/
    ├── DataGrids/
    │   └── Credential/
    ├── Services/
    ├── Helpers/
    │   ├── Exporters/
    │   │   ├── Product/
    │   │   ├── Category/
    │   │   └── Attribute/
    │   └── Importers/
    │       └── Product/
    ├── Validators/
    │   └── JobInstances/
    │       ├── Export/
    │       └── Import/
    └── Presenters/
```

### Step 2: composer.json

```json
{
    "name": "webkul/{module-name}",
    "type": "library",
    "autoload": {
        "psr-4": { "Webkul\\{ModuleName}\\": "src/" }
    },
    "extra": {
        "laravel": {
            "providers": ["Webkul\\{ModuleName}\\Providers\\{ModuleName}ServiceProvider"]
        }
    }
}
```

### Step 3: {ModuleName}ServiceProvider

**Critical rules:**
- Routes: `Route::middleware('web')->group(...)` — NOT `$this->loadRoutesFrom()`
- Event: `unopim.admin.layout.head.before` — NOT without `.before`
- Register `ModuleServiceProvider` inside `register()`

```php
public function boot(): void
{
    Route::middleware('web')->group(__DIR__ . '/../../Routes/{module-name}-routes.php');
    $this->loadViewsFrom(...);
    $this->loadTranslationsFrom(...);
    $this->loadMigrationsFrom(__DIR__ . '/../../Database/Migration');

    Event::listen('unopim.admin.layout.head.before', function ($viewRenderEventManager) {
        $viewRenderEventManager->addTemplate('{module-name}::layouts.head');
    });
}

public function register(): void
{
    $this->app->register(ModuleServiceProvider::class);
    $this->registerConfig();
}

protected function registerConfig(): void
{
    $this->mergeConfigFrom(..., 'acl');
    $this->mergeConfigFrom(..., 'menu');
    $this->mergeConfigFrom(..., 'exporters');
    $this->mergeConfigFrom(..., 'quick_exporters');
    $this->mergeConfigFrom(..., 'importers');
}
```

### Step 4: ModuleServiceProvider

```php
class ModuleServiceProvider extends CoreModuleServiceProvider
{
    protected $models = [
        \Webkul\{ModuleName}\Models\Credential::class,
    ];
}
```

---

## Phase 2 — Database & Model (1 hour)

### Step 5: Migration

- File in: `Database/Migration/` (NOT `Database/Migrations/`)
- Table name: `{module}_credentials` (DB_PREFIX added automatically by Laravel)
- Column names: camelCase matching model `$fillable` (e.g. `apiUrl`, `consumerKey`)
- Include `extras` JSON column for flexible extra config

```php
Schema::create('{module}_credentials', function (Blueprint $table) {
    $table->id();
    $table->string('label');
    $table->string('apiUrl');
    $table->string('consumerKey');
    $table->string('consumerSecret');
    $table->json('extras')->nullable();
    $table->boolean('status')->default(true);
    $table->timestamps();
});
```

### Step 6: Contract Interface

```
src/Contracts/Credential.php   ← interface Credential {}
```

### Step 7: Credential Model

```php
class Credential extends Model implements CredentialContract, PresentableHistoryInterface
{
    use HasFactory, HistoryTrait;

    protected $table = '{module}_credentials';
    protected $casts = ['extras' => 'array', 'status' => 'boolean'];
    protected $auditExclude = ['consumerSecret'];   // never Crypt::encryptString
}
```

### Step 8: CredentialRepository

```php
class CredentialRepository extends Repository
{
    public function model(): string { return Credential::class; }
}
```

---

## Phase 3 — HTTP Client (30 min)

### Step 9: cURL-based ApiClient

Unopim connectors use **native cURL** — NOT Guzzle, NOT Laravel HTTP facade.

```
src/Http/Client/
├── ApiClient.php     ← curl_init / curl_exec / curl_close
└── BasicAuth.php     ← curl_setopt(CURLOPT_HTTPAUTH)
```

Key methods: `configure()`, `buildApiUrl()`, `get()`, `post()`, `put()`, `delete()`

### Step 10: Service class wraps all API calls

```
src/Services/{ModuleName}Service.php
```

Controllers inject `{ModuleName}Service`, never `ApiClient` directly.

---

## Phase 4 — CRUD Controller & Routes (1 hour)

### Step 11: FormRequest

```
src/Http/Requests/CredentialForm.php
```

Never use inline `$request->validate()` in controllers.

### Step 12: CredentialController

- Returns `JsonResponse` with `redirect_url` for store/update/delete
- Inject `CredentialRepository` and `{ModuleName}Service`
- `testConnection()` method for API connectivity check

### Step 13: Routes

```php
// Middleware: ['admin'] only — NOT ['web', 'admin']
Route::group(['middleware' => ['admin'], 'prefix' => config('app.admin_url')], function () {
    // credentials CRUD + test-connection
    // credentials/get  ← required for exporters filter list_route
});
```

---

## Phase 5 — Admin UI (1 hour)

### Step 14: ACL (flat array — no nested children)

```php
return [
    ['key' => '{module-slug}', 'name' => '...', 'route' => '...', 'sort' => 1],
    ['key' => '{module-slug}.credentials', ...],
    ['key' => '{module-slug}.credentials.create', ...],
    ['key' => '{module-slug}.credentials.edit', ...],
    ['key' => '{module-slug}.credentials.delete', ...],
];
```

### Step 15: DataGrid

```
src/DataGrids/Credential/CredentialDataGrid.php
```

Rules:
- `DB::table('{module}_credentials')` in `prepareQueryBuilder()`
- Methods have PHPDoc `@return` only (no PHP type hints)
- Column `closure` uses `fn ($row) =>` (arrow function)
- Action `url` uses `function ($row) { return route(...); }` (regular function)
- Status badges: `label-active` / `label-info text-gray-600 dark:text-gray-300`

### Step 16: Blade views

```
views/credentials/index.blade.php    ← <x-admin::datagrid :src="route(...)" />
views/credentials/create.blade.php
views/credentials/edit.blade.php
```

---

## Phase 6 — Export/Import Workflow (2 hours)

### Step 17: exporters.php (every select field MUST have these 4 keys)

```php
[
    'name'       => 'credential',
    'type'       => 'select',
    'async'      => true,         ← required
    'track_by'   => 'id',         ← required
    'label_by'   => 'label',      ← required
    'list_route' => '{module-slug}.credentials.get',  ← required
]
```

### Step 18: quick_exporters.php (one-click from product listing)

```php
'{ModuleName}QuickExport' => [
    'title'    => '...',
    'route'    => '{module-slug}.quick_export',
    'exporter' => ...,
    'source'   => \Webkul\Product\Repositories\ProductRepository::class,
];
```

### Step 19: importers.php (same filter field structure as exporters)

### Step 20: Exporter & Importer classes

```
src/Helpers/Exporters/{Entity}/Exporter.php   ← extends AbstractExporter
src/Helpers/Importers/{Entity}/Importer.php   ← extends AbstractImporter
```

Each exporter needs: `BATCH_SIZE`, `UNOPIM_ENTITY_NAME`, `ACTION_ADD`, `ACTION_UPDATE`, `CODE_ALREADY_EXIST`, `CODE_NOT_EXIST`

### Step 21: Validator classes

```
src/Validators/JobInstances/Export/ProductsValidator.php
src/Validators/JobInstances/Import/ProductsValidator.php
```

---

## Phase 7 — Lang & Final Polish (30 min)

### Step 22: Translation file

```php
// Resources/lang/en/app.php
return [
    'credentials' => [
        'create-success' => 'Credential created successfully.',
        'update-success' => 'Credential updated successfully.',
        'delete-success' => 'Credential deleted successfully.',
        'test-success'   => 'Connection successful.',
        'test-failed'    => 'Connection failed. Check credentials.',
    ],
    // acl, menu, data-transfer keys...
];
```

### Step 23: Register provider

Add to `bootstrap/providers.php`:

```php
\Webkul\{ModuleName}\Providers\{ModuleName}ServiceProvider::class,
```

---

## Complete Checklist (in order)

### Scaffolding
- [ ] `composer.json` with correct PSR-4 autoload
- [ ] `{ModuleName}ServiceProvider` with `Route::middleware('web')->group()`
- [ ] Event: `unopim.admin.layout.head.before` (with `.before`)
- [ ] `ModuleServiceProvider` extends `CoreModuleServiceProvider` with `$models[]`
- [ ] All 5 configs merged in `registerConfig()`

### Database
- [ ] Migration in `Database/Migration/` (NOT `Migrations`)
- [ ] Tables use DB_PREFIX (auto-added by Laravel)
- [ ] camelCase column names match model `$fillable`
- [ ] `extras` JSON column present

### Model
- [ ] `HistoryTrait` + `PresentableHistoryInterface`
- [ ] `$auditExclude` for sensitive fields
- [ ] `'extras' => 'array'` cast
- [ ] Matching `Contracts/` interface

### Routes & Controller
- [ ] Route middleware: `['admin']` only
- [ ] `credentials/get` route for exporter `list_route`
- [ ] Controller uses `FormRequest` (no inline validate)
- [ ] Controller returns `JsonResponse` with `redirect_url`

### HTTP Client
- [ ] `ApiClient.php` uses cURL (no Guzzle)
- [ ] `BasicAuth.php` or equivalent auth class
- [ ] `{ModuleName}Service.php` wraps all API calls

### DataGrid
- [ ] Subdirectory: `DataGrids/Credential/`
- [ ] PHPDoc `@return` only (no PHP type hints on methods)
- [ ] Column `closure` uses `fn ($row) =>`
- [ ] Action `url` uses `function ($row) { return ...; }`

### Export/Import
- [ ] `exporters.php` filter fields have `async/track_by/label_by/list_route`
- [ ] `quick_exporters.php` created
- [ ] `importers.php` created
- [ ] Exporter classes in `Helpers/Exporters/{Entity}/`
- [ ] Validator classes in `Validators/JobInstances/`

### ACL
- [ ] Flat array (no nested `children`)
- [ ] Permission checks use `bouncer()->hasPermission()`

---

## Skill Cross-Reference

| Topic | Skill to use |
|---|---|
| Full module scaffold | `unopim-package` |
| Credential CRUD + model | `unopim-credential-management` |
| cURL HTTP client | `unopim-http-client` |
| Export/import jobs | `unopim-export-workflow` |
| DataGrid listing | `unopim-datagrid` |
| module mapping | `unopim-connector-export-mapping` |


---

# @core: Package Structure & Scaffold

## Overview

All Unopim third-party connector packages follow the same structure inspired by
`packages/Webkul/WooCommerce/`. Every pattern here is derived from that
production reference implementation.

**Vendor/Module convention:** `Webkul/{ModuleName}` where `{ModuleName}` is
PascalCase (e.g. `WooCommerce`, `Shopify`, `module`, `ShopwareIntegration`).

**Admin UI rule (critical):**
- For admin Blade forms, always use UnoPim Blade components (`x-admin::form.control-group`, `.label`, `.control`, `.error`).
- Do not generate raw `<select>`, `<input>`, `<textarea>`, or `<label>` controls when a component equivalent exists.
- Keep all user-facing text in translation keys.
- For select fields, use component select with `type="select"`, `:options="json_encode(...)"`, `track-by`, `label-by`, and Vue `@input`.

---

## 1. Directory Structure

```
packages/Webkul/{ModuleName}/
├── composer.json
├── Config/
│   ├── acl.php
│   ├── menu.php
│   ├── exporters.php
│   ├── quick_exporters.php
│   └── importers.php
├── Routes/
│   └── {module-name}-routes.php
├── Database/
│   ├── Migration/                               # NOT "Migrations" — singular
│   │   └── 2025_01_01_000000_{module}_credentials.php
│   └── Factories/
│       └── CredentialFactory.php
├── Resources/
│   ├── lang/
│   │   └── en/
│   │       └── app.php
│   └── views/
│       ├── credentials/
│       │   ├── index.blade.php
│       │   ├── create.blade.php
│       │   └── edit.blade.php
│       └── export/
│           └── export.blade.php
└── src/
    ├── Providers/
    │   ├── {ModuleName}ServiceProvider.php          # Main provider
    │   └── ModuleServiceProvider.php                # CoreModuleServiceProvider
    ├── Models/
    │   ├── Credential.php
    │   └── ...
    ├── Contracts/
    │   ├── Credential.php                           # Interface per model
    │   └── ...
    ├── Repositories/
    │   ├── CredentialRepository.php
    │   └── ...
    ├── Http/
    │   ├── Controllers/
    │   │   ├── CredentialController.php
    │   │   └── ...
    │   ├── Requests/
    │   │   ├── CredentialForm.php                   # FormRequest class
    │   │   └── ...
    │   └── Client/
    │       ├── ApiClient.php                        # cURL-based HTTP client
    │       └── BasicAuth.php
    ├── DataGrids/
    │   └── Credential/
    │       └── CredentialDataGrid.php               # Always in subdirectory
    ├── Services/
    │   └── {ModuleName}Service.php                  # Wraps all API calls
    └── Presenters/
        └── CredentialPresenter.php                  # For HistoryControl display
```

---

## 2. composer.json

```json
{
    "name": "webkul/{module-name}",
    "description": "{Module Name} integration for Unopim",
    "type": "library",
    "require": {
        "php": "^8.1"
    },
    "autoload": {
        "psr-4": {
            "Webkul\\{ModuleName}\\": "src/"
        }
    },
    "extra": {
        "laravel": {
            "providers": [
                "Webkul\\{ModuleName}\\Providers\\{ModuleName}ServiceProvider"
            ]
        }
    }
}
```

---

## 3. Main ServiceProvider

The main ServiceProvider handles booting routes, views, translations, events,
and registering configs.

**CRITICAL patterns:**
- Routes must use `Route::middleware('web')->group(...)` — NOT `$this->loadRoutesFrom()`
- Event name for head injection is `unopim.admin.layout.head.before` (with `.before`)
- Six configs must be registered: `acl`, `menu`, `exporters`, `quick_exporters`, `importers`, plus any custom ones
- `loadTranslationsFrom` and `loadViewsFrom` use the module slug as the namespace

```php
<?php

namespace Webkul\{ModuleName}\Providers;

use Illuminate\Routing\Router;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\ServiceProvider;

class {ModuleName}ServiceProvider extends ServiceProvider
{
    /**
     * Bootstrap services.
     */
    public function boot(Router $router): void
    {
        // Routes — must use Route::middleware('web')->group(), NOT loadRoutesFrom()
        Route::middleware('web')->group(
            __DIR__ . '/../../Routes/{module-name}-routes.php'
        );

        // Views
        $this->loadViewsFrom(__DIR__ . '/../../Resources/views', '{module-name}');

        // Translations
        $this->loadTranslationsFrom(
            __DIR__ . '/../../Resources/lang',
            '{module-name}'
        );

        // Migrations
        $this->loadMigrationsFrom(__DIR__ . '/../../Database/Migration');

        // Inject assets/scripts into admin head
        // IMPORTANT: event name ends with ".before"
        Event::listen('unopim.admin.layout.head.before', function ($viewRenderEventManager) {
            $viewRenderEventManager->addTemplate(
                '{module-name}::layouts.head'
            );
        });
    }

    /**
     * Register services.
     */
    public function register(): void
    {
        $this->registerConfig();
    }

    /**
     * Register config files.
     */
    protected function registerConfig(): void
    {
        $this->mergeConfigFrom(__DIR__ . '/../../Config/acl.php',            'acl');
        $this->mergeConfigFrom(__DIR__ . '/../../Config/menu.php',           'menu');
        $this->mergeConfigFrom(__DIR__ . '/../../Config/exporters.php',      'exporters');
        $this->mergeConfigFrom(__DIR__ . '/../../Config/quick_exporters.php', 'quick_exporters');
        $this->mergeConfigFrom(__DIR__ . '/../../Config/importers.php',      'importers');
    }
}
```

---

## 4. ModuleServiceProvider (Model Binding)

Extends `Webkul\Core\Providers\CoreModuleServiceProvider`. Only declare the
`$models` array — never write manual `$app->bind()` calls.

```php
<?php

namespace Webkul\{ModuleName}\Providers;

use Webkul\Core\Providers\CoreModuleServiceProvider;

class ModuleServiceProvider extends CoreModuleServiceProvider
{
    /**
     * Models to register their repository bindings.
     *
     * @var array
     */
    protected $models = [
        \Webkul\{ModuleName}\Models\Credential::class,
        // add more models here
    ];
}
```

Register both providers in `{ModuleName}ServiceProvider::register()`:

```php
public function register(): void
{
    $this->app->register(ModuleServiceProvider::class);
    $this->registerConfig();
}
```

---

## 5. Model (with HistoryTrait)

Every model must use `HistoryTrait` from `Webkul\HistoryControl` and implement
`PresentableHistoryInterface`. Sensitive fields must be excluded via
`$auditExclude`. Use an `extras` JSON column for flexible additional config.

```php
<?php

namespace Webkul\{ModuleName}\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Webkul\{ModuleName}\Contracts\Credential as CredentialContract;
use Webkul\HistoryControl\Interfaces\PresentableHistoryInterface;
use Webkul\HistoryControl\Traits\HistoryTrait;

class Credential extends Model implements CredentialContract, PresentableHistoryInterface
{
    use HasFactory, HistoryTrait;

    /**
     * Table name — always use DB_PREFIX.
     *
     * @var string
     */
    protected $table = '{module}_credentials';

    /**
     * Fillable attributes.
     *
     * @var array
     */
    protected $fillable = [
        'label',
        'apiUrl',
        'consumerKey',
        'consumerSecret',   // secret — excluded from history below
        'extras',
        'status',
    ];

    /**
     * Casts.
     *
     * @var array
     */
    protected $casts = [
        'extras' => 'array',
    ];

    /**
     * Fields excluded from history audit.
     * Sensitive values should never appear in history log.
     *
     * @var array
     */
    protected $auditExclude = [
        'consumerSecret',
    ];

    /**
     * History auditable attributes (subset shown in history UI).
     *
     * @var array
     */
    protected $historyAuditable = [
        'label',
        'apiUrl',
        'consumerKey',
        'status',
    ];
}
```

---

## 6. Contract Interface

Every model must have a matching interface in `src/Contracts/`.

```php
<?php

namespace Webkul\{ModuleName}\Contracts;

interface Credential
{
    // marker interface — methods defined in model
}
```

---

## 7. Routes

Route middleware is `['admin']` only — NOT `['web', 'admin']`.
Webhook routes (if any) must exclude `VerifyCsrfToken`.

```php
<?php

use Illuminate\Support\Facades\Route;
use Webkul\{ModuleName}\Http\Controllers\CredentialController;

Route::group(['middleware' => ['admin'], 'prefix' => config('app.admin_url')], function () {

    Route::prefix('{module-slug}')->name('{module-slug}.')->group(function () {

        // Credentials
        Route::get('credentials',          [CredentialController::class, 'index'])->name('credentials.index');
        Route::get('credentials/create',   [CredentialController::class, 'create'])->name('credentials.create');
        Route::post('credentials',         [CredentialController::class, 'store'])->name('credentials.store');
        Route::get('credentials/{id}/edit',[CredentialController::class, 'edit'])->name('credentials.edit');
        Route::put('credentials/{id}',     [CredentialController::class, 'update'])->name('credentials.update');
        Route::delete('credentials/{id}',  [CredentialController::class, 'destroy'])->name('credentials.destroy');

        // Test connection endpoint
        Route::post('credentials/test-connection', [CredentialController::class, 'testConnection'])
             ->name('credentials.test-connection');
    });

});

// Webhook (no CSRF check)
Route::post('{module-slug}/webhook', [\Webkul\{ModuleName}\Http\Controllers\WebhookController::class, 'handle'])
     ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class])
     ->name('{module-slug}.webhook');
```

---

## 8. ACL Config

Flat array structure — no nested `children` arrays.

```php
<?php

return [
    [
        'key'   => '{module-slug}',
        'name'  => '{module-name}::app.acl.{module-slug}',
        'route' => '{module-slug}.credentials.index',
        'sort'  => 1,
    ],
    [
        'key'   => '{module-slug}.credentials',
        'name'  => '{module-name}::app.acl.credentials',
        'route' => '{module-slug}.credentials.index',
        'sort'  => 1,
    ],
    [
        'key'   => '{module-slug}.credentials.create',
        'name'  => '{module-name}::app.acl.create',
        'route' => '{module-slug}.credentials.create',
        'sort'  => 1,
    ],
    [
        'key'   => '{module-slug}.credentials.edit',
        'name'  => '{module-name}::app.acl.edit',
        'route' => '{module-slug}.credentials.edit',
        'sort'  => 2,
    ],
    [
        'key'   => '{module-slug}.credentials.delete',
        'name'  => '{module-name}::app.acl.delete',
        'route' => '{module-slug}.credentials.destroy',
        'sort'  => 3,
    ],
];
```

---

## 9. Menu Config

```php
<?php

return [
    [
        'key'        => '{module-slug}',
        'name'       => '{module-name}::app.menu.{module-slug}',
        'route'      => '{module-slug}.credentials.index',
        'sort'       => 5,
        'icon'       => 'icon-{module-slug}',
    ],
    [
        'key'        => '{module-slug}.credentials',
        'name'       => '{module-name}::app.menu.credentials',
        'route'      => '{module-slug}.credentials.index',
        'sort'       => 1,
        'icon'       => '',
    ],
];
```

---

## 10. Migration

Table prefix is set via DB_PREFIX in .env (default: wk_). Folder is `Database/Migration/` (NOT `Migrations`).
Column names use camelCase to match model `$fillable` exactly.

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('{module}_credentials', function (Blueprint $table) {
            $table->id();
            $table->string('label');
            $table->string('apiUrl');
            $table->string('consumerKey');
            $table->string('consumerSecret');
            $table->json('extras')->nullable();    // flexible JSON for extra config
            $table->boolean('status')->default(true);
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('{module}_credentials');
    }
};
```

---

## 11. App Service Provider Registration

Register the package providers in the Unopim core `config/app.php` or via
package discovery. For local dev, add to `bootstrap/providers.php`:

```php
\Webkul\{ModuleName}\Providers\{ModuleName}ServiceProvider::class,
```

---

## 12. Checklist for New Module

- [ ] `composer.json` created with correct PSR-4 namespace
- [ ] `{ModuleName}ServiceProvider` uses `Route::middleware('web')->group(...)`
- [ ] `{ModuleName}ServiceProvider` registers `ModuleServiceProvider`
- [ ] `ModuleServiceProvider` extends `CoreModuleServiceProvider` with `$models[]`
- [ ] Event name: `unopim.admin.layout.head.before` (never without `.before`)
- [ ] Migration in `Database/Migration/` (not `Migrations`)
- [ ] Table names use DB_PREFIX (auto-added by Laravel)
- [ ] All models use `HistoryTrait` + implement `PresentableHistoryInterface`
- [ ] All models have `$auditExclude` for sensitive fields
- [ ] All models have `extras` JSON column with `'extras' => 'array'` cast
- [ ] All models have matching `Contracts/` interface
- [ ] ACL is flat array (no nested `children`)
- [ ] `registerConfig()` merges all 5 config files
- [ ] `quick_exporters.php` and `importers.php` both created
- [ ] Route middleware is `['admin']` only

Complete guide for creating, configuring, and deploying UnoPim plugins (packages).

## When to Use This Skill

Invoke this skill when:

- Creating a new plugin/package for UnoPim
- Adding custom importers or exporters
- Extending admin menus, ACL, or system configuration
- Building custom DataGrids
- Creating custom models with Concord proxy pattern

## Instructions

1. **Plugin structure**: See [plugin-structure.md](plugin-structure.md) for directory layout and boilerplate
2. **Service providers**: See [service-providers.md](service-providers.md) for registration and bootstrapping
3. **Config integration**: See [config-integration.md](config-integration.md) for menu, ACL, and system config
4. **Custom importers/exporters**: See [custom-data-transfer.md](custom-data-transfer.md) for import/export profiles

## Quick Start

```bash
# 1. Create directory structure
mkdir -p packages/Webkul/Example/src/{Config,Contracts,Database/Migration,Http/Controllers,Models,Providers,Repositories,Resources/views,Routes}

# 2. Add PSR-4 autoload to composer.json
# "Webkul\\Example\\": "packages/Webkul/Example/src"

# 3. Register in config/app.php providers array
# Webkul\Example\Providers\ExampleServiceProvider::class,

# 4. Dump autoload
composer dump-autoload

# 5. Run migrations
php artisan migrate
```

## Key Principles

- Always use the Concord proxy pattern for models
- Extend `Webkul\Core\Eloquent\Repository` for data access
- Register configs via `mergeConfigFrom()` in `register()`
- Load routes via `Route::middleware('web')->group(...)` and migrations via `loadMigrationsFrom(.../Database/Migration)` in `boot()`
- Follow existing package structure conventions
- Add ACL entries for all new admin routes


---

# @backend: Backend PHP Development

This skill provides guidance for developing UnoPim backend PHP code according to project standards and conventions.

## When to Use This Skill

**ALWAYS invoke this skill before:**

- Writing new PHP tests (`*Test.php` files)
- Creating new PHP classes, models, or repositories
- Modifying existing backend PHP code
- Adding events, listeners, or observers
- Working with Eloquent models and Concord proxies

## Instructions

Follow UnoPim project conventions when adding or modifying backend PHP code:

1. **Coding style**: See [coding-conventions.md](coding-conventions.md) for Laravel/PSR standards
2. **Architecture patterns**: See [architecture.md](architecture.md) for Concord, Repository, Strategy patterns
3. **Models and repositories**: See [models-repositories.md](models-repositories.md) for Eloquent and Concord proxy patterns
4. **Events and listeners**: See [events-listeners.md](events-listeners.md) for event-driven patterns
5. **Writing tests**: See [testing.md](testing.md) for Pest testing conventions

## Key Principles

- Follow Laravel coding standards with `pint` (Laravel preset)
- Use the Repository pattern — all repos extend `Webkul\Core\Eloquent\Repository`
- Use Concord proxy models for model extensibility
- Place new code under the appropriate `packages/Webkul/{Package}/src/` directory
- Use PSR-4 autoloading: `Webkul\{Package}\` namespace
- Events follow `{domain}.{entity}.{action}.{before|after}` naming
- Product/category values use structured JSON with scoping (`common`, `locale_specific`, `channel_specific`, `channel_locale_specific`)
- Run `./vendor/bin/pint` before committing
- Run `./vendor/bin/pest` to verify tests pass


---

# @credentials: Credential Management

## Overview

Credentials store API connection details for a third-party integration.
All patterns are derived from the WooCommerce connector reference implementation.

**Key rules:**
- Table prefix: DB_PREFIX from .env (default wk_) — never hardcode in code
- Migration folder: `Database/Migration/` (NOT `Migrations`)
- Every model uses `HistoryTrait` + implements `PresentableHistoryInterface`
- Sensitive fields (API secrets, passwords) go in `$auditExclude` — NOT `Crypt::encryptString()`
- Flexible extra config uses `extras` JSON column (single column, not many columns)
- Controllers return `JsonResponse` with `redirect_url` for store/update/delete
- Use dedicated `Http/Requests/CredentialForm.php` FormRequest — not inline `$request->validate()`
- A `Services/{ModuleName}Service.php` wraps all API calls

**Admin UI rule (critical):**
- For admin forms, use UnoPim components: `x-admin::form.control-group`, `.label`, `.control`, `.error`.
- Do not generate raw `<select>`, `<input>`, `<textarea>`, or `<label>` when component equivalents exist.
- Use translations for all user-facing form text.
- For dropdowns, use component select with `type="select"`, `:options="json_encode(...)"`, `track-by`, `label-by`, and Vue `@input` handling.

---

## 1. Migration

```php
<?php
// Database/Migration/2025_01_01_000000_{module}_credentials.php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('{module}_credentials', function (Blueprint $table) {
            $table->id();
            $table->string('label');
            $table->string('apiUrl');
            $table->string('consumerKey');
            $table->string('consumerSecret');          // stored plaintext; excluded from history
            $table->string('storeId')->nullable();
            $table->json('extras')->nullable();        // flexible JSON for additional config
            $table->boolean('status')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('{module}_credentials');
    }
};
```

---

## 2. Contract Interface

```php
<?php
// src/Contracts/Credential.php

namespace Webkul\{ModuleName}\Contracts;

interface Credential
{
    // marker interface
}
```

---

## 3. Credential Model

```php
<?php
// src/Models/Credential.php

namespace Webkul\{ModuleName}\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Webkul\{ModuleName}\Contracts\Credential as CredentialContract;
use Webkul\HistoryControl\Interfaces\PresentableHistoryInterface;
use Webkul\HistoryControl\Traits\HistoryTrait;

class Credential extends Model implements CredentialContract, PresentableHistoryInterface
{
    use HasFactory, HistoryTrait;

    /**
     * Table — always DB_PREFIX.
     *
     * @var string
     */
    protected $table = '{module}_credentials';

    /**
     * @var array
     */
    protected $fillable = [
        'label',
        'apiUrl',
        'consumerKey',
        'consumerSecret',
        'storeId',
        'extras',
        'status',
    ];

    /**
     * @var array
     */
    protected $casts = [
        'extras' => 'array',
        'status' => 'boolean',
    ];

    /**
     * Fields excluded from audit history.
     * Use this instead of Crypt::encryptString() for secrets.
     *
     * @var array
     */
    protected $auditExclude = [
        'consumerSecret',
    ];

    /**
     * Fields shown in history UI.
     *
     * @var array
     */
    protected $historyAuditable = [
        'label',
        'apiUrl',
        'consumerKey',
        'storeId',
        'status',
    ];
}
```

---

## 4. CredentialRepository

```php
<?php
// src/Repositories/CredentialRepository.php

namespace Webkul\{ModuleName}\Repositories;

use Webkul\Core\Eloquent\Repository;
use Webkul\{ModuleName}\Contracts\Credential;

class CredentialRepository extends Repository
{
    /**
     * Specify model class.
     */
    public function model(): string
    {
        return Credential::class;
    }
}
```

---

## 5. FormRequest

Never use inline `$request->validate()` in the controller.
Use a dedicated `Http/Requests/CredentialForm.php` class.

```php
<?php
// src/Http/Requests/CredentialForm.php

namespace Webkul\{ModuleName}\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class CredentialForm extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Validation rules.
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $credentialId = $this->route('id');

        return [
            'label'          => 'required|string|max:255|unique:{module}_credentials,label' . ($credentialId ? ",{$credentialId}" : ''),
            'apiUrl'         => 'required|url',
            'consumerKey'    => 'required|string',
            'consumerSecret' => $credentialId ? 'nullable|string' : 'required|string',
            'status'         => 'required|boolean',
        ];
    }

    /**
     * Custom attribute names in messages.
     *
     * @return array<string, string>
     */
    public function attributes(): array
    {
        return [
            'apiUrl'         => trans('{module-name}::app.credentials.api-url'),
            'consumerKey'    => trans('{module-name}::app.credentials.consumer-key'),
            'consumerSecret' => trans('{module-name}::app.credentials.consumer-secret'),
        ];
    }
}
```

---

## 6. CredentialController

Controllers must:
- Return `JsonResponse` with `redirect_url` for store/update/delete (not redirect())
- Guard with `bouncer()->hasPermission()` for ACL
- Use the FormRequest type-hint for automatic validation

```php
<?php
// src/Http/Controllers/CredentialController.php

namespace Webkul\{ModuleName}\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Routing\Controller;
use Webkul\{ModuleName}\DataGrids\Credential\CredentialDataGrid;
use Webkul\{ModuleName}\Http\Requests\CredentialForm;
use Webkul\{ModuleName}\Repositories\CredentialRepository;
use Webkul\{ModuleName}\Services\{ModuleName}Service;

class CredentialController extends Controller
{
    public function __construct(
        protected CredentialRepository $credentialRepository,
        protected {ModuleName}Service $service,
    ) {}

    /**
     * List credentials.
     */
    public function index()
    {
        if (request()->ajax()) {
            return app(CredentialDataGrid::class)->toJson();
        }

        return view('{module-name}::credentials.index');
    }

    /**
     * Create form.
     */
    public function create()
    {
        return view('{module-name}::credentials.create');
    }

    /**
     * Store a new credential.
     */
    public function store(CredentialForm $request): JsonResponse
    {
        $credential = $this->credentialRepository->create($request->validated());

        return new JsonResponse([
            'redirect_url' => route('{module-slug}.credentials.index'),
            'message'      => trans('{module-name}::app.credentials.create-success'),
        ]);
    }

    /**
     * Edit form.
     */
    public function edit(int $id)
    {
        $credential = $this->credentialRepository->findOrFail($id);

        return view('{module-name}::credentials.edit', compact('credential'));
    }

    /**
     * Update an existing credential.
     */
    public function update(CredentialForm $request, int $id): JsonResponse
    {
        $data = $request->validated();

        // Don't overwrite secret if left blank on edit
        if (empty($data['consumerSecret'])) {
            unset($data['consumerSecret']);
        }

        $this->credentialRepository->update($data, $id);

        return new JsonResponse([
            'redirect_url' => route('{module-slug}.credentials.index'),
            'message'      => trans('{module-name}::app.credentials.update-success'),
        ]);
    }

    /**
     * Delete a credential.
     */
    public function destroy(int $id): JsonResponse
    {
        $this->credentialRepository->delete($id);

        return new JsonResponse([
            'message' => trans('{module-name}::app.credentials.delete-success'),
        ]);
    }

    /**
     * Test the API connection for a credential.
     */
    public function testConnection(): JsonResponse
    {
        $validated = request()->validate([
            'apiUrl'         => 'required|url',
            'consumerKey'    => 'required|string',
            'consumerSecret' => 'required|string',
        ]);

        try {
            $connected = $this->service->testConnection(
                $validated['apiUrl'],
                $validated['consumerKey'],
                $validated['consumerSecret'],
            );

            if ($connected) {
                return new JsonResponse(['message' => trans('{module-name}::app.credentials.test-success')]);
            }

            return new JsonResponse(
                ['error' => trans('{module-name}::app.credentials.test-failed')],
                422
            );
        } catch (\Throwable $e) {
            return new JsonResponse(['error' => $e->getMessage()], 422);
        }
    }
}
```

---

## 7. Service Class

A service class wraps all external API calls so controllers stay thin.

```php
<?php
// src/Services/{ModuleName}Service.php

namespace Webkul\{ModuleName}\Services;

use Webkul\{ModuleName}\Http\Client\ApiClient;
use Webkul\{ModuleName}\Models\Credential;

class {ModuleName}Service
{
    protected ApiClient $client;

    public function __construct(ApiClient $client)
    {
        $this->client = $client;
    }

    /**
     * Test if the API credentials are valid.
     */
    public function testConnection(string $apiUrl, string $key, string $secret): bool
    {
        $this->client->configure($apiUrl, $key, $secret);

        $response = $this->client->get('system_status');

        return isset($response['environment']);
    }

    /**
     * Set client from a stored credential.
     */
    public function useCredential(Credential $credential): static
    {
        $this->client->configure(
            $credential->apiUrl,
            $credential->consumerKey,
            $credential->consumerSecret,
        );

        return $this;
    }
}
```

---

## 8. Credential Presenter (HistoryControl)

```php
<?php
// src/Presenters/CredentialPresenter.php

namespace Webkul\{ModuleName}\Presenters;

use Webkul\HistoryControl\Presenters\BasePresenter;

class CredentialPresenter extends BasePresenter
{
    /**
     * Label shown on history timeline.
     */
    public function getTitle(): string
    {
        return trans('{module-name}::app.credentials.title');
    }
}
```

---

## 9. Checklist

- [ ] Table name uses DB_PREFIX (auto-added)
- [ ] Migration in `Database/Migration/` folder
- [ ] Model uses `HistoryTrait` + `PresentableHistoryInterface`
- [ ] Model has `$auditExclude` for secret fields (no `Crypt::encryptString`)
- [ ] Model has `extras` JSON column with `'extras' => 'array'` cast
- [ ] Contract interface exists in `src/Contracts/`
- [ ] `ModuleServiceProvider` lists the model in `$models[]`
- [ ] Dedicated `Http/Requests/CredentialForm.php` used (not inline validate)
- [ ] Controller returns `JsonResponse` with `redirect_url`
- [ ] Edit flow keeps existing secret when field left blank
- [ ] Service class created for API test connection logic
- [ ] Presenter created for history display


---

# @http: cURL HTTP Client

## Overview

Unopim connectors use **native cURL** for HTTP communication — not Guzzle,
not Laravel's `Http` facade. This matches the production WooCommerce connector
reference (`ApiClient.php` / `BasicAuth.php`).

**Key rules:**
- Use `curl_init()` / `curl_setopt_array()` / `curl_exec()` / `curl_close()`
- Always check `curl_errno()` after exec
- Auth classes set cURL options on the handle — not HTTP headers separately
- An `ApiClient` class wraps all HTTP methods (get/post/put/delete)
- A `Service` class uses `ApiClient` — controllers never call `ApiClient` directly

**Admin UI compatibility rule:**
- If this skill also generates admin Blade setup or credential forms, use UnoPim form components (`x-admin::form.control-group`, `.label`, `.control`, `.error`) instead of raw HTML controls.

---

## 1. Auth: BasicAuth

Used by WooCommerce (consumer key + secret as HTTP Basic).

```php
<?php
// src/Http/Client/BasicAuth.php

namespace Webkul\{ModuleName}\Http\Client;

class BasicAuth
{
    /**
     * @param string $key    Consumer key / API key
     * @param string $secret Consumer secret / API secret
     */
    public function __construct(
        protected string $key,
        protected string $secret,
    ) {}

    /**
     * Apply Basic Auth credentials to a cURL handle.
     *
     * @param resource|\CurlHandle $ch
     */
    public function apply($ch): void
    {
        curl_setopt($ch, CURLOPT_HTTPAUTH, CURLAUTH_BASIC);
        curl_setopt($ch, CURLOPT_USERPWD, $this->key . ':' . $this->secret);
    }
}
```

---

## 2. Auth: BearerToken (OAuth / JWT)

```php
<?php
// src/Http/Client/BearerToken.php

namespace Webkul\{ModuleName}\Http\Client;

class BearerToken
{
    public function __construct(protected string $token) {}

    /**
     * Apply Bearer token to a cURL handle.
     *
     * @param resource|\CurlHandle $ch
     */
    public function apply($ch): void
    {
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Authorization: Bearer ' . $this->token,
            'Content-Type: application/json',
            'Accept: application/json',
        ]);
    }
}
```

---

## 3. ApiClient

```php
<?php
// src/Http/Client/ApiClient.php

namespace Webkul\{ModuleName}\Http\Client;

use Webkul\{ModuleName}\Exceptions\ApiException;

class ApiClient
{
    protected string $baseUrl = '';

    protected BasicAuth|BearerToken|null $auth = null;

    /**
     * Configure the client for a specific credential.
     */
    public function configure(string $baseUrl, string $key, string $secret): static
    {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->auth    = new BasicAuth($key, $secret);

        return $this;
    }

    /**
     * Configure with a Bearer token (e.g. after OAuth exchange).
     */
    public function configureWithToken(string $baseUrl, string $token): static
    {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->auth    = new BearerToken($token);

        return $this;
    }

    /**
     * Build a full API URL from an endpoint path.
     */
    public function buildApiUrl(string $endpoint): string
    {
        // Subclasses can override to add a version prefix, e.g. /wp-json/wc/v3/
        return $this->baseUrl . '/' . ltrim($endpoint, '/');
    }

    /**
     * Issue a GET request.
     *
     * @param  array<string,mixed> $params  Query parameters
     * @return array<mixed>
     */
    public function get(string $endpoint, array $params = []): array
    {
        $url = $this->buildApiUrl($endpoint);

        if ($params) {
            $url .= '?' . http_build_query($params);
        }

        return $this->execute('GET', $url);
    }

    /**
     * Issue a POST request.
     *
     * @param  array<mixed> $data  JSON body
     * @return array<mixed>
     */
    public function post(string $endpoint, array $data = []): array
    {
        return $this->execute('POST', $this->buildApiUrl($endpoint), $data);
    }

    /**
     * Issue a PUT request.
     *
     * @param  array<mixed> $data
     * @return array<mixed>
     */
    public function put(string $endpoint, array $data = []): array
    {
        return $this->execute('PUT', $this->buildApiUrl($endpoint), $data);
    }

    /**
     * Issue a DELETE request.
     *
     * @return array<mixed>
     */
    public function delete(string $endpoint): array
    {
        return $this->execute('DELETE', $this->buildApiUrl($endpoint));
    }

    /**
     * Execute a cURL request.
     *
     * @param  array<mixed>|null $data
     * @return array<mixed>
     *
     * @throws ApiException
     */
    protected function execute(string $method, string $url, ?array $data = null): array
    {
        $ch = curl_init();

        $options = [
            CURLOPT_URL            => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 30,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_HTTPHEADER     => [
                'Content-Type: application/json',
                'Accept: application/json',
            ],
        ];

        match ($method) {
            'POST'   => $options[CURLOPT_POST]      = true,
            'PUT'    => $options[CURLOPT_CUSTOMREQUEST] = 'PUT',
            'DELETE' => $options[CURLOPT_CUSTOMREQUEST] = 'DELETE',
            default  => null,
        };

        if ($data !== null) {
            $options[CURLOPT_POSTFIELDS] = json_encode($data);
        }

        curl_setopt_array($ch, $options);

        // Apply auth strategy
        if ($this->auth) {
            $this->auth->apply($ch);
        }

        $response = curl_exec($ch);
        $errno    = curl_errno($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($errno) {
            throw new ApiException("cURL error [{$errno}]: " . curl_strerror($errno));
        }

        if ($httpCode >= 400) {
            $body = json_decode($response ?: '', true) ?? [];
            $msg  = $body['message'] ?? "HTTP {$httpCode} from {$url}";
            throw new ApiException($msg, $httpCode);
        }

        return json_decode($response ?: '[]', true) ?? [];
    }
}
```

---

## 4. WooCommerce ApiClient (Subclass Example)

For WooCommerce REST API v3, the base URL includes the WP REST prefix:

```php
<?php
// src/Http/Client/WooCommerceApiClient.php

namespace Webkul\WooCommerce\Http\Client;

class WooCommerceApiClient extends ApiClient
{
    /**
     * WooCommerce API uses /wp-json/wc/v3/ prefix.
     */
    public function buildApiUrl(string $endpoint): string
    {
        return $this->baseUrl . '/wp-json/wc/v3/' . ltrim($endpoint, '/');
    }
}
```

---

## 5. ApiException

```php
<?php
// src/Exceptions/ApiException.php

namespace Webkul\{ModuleName}\Exceptions;

use RuntimeException;

class ApiException extends RuntimeException
{
    public function __construct(
        string $message,
        int $code = 0,
        ?\Throwable $previous = null
    ) {
        parent::__construct($message, $code, $previous);
    }
}
```

---

## 6. OAuth Token Client (for token-based APIs like Shopify)

```php
<?php
// src/Http/Client/OAuthClient.php

namespace Webkul\{ModuleName}\Http\Client;

use Webkul\{ModuleName}\Exceptions\ApiException;

class OAuthClient
{
    /**
     * Exchange authorization code for an access token.
     *
     * @return array{access_token: string, scope: string}
     * @throws ApiException
     */
    public function exchangeCode(
        string $shopDomain,
        string $clientId,
        string $clientSecret,
        string $code
    ): array {
        $url = "https://{$shopDomain}/admin/oauth/access_token";

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL            => $url,
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => json_encode([
                'client_id'     => $clientId,
                'client_secret' => $clientSecret,
                'code'          => $code,
            ]),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
        ]);

        $response = curl_exec($ch);
        $errno    = curl_errno($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($errno) {
            throw new ApiException('OAuth exchange cURL error: ' . curl_strerror($errno));
        }

        $data = json_decode($response ?: '', true) ?? [];

        if ($httpCode !== 200 || empty($data['access_token'])) {
            throw new ApiException('OAuth token exchange failed: ' . ($data['error'] ?? 'unknown'));
        }

        return $data;
    }
}
```

---

## 7. Service Provider Binding

Register `ApiClient` in the module ServiceProvider so it can be injected:

```php
// In {ModuleName}ServiceProvider::register()
$this->app->singleton(\Webkul\{ModuleName}\Http\Client\ApiClient::class);
$this->app->singleton(\Webkul\{ModuleName}\Services\{ModuleName}Service::class);
```

---

## 8. Usage in Service Layer

```php
<?php
// src/Services/{ModuleName}Service.php

namespace Webkul\{ModuleName}\Services;

use Webkul\{ModuleName}\Http\Client\ApiClient;
use Webkul\{ModuleName}\Models\Credential;

class {ModuleName}Service
{
    public function __construct(protected ApiClient $client) {}

    public function testConnection(string $apiUrl, string $key, string $secret): bool
    {
        $this->client->configure($apiUrl, $key, $secret);
        $response = $this->client->get('system_status');
        return isset($response['environment']);
    }

    public function useCredential(Credential $credential): static
    {
        $this->client->configure(
            $credential->apiUrl,
            $credential->consumerKey,
            $credential->consumerSecret,
        );
        return $this;
    }
}
```

---

## 9. Checklist

- [ ] `ApiClient` uses cURL (no Guzzle, no Laravel Http facade)
- [ ] Auth strategies (`BasicAuth`, `BearerToken`) are separate classes
- [ ] Auth classes call `curl_setopt()` directly on the handle
- [ ] Always call `curl_errno()` after `curl_exec()`
- [ ] Always call `curl_close()` after use
- [ ] HTTP errors (4xx/5xx) throw `ApiException` with code
- [ ] `buildApiUrl()` is overridable in subclasses for version-prefix APIs
- [ ] `ApiClient` and `Service` registered as singletons in ServiceProvider
- [ ] Controllers never use `ApiClient` directly — always via Service
- [ ] OAuth flow uses separate `OAuthClient` class


---

# @mapping: Attribute Export Mapping

You are a senior Unopim backend engineer.

This skill applies when:

- Creating module Attribute Mapping UI
- Creating module mapping controller
- Removing Custom Field Mapping tab
- Restricting mapping fields to module structure
- Implementing mapping history

---

## 1. Allowed Tabs (STRICT)

## Admin UI Rule (CRITICAL)

When generating or updating admin Blade forms, always use UnoPim Blade components.

- Use `x-admin::form.control-group` wrappers.
- Use `x-admin::form.control-group.label` for labels.
- Use `x-admin::form.control-group.control` for inputs/selects/textareas.
- Use `x-admin::form.control-group.error` for validation errors.
- Do not generate raw `<select>`, `<input>`, `<textarea>`, or `<label>` controls when a component equivalent exists.
- Keep all user-facing text in translation keys.

For select dropdowns, use `type="select"` with `:options="json_encode(...)"`, `track-by`, `label-by`, and Vue `@input` event binding.

module Export Mapping must contain ONLY:

- ✅ Attribute Mapping
- ✅ History

❌ Remove Custom Fields Mapping  
❌ Remove Other Mapping  
❌ Do NOT create extra tabs

UI must match:

```
Attribute Mapping | History
```

---

## 2. Route Structure (STRICT UNOPIM STANDARD)

Must follow `config('app.admin_url')` with `middleware => ['admin']`.
(The `web` middleware is already applied in the ServiceProvider's
`Route::middleware('web')->group(...)` — do NOT repeat it in routes.)

```php
Route::group(['middleware' => ['admin'], 'prefix' => config('app.admin_url')], function () {
    Route::prefix('module')->group(function () {
        Route::prefix('export-mapping')->group(function () {

            Route::controller(AttributeMappingController::class)
                ->prefix('attribute-mapping')
                ->group(function () {
                    Route::get('', 'index')
                        ->name('module.export_mappings.attribute_mapping.index');
                    Route::post('save', 'store')
                        ->name('module.export_mappings.attribute_mapping.store');
                });

            Route::controller(MappingHistoryController::class)
                ->group(function () {
                    Route::get('history', 'index')
                        ->name('module.export_mappings.history');
                });
        });
    });
});
```

---

## 3. module Attribute Mapping Fields (STRICT FIELD SET)

| module Field              | Required Unopim Attribute Type     |
| ------------------------- | ---------------------------------- |
| EAN                       | text                               |
| Product Code              | text OR number                     |
| Vendor (Brand)            | simple select OR text              |
| Name                      | text                               |
| Title                     | text                               |
| Description               | textarea                           |
| Short Description         | textarea                           |
| Summary Description       | textarea                           |
| Short Summary Description | textarea                           |
| Pictures                  | image (multiple selection allowed) |

❌ Do NOT allow unsupported attribute types  
❌ Do NOT allow dynamic field injection  
❌ Do NOT allow additional fields

---

## 4. Attribute Type Validation Rule (MANDATORY)

```php
$allowedTypes = [
    'ean'                       => ['text'],
    'product_code'              => ['text', 'number'],
    'vendor'                    => ['select', 'text'],
    'name'                      => ['text'],
    'title'                     => ['text'],
    'description'               => ['textarea'],
    'short_description'         => ['textarea'],
    'summary_description'       => ['textarea'],
    'short_summary_description' => ['textarea'],
    'pictures'                  => ['image'],
];
```

If mismatch → throw validation error with field name.

---

## 5. Pictures Attribute Rule

- Allow selecting image-type attributes only
- Allow multiple images (multi-select)
- Store as JSON array
- Validate attribute type = image on save

---

## 6. Database Structure

### Table: `module_attribute_mappings`

| Column                | Type       | Notes               |
| --------------------- | ---------- | ------------------- |
| id                    | bigInt PK  |                     |
| attribute_code        | string     | module field key    |
| unopim_attribute_id   | bigInt FK  |                     |
| default_value         | json null  | Optional defaults   |
| created_at / updated_at | timestamps |                  |

For pictures: store multiple attribute IDs as JSON array.

### Table: `module_mapping_histories`

| Column      | Type       | Notes                    |
| ----------- | ---------- | ------------------------ |
| id          | bigInt PK  |                          |
| action_type | string     | create / update          |
| user_id     | bigInt FK  |                          |
| payload     | json       | Full snapshot of mapping |
| created_at  | timestamp  |                          |

---

## 7. Store Flow

1. Validate attribute type compatibility
2. Validate all required fields are mapped (EAN, Product Code, Name, Description)
3. Store mapping (upsert)
4. Save history snapshot

---

## 8. Required Mandatory Fields

Must be mapped before saving:

- EAN
- Product Code
- Name
- Description

If any missing → block save with validation error.

---

## 9. Controller Requirements

Generate two controllers:

- `AttributeMappingController` — index + store
- `MappingHistoryController` — index only

Rules:
- No DB logic in controllers
- Use repository injection
- Validate types before storing
- Log history on every save

---

## 10. UI Rules

Table columns: `module Field | Unopim Field | Default Value`

- Default value column is optional per field
- Pictures field must render multi-select dropdown (image attributes only)
- Use Unopim admin blade components

---

## 11. Security & Validation Rules

- Only admin users via `middleware(['admin'])` (NOT `['web', 'admin']`)
- Validate attribute exists in Unopim
- Validate attribute type against allowed set
- Prevent duplicate mappings per attribute_code
- Prevent invalid attribute IDs
- Log errors with `Log::error()`

---

## 12. Output Requirements

When generating module Export Mapping module, MUST generate:

- Migration: `module_attribute_mappings`
- Migration: `module_mapping_histories`
- Model + Contract interface for each table
- Repository for each model
- `AttributeMappingController`
- `MappingHistoryController`
- Validation logic (type-aware)
- Routes file (strict Unopim structure)
- Blade view (exactly 2 tabs)
- ACL entry in `acl.php`
- Menu entry in `menu.php`

---

## FINAL RULE

module export mapping must be:

- Minimal (2 tabs only)
- Strictly validated with type-checking
- Attribute-type restricted
- History-tracked on every change
- Unopim route compliant
- Clean and repository-driven
