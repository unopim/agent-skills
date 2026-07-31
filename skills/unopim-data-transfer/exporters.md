# Exporters

Base class: `packages/Webkul/DataTransfer/src/Helpers/Exporters/AbstractExporter.php`. Working exemplar: `packages/Webkul/DataTransfer/src/Helpers/Exporters/Product/Exporter.php`. Copy the exemplar's shape; do not invent lifecycle methods.

## Contents

- The real contract
- Exporter template
- Sources must stream — `getResults()`
- exporters.php
- quick_exporters.php
- Provider wiring and the list route

## The real contract

| Member | Signature / value | Notes |
|---|---|---|
| constructor | `__construct(JobTrackBatchRepository $exportBatchRepository, FileExportFileBuffer $exportFileBuffer)` | Subclasses add their own promoted deps and MUST call `parent::__construct()` |
| `exportBatch()` | `abstract public function exportBatch(JobTrackBatchContract $exportBatchContract, $filePath): bool` | The only abstract method — `$filePath` is untyped in core; match it |
| `initilize()` | `public function initilize() {}` | Misspelled in core, empty. NOT called automatically — your `exportBatch()` calls it, so it runs once per batch. Cache cross-batch work statically (the Product exporter memoizes channels/locales in a static property) |
| `getFilters()` | returns the job's filter array | `$this->getFilters()['credential']` — there is no `getFilterValue()` |
| `getResults()` | `protected`, returns an iterator | Default is `$this->source->all()?->getIterator()` — full hydration; see streaming below |
| `initializeBatches()` | no args | Walks the `getResults()` iterator and persists `BATCH_SIZE` rows per `job_track_batches` record. Called by the pipeline, not by you |
| `updateBatchState()` | `updateBatchState(int $id, string $state): void` | Writes state + summary (processed/created/skipped) — the ONLY way to close a batch |
| `BATCH_SIZE` | `1000` | Override per exporter if the remote API needs smaller pages |
| counters | `createdItemsCount`, `updatedItemsCount`, `skippedItemsCount`, `processedRowsCount` | `created` means created, `updated` means updated — job summaries report them by name |
| `ERROR_CODE_*` | string codes (`system_exception`, `column_not_found`, …) | Registered into the error helper via `$errorMessages`; add your own the same way |

`setExport()`, `setSource()`, `setLogger()`, `setErrorHelper()` are called by `Export::getTypeExporter()` — never construct an exporter by hand in a controller.

## Exporter template

Verified against the base class above; every method resolves.

```php
<?php

namespace Webkul\{ModuleName}\Helpers\Exporters\Product;

use Illuminate\Support\Facades\Event;
use Webkul\DataTransfer\Contracts\JobTrackBatch as JobTrackBatchContract;
use Webkul\DataTransfer\Helpers\Export;
use Webkul\DataTransfer\Helpers\Exporters\AbstractExporter;
use Webkul\DataTransfer\Jobs\Export\File\FlatItemBuffer as FileExportFileBuffer;
use Webkul\DataTransfer\Repositories\JobTrackBatchRepository;
use Webkul\{ModuleName}\Repositories\CredentialRepository;
use Webkul\{ModuleName}\Services\{ModuleName}Service;

class Exporter extends AbstractExporter
{
    public const BATCH_SIZE = 1000;

    public function __construct(
        protected JobTrackBatchRepository $exportBatchRepository,
        protected FileExportFileBuffer $exportFileBuffer,
        protected CredentialRepository $credentialRepository,
        protected {ModuleName}Service $service,
    ) {
        parent::__construct($exportBatchRepository, $exportFileBuffer);
    }

    /**
     * Point the API client at the credential selected in the job filters.
     */
    public function initilize(): void
    {
        $credential = $this->credentialRepository->findOrFail($this->getFilters()['credential']);

        $this->service->useCredential($credential);
    }

    /**
     * Export one queued batch.
     */
    public function exportBatch(JobTrackBatchContract $batch, $filePath): bool
    {
        Event::dispatch('data_transfer.exports.batch.export.before', $batch);

        $this->initilize();

        foreach ($batch->data as $rowData) {
            $this->processItem($rowData);
        }

        $this->updateBatchState($batch->id, Export::STATE_PROCESSED);

        Event::dispatch('data_transfer.exports.batch.export.after', $batch);

        return true;
    }

    /**
     * Create or update one row on the remote platform.
     */
    protected function processItem(array $rowData): void
    {
        try {
            $externalId = $this->service->findProductIdBySku($rowData['sku'] ?? null);

            if ($externalId) {
                $this->service->updateProduct($externalId, $rowData);
                $this->updatedItemsCount++;
            } else {
                $this->service->createProduct($rowData);
                $this->createdItemsCount++;
            }
        } catch (\Throwable $e) {
            $this->jobLogger?->warning($e->getMessage());
            $this->skippedItemsCount++;
        }
    }
}
```

When the remote API supports batch search, preload the SKU→id map once per batch instead of one lookup call per row — the per-row call above is the floor, not the goal.

## Sources must stream — `getResults()`

`initializeBatches()` walks the iterator from `getResults()` and persists `BATCH_SIZE` rows per `job_track_batches` record; each batch then runs as a queued `ExportBatch` job. The inherited default is `$this->source->all()?->getIterator()` — full hydration of the source table.

