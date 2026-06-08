---
name: unopim-data-transfer
description: "Import/export pipeline for UnoPim. Activates when configuring imports, exports, debugging job pipelines, or creating data transfer profiles; or when the user mentions import, export, CSV, Excel, job, queue, batch, or data transfer."
license: MIT
metadata:
  author: unopim
---

# UnoPim Data Transfer

The import/export pipeline uses a queued job system with state tracking.

## When to Use This Skill

Invoke this skill when:

- Configuring or running imports/exports
- Debugging failed import/export jobs
- Creating custom importer/exporter classes
- Understanding the job pipeline

## Job Pipeline

### Import States

```
PENDING → VALIDATED → PROCESSING → PROCESSED → LINKING → LINKED → INDEXING → INDEXED → COMPLETED
                                                                                          ↓
                                                                                        FAILED
```

### Export States

```
PENDING → PROCESSING → COMPLETED
                         ↓
                       FAILED
```

## Import Architecture

| Class | Purpose |
|---|---|
| `Helpers/Import.php` | Import orchestrator — validates, batches, processes |
| `Helpers/Importers/AbstractImporter.php` | Base importer with batch processing |
| `Helpers/Importers/Product/Importer.php` | Product-specific import logic |
| `Helpers/Importers/Category/Importer.php` | Category-specific import logic |
| `Helpers/Sources/CSV.php` | CSV file reader |
| `Helpers/Sources/Excel.php` | Excel file reader |

## Export Architecture

| Class | Purpose |
|---|---|
| `Helpers/Export.php` | Export orchestrator |
| `Helpers/Exporters/AbstractExporter.php` | Base exporter |
| `Helpers/Exporters/Product/Exporter.php` | Product export |
| `Helpers/Exporters/Category/Exporter.php` | Category export |

## Queued Jobs

| Stage | Job Class |
|---|---|
| Import track | `ImportTrackBatch` |
| Import batch | `ImportBatch` |
| Link batch | `LinkBatch` |
| Linking | `Linking` |
| Index batch | `IndexBatch` |
| Indexing | `Indexing` |
| Completed | `Completed` |
| Export track | `ExportTrackBatch` |
| Export batch | `ExportBatch` |
| Upload | `UploadFile` |

## CLI Commands

```bash
# Start queue worker (required for import/export)
php artisan queue:work --queue="default,system"

# Run a specific job
php artisan unopim:queue:work {jobId} {userEmail}

# Restart workers after code changes
php artisan queue:restart
```

## Models

| Model | Purpose |
|---|---|
| `JobInstances` | Job definition (type, entity, file path, settings) |
| `JobTrack` | Single job run (state, stats, errors) |
| `JobTrackBatch` | Individual batch within a job |

## Troubleshooting

### Import stuck in PENDING

Queue worker not running:

```bash
php artisan queue:work --queue="default,system"
```

### Import fails with validation errors

Check `JobTrack.errors` for detailed row-level errors.

### Export produces empty file

Verify data exists and filters match records.

## Creating Custom Importers/Exporters

See the `unopim-plugin-dev` skill → [custom-data-transfer.md](../unopim-plugin-dev/custom-data-transfer.md).

---

# @export-workflow: Connector Export/Import Workflow

## Overview

All export/import patterns are derived from the WooCommerce connector reference.

**Key rules:**
- Every `select`-type filter field MUST include `async`, `track_by`, `label_by`, `list_route`
- `quick_exporters.php` registers one-click export jobs (no filter UI)
- `importers.php` uses the same filter field structure as `exporters.php`
- Exporter classes live in `Helpers/Exporters/{Entity}/Exporter.php`
- Importer classes live in `Helpers/Importers/{Entity}/Importer.php`
- All Exporter classes extend `Webkul\DataTransfer\Helpers\Exporters\AbstractExporter`
- You must register a route `{module}.credentials.get` that returns `{id, label}` pairs

**Admin UI rule (critical):**
- Any admin Blade UI added for export/import configuration must use UnoPim form components.
- Do not generate raw `<select>`, `<input>`, `<textarea>`, or `<label>` controls when component equivalents exist.
- Use translated labels/placeholders/messages.
- For dropdown controls, use component select with `:options="json_encode(...)"`, `track-by`, `label-by`, and Vue `@input` binding.

---

## 1. exporters.php

