# Importers

Base class: `packages/Webkul/DataTransfer/src/Helpers/Importers/AbstractImporter.php`. Compact working exemplar: `packages/Webkul/DataTransfer/src/Helpers/Importers/Currency/Importer.php`. The heavyweight exemplar (chunked lookups, unique-value scans) is `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/Importer.php`.

## Contents

- The real contract
- importers.php
- Importer template
- Error codes
- Bulk lookups — never one query per row
- File sources

## The real contract

| Member | Signature / value | Notes |
|---|---|---|
| constructor | `__construct(protected ImportJobBatchRepository $importBatchRepository)` | `ImportJobBatchRepository` is an alias of `JobTrackBatchRepository`. Subclasses add their own promoted deps and MUST call `parent::__construct($importBatchRepository)` — omitting it breaks batch persistence |
| `validateRow()` | `abstract public function validateRow(array $rowData, int $rowNumber): bool` | Abstract — a subclass without it cannot load |
| `importBatch()` | `abstract public function importBatch(ImportJobBatchContract $importBatchContract): bool` | Abstract. `ImportJobBatchContract` is `Webkul\DataTransfer\Contracts\JobTrackBatch`. `importBatch(array): void` is an incompatible override — fatal |
| `BATCH_SIZE` | `100` (`LARGE_BATCH_SIZE` = `1000`) | Rows per persisted batch |
| counters | `createdItemsCount`, `updatedItemsCount`, `deletedItemsCount`, `processedRowsCount` | Read back via `getCreatedItemsCount()` etc. for the batch summary |
| `skipRow()` | `skipRow(?int $rowNumber, string $errorCode, ?string $columnName = null, ?string $errorMessage = null)` | Records the error and marks the row skipped |
| `ERROR_CODE_*` | string codes (`system_exception`, `column_not_found`, `invalid_attribute_name`, …) | Base codes; add entity-specific ones as string constants |
| `$linkingRequired` / `$indexingRequired` | `bool`, default `false` | Opt in to the linking/indexing chain stages |

`Import::ACTION_APPEND` / `Import::ACTION_DELETE` describe what the user chose for the job; branch on `$this->import->action` as the Currency importer does.

## importers.php

Core reference: `packages/Webkul/DataTransfer/src/Config/importers.php`. Keys per entity: `title` (translation key), `importer`, `validator`, `sample_path`, `has_file_options`. Connector importers that pull from an API instead of a file add a `filters.fields` array with the same field structure as exporters (see [exporters.md](exporters.md) — async quartet only for route-backed selects, `depends_on` for dependent selects).

```php
<?php

return [
    '{module_slug}-products' => [
        'title'     => '{module-name}::app.imports.products.title',
        'importer'  => Webkul\{ModuleName}\Helpers\Importers\Product\Importer::class,
        'validator' => Webkul\{ModuleName}\Validators\JobInstances\Import\ProductJobValidator::class,
        'filters'   => [
            'fields' => [
                [
                    'name'       => 'credential',
                    'title'      => '{module-name}::app.imports.filters.credential',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module_slug}.credentials.get',
                ],
            ],
        ],
    ],
];
```

Merge with `mergeConfigFrom(..., 'importers')` in the provider — exemplar `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php`.

## Importer template

Modeled on the Currency importer; every call resolves against the base class.

