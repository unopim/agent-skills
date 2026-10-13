# Agent and Magic AI commands

Resolve the `php artisan` prefix with unopim-exec first. Every command below is registered inside a `runningInConsole()` block — `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php` and `packages/Webkul/MagicAI/src/Providers/MagicAIServiceProvider.php`. A command that is not in one of those two lists does not exist, whatever a docblock or `AGENTS.md` says.

## Contents

- [ai-agent commands](#ai-agent-commands)
- [Commands that do not exist](#commands-that-do-not-exist)
- [Scheduling](#scheduling)
- [Writing a new ai-agent command](#writing-a-new-ai-agent-command)
- [Magic AI platform commands](#magic-ai-platform-commands)

## ai-agent commands

| Command | Options | Class |
|---|---|---|
| `ai-agent:quality-monitor` | `--channel=default`, `--locale=en_US`, `--limit=500` | `packages/Webkul/AiAgent/src/Console/Commands/CatalogQualityMonitor.php` |
| `ai-agent:cleanup` | `--days=7`, `--dry-run` | `packages/Webkul/AiAgent/src/Console/Commands/CleanupTempFiles.php` |
| `ai-agent:embeddings:index` | `--since=`, `--batch=` | `packages/Webkul/AiAgent/src/Console/Commands/IndexProductEmbeddings.php` |

### ai-agent:quality-monitor

- Exits `SUCCESS` and does nothing unless both `general.magic_ai.agentic_pim.enabled` and `general.magic_ai.agentic_pim.quality_monitor` are on (`packages/Webkul/Admin/src/Config/system.php`). "It ran and found nothing" is usually "it is switched off" — check config before debugging.
- Scans at most `--limit` products, decodes `values` in PHP, and inserts a `quality_report` row plus, when issues exist, a `notification` row into `ai_agent_tasks`; the dashboard reads them.
- The query has a `limit` but no `orderBy`, so which products are scanned is engine-defined and differs between MySQL and PostgreSQL. It is a sample, not a full audit — never raise `--limit` to the catalog size to "scan everything"; that loads every row's JSON into memory. A full scan must be an id-ordered `chunkById` like `ai-agent:embeddings:index`.
- `--channel` / `--locale` go into PHP array keys only, not SQL; an unknown code just reports everything as missing.

### ai-agent:cleanup

- Deletes `ai_compressed_*` files in `sys_get_temp_dir()` and files older than `--days` under `storage/app/public/ai-agent/{images,files,exports,generated,edited}`.
- Uses local paths, so on a multi-server or container deployment it cleans only the node it runs on — schedule it per node, not `onOneServer()`.
- Always run `--dry-run` first on a live install. Test pattern: `packages/Webkul/AiAgent/tests/Feature/CleanupTempFilesTest.php` — but note that directory is not in any `phpunit.xml` suite (see SKILL.md), so mirror the test under `packages/Webkul/AiAgent/tests/Unit` if you change the command.

### ai-agent:embeddings:index

- No-op with a warning unless `ProductEmbeddingIndex::isEnabled()` — `ai-agent.vector_store.enabled` (`AI_AGENT_VECTOR_STORE_ENABLED`) AND `elasticsearch.enabled`. Without Elasticsearch the agent falls back to database similarity; do not make a feature depend on this command having run.
- Calls `ensureIndex()`, then `chunkById($batch)` over `products.id` and dispatches one `packages/Webkul/AiAgent/src/Jobs/IndexProductEmbeddingsJob.php` per chunk. `--batch` defaults to `ai-agent.vector_store.batch_size` and is clamped to 1–1000. Nothing is indexed until a queue worker runs.
- `--since` filters on `updated_at` and rejects unparseable dates with `FAILURE`. Use it for incremental re-runs; the observer (`packages/Webkul/AiAgent/src/Observers/ProductEmbeddingObserver.php`) keeps single-product edits in sync.
- This is the exemplar for any catalog-wide AI command: select ids only, `chunkById`, queue the work, clamp the batch.

## Commands that do not exist

`ai-agent:enrich-products` and `ai-agent:analyze-image` appear in docblocks of `packages/Webkul/AiAgent/src/Examples/EnrichProductsBatchCommand.php` and `packages/Webkul/AiAgent/src/Examples/AnalyzeProductImageCommand.php`, and in the package's `AGENTS.md`. Neither class is registered by any provider; running them prints "command not defined".

Do not register them as they stand:

- `EnrichProductsBatchCommand` calls `$productRepository->all()->take($limit)->get()` — `all()` hydrates every product before `take()`, and `Collection::get()` needs a key, so it fails after loading the catalog. It also reads `$p->name` / `$p->description`, which live in `values` JSON, not columns.
- Both default to `--agent-id` / `--credential-id` of 1 or 4 — ids that exist only on the author's install.

To ship bulk enrichment, write a new command on the `ai-agent:embeddings:index` shape (ids via `chunkById`, one queued job per chunk) that calls the agent from the job — see `packages/Webkul/AiAgent/src/Jobs/AutoEnrichProductJob.php` for the per-product call — and register it in the provider.

## Scheduling

None of the ai-agent commands is scheduled by core. The schedule lives in `bootstrap/app.php` `withSchedule()`, inside a group that applies `onOneServer()->withoutOverlapping()->runInBackground()`. Docblocks that say "schedule in the kernel" predate Laravel 11 — there is no `Console\Kernel`.

- `ai-agent:quality-monitor` belongs in that group (it writes shared DB rows; one server is right).
- `ai-agent:cleanup` does not — it cleans local disk, so it must run on every node.
- `ai-agent:embeddings:index` is a backfill; schedule it only with `--since`, never as a nightly full reindex.

A plugin schedules its own commands from its provider with `$this->callAfterResolving(Schedule::class, ...)`, not by editing `bootstrap/app.php`.

## Writing a new ai-agent command

1. Declare it with the `#[Signature(...)]` and `#[Description(...)]` attributes, as every command above does; prefix the name `ai-agent:` (core) or your package slug (plugin).
2. Open `handle()` with the same feature gate as `quality-monitor`: return `SUCCESS` with a message when `general.magic_ai.agentic_pim.enabled` is off.
3. Never load products unbounded: ids only, `chunkById`, queue one job per chunk, clamp the batch size (unopim-standards scale.md).
4. Read credentials and platforms through their repositories (`packages/Webkul/MagicAI/src/Repository/MagicAIPlatformRepository.php`, `packages/Webkul/AiAgent/src/Repositories/CredentialRepository.php`); never hardcode an id default.
5. Output goes through `trans()`. The three ai-agent commands still print English literals; the localized exemplar is the Magic AI platform command set below — copy that, not them.
6. Register it in the provider's `runningInConsole()` `commands([...])` list.
7. Test with `$this->artisan(...)->assertSuccessful()` in a suite that actually runs.

## Magic AI platform commands

Provision AI providers from the CLI (hosting, Docker entrypoints, CI) — the same validation and repository path as the admin form. Base class: `packages/Webkul/MagicAI/src/Console/Commands/Platform/PlatformCommand.php`; shared collection logic: `packages/Webkul/MagicAI/src/Console/Commands/Platform/Concerns/CollectsPlatform.php`.

| Command | Arguments / options |
|---|---|
| `unopim:magic-ai:platform:list` | — |
| `unopim:magic-ai:platform:add` | `--provider=` `--label=` `--api-url=` `--models=` `--azure-deployment=` `--azure-api-version=` `--default` `--disabled` `--unmanaged` `--key-stdin` |
| `unopim:magic-ai:platform:edit` | `{id?}` plus the add options, `--enabled`, `--managed`; omitting `--key-stdin` keeps the stored key |
| `unopim:magic-ai:platform:delete` | `{id?}` `--force` |
| `unopim:magic-ai:platform:default` | `{id?}` |

Provider codes are the cases of `packages/Webkul/MagicAI/src/Enums/AiProvider.php`: `openai`, `anthropic`, `gemini`, `groq`, `ollama`, `xai`, `mistral`, `deepseek`, `azure`, `openrouter`, `concentrate`, `custom`. An unknown code fails and lists the valid ones.

Rules the commands enforce — do not work around them:

- **The key never goes on the command line.** There is no `--api-key` option. Non-interactive runs pipe it: `printf '%s\n' "$KEY" | php artisan unopim:magic-ai:platform:add --provider=openai --models=gpt-4o --key-stdin`. argv is visible in the process table and shell history. Every provider except `ollama` requires a key on add.
- **Non-interactive add needs `--provider` and `--models`** (or an existing platform's values on edit); missing ones fail with `missing-option`.
- **Delete** refuses the default platform, and refuses without `--force` when the input is non-interactive.
- **Default** refuses a disabled platform.
- **Managed lock** — CLI-added platforms are managed unless `--unmanaged`. `packages/Webkul/MagicAI/src/Services/ManagedPlatform.php` then pins provider, endpoint and model list while the stored key is used, so an admin cannot point the hosting owner's key at another endpoint. A form or API change that bypasses `ManagedPlatform::violations()` reopens that hole.

Storage: the key is saved through the repository, encrypted at rest. The pattern (`encrypted` cast + hidden + `$auditExclude`, masked display, keep-on-empty) is documented once in unopim-plugin-development `credentials.md` — follow it for any new AI credential field; do not re-derive it.

Command strings live under `admin::app.configuration.platform.command.*` in `packages/Webkul/Admin/src/Resources/lang/en_US/app.php`; a new message goes there first, then all 33 locales.

Tests: `packages/Webkul/MagicAI/tests/Feature/PlatformCommandsTest.php` — mocks `ModelDiscovery` and `packages/Webkul/MagicAI/src/Console/Support/StdinReader.php` and drives prompts with `expectsQuestion()`. The MagicAI suites run only in the MariaDB workflow, so run `--testsuite="MagicAI Feature Test"` locally.
