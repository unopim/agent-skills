# unopim/agent-skills

Agent skills for [UnoPim](https://unopim.com) — a Laravel-based open-source Product Information Management (PIM) system.

These skills provide domain-specific, reusable context for AI agents (Claude Code, Cursor, Windsurf, etc.) working inside an UnoPim codebase. They encode UnoPim's modular Concord architecture, connector conventions, and coding standards so agents generate correct code on the first try.

## Available Skills

### `unopim-package`

Generate complete production-ready UnoPim modules.

**Activates when:** creating new packages/modules — ServiceProvider, ModuleServiceProvider, routes, ACL, menu, controllers, repositories, models with `HistoryTrait`, views, config files (exporters / quick_exporters / importers / acl / menu), migrations with the `wk_` prefix, factories, presenters, contracts, and `composer.json`.

---

### `unopim-plugin-dev`

Plugin and package development for UnoPim.

**Activates when:** creating new packages, extending UnoPim, adding custom importers/exporters, configuring menus/ACL, or building admin features — or when the user mentions `plugin`, `package`, `module`, `extension`, `importer`, `exporter`, `menu`, `ACL`, or `service provider`.

---

### `unopim-backend-dev`

Backend PHP development for UnoPim.

**Activates when:** writing PHP code, creating classes, models, repositories, events, listeners, or tests — or when the user mentions `model`, `repository`, `controller`, `service`, `event`, `listener`, `observer`, `Concord`, or `proxy`. MUST be invoked before writing any PHP tests.

---

### `unopim-datagrid`

Implement UnoPim DataGrid classes for admin listing pages.

**Activates when:** building admin listings with search, filter, sort, row actions (edit/delete), and mass actions — `prepareQueryBuilder` with `DB::table`, `addColumn` closures, `addAction`, `addMassAction`, `bouncer()` permission checks, and Blade integration.

---

### `unopim-credential-management`

Credential storage and API connection testing for connectors.

**Activates when:** building the credentials section of any connector — `Credential` model with `HistoryTrait` and `extras` JSON, Contract interface, `CredentialRepository`, `CredentialController` with `JsonResponse`, FormRequest validation, DataGrid, and migration.

---

### `unopim-http-client`

cURL-based HTTP client classes for third-party connectors.

**Activates when:** building the HTTP layer of a connector — `ApiClient` with retry logic, BasicAuth and OAuth token strategies, connection testing, and error handling. **UnoPim connectors use cURL directly, NOT Guzzle or Laravel HTTP.**

---

### `unopim-connector-quickstart`

Day-1 checklist to build a complete UnoPim connector within one working day.

**Activates when:** starting a new integration (WooCommerce, Shopify, Shopware, module, or any REST API), planning a connector from scratch, or needing the full ordered sequence of steps to ship a production-ready connector module.

---

### `unopim-connector-export-mapping`

Module attribute mapping and mapping history for connectors.

**Activates when:** creating attribute-mapping UI, mapping controller, mapping history, or restricting fields to a module structure. Covers `HistoryTrait`, flat ACL, cURL client, and `JsonResponse` controller patterns.

---

### `unopim-export-workflow`

End-to-end export/import workflow for connectors.

**Activates when:** building export jobs, defining job validators, or implementing exporter/importer logic — `exporters.php`, `quick_exporters.php`, `importers.php`, `Exporter` classes extending `AbstractExporter`, `Validator` classes, queue jobs, and the get-credentials API route.

---

### `unopim-data-transfer`

Import/export pipeline for UnoPim.

**Activates when:** configuring imports/exports, debugging job pipelines, or creating data transfer profiles — or when the user mentions `import`, `export`, `CSV`, `Excel`, `job`, `queue`, `batch`, or `data transfer`.

---

### `unopim-code-review`

Code review for UnoPim.

**Activates when:** reviewing code changes, checking standards compliance, flagging violations, or performing PR reviews — or when the user mentions `review`, `standards`, `conventions`, `best practices`, or `code quality`.

---

### `unopim-git`

Git and GitHub operations for UnoPim.

**Activates when:** creating branches, writing commit messages, or creating pull requests — or when the user mentions `git`, `branch`, `commit`, `PR`, `pull request`, `merge`, or `changelog`.

---

### `unopim-dev-cycle`

Development workflow for UnoPim.

**Activates when:** running tests, linting code, building assets, or debugging — or when the user mentions `test`, `lint`, `pint`, `build`, `npm`, `pest`, `format`, `style`, `quality`, or `coverage`.

---

## Install

Install all skills from this repo into your AI agent:

```bash
npx skills add unopim/agent-skills
```

Install a specific skill only:

```bash
npx skills add unopim/agent-skills --skill "unopim-package"
npx skills add unopim/agent-skills --skill "unopim-plugin-dev"
npx skills add unopim/agent-skills --skill "unopim-backend-dev"
npx skills add unopim/agent-skills --skill "unopim-datagrid"
npx skills add unopim/agent-skills --skill "unopim-credential-management"
npx skills add unopim/agent-skills --skill "unopim-http-client"
npx skills add unopim/agent-skills --skill "unopim-connector-quickstart"
npx skills add unopim/agent-skills --skill "unopim-connector-export-mapping"
npx skills add unopim/agent-skills --skill "unopim-export-workflow"
npx skills add unopim/agent-skills --skill "unopim-data-transfer"
npx skills add unopim/agent-skills --skill "unopim-code-review"
npx skills add unopim/agent-skills --skill "unopim-git"
npx skills add unopim/agent-skills --skill "unopim-dev-cycle"
```

Install for a specific agent:

```bash
npx skills add unopim/agent-skills -a claude-code
npx skills add unopim/agent-skills -a cursor
```

## Repository Structure

```
agent-skills/
├── skills/
│   ├── unopim-package/
│   │   └── SKILL.md
│   ├── unopim-plugin-dev/
│   │   └── SKILL.md
│   ├── unopim-backend-dev/
│   │   └── SKILL.md
│   ├── unopim-datagrid/
│   │   └── SKILL.md
│   ├── unopim-credential-management/
│   │   └── SKILL.md
│   ├── unopim-http-client/
│   │   └── SKILL.md
│   ├── unopim-connector-quickstart/
│   │   └── SKILL.md
│   ├── unopim-connector-export-mapping/
│   │   └── SKILL.md
│   ├── unopim-export-workflow/
│   │   └── SKILL.md
│   ├── unopim-data-transfer/
│   │   └── SKILL.md
│   ├── unopim-code-review/
│   │   └── SKILL.md
│   ├── unopim-git/
│   │   └── SKILL.md
│   └── unopim-dev-cycle/
│       └── SKILL.md
├── AGENTS.md
├── LICENSE
└── README.md
```

Each skill folder contains a `SKILL.md` file with agent-readable instructions and a YAML frontmatter block that defines when the skill activates.

## License

[MIT](LICENSE)