Every `select` filter field needs: `async`, `track_by`, `label_by`, `list_route`.
Optional: `dependent` (array of field names this field depends on).

```php
<?php
// Config/exporters.php

return [

    // ---- Product Export ----
    '{ModuleName}Products' => [
        'title'     => '{module-name}::app.data-transfer.exports.type.product',
        'exporter'  => \Webkul\{ModuleName}\Helpers\Exporters\Product\Exporter::class,
        'validator' => \Webkul\{ModuleName}\Validators\JobInstances\Export\ProductsValidator::class,
        'source'    => \Webkul\Product\Repositories\ProductRepository::class,
        'filters'   => [
            'fields' => [
                [
                    'name'       => 'credential',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.credential',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,          // REQUIRED for select fields
                    'track_by'   => 'id',          // REQUIRED — key used to track value
                    'label_by'   => 'label',       // REQUIRED — key used for display
                    'list_route' => '{module-slug}.credentials.get', // REQUIRED — API route
                ],
                [
                    'name'       => 'channel',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.channel',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.channel.get',
                    'dependent'  => ['locale'],    // optional: fields this depends on
                ],
                [
                    'name'       => 'locale',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.locale',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.locale.get',
                ],
                [
                    'name'       => 'currency',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.currency',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.currency.get',
                ],
                [
                    'name'       => 'with_media',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.with-media',
                    'type'       => 'boolean',      // boolean fields have no async/track_by
                ],
            ],
        ],
    ],

    // ---- Category Export ----
    '{ModuleName}Categories' => [
        'title'     => '{module-name}::app.data-transfer.exports.type.category',
        'exporter'  => \Webkul\{ModuleName}\Helpers\Exporters\Category\Exporter::class,
        'validator' => \Webkul\{ModuleName}\Validators\JobInstances\Export\CategoryAndAttributesValidator::class,
        'source'    => \Webkul\Category\Repositories\CategoryRepository::class,
        'filters'   => [
            'fields' => [
                [
                    'name'       => 'credential',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.credential',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.credentials.get',
                ],
                [
                    'name'       => 'channel',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.channel',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.channel.get',
                    'dependent'  => ['locale'],
                ],
                [
                    'name'       => 'locale',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.locale',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.locale.get',
                ],
            ],
        ],
    ],

    // ---- Attribute Export ----
    '{ModuleName}Attributes' => [
        'title'     => '{module-name}::app.data-transfer.exports.type.attribute',
        'exporter'  => \Webkul\{ModuleName}\Helpers\Exporters\Attribute\Exporter::class,
        'validator' => \Webkul\{ModuleName}\Validators\JobInstances\Export\CategoryAndAttributesValidator::class,
        'source'    => \Webkul\Attribute\Repositories\AttributeRepository::class,
        'filters'   => [
            'fields' => [
                [
                    'name'       => 'credential',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.credential',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.credentials.get',
                ],
                [
                    'name'       => 'channel',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.channel',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.channel.get',
                    'dependent'  => ['locale'],
                ],
                [
                    'name'       => 'locale',
                    'title'      => '{module-name}::app.data-transfer.exports.filters.locale',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.locale.get',
                ],
            ],
        ],
    ],
];
```

---

## 2. quick_exporters.php

One-click export jobs that appear in the Unopim product listing toolbar.
Keys: `title`, `route`, `exporter`, `source`. No `filters` key.

```php
<?php
// Config/quick_exporters.php

return [
    '{ModuleName}QuickExport' => [
        'title'    => '{Module Name} Quick Export Product',
        'route'    => '{module-slug}.quick_export',
        'exporter' => \Webkul\{ModuleName}\Helpers\Exporters\Product\Exporter::class,
        'source'   => \Webkul\Product\Repositories\ProductRepository::class,
    ],
];
```

---

## 3. importers.php

Same filter structure as exporters.php — `async/track_by/label_by/list_route` required.

