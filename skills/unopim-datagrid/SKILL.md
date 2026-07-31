---
name: unopim-datagrid
description: Use when building or changing an UnoPim admin listing page — a DataGrid class with columns, search, filters, sorting, row actions or mass actions, or the Blade view that renders it. Trigger phrases include "datagrid", "admin listing", "add a column", "mass action", "prepareQueryBuilder", "listing page".
requires: unopim-standards, unopim-verify
---

# UnoPim DataGrid

Copy shape from these exemplars — never invent engine API:

- Grid class: `packages/Webkul/AiAgent/src/DataGrids/Credential/CredentialDataGrid.php`
- Mass actions: `packages/Webkul/Admin/src/DataGrids/Catalog/ProductDataGrid.php`
- Listing Blade: `packages/Webkul/Webhook/src/Resources/views/webhooks/index.blade.php`
- Raw SQL with prefix: `packages/Webkul/Measurement/src/DataGrids/UnitDataGrid.php`

## Rules

- Grid lives in a subdirectory — `src/DataGrids/{Section}/{Name}DataGrid.php` — and extends `Webkul\DataGrid\DataGrid`.
- `prepareQueryBuilder()` MUST use `DB::table()` with bare table names (no prefix — Laravel applies `env('DB_PREFIX', '')`). NEVER query Eloquent models here.
- Any raw fragment (`selectRaw`, `whereRaw`, `orderByRaw`, `DB::raw`) that names a table MUST prepend `DB::getTablePrefix()` — see `packages/Webkul/Measurement/src/DataGrids/UnitDataGrid.php`. MySQL and PostgreSQL both run in CI: no MySQL-only SQL (GROUP_CONCAT, backticks, DATE_FORMAT).
- `addColumn()` MUST set all six keys — `index`, `label`, `type`, `searchable`, `filterable`, `sortable`. The engine reads the three flags with no null-coalescing; omitting one throws "Undefined array key" at request time.
- Hook signatures: the abstract base declares `prepareColumns()`/`prepareActions()` untyped, so PHPDoc-`@return`-only (older Admin grids) and `: void` (newest grids, including the Credential exemplar) both compile. Write `: void` in new code; match the existing style when editing. NEVER flag either style as a violation.
- Action `url` accepts any callable — prefer `fn ($row): string => route(...)`. Mass-action `url` is a plain `route(...)` string, no callable.
- Gate every action and mass action with `bouncer()->hasPermission()`. Mass-action ACL keys are snake_case (`{module-slug}.credentials.mass_delete`), matching the route names — NEVER hyphenated (`mass-delete`).
- Column `closure` output renders as raw HTML; the engine `strip_tags()`-sanitizes plain string cells only. Any user-supplied value interpolated in closure HTML MUST be escaped with `e()`.
- Every label and title uses `trans()` with keys added to `en_US` first, then all 33 locales. Boolean badges: `label-active` (true), `label-info text-gray-600 dark:text-gray-300` (false).
- Zero comments inside method bodies or array literals. Method PHPDoc is a one-line imperative summary; `@return` only where there is no native return type.

## Grid class

```php
<?php

namespace Webkul\{ModuleName}\DataGrids\Credential;

use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;
use Webkul\DataGrid\DataGrid;

class CredentialDataGrid extends DataGrid
{
    /**
     * Prepare query builder.
     *
     * @return Builder
     */
    public function prepareQueryBuilder()
    {
        return DB::table('{module}_credentials')
            ->select('id', 'label', 'status', 'created_at');
    }

    /**
     * Prepare columns.
     */
    public function prepareColumns(): void
    {
        $this->addColumn([
            'index'      => 'label',
            'label'      => trans('{module-name}::app.credentials.datagrid.label'),
            'type'       => 'string',
            'searchable' => true,
            'filterable' => true,
            'sortable'   => true,
        ]);

        $this->addColumn([
            'index'      => 'status',
            'label'      => trans('{module-name}::app.credentials.datagrid.status'),
            'type'       => 'boolean',
            'searchable' => false,
            'filterable' => true,
            'sortable'   => true,
            'closure'    => fn ($row): string => $row->status
                ? '<span class="label-active">'.trans('admin::app.common.yes').'</span>'
                : '<span class="label-info text-gray-600 dark:text-gray-300">'.trans('admin::app.common.no').'</span>',
        ]);
    }

    /**
     * Prepare actions.
     */
    public function prepareActions(): void
    {
        if (bouncer()->hasPermission('{module-slug}.credentials.edit')) {
            $this->addAction([
                'icon'   => 'icon-edit',
                'title'  => trans('{module-name}::app.credentials.datagrid.edit'),
                'method' => 'GET',
                'url'    => fn ($row): string => route('{module-slug}.credentials.edit', $row->id),
            ]);
        }

        if (bouncer()->hasPermission('{module-slug}.credentials.delete')) {
            $this->addAction([
                'icon'   => 'icon-delete',
                'title'  => trans('{module-name}::app.credentials.datagrid.delete'),
                'method' => 'DELETE',
                'url'    => fn ($row): string => route('{module-slug}.credentials.destroy', $row->id),
            ]);
        }
    }

    /**
     * Prepare mass actions.
     */
    public function prepareMassActions(): void
    {
        if (bouncer()->hasPermission('{module-slug}.credentials.mass_delete')) {
            $this->addMassAction([
                'title'   => trans('{module-name}::app.credentials.datagrid.delete'),
                'url'     => route('{module-slug}.credentials.mass_delete'),
                'method'  => 'POST',
                'options' => ['actionType' => 'delete'],
            ]);
        }
    }
}
```

For a status mass update, copy the `options` array of label/value pairs from the `catalog.products.mass_update` block in `packages/Webkul/Admin/src/DataGrids/Catalog/ProductDataGrid.php`.

## Controller

```php
public function index()
{
    if (request()->ajax()) {
        return resolve(CredentialDataGrid::class)->toJson();
    }

    return view('{module-name}::credentials.index');
}
```

## Listing Blade

`admin::layouts.master` and `@extends` do not exist — the admin layout is a component. Create is a modal on the index page whose `store()` redirects to edit (copy `v-create-webhook-form` from the Webhook exemplar); do not add a GET create page.

```blade
<x-admin::layouts>
    <x-slot:title>
        @lang('{module-name}::app.credentials.index.title')
    </x-slot>

    <x-admin::layouts.page-header :title="trans('{module-name}::app.credentials.index.title')" />

    <x-admin::datagrid :src="route('{module-slug}.credentials.index')" />
</x-admin::layouts>
```
