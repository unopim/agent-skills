---
name: unopim-data-transfer
description: Use when configuring an UnoPim import or export, building an Exporter, Importer or Validator class, debugging a queued data-transfer job, or wiring exporters.php, quick_exporters.php or importers.php. Trigger phrases include "import", "export", "data transfer", "exporter", "importer", "CSV", "queued job", "batch".
requires: unopim-standards, unopim-exec, unopim-verify
---

# UnoPim Data Transfer

Import/export runs as a queued, batched, state-tracked pipeline in `packages/Webkul/DataTransfer`. The pipeline instantiates your classes through config — a wrong signature is a fatal at runtime, and an invented method is silently never called. Verify every override against the base class before writing it.

**REQUIRED BACKGROUND:** Use unopim-standards for Laravel 13 / PHP 8.4 idiom, comments, localization and scale rules. Use unopim-exec to resolve commands for this workspace. Use unopim-verify before claiming any change complete. For package scaffolding, providers, credentials and cURL clients, use unopim-plugin-development.

## Reference files

| File | Read when |
|---|---|
| [pipeline.md](pipeline.md) | Job flow, full state machines, queues, models, debugging a stuck or failed job |
| [exporters.md](exporters.md) | Building an Exporter, streaming sources, `exporters.php` / `quick_exporters.php` wiring |
| [importers.md](importers.md) | Building an Importer, `importers.php` wiring, chunked lookups, error codes |
| [validators.md](validators.md) | Job validators — declarative rules, naming, wiring |

## Invented API vs real API

Earlier docs invented methods that do not exist anywhere in the codebase. NEVER write the left column; the right column is what core ships.

| Invented (fatal or dead) | Real API |
|---|---|
| `initializeExport()` | `initilize()` — misspelled in core, empty on `AbstractExporter`; your `exportBatch()` calls it, once per batch |
| `$this->getFilterValue('credential')` | `$this->getFilters()['credential']` |
| `$this->initializeBatch($batch)` | nothing — `exportBatch()` opens with `Event::dispatch` then `$this->initilize()` |
| `$this->saveBatchSummary($batch, $filePath)` | `$this->updateBatchState($batch->id, Export::STATE_PROCESSED)` |
| `AbstractValidator` with `validate(array $filters): array` | `Validators\JobInstances\Default\JobValidator` with `validate(array $data, array $options = []): void` — throws `ValidationException` |
| `importBatch(array $items): void` | `importBatch(JobTrackBatchContract $batch): bool` plus `validateRow(array $rowData, int $rowNumber): bool` — both abstract, both required |
| `UNOPIM_ENTITY_NAME`, `ACTION_ADD`, `ACTION_UPDATE`, `CODE_ALREADY_EXIST`, `CODE_NOT_EXIST` constants | nothing reads them — real conventions are `ERROR_*` string codes and `BATCH_SIZE` |
| `'dependent' => ['locale']` filter key | `'depends_on' => ['field' => ..., 'as' => ...]` — `dependent` is silently dropped |

Core keeps the misspellings `initilize()` and `getSkippedtemsCount()`. Match them in subclasses; "fixing" the spelling creates a new method core never calls.

## Hard rules

- Exporters extend `Webkul\DataTransfer\Helpers\Exporters\AbstractExporter`; importers extend `Webkul\DataTransfer\Helpers\Importers\AbstractImporter` and MUST pass `JobTrackBatchRepository` to `parent::__construct()`.
- Counters: `$this->createdItemsCount++` after a create, `$this->updatedItemsCount++` after an update, `$this->skippedItemsCount++` on skip. Never swap them — job summaries report them by name.
- The async quartet (`async`, `track_by`, `label_by`, `list_route`) is required ONLY for route-backed select options. Static inline `options` are correct for fixed lists — core ships `file_format` and `date_format` that way in `packages/Webkul/DataTransfer/src/Config/exporters.php`.
- Export sources MUST stream for large entities: override `getResults()` with an id-cursor (keyset) source like `packages/Webkul/DataTransfer/src/Helpers/Sources/Export/ProductCursor.php`. The inherited default hydrates `source->all()` — acceptable only for small entities (locales, currencies, channels).
- Bulk existence lookups inside batches use `array_chunk($keys, 1000)` + `whereIn`, never one query per row — see `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/SKUStorage.php`.
- State machines include `validating` (import), `paused` and `cancelled` besides pending/validated/processing/completed/failed — pause, resume and cancel are live flows; see [pipeline.md](pipeline.md).
- Job config `title` values and every user-facing string are translation keys (`{package}::app...`), propagated to all 33 locales.
- No comments inside method bodies, array literals, route groups or Blade markup in any code you write here.

## Checklist

- [ ] Exporter: `exportBatch(JobTrackBatchContract $batch, $filePath): bool`; opens with `Event::dispatch` + `initilize()`; closes with `updateBatchState(..., Export::STATE_PROCESSED)`
- [ ] Importer: both `validateRow()` and `importBatch()` implemented with the exact base signatures; parent constructor called
- [ ] Validator: extends `Default\JobValidator`, named `{Entity}JobValidator`, declarative `$rules`
- [ ] `getResults()` streams via id-cursor for any large entity — no unbounded `->all()`/`->get()`
- [ ] External-id/SKU lookups preloaded chunked (`array_chunk(..., 1000)` + `whereIn`), not queried per row
- [ ] Select filter fields: static `options` for fixed lists; async quartet only with a real `list_route` returning objects keyed by `track_by`/`label_by`
- [ ] Dependent selects use `depends_on`
- [ ] Config files merged in the provider (`exporters`, `importers`, `quick_exporters` keys) — exemplar `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php`
- [ ] Counters increment on the matching action; summary counts verified in the job report
- [ ] New admin routes (e.g. `list_route` endpoints) registered under `['admin']` middleware and ACL-covered — enforcement is fail-open by route name
