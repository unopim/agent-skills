# Baseline — without the skill

**Status: desk-run, not a live session.** The plan below was written from generic
Laravel 13 / laravel/ai knowledge before reading the AiAgent package, then checked
line by line against UnoPim `origin/master`. No agent transcript was captured.

## Task

> Add an AI agent chat tool `find_products_missing_attribute` that lists products
> whose value for a given attribute is empty, so a catalog manager can ask
> "which shoes have no description?" in the chat.

## Plan produced without the skill

1. Create `app/Ai/Tools/FindProductsMissingAttribute.php` implementing
   `Laravel\Ai\Contracts\Tool` with `description()`, `schema()`, `handle()`.
2. Register it in `config/ai.php` under a `tools` key, or in `AppServiceProvider`
   via an `AiAgent::tool(...)` call.
3. Query with Eloquent:
   `Product::whereNull("values->common->{$attr}")->get()` and return
   `$products->toJson()`.
4. No permission check — the chat route already requires an admin login.
5. Tool description as a plain English string.
6. If a table is needed, add a migration under
   `packages/Webkul/AiAgent/src/Database/Migrations/`.
7. Add `packages/Webkul/AiAgent/tests/Feature/FindProductsMissingAttributeTest.php`
   and run `php artisan test`.

## What was wrong against UnoPim master

| # | Baseline step | Reality on master | Consequence |
|---|---|---|---|
| 1 | Implement `Laravel\Ai\Contracts\Tool` in `app/` | `ToolRegistry::register(PimTool $tool, …)` accepts only `Chat\Contracts\PimTool`; tools live in `packages/Webkul/AiAgent/src/Chat/Tools/` and return an anonymous `ContextualTool` from `register(ChatContext)` | `TypeError` at boot, or the tool is never offered |
| 2 | `config/ai.php` / `AiAgent::tool()` | Neither exists. The registry singleton reads `ai-agent.tools` (`packages/Webkul/AiAgent/Config/ai-agent.php`) | Hallucinated API; tool silently absent |
| 2b | (plugin variant) `mergeConfigFrom($file, 'ai-agent')` — what the config docblock itself suggests | `mergeConfigFrom` is a shallow `array_merge`; the `tools` key of one side replaces the other | Either the plugin's tool or all 35 core tools disappear, depending on provider order |
| 3 | `whereNull("values->common->{$attr}")` | The value may sit under `locale_specific`, `channel_specific` or `channel_locale_specific` depending on the attribute's `value_per_locale` / `value_per_channel`; core resolves the path per attribute (`SearchProducts::valuePath()`) and emits SQL through `GrammarQueryManager` | Wrong answer for every localizable attribute — `description` included, the exact case in the task |
| 3b | `$attr` interpolated into the JSON path | Model-supplied; core allow-lists codes with `^[a-zA-Z0-9_-]+$` before any query | Injection surface fed by prompt-injected product text |
| 3c | `->get()` with no limit, `toJson()` of full models | Core clamps every limit (`min(max(…))`, ceilings 50–1000) and returns SKU/id/name only | Hydrates the whole catalog per chat turn; ships every attribute value of every product to a third-party model |
| 3d | No `orderBy` | PostgreSQL returns a different subset than MySQL | Non-deterministic, unportable results |
| 4 | No permission | Two layers on master: `permission` metadata filtered in `ToolRegistry::build()` and `denyUnlessAllowed()` in `handle()` | Any admin with chat access reads catalog data they cannot see in the UI |
| 5 | English description | Correct — every core tool keeps model-facing text in English. The baseline got this right by accident; it had no rule for the user-facing/model-facing split | — |
| 6 | A `src/Database/Migrations/` folder (invented) | AiAgent loads only root-level `Database/Migration/` (singular) | Migration never runs |
| 7 | Test in the package's Feature folder, `php artisan test` | `phpunit.xml` registers only `packages/Webkul/AiAgent/tests/Unit` ("AiAgent Unit Test"); the Feature folder is in no suite | Test is green locally when run by path and never runs in CI |
| — | Not considered | `write` metadata, approval modes, `AgentToolExecuted`, the Octane singleton capture of constructor-injected services | — (read-only tool, but the same agent would get a write tool wrong) |

## Failure the skill must prevent

An agent with generic Laravel knowledge produces a tool that does not register,
returns wrong data for localizable attributes, reads unbounded rows, leaks the
catalog past ACL to an external model, and ships with a test CI never executes.
