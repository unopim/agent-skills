# Package Structure and Service Providers

Reference: `packages/Webkul/AiAgent` (connector-style plugin).

## Contents

- Directory layout
- composer.json
- Main service provider
- ModuleServiceProvider — Concord model binding
- Application registration
- Menu config
- Database rules

## Directory layout

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
│   └── {module}-routes.php
├── Database/
│   ├── Migration/
│   └── Factories/
├── Resources/
│   ├── lang/en_US/app.php
│   └── views/
└── src/
    ├── Providers/
    ├── Contracts/
    ├── Models/
    ├── Repositories/
    ├── Http/{Controllers,Requests,Client}/
    ├── DataGrids/{Section}/
    ├── Services/
    ├── Exceptions/
    └── Presenters/
```

Migration folder rules — get this wrong and migrations silently never run:

- Plugin-style packages (exemplar: `packages/Webkul/AiAgent/Database/Migration`): root-level
  `Database/Migration/` (singular), loaded by the provider's `loadMigrationsFrom()`.
- Core packages keep migrations in `src/Database/Migrations/` (plural, under `src/`).
- NEVER assert one layout for all packages; match the package you are editing.

## composer.json

```json
{
    "name": "webkul/{module-name}",
    "description": "{Module Name} integration for UnoPim",
    "type": "library",
    "require": {
        "php": "^8.4"
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

Also add `"Webkul\\{ModuleName}\\": "packages/Webkul/{ModuleName}/src"` to the root
`composer.json` `autoload.psr-4` block (every Webkul package is mapped there), then run
`composer dump-autoload`.

## Main service provider

Exemplar: `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php`.

MUST: routes via `Route::middleware('web')->group()` (not `loadRoutesFrom()`); menu
merged into `'menu.admin'` (the sidebar reads only `config('menu.admin')` — a module
merged into `'menu'` never appears); stateful bindings `scoped()`.

```php
<?php

namespace Webkul\{ModuleName}\Providers;

use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\ServiceProvider;
use Webkul\{ModuleName}\Http\Client\ApiClient;
use Webkul\{ModuleName}\Services\{ModuleName}Service;

class {ModuleName}ServiceProvider extends ServiceProvider
{
    /**
     * Bootstrap services.
     */
    public function boot(): void
    {
        Route::middleware('web')->group(__DIR__.'/../../Routes/{module}-routes.php');

        $this->loadViewsFrom(__DIR__.'/../../Resources/views', '{module}');

        $this->loadTranslationsFrom(__DIR__.'/../../Resources/lang', '{module}');

        $this->loadMigrationsFrom(__DIR__.'/../../Database/Migration');

        Event::listen('unopim.admin.layout.head.before', function ($viewRenderEventManager): void {
            $viewRenderEventManager->addTemplate('{module}::layouts.head');
        });
    }

    /**
     * Register services.
     */
    public function register(): void
    {
        $this->app->register(ModuleServiceProvider::class);

        $this->registerConfig();
        $this->registerBindings();
    }

    /**
     * Merge package config files.
     */
    protected function registerConfig(): void
    {
        $this->mergeConfigFrom(__DIR__.'/../../Config/acl.php', 'acl');
        $this->mergeConfigFrom(__DIR__.'/../../Config/menu.php', 'menu.admin');
        $this->mergeConfigFrom(__DIR__.'/../../Config/exporters.php', 'exporters');
        $this->mergeConfigFrom(__DIR__.'/../../Config/quick_exporters.php', 'quick_exporters');
        $this->mergeConfigFrom(__DIR__.'/../../Config/importers.php', 'importers');
    }

    /**
     * Register container bindings.
     */
    protected function registerBindings(): void
    {
        $this->app->scoped(ApiClient::class);
        $this->app->scoped({ModuleName}Service::class);
    }
}
```

The head-injection event listener is optional — add it only when the module ships admin
assets. The layout fires `unopim.admin.layout.head.before` (see
`packages/Webkul/Admin/src/Resources/views/components/layouts/index.blade.php`).

## ModuleServiceProvider — Concord model binding

Exemplar: `packages/Webkul/AiAgent/src/Providers/ModuleServiceProvider.php`. Declare the
`$models` array only; `CoreModuleServiceProvider` wires proxies and repositories — never
write manual `bind()` calls for models.

```php
<?php

namespace Webkul\{ModuleName}\Providers;

use Webkul\{ModuleName}\Models\Credential;
use Webkul\Core\Providers\CoreModuleServiceProvider;

class ModuleServiceProvider extends CoreModuleServiceProvider
{
    /**
     * Models to register their repository bindings.
     *
     * @var array
     */
    protected $models = [
        Credential::class,
    ];
}
```

## Application registration

Add the provider to the array returned by `bootstrap/providers.php` (Laravel 13
skeleton). `config('app.php')` has NO providers array — do not send agents there.

```php
Webkul\{ModuleName}\Providers\{ModuleName}ServiceProvider::class,
```

Then list the `ModuleServiceProvider` in the `modules` array of `config/concord.php`.
Every first-party package with models is listed there, including those whose service
provider also calls `$this->app->register(ModuleServiceProvider::class)`
(`packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php`) — follow suit.

```php
Webkul\{ModuleName}\Providers\ModuleServiceProvider::class,
```

## Menu config

Exemplar: `packages/Webkul/AiAgent/Config/menu.php`. Flat entries; sub-items nest by
dotted `key`.

```php
<?php

return [
    [
        'key'   => '{module}',
        'name'  => '{module}::app.menu.{module}',
        'route' => '{module}.credentials.index',
        'sort'  => 8,
        'icon'  => 'icon-settings',
    ],
    [
        'key'   => '{module}.credentials',
        'name'  => '{module}::app.menu.credentials',
        'route' => '{module}.credentials.index',
        'sort'  => 1,
        'icon'  => '',
    ],
];
```

## Database rules

- Table names are bare (`{module}_credentials`) — the prefix comes from
  `env('DB_PREFIX', '')` and the default is EMPTY. Never claim tables "use wk_".
- `DB::table()` and `Schema::create()` take unprefixed names; Laravel applies whatever
  prefix is configured.
- Raw SQL fragments (`DB::raw`, `selectRaw`, `whereRaw`, `orderByRaw`) that name a table
  MUST prepend `DB::getTablePrefix()` (exemplar:
  `packages/Webkul/Measurement/src/DataGrids/UnitDataGrid.php`).
- MySQL AND PostgreSQL are both supported: no `GROUP_CONCAT`, no backticks, no
  `DATE_FORMAT`. Cross-DB SQL goes through the core `DB::rawQueryGrammar()` macro
  (`packages/Webkul/Core/src/Helpers/Database/Grammars/MySQLGrammar.php`); one-off
  branches test `DB::getDriverName() === 'pgsql'`.
- Data migrations stream with `cursor()`/`chunkById()` — catalog tables hold millions of
  rows.