- Default acceptable ONLY for small entities: locales, currencies, channels, roles.
- For products or any table that reaches millions of rows, override `getResults()` to return a keyset (id-cursor) source. The exemplar is `packages/Webkul/DataTransfer/src/Helpers/Sources/Export/ProductCursor.php`, which fetches each page as a constant-cost index range scan:

```php
$ids = $query->select('id')
    ->where('id', '>', $this->lastId)
    ->orderBy('id')
    ->limit($this->batchSize)
    ->pluck('id');
```

BAD — hydrates every row before batching; exhausts memory and times out at scale:

```php
protected function getResults()
{
    return $this->repository->all()->getIterator();
}
```

The Product exporter's own `getResults()` returns a `ProductCursor` (or its Elasticsearch twin in `packages/Webkul/DataTransfer/src/Helpers/Sources/Export/Elastic/ProductCursor.php`) — copy that shape for any large custom entity.

CSV output is formula-injection-escaped by `packages/Webkul/DataTransfer/src/Helpers/Formatters/EscapeFormulaOperators.php`; route file output through the provided buffers rather than writing files by hand.

## exporters.php

Core reference: `packages/Webkul/DataTransfer/src/Config/exporters.php`. Field arrays are normalized by `packages/Webkul/Admin/src/Fields/FieldConfig.php` — keys outside its whitelist are silently dropped.

```php
<?php

use Webkul\Product\Repositories\ProductRepository;

return [
    '{ModuleName}Products' => [
        'title'     => '{module-name}::app.exports.products.title',
        'exporter'  => Webkul\{ModuleName}\Helpers\Exporters\Product\Exporter::class,
        'validator' => Webkul\{ModuleName}\Validators\JobInstances\Export\ProductJobValidator::class,
        'source'    => ProductRepository::class,
        'filters'   => [
            'fields' => [
                [
                    'name'       => 'credential',
                    'title'      => '{module-name}::app.exports.filters.credential',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module_slug}.credentials.get',
                ],
                [
                    'name'       => 'file_format',
                    'title'      => 'data_transfer::app.exporters.fields.file-format',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'options'    => [
                        ['value' => 'Csv', 'label' => 'CSV'],
                        ['value' => 'Xls', 'label' => 'XLS'],
                        ['value' => 'Xlsx', 'label' => 'XLSX'],
                    ],
                ],
                [
                    'name'     => 'with_media',
                    'title'    => '{module-name}::app.exports.filters.with-media',
                    'required' => false,
                    'type'     => 'boolean',
                ],
            ],
        ],
    ],
];
```

Select field rules:

- Static inline `options` for fixed lists — core ships `file_format` and `date_format` this way. NEVER bolt the async quartet onto a static list.
- `async` + `track_by` + `label_by` + `list_route` together, and only when options come from a route. The endpoint returns objects containing the `track_by` and `label_by` keys (e.g. `[{"id": 1, "label": "Staging"}]`).
- Dependent selects use `'depends_on' => ['field' => 'channels', 'as' => 'channels']` (core `exporters.php` wires locales/currencies to channels this way). The key `dependent` does not exist — `FieldConfig::field()` drops it and the select never reacts.

## quick_exporters.php

Core reference: `packages/Webkul/DataTransfer/src/Config/quick_exporters.php`. Entries feed the DataGrid export modal (`packages/Webkul/Admin/src/Resources/views/components/datagrid/export/index.blade.php`): the key is the option id, `title` (a translation key) is the label, and an optional `route` is resolved with `route()` and used by the modal. There is no `filters` key. When a quick-export entity actually runs through the pipeline, `Export::getTypeExporter()` falls back to `config('quick_exporters.{entity}')` and requires `exporter` + `source` there.

```php
<?php

return [
    '{module_slug}_products' => [
        'title'    => '{module-name}::app.exports.quick.products',
        'route'    => '{module_slug}.quick_export',
        'exporter' => Webkul\{ModuleName}\Helpers\Exporters\Product\Exporter::class,
        'source'   => Webkul\Product\Repositories\ProductRepository::class,
    ],
];
```

## Provider wiring and the list route

Merge all three configs in your service provider — exemplar `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php`:

```php
$this->mergeConfigFrom(__DIR__.'/../../Config/exporters.php', 'exporters');
$this->mergeConfigFrom(__DIR__.'/../../Config/quick_exporters.php', 'quick_exporters');
$this->mergeConfigFrom(__DIR__.'/../../Config/importers.php', 'importers');
```

The `list_route` endpoint is an ordinary admin route returning the `track_by`/`label_by` objects:

```php
Route::get('credentials/get', [CredentialController::class, 'getCredentials'])->name('{module_slug}.credentials.get');
```

```php
public function getCredentials(): JsonResponse
{
    return new JsonResponse(
        $this->credentialRepository->all(['id', 'label'])
    );
}
```

Register it under the `['admin']` middleware group and cover it in `acl.php` — ACL enforcement is fail-open by route name, so an uncovered route is reachable by every logged-in admin. `->all()` is acceptable here only because credentials are a small table; a large option source must paginate or filter server-side.