```php
<?php
// Config/importers.php

return [

    // ---- Category Import ----
    '{ModuleName}CategoriesImport' => [
        'title'     => '{module-name}::app.data-transfer.imports.type.category',
        'importer'  => \Webkul\{ModuleName}\Helpers\Importers\Category\Importer::class,
        'validator' => \Webkul\{ModuleName}\Validators\JobInstances\Import\CategoryAndAttributesValidator::class,
        'source'    => \Webkul\Category\Repositories\CategoryRepository::class,
        'filters'   => [
            'fields' => [
                [
                    'name'       => 'credential',
                    'title'      => '{module-name}::app.data-transfer.imports.filters.credential',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.credentials.get',
                ],
                [
                    'name'       => 'locale',
                    'title'      => '{module-name}::app.data-transfer.imports.filters.locale',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.locale.get',
                ],
            ],
        ],
    ],

    // ---- Product Import ----
    '{ModuleName}ProductImport' => [
        'title'     => '{module-name}::app.data-transfer.imports.type.product',
        'importer'  => \Webkul\{ModuleName}\Helpers\Importers\Product\Importer::class,
        'validator' => \Webkul\{ModuleName}\Validators\JobInstances\Import\ProductsValidator::class,
        'source'    => \Webkul\Product\Repositories\ProductRepository::class,
        'filters'   => [
            'fields' => [
                [
                    'name'       => 'credential',
                    'title'      => '{module-name}::app.data-transfer.imports.filters.credential',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.credentials.get',
                ],
                [
                    'name'       => 'channel',
                    'title'      => '{module-name}::app.data-transfer.imports.filters.channel',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.channel.get',
                    'dependent'  => ['locale'],
                ],
                [
                    'name'       => 'locale',
                    'title'      => '{module-name}::app.data-transfer.imports.filters.locale',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.locale.get',
                ],
                [
                    'name'       => 'currency',
                    'title'      => '{module-name}::app.data-transfer.imports.filters.currency',
                    'required'   => true,
                    'validation' => 'required',
                    'type'       => 'select',
                    'async'      => true,
                    'track_by'   => 'id',
                    'label_by'   => 'label',
                    'list_route' => '{module-slug}.currency.get',
                ],
            ],
        ],
    ],
];
```

---

## 4. Credentials GET Route (Required for list_route)

The `list_route` values in filter fields reference named routes that return
`{id, label}` JSON for each selectable item.

```php
// In routes file — inside the admin middleware group
Route::get('credentials/get', [CredentialController::class, 'getCredentials'])
     ->name('{module-slug}.credentials.get');
```

```php
// In CredentialController
public function getCredentials(): JsonResponse
{
    $credentials = $this->credentialRepository->all(['id', 'label']);

    return new JsonResponse($credentials);
}
```

---

## 5. Exporter Class (AbstractExporter)

```php
<?php
// src/Helpers/Exporters/Product/Exporter.php

namespace Webkul\{ModuleName}\Helpers\Exporters\Product;

use Webkul\DataTransfer\Contracts\JobTrackBatch as JobTrackBatchContract;
use Webkul\DataTransfer\Helpers\Export as ExportHelper;
use Webkul\DataTransfer\Helpers\Exporters\AbstractExporter;
use Webkul\DataTransfer\Jobs\Export\File\FlatItemBuffer as FileExportFileBuffer;
use Webkul\DataTransfer\Repositories\JobTrackBatchRepository;
use Webkul\{ModuleName}\Repositories\CredentialRepository;
use Webkul\{ModuleName}\Services\{ModuleName}Service;

class Exporter extends AbstractExporter
{
    /**
     * Batch size for chunked processing.
     */
    public const BATCH_SIZE = 100;

    /**
     * Entity tag used in error reporting.
     */
    public const UNOPIM_ENTITY_NAME = 'product';

    /**
     * Action for creating a new record.
     */
    public const ACTION_ADD = 'createProduct';

    /**
     * Action for updating an existing record.
     */
    public const ACTION_UPDATE = 'updateProduct';

    /**
     * Error code when item already exists.
     */
    public const CODE_ALREADY_EXIST = 'product_invalid_sku';

    /**
     * Error code when item does not exist.
     */
    public const CODE_NOT_EXIST = 'rest_term_invalid';

    public function __construct(
        protected JobTrackBatchRepository $importBatchRepository,
        protected FileExportFileBuffer $exportFileBuffer,
        protected CredentialRepository $credentialRepository,
        protected {ModuleName}Service $service,
    ) {
        parent::__construct($importBatchRepository, $exportFileBuffer);
    }

    /**
     * Initialize: called once before batch processing.
     *
     * @return void
     */
    public function initializeExport(): void
    {
        $credentialId = $this->getFilterValue('credential');
        $credential   = $this->credentialRepository->findOrFail($credentialId);
        $this->service->useCredential($credential);
    }

    /**
     * Export a batch of items.
     *
     * @return bool
     */
    public function exportBatch(JobTrackBatchContract $batch, $filePath): bool
    {
        $this->initializeBatch($batch);

        foreach ($batch->data as $rowData) {
            $this->processItem($rowData);
        }

        $this->saveBatchSummary($batch, $filePath);

        return true;
    }

    /**
     * Process a single item.
     *
     * @param  array<mixed>  $rowData
     */
    protected function processItem(array $rowData): void
    {
        try {
            $existingId = $this->findExternalId($rowData['sku'] ?? null);

            if ($existingId) {
                $this->service->updateProduct($existingId, $rowData);
                $this->createdItemsCount++;
            } else {
                $this->service->createProduct($rowData);
                $this->updatedItemsCount++;
            }
        } catch (\Throwable $e) {
            $this->jobLogger?->warning($e->getMessage());
            $this->skippedItemsCount++;
        }
    }

    /**
     * Look up whether this SKU already exists externally.
     */
    protected function findExternalId(?string $sku): ?int
    {
        if (! $sku) {
            return null;
        }

        $results = $this->service->searchProducts(['sku' => $sku]);

        return $results[0]['id'] ?? null;
    }
}
```

