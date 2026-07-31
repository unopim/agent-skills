# Backend: Models, Repositories, Events, Bindings

## Contents

- Model house style (Laravel 13 / PHP 8.4)
- Contract interface
- Repository
- Events
- Container bindings — Octane safety
- Scale rules (catalog tables hold millions of rows)

## Model house style (Laravel 13 / PHP 8.4)

Models use PHP attributes plus a `casts(): array` method — NEVER the legacy
`protected $fillable`/`$casts`/`$table` properties (53 model files use `#[Fillable]`;
nine legacy models still declare the properties and are frozen debt, never
precedent). A new one is hook-blocked. Exemplar:
`packages/Webkul/AiAgent/src/Models/Credential.php`.

```php
<?php

namespace Webkul\{ModuleName}\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Table;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Webkul\{ModuleName}\Contracts\Setting as SettingContract;

#[Fillable([
    'code',
    'label',
    'extras',
    'status',
])]
#[Table(name: '{module}_settings')]
class Setting extends Model implements SettingContract
{
    use HasFactory;

    /**
     * Casts.
     */
    protected function casts(): array
    {
        return [
            'extras' => 'array',
            'status' => 'boolean',
        ];
    }
}
```

If the model needs history/audit (any admin-editable record does), follow the full
pattern in [credentials.md](credentials.md) — the trio of contracts, `getPresenters()`
and `$historyTags` are each load- or save-fatal when missing.

### Array-cast pitfall

`$model->extras['key'] = $value;` NEVER persists (indirect modification of an overloaded
property). Read the whole array, modify, reassign:

```php
$extras = $model->extras ?? [];
$extras['last_sync'] = now()->toISOString();
$model->extras = $extras;
$model->save();
```

## Contract interface

Every model gets a marker interface in `src/Contracts/` (Concord convention; exemplar
`packages/Webkul/AiAgent/src/Contracts/Credential.php`), listed in
`ModuleServiceProvider::$models`.

```php
<?php

namespace Webkul\{ModuleName}\Contracts;

interface Setting
{
}
```

## Repository

All queries go through a repository extending `Webkul\Core\Eloquent\Repository`
(`packages/Webkul/Core/src/Eloquent/Repository.php`) — no Eloquent in controllers.
Exemplar: `packages/Webkul/AiAgent/src/Repositories/CredentialRepository.php`.

```php
<?php

namespace Webkul\{ModuleName}\Repositories;

use Webkul\{ModuleName}\Models\Setting;
use Webkul\Core\Eloquent\Repository;

class SettingRepository extends Repository
{
    /**
     * Specify model class name.
     */
    public function model(): string
    {
        return Setting::class;
    }

    /**
     * Get active settings list for dropdowns.
     */
    public function getActiveList(): \Illuminate\Support\Collection
    {
        return $this->model
            ->where('status', true)
            ->select('id', 'label')
            ->get();
    }
}
```

## Events

- Naming: `{domain}.{entity}.{action}.{before|after}` — e.g.
  `catalog.product.create.after`.
- Listen in the provider's `boot()`:
  `Event::listen('catalog.product.create.after', [ProductEventListener::class, 'afterCreate']);`
  (exemplar: `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php`).
- Fire both `.before` and `.after` around any state change your module exposes to others.

## Container bindings — Octane safety

This stack runs Octane. A `singleton()` outlives the request: a client configured with
one admin's credential would answer the next request with it.

| Binding | Use for | Exemplar |
|---|---|---|
| `scoped()` | Anything holding per-request state: configured API clients, credential-bound services, per-request memoization | `packages/Webkul/Core/src/Providers/CoreServiceProvider.php`, `packages/Webkul/Core/src/RequestMemo.php` |
| `singleton()` | Genuinely stateless registries and factories only | `ToolRegistry` in `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php` |
| `bind()` | State that must not survive same-request mutation (fresh instance per resolve) | contract-to-implementation pairs in the same provider |

NEVER memoize in static properties — use the scoped `Webkul\Core\RequestMemo`.

## Scale rules (catalog tables hold millions of rows)

- No unbounded `->all()`, `->get()` or `->pluck()` on catalog tables. Batch scans use
  `chunkById()`/`lazyById()` (exemplar:
  `packages/Webkul/Completeness/src/Jobs/BulkProductCompletenessJob.php`).
- Bulk lookups: `array_chunk($keys, 1000)` + `whereIn` (exemplar:
  `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/SKUStorage.php`).
- Heavy work is a `ShouldQueue` job; eager-load every relation you traverse; no query
  inside a loop or a Blade partial.
- Elasticsearch is optional (`config('elasticsearch.enabled')`, default false): every ES
  code path needs a database fallback (exemplar:
  `packages/Webkul/Product/src/Factories/ProductQueryBuilderFactory.php`).