```php
<?php

namespace Webkul\{ModuleName}\Helpers\Importers\Product;

use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Validator;
use Webkul\DataTransfer\Contracts\JobTrackBatch as JobTrackBatchContract;
use Webkul\DataTransfer\Helpers\Import;
use Webkul\DataTransfer\Helpers\Importers\AbstractImporter;
use Webkul\DataTransfer\Repositories\JobTrackBatchRepository;
use Webkul\{ModuleName}\Repositories\CredentialRepository;
use Webkul\{ModuleName}\Services\{ModuleName}Service;

class Importer extends AbstractImporter
{
    public const ERROR_DUPLICATE_CODE = 'duplicate_code';

    protected array $validColumnNames = [
        'sku',
        'name',
        'status',
    ];

    protected array $permanentAttributes = ['sku'];

    protected array $messages = [
        self::ERROR_DUPLICATE_CODE => '{module-name}::app.imports.validation.duplicate-code',
    ];

    public function __construct(
        protected JobTrackBatchRepository $importBatchRepository,
        protected CredentialRepository $credentialRepository,
        protected {ModuleName}Service $service,
    ) {
        parent::__construct($importBatchRepository);
    }

    protected function initErrorMessages(): void
    {
        foreach ($this->messages as $errorCode => $message) {
            $this->errorHelper->addErrorMessage($errorCode, trans($message));
        }

        parent::initErrorMessages();
    }

    public function validateRow(array $rowData, int $rowNumber): bool
    {
        if (isset($this->validatedRows[$rowNumber])) {
            return ! $this->errorHelper->isRowInvalid($rowNumber);
        }

        $this->validatedRows[$rowNumber] = true;

        $validator = Validator::make($rowData, [
            'sku'    => ['required', 'string'],
            'name'   => ['nullable', 'string'],
            'status' => ['nullable', 'in:0,1'],
        ]);

        if ($validator->fails()) {
            $failedAttributes = $validator->failed();

            foreach ($validator->errors()->getMessages() as $attributeCode => $message) {
                $errorCode = array_key_first($failedAttributes[$attributeCode] ?? []);

                $this->skipRow($rowNumber, $errorCode, $attributeCode, current($message));
            }
        }

        return ! $this->errorHelper->isRowInvalid($rowNumber);
    }

    public function importBatch(JobTrackBatchContract $batch): bool
    {
        Event::dispatch('data_transfer.imports.batch.import.before', $batch);

        $this->saveProductsData($batch);

        $batch = $this->importBatchRepository->update([
            'state'   => Import::STATE_PROCESSED,
            'summary' => [
                'created' => $this->getCreatedItemsCount(),
                'updated' => $this->getUpdatedItemsCount(),
                'deleted' => $this->getDeletedItemsCount(),
            ],
        ], $batch->id);

        Event::dispatch('data_transfer.imports.batch.import.after', $batch);

        return true;
    }

    protected function saveProductsData(JobTrackBatchContract $batch): bool
    {
        foreach ($batch->data as $rowData) {
            if ($this->service->upsertProduct($rowData)) {
                $this->updatedItemsCount++;
            } else {
                $this->createdItemsCount++;
            }
        }

        return true;
    }
}
```

## Error codes

There is no `UNOPIM_ENTITY_NAME`, `ACTION_ADD`, `ACTION_UPDATE`, `CODE_ALREADY_EXIST` or `CODE_NOT_EXIST` convention — nothing in the pipeline reads those. The real convention is `ERROR_*` string constants mapped to translation keys in `$messages` and registered by extending `initErrorMessages()` (call the parent). See the constants block in `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/Importer.php` for the house naming style (`invalid_product_type`, `duplicated_url_key`, …).

## Bulk lookups — never one query per row

Batches hold up to `BATCH_SIZE` rows; the catalog holds millions. Two idioms from `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/SKUStorage.php` and the Product importer:

- Preload existence maps chunked: `array_chunk($skus, 1000)` + `whereIn('sku', $chunk)` into an in-memory map, then check the map per row. Load only keys not already cached.
- Whole-column scans (e.g. unique-value checks) stream with `->orderBy('id')->chunk(5000, ...)` — a single `->get()` over `products` exhausts memory on 500K+ row catalogs.

MUST NOT: call `$repository->findOneByField(...)` or `DB::table(...)->where(...)->first()` inside the per-row loop of `validateRow()`/`importBatch()` when the same lookup can be preloaded for the batch.

## File sources

File-based imports read through `packages/Webkul/DataTransfer/src/Helpers/Sources/CSV.php` and `packages/Webkul/DataTransfer/src/Helpers/Sources/Excel.php`; the pipeline hands your importer already-parsed row arrays in `$batch->data`. Do not open the uploaded file yourself inside an importer.