---

## 6. Validator Class

```php
<?php
// src/Validators/JobInstances/Export/ProductsValidator.php

namespace Webkul\{ModuleName}\Validators\JobInstances\Export;

use Webkul\DataTransfer\Validators\JobInstances\AbstractValidator;

class ProductsValidator extends AbstractValidator
{
    /**
     * Validate the job filter inputs.
     *
     * @param  array<string, mixed>  $filters
     * @return array<string>  error messages, empty if valid
     */
    public function validate(array $filters): array
    {
        $errors = [];

        if (empty($filters['credential'])) {
            $errors[] = trans('{module-name}::app.validation.credential-required');
        }

        if (empty($filters['channel'])) {
            $errors[] = trans('{module-name}::app.validation.channel-required');
        }

        if (empty($filters['locale'])) {
            $errors[] = trans('{module-name}::app.validation.locale-required');
        }

        return $errors;
    }
}
```

---

## 7. Importer Class

```php
<?php
// src/Helpers/Importers/Product/Importer.php

namespace Webkul\{ModuleName}\Helpers\Importers\Product;

use Webkul\DataTransfer\Helpers\Importers\AbstractImporter;
use Webkul\{ModuleName}\Repositories\CredentialRepository;
use Webkul\{ModuleName}\Services\{ModuleName}Service;

class Importer extends AbstractImporter
{
    public const BATCH_SIZE = 100;

    public const UNOPIM_ENTITY_NAME = 'product';

    public function __construct(
        protected CredentialRepository $credentialRepository,
        protected {ModuleName}Service $service,
    ) {}

    /**
     * Import a batch of external products into Unopim.
     *
     * @param  array<mixed>  $items   Raw items from external API
     * @return void
     */
    public function importBatch(array $items): void
    {
        foreach ($items as $item) {
            $this->processImportItem($item);
        }
    }

    /**
     * @param  array<mixed>  $item
     */
    protected function processImportItem(array $item): void
    {
        // Transform external item to Unopim product format
        // and upsert via product repository
    }
}
```

---

## 8. Checklist

- [ ] `exporters.php` has `async`, `track_by`, `label_by`, `list_route` on every `select` field
- [ ] `quick_exporters.php` created with `title/route/exporter/source` (no `filters`)
- [ ] `importers.php` created using same filter field structure as exporters
- [ ] `{module-slug}.credentials.get` route registered returning `[{id, label}]`
- [ ] Exporter classes in `Helpers/Exporters/{Entity}/` (not `Services/`)
- [ ] Importer classes in `Helpers/Importers/{Entity}/`
- [ ] Both extend `AbstractExporter` / `AbstractImporter` from `Webkul\DataTransfer`
- [ ] `BATCH_SIZE` constant defined in each exporter/importer
- [ ] `UNOPIM_ENTITY_NAME` constant defined
- [ ] Validator classes in `Validators/JobInstances/Export/` and `.../Import/`
- [ ] All 3 config files registered in ServiceProvider's `registerConfig()`
- [ ] `dependent` used in fields where one selection changes another's options
