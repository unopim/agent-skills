# Data Transfer Pipeline

How a job runs from click to completion. Orchestrators live in `packages/Webkul/DataTransfer/src/Helpers/Import.php` and `packages/Webkul/DataTransfer/src/Helpers/Export.php`.

## Architecture

| Class | Purpose |
|---|---|
| `packages/Webkul/DataTransfer/src/Helpers/Import.php` | Import orchestrator — validates, batches, dispatches, tracks state |
| `packages/Webkul/DataTransfer/src/Helpers/Export.php` | Export orchestrator — resolves the exporter from config, tracks state |
| `packages/Webkul/DataTransfer/src/Helpers/Importers/AbstractImporter.php` | Base importer — batch splitting, counters, error codes |
| `packages/Webkul/DataTransfer/src/Helpers/Exporters/AbstractExporter.php` | Base exporter — batch persistence, file buffers, counters |
| `packages/Webkul/DataTransfer/src/Helpers/Sources/CSV.php`, `packages/Webkul/DataTransfer/src/Helpers/Sources/Excel.php` | File readers for imports |
| `packages/Webkul/DataTransfer/src/Helpers/Sources/Export/ProductCursor.php` | Keyset-paginated export source (the streaming exemplar) |

## Models

| Model | Purpose |
|---|---|
| `packages/Webkul/DataTransfer/src/Models/JobInstances.php` | Job definition — type, entity, file path, filters |
| `packages/Webkul/DataTransfer/src/Models/JobTrack.php` | One job run — state, summary, errors |
| `packages/Webkul/DataTransfer/src/Models/JobTrackBatch.php` | One batch of rows within a run — state, data, summary |

Table names are bare (`job_track_batches`); any prefix comes from `env('DB_PREFIX', '')`, default empty.

## Queued jobs

Every batch runs as a `ShouldQueue` job. Import chains are built in `AbstractImporter::importData()`; export chains in `AbstractExporter::exportData()` — both via `Bus::batch()` + `Bus::chain()`.

| Stage | Job class |
|---|---|
| Import track / batch | `ImportTrackBatch`, `packages/Webkul/DataTransfer/src/Jobs/Import/ImportBatch.php` |
| Linking | `Linking`, `LinkBatch` (only when the importer sets `$linkingRequired`) |
| Indexing | `Indexing`, `IndexBatch` (only when the importer sets `$indexingRequired`) |
| Completion | `Completed` (import and export variants) |
| Export track / batch | `ExportTrackBatch`, `packages/Webkul/DataTransfer/src/Jobs/Export/ExportBatch.php` |
| Upload | `UploadFile` |

## State machines

State constants live on `Import` and `Export` (`STATE_*`). Both machines include pause/cancel — these are live flows, not dead constants: processing halts when the track state is `paused`, `cancelled` or `failed`.

Import (`packages/Webkul/DataTransfer/src/Helpers/Import.php`):

```
pending → validating → validated → processing → processed
        → [linking → linked]      (importer sets $linkingRequired)
        → [indexing → indexed]    (importer sets $indexingRequired)
        → completed

any active state → paused ⇄ processing (resume)
any active state → cancelled
any state        → failed
```

Export (`packages/Webkul/DataTransfer/src/Helpers/Export.php`):

```
pending → processing → completed
batches: pending → processed   (your exportBatch() sets this via updateBatchState)

processing → paused ⇄ processing (resume)
processing → cancelled
any state  → failed
```

NEVER document or test against a diagram that omits `validating`, `paused` or `cancelled` — the admin UI exposes pause/resume/cancel buttons and support tickets arrive in those states.

## CLI

Resolve the actual command wrapper (container vs host) through unopim-exec first.

```bash
php artisan queue:work --queue=webhooks,default,system,completeness,publication

php artisan unopim:queue:work {jobId} {userEmail}

php artisan queue:restart
```

The five-queue list matches CI (`.github/workflows/playwright_test.yml` in the UnoPim repo). `unopim:queue:work` is defined in `packages/Webkul/DataTransfer/src/Console/JobExecuteCommand.php` — it runs a single job as the given admin user, useful for reproducing a failure in the foreground.

## Troubleshooting

| Symptom | Check |
|---|---|
| Job stuck in `pending` | No queue worker running — start `queue:work` with the queue list above |
| Job stuck in `paused` | Someone paused it in the admin UI; resume from there or check `JobTrack.state` |
| Import fails at validation | `JobTrack.errors` holds row-level errors keyed by the `ERROR_*` codes; state is `failed` with summary intact |
| Export produces an empty file | Filters match no records, or a custom `getResults()` returns an empty iterator — run `unopim:queue:work` in the foreground and read the job log |
| Batches processed but track never completes | The chain's `Completed` job died — inspect `failed_jobs` |
| Code changes not picked up by workers | Workers cache code — `php artisan queue:restart` after every deploy/edit |

## Wiring an entity into the pipeline

The orchestrators resolve everything from config: `Export::getTypeExporter()` reads `config('exporters.{entity}')` falling back to `config('quick_exporters.{entity}')` and requires `exporter` + `source` keys. Register configs in your provider — see [exporters.md](exporters.md) and [importers.md](importers.md).
