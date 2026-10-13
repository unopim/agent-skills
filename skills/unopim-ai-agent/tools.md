# Chat tools

## Contents

- [Request flow](#request-flow)
- [Tool anatomy](#tool-anatomy)
- [Metadata](#metadata)
- [Registering, overriding, disabling](#registering-overriding-disabling)
- [Permission layers](#permission-layers)
- [Input schema](#input-schema)
- [Safe database access](#safe-database-access)
- [Write tools and approval modes](#write-tools-and-approval-modes)
- [Output contract](#output-contract)
- [Extension events](#extension-events)
- [Testing a tool](#testing-a-tool)

## Request flow

1. `packages/Webkul/AiAgent/src/Http/Controllers/ChatController.php` aborts unless `bouncer()->hasPermission('ai-agent')`, then builds an immutable `ChatContext` (`packages/Webkul/AiAgent/src/Chat/ChatContext.php`): message, history, product id/SKU/name, `locale`, `channel`, the `MagicAIPlatform`, model, uploaded paths, current page, the `Admin` user.
2. `ChatContext::__construct()` rejects any `locale` or `channel` that is not `^[a-zA-Z0-9_-]+$` — so those two are safe to put in JSON paths. Nothing else the model sends is.
3. `AgentRunner::buildAgent()` (`packages/Webkul/AiAgent/src/Chat/AgentRunner.php`) calls `ToolRegistry::build($context)`, which drops tools whose `permission` the user lacks or whose `authorize()` returns false, then calls each remaining tool's `register($context)`.
4. laravel/ai runs the tool loop inside `BoundedAgent` (`max_steps` from `general.magic_ai.agentic_pim.max_steps`). There is no per-call hook — the only veto is inside your `handle()`.
5. After the loop, `AgentRunner` dispatches `AgentToolExecuted` per result, merges action keys into the response, and sets `mutated` for successful `write` tools.

## Tool anatomy

Copy `packages/Webkul/AiAgent/src/Chat/Tools/DataQualityReport.php` (no dependencies) or `packages/Webkul/AiAgent/src/Chat/Tools/SearchProducts.php` (injected service). Shape:

```php
<?php

namespace Webkul\{Package}\Chat\Tools;

use Illuminate\Contracts\JsonSchema\JsonSchema;
use Illuminate\Support\Facades\DB;
use Laravel\Ai\Contracts\Tool;
use Laravel\Ai\Tools\Request;
use Webkul\AiAgent\Chat\ChatContext;
use Webkul\AiAgent\Chat\Concerns\ChecksPermission;
use Webkul\AiAgent\Chat\Contracts\PimTool;
use Webkul\AiAgent\Chat\Tools\ContextualTool;

class FindProductsMissingAttribute implements PimTool
{
    public function register(ChatContext $context): Tool
    {
        return new class($context) extends ContextualTool
        {
            use ChecksPermission;

            public function name(): string
            {
                return 'find_products_missing_attribute';
            }

            public function description(): string
            {
                return 'List products whose value for one attribute is empty in the current channel and locale. Use for gap reports, not for editing.';
            }

            public function schema(JsonSchema $schema): array
            {
                return [
                    'attribute_code' => $schema->string()->description('Attribute code to check, e.g. description'),
                    'limit'          => $schema->integer()->description('Maximum products to return (default 20, max 100)'),
                ];
            }

            public function handle(Request $request): string
            {
                if ($denied = $this->denyUnlessAllowed($this->context, 'catalog.products')) {
                    return $denied;
                }

                $code = $request->string('attribute_code')->toString();
                $limit = min(max($request->integer('limit', 20), 1), 100);

                if (! preg_match('/^[a-zA-Z0-9_]+$/', $code)) {
                    return json_encode(['error' => 'Invalid attribute_code.']);
                }

                $attribute = DB::table('attributes')
                    ->where('code', $code)
                    ->first(['code', 'value_per_locale', 'value_per_channel']);

                if (! $attribute) {
                    return json_encode(['error' => "Attribute '{$code}' not found."]);
                }

                ...

                return json_encode(['result' => ['total' => $rows->count(), 'products' => $rows->all()]]);
            }
        };
    }
}
```

- The outer class is what the registry holds; the anonymous `ContextualTool` is rebuilt per request with that request's `ChatContext`. Put every per-request value on `$this->context`, never on the outer class.
- An injected service goes in the outer constructor and is handed to the anonymous class — see how `SearchProducts` passes `SemanticRankingService`. The outer instance lives as long as the worker, so inject only stateless services there; resolve `scoped()` ones (see `registerBindings()` in `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php`) inside `handle()`.
- `name()` must equal the metadata `name`. `flagMutation()` and `writeToolNames()` look tools up by that name; a mismatch silently loses the `write` flag.
- The `description()` is the whole of the model's routing signal. Say when to use the tool and when not to. Do not overlap an existing tool's description.

## Metadata

Read by `ToolRegistry::register()`; documented in `packages/Webkul/AiAgent/Config/ai-agent.php`.

| Key | Default | Effect |
|---|---|---|
| `name` | `Str::snake(class_basename)` | Tool name exposed to the model; must match `name()` |
| `group` | `general` | Section in the system prompt's "Tool Groups"; core uses `catalog`, `content`, `taxonomy`, `admin`, `intelligence` |
| `write` | `false` | Listed as a write tool in `review`/`suggest` prompt text; drives the widget's `mutated` reload |
| `permission` | `null` | ACL key checked in `build()`; `null` offers the tool to anyone with chat access |
| `enabled` | `true` | Read only by the provider's config loop; `false` keeps the class out of the registry |
| `guidance` | `null` | Extra line under "Tool Notes:"; control characters stripped and cut to 500 characters |

## Registering, overriding, disabling

**Core tool** — add one line to `packages/Webkul/AiAgent/Config/ai-agent.php` in its group block.

**Plugin tool** — do NOT `mergeConfigFrom()` a file with a `tools` key into `ai-agent`. Laravel's `mergeConfigFrom` is `array_merge(file, existing)` at the top level only: if core merged first, the plugin's `tools` array is discarded; if the plugin merged first, core's file overwrites it — either way one side's tools vanish. Register against the singleton instead, from the plugin provider's `register()`:

```php
$this->callAfterResolving(ToolRegistry::class, function (ToolRegistry $registry, $app): void {
    $registry->register($app->make(FindProductsMissingAttribute::class), [
        'name'       => 'find_products_missing_attribute',
        'group'      => 'intelligence',
        'write'      => false,
        'permission' => 'catalog.products',
    ]);
});
```

`callAfterResolving` also runs immediately if the registry was already resolved, and it survives `config:cache`.

**Override a core tool** — register a subclass or replacement under the same tool `name` after calling `$registry->disable('search_products')`, or re-register the same class: `register()` keyed by class replaces the earlier instance and metadata.

**Disable** — `$registry->disable($classOrName)`, or at config level `config()->set('ai-agent.tools.'.SearchProducts::class.'.enabled', false)` before the registry is first resolved (the extensibility test does exactly this).

## Permission layers

| Layer | Where | Purpose |
|---|---|---|
| Chat route | `ChatController` `abort_unless(bouncer()->hasPermission('ai-agent'), 403)` + `packages/Webkul/AiAgent/Config/acl.php` | Who can talk to the agent at all |
| Offer | `permission` metadata, checked in `ToolRegistry::build()` | The model never sees a tool the user cannot use |
| Availability | `AuthorizesContext::authorize(ChatContext)` | Feature flags, channel scope, product-context-only tools |
| Enforcement | `denyUnlessAllowed()` from `packages/Webkul/AiAgent/src/Chat/Concerns/ChecksPermission.php`, first line of `handle()` | Defence in depth; also the only check when a tool is registered with `permission => null` |

Rules:

- Use an ACL key that already exists in an `acl.php` and matches the action: read → `catalog.products`, edit → `catalog.products.edit`, mass write → `catalog.products.mass_update`, delete → `catalog.products.delete`. Copy the pairing from the core rows in `ai-agent.php`.
- `ChatContext::hasPermission()` returns true for `permission_type = all` before it consults the key. A misspelt key therefore works for the super-admin you test with and denies every custom role. Test the denial with a role that holds explicit permissions.
- `ChatContext::$user` can be null (`hasPermission()` then returns false); never dereference it without the null-safe operator.
- A new tool needs no new route, so the route-name ACL fail-open rule does not apply to it — but a new controller endpoint for the widget does (unopim-standards security.md).

## Input schema

- Builder methods in core: `$schema->string()`, `->integer()`, `->boolean()`, `->enum([...])`, `->description(...)`. No core tool marks a field `required()` — the model may omit any argument, so default every field in `handle()`.
- Read arguments with the typed accessors core uses: `$request->string('x')->toString()`, `$request->integer('x', $default)`. Treat each as hostile: the model can be steered by prompt-injected product data.
- Structured payloads are passed as JSON strings (`changes_json` in `packages/Webkul/AiAgent/src/Chat/Tools/BulkEdit.php`); `json_decode`, check `is_array`, then allow-list keys against the family's attributes.
- Return validation failures as `json_encode(['error' => ...])` — the model reads it and retries. Do not throw.

## Safe database access

- **Allow-list every identifier** the model supplies (attribute, family, category, channel codes) with `preg_match('/^[a-zA-Z0-9_-]+$/', ...)` before it reaches a query, as `SearchProducts` does for `family_code` and `category_code`. Bind values; never interpolate them.
- **Bound every read.** Clamp the `limit` (`min(max($limit, 1), N)`), keep the ceiling low (core: 50 for search, 100 for bulk edit, 1000 for the quality scan), select named columns, add an explicit `orderBy` — insert-then-read order differs on PostgreSQL. A tool never `->get()`s a table without a limit; for anything larger, queue a job and return its tracker, as `packages/Webkul/AiAgent/src/Chat/Tools/ImportProducts.php` does.
- **No per-row queries.** Load lookups once before the loop (`BulkEdit` loads `currencies` once). See unopim-standards scale.md.
- **JSON values are dialect-specific.** Product data lives in `products.values` keyed `common`, `locale_specific.{locale}`, `channel_specific.{channel}`, `channel_locale_specific.{channel}.{locale}`. Build the path from the attribute's `value_per_locale` / `value_per_channel` (`SearchProducts::valuePath()`), and emit SQL through `GrammarQueryManager::getGrammar()` (`packages/Webkul/Core/src/Helpers/Database/GrammarQueryManager.php`) — `jsonExtract()`, `jsonContains()`, `castToText()`.
- **Prefix raw aliases.** Laravel prefixes the alias in `DB::table('products as p')`, so a raw fragment must say `DB::getTablePrefix().'p.values'` (see `SearchProducts`). A bare column name with no table qualifier needs no prefix.
- **Writes go through the domain layer** — `ProductRepository` or `packages/Webkul/AiAgent/src/Services/ProductWriterService.php` — so product events, history, completeness and the embedding observer fire. A raw `DB::table('products')->update()` skips all of them.

## Write tools and approval modes

`general.magic_ai.agentic_pim.approval_mode` (`packages/Webkul/Admin/src/Config/system.php`):

| Mode | What actually happens |
|---|---|
| `auto` (seeded default) | Prompt tells the model to confirm with the user first; tools execute |
| `review` | Prompt asks for confirmation; a tool that calls `shouldQueueForApproval()` writes a pending row to `ai_agent_changesets` via `queueChange()` instead of mutating; `packages/Webkul/AiAgent/src/Http/Controllers/ApprovalController.php` applies it later |
| `suggest` | Prompt forbids write tools — enforced by nothing but the model |

So:

- A write tool `use QueuesForApproval;` and, after validation and before the first mutation, returns `$this->queueChange($this->context, $summary, $changeData)` when `shouldQueueForApproval()` is true. Exemplar: `CreateProduct`. Include `affected_count` in `$changeData`.
- `ApprovalController::approve()` applies only the `type`s it branches on — `create_product` (reads `data.create`, `data.values`), `update_product` (`product_id`, `data.values`), `delete_products` (`product_ids`), `bulk_edit` and `assign_categories` (`product_updates[]` of `product_id` + `values`). Any other type, or a matching type with the wrong shape, is marked `applied` with zero changes. Queue one of those exact shapes, or extend `approve()` in the same change. Do not copy `CreateProduct`'s queued payload: it stores `data.sku`, `data.name`, … which `approve()` does not read.
- If a write must never run in `suggest` mode, check the mode in `handle()`; the prompt alone is not a control.
- Mark the tool `'write' => true` so it appears in the review/suggest prompt lists and the widget reloads.

## Output contract

Return a JSON string. `AgentRunner::mergeActionPayload()` and `flagMutation()` read these keys:

| Key | Effect |
|---|---|
| `error` | Treated as failure; no `mutated` flag |
| `result` (array) | Passed to the widget as the action result |
| `result.updated` (int) | `< 1` means nothing changed — no reload |
| `result.status` starting with `error` | Treated as failure |
| `product_url` / `download_url` | Rendered as action buttons; build with `route()`, never a hardcoded host |

Keep payloads small — every byte goes back into the model's context and the provider's bill. Return SKUs and ids, cap lists (core slices to 10–20), and mask personal data (`ManageUsers::maskUserData()`, tested by `packages/Webkul/AiAgent/tests/Unit/ManageUsersEmailMaskingTest.php`).

## Extension events

- `packages/Webkul/AiAgent/src/Events/AgentSystemPromptBuilding.php` — listeners may rewrite `$event->prompt` before the run.
- `packages/Webkul/AiAgent/src/Events/AgentToolExecuted.php` — fires after the loop, once per tool result. Audit and metrics only; it cannot veto.

## Testing a tool

Put the file in `packages/Webkul/AiAgent/tests/Unit/Tools/` (bound to `CoreTestCase` by `tests/Pest.php`). Build a `ChatContext` the way `packages/Webkul/AiAgent/tests/Unit/ToolRegistryExtensibilityTest.php` does — named arguments, `(new MagicAIPlatform)->forceFill(['provider' => 'openai'])`, an `Admin` with a `Role` relation set — and invoke `register($context)->handle(new Request([...]))`.

Cases every tool needs:

- [ ] Denied for a role without the permission (explicit permissions, not `all`)
- [ ] `limit` above the ceiling is clamped; result count never exceeds it
- [ ] A code with a quote, space or `%` returns `error`, runs no query
- [ ] Write tool: `review` mode inserts into `ai_agent_changesets` and leaves the product unchanged
- [ ] Registry: tool appears in `build()` for a permitted user and not for a denied one
- [ ] Raw SQL: add the file to `packages/Webkul/AiAgent/tests/Unit/Tools/PgsqlCompatibilityTest.php`
