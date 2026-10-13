---
name: unopim-ai-agent
description: Use when adding, changing or debugging an UnoPim AI agent chat tool — a PimTool class, its ToolRegistry entry or the ai-agent.tools config — or when running, scheduling or extending the ai-agent:* console commands, or provisioning Magic AI platforms with the unopim:magic-ai:platform:* commands. Trigger phrases include "AI agent", "chat tool", "PimTool", "ToolRegistry", "agentic PIM", "agent tool", "Magic AI platform", "quality-monitor", "embeddings:index", "magic-ai:platform".
requires: unopim-standards, unopim-exec, unopim-verify, unopim-plugin-development
---

# UnoPim AI Agent

The agentic chat lives in `packages/Webkul/AiAgent`; the provider/platform layer it calls lives in `packages/Webkul/MagicAI`. An LLM decides which tool to call, with arguments it invents — every tool is an untrusted-input entry point, and every read it runs can be asked for the whole catalog.

**REQUIRED BACKGROUND:** unopim-standards (security.md, scale.md, localization.md) for the rules; unopim-exec to resolve commands; unopim-verify before calling anything done. Credential storage for an AI connector is in unopim-plugin-development `credentials.md` — do not re-derive it here.

## Reference files

| File | Read when |
|---|---|
| [tools.md](tools.md) | Adding, overriding or disabling a chat tool; permission layers; approval modes; safe queries; testing a tool |
| [commands.md](commands.md) | Running or writing an `ai-agent:*` command; scheduling; the `unopim:magic-ai:platform:*` commands |

## Exemplars — copy shape from these

| Need | File |
|---|---|
| The contract | `packages/Webkul/AiAgent/src/Chat/Contracts/PimTool.php` |
| Registry and metadata | `packages/Webkul/AiAgent/src/Chat/ToolRegistry.php`, `packages/Webkul/AiAgent/Config/ai-agent.php` |
| Read tool, portable JSON SQL, capped limit | `packages/Webkul/AiAgent/src/Chat/Tools/SearchProducts.php` |
| Write tool that honours review mode | `packages/Webkul/AiAgent/src/Chat/Tools/CreateProduct.php` |
| Per-request availability gate | `packages/Webkul/AiAgent/src/Chat/Contracts/AuthorizesContext.php` |
| PII in tool output | `packages/Webkul/AiAgent/src/Chat/Tools/ManageUsers.php` |
| Batched, resumable command | `packages/Webkul/AiAgent/src/Console/Commands/IndexProductEmbeddings.php` |
| Registry tests | `packages/Webkul/AiAgent/tests/Unit/ToolRegistryExtensibilityTest.php` |

## Invented API vs real API

| Invented | Real |
|---|---|
| A class implementing `Laravel\Ai\Contracts\Tool` registered directly | Implement `PimTool::register(ChatContext $context): Tool`; return an anonymous class extending `Chat\Tools\ContextualTool` |
| Tools in `config/ai.php` or `AiAgent::tool()` | `ai-agent.tools` map (class => metadata) read once by the `ToolRegistry` singleton |
| `mergeConfigFrom(…, 'ai-agent')` from a plugin to add a tool | Shallow merge — it drops the plugin's tools or wipes core's. Use `callAfterResolving(ToolRegistry::class, …)`; see [tools.md](tools.md) |
| `auth()->user()->can(...)` inside `handle()` | `$this->context->hasPermission($key)` via the `ChecksPermission` trait |
| `php artisan ai-agent:enrich-products`, `ai-agent:analyze-image` | Classes in `packages/Webkul/AiAgent/src/Examples/`, never registered — the commands do not exist |
| A `src/Database/Migrations/` folder in AiAgent | Root-level `packages/Webkul/AiAgent/Database/Migration` (singular) — the provider loads only that path |

## Decision procedure — new chat tool

1. Search `packages/Webkul/AiAgent/src/Chat/Tools/` first. A gap in an existing tool is a parameter on it, not a second tool with an overlapping description — the model picks between near-duplicates at random.
2. Pick the ACL key the tool's action maps to in an existing `acl.php` (`catalog.products`, `catalog.products.edit`, …). A key that matches nothing still passes for `permission_type = all` roles, so a typo ships invisibly — see [tools.md](tools.md).
3. Write the class: `implements PimTool`; anonymous `ContextualTool` with `name()`, `description()`, `schema()`, `handle()`; `use ChecksPermission` and call `denyUnlessAllowed()` first in `handle()`.
4. Bound every read: clamp `limit` with `min(max(…))`, a hard ceiling, an explicit `orderBy`, and allow-list every code the model passes before it reaches SQL.
5. Write tools: set `'write' => true`, call `shouldQueueForApproval()` / `queueChange()` before mutating, and go through repositories or `ProductWriterService` so events, history and completeness fire.
6. Register: core → one line in `Config/ai-agent.php`; plugin → `callAfterResolving` in its provider.
7. Test in `packages/Webkul/AiAgent/tests/Unit/Tools/` — the only AiAgent directory in a `phpunit.xml` suite. Its sibling Feature folder belongs to no suite and never runs in CI. Cover: permission denied, limit clamp, invalid code rejected, review-mode queueing.

## UnoPim-specific pitfalls

- **Two permission layers, both required.** `permission` metadata hides the tool from the LLM in `ToolRegistry::build()`; `denyUnlessAllowed()` inside `handle()` is the enforcement. A tool registered with metadata `permission => null` is offered to every admin who can open the chat.
- **Approval mode is mostly prompt text.** `suggest` and `review` are instructions to the model (`AgentRunner::buildSystemPrompt()`); only a tool that calls `shouldQueueForApproval()` actually queues. A write tool without it mutates in every mode.
- **`write` metadata drives the UI.** `AgentRunner::flagMutation()` reads it to tell the widget to reload. A mutating tool flagged `write => false` leaves a stale product page.
- **Singleton capture (Octane).** `ToolRegistry` is a singleton and builds each tool once per worker, so constructor dependencies live for the worker's lifetime. Inject only stateless services; resolve `scoped()` ones (`ProductWriterService`, `VisionService`) inside `handle()`. Keep all request state on `ChatContext`.
- **Portability.** Product values are JSON. Use `GrammarQueryManager::getGrammar()->jsonExtract()` / `jsonContains()` and prefix raw table aliases with `DB::getTablePrefix()`, exactly as `SearchProducts` does. `packages/Webkul/AiAgent/tests/Unit/Tools/PgsqlCompatibilityTest.php` greps for MySQL-only JSON functions — add your tool to it.
- **Elasticsearch is optional.** The vector store needs both `ai-agent.vector_store.enabled` and `elasticsearch.enabled` (`ProductEmbeddingIndex::isEnabled()`); `FindSimilarProducts` falls back to a database pool. Any tool using embeddings needs the same fallback.
- **Model-facing vs user-facing text.** `name()`, `description()`, schema descriptions and JSON `error` strings are read by the LLM and stay English like every core tool. Anything rendered in the admin UI or a command's output goes through `trans()` in all 33 locales (unopim-standards localization.md).
- **Tool output is data sent to a third-party model.** Return the minimum fields; mask PII as `ManageUsers` does; never return credential or platform rows.

## Verification

unopim-verify gates 1–4 and 6 always. Gate 5 (Playwright) only when the chat widget Blade or its JS changed — otherwise state the skip. Run `--testsuite="AiAgent Unit Test"` (CI runs it on MySQL and PostgreSQL). `MagicAI Unit Test` / `MagicAI Feature Test` are absent from the MySQL and PostgreSQL workflows' suite lists — only the MariaDB workflow runs them — so run them yourself after touching MagicAI.
