# unopim/agent-skills

Agent skills for [UnoPim](https://unopim.com) — a Laravel-based open-source Product Information Management (PIM) system.

These skills provide domain-specific, reusable context for AI agents (Claude Code, Cursor, Windsurf, etc.) working inside an UnoPim codebase. They encode UnoPim's modular Concord architecture, connector conventions, and coding standards so agents generate correct code on the first try.

## Available Skills

### `unopim-plugin-development`

Plugin, package, and connector development for UnoPim — the comprehensive module-building skill.

**Activates when:** creating modules/packages, service providers, models, repositories, controllers, routes, ACL, menus, migrations, credentials, cURL HTTP clients, attribute mapping, or scaffolding a third-party connector (WooCommerce, Shopify, Shopware, any REST API).

**Reference sections:** `@quickstart` (day-1 connector checklist) · `@core` (package structure, service providers, config) · `@backend` (PHP classes, models, repositories, events) · `@credentials` (credential storage, connection testing, history) · `@http` (cURL ApiClient, BasicAuth/OAuth) · `@mapping` (attribute mapping + history).

---

### `unopim-datagrid`

Implement UnoPim DataGrid classes for admin listing pages.

**Activates when:** building admin listings with search, filter, sort, row actions (edit/delete), and mass actions — `prepareQueryBuilder` with `DB::table`, `addColumn` closures, `addAction`, `addMassAction`, `bouncer()` permission checks, and Blade integration.

---

### `unopim-data-transfer`

Import/export pipeline and connector export/import workflow for UnoPim.

**Activates when:** configuring imports/exports, debugging job pipelines, creating data transfer profiles, or building connector export jobs — `exporters.php`, `quick_exporters.php`, `importers.php`, `Exporter` classes, `Validator` classes, and queue jobs. Includes the `@export-workflow` reference section for connector data transfer.

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
npx skills add unopim/agent-skills --skill "unopim-plugin-development"
npx skills add unopim/agent-skills --skill "unopim-datagrid"
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
│   ├── unopim-plugin-development/
│   │   └── SKILL.md
│   ├── unopim-datagrid/
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

Each skill folder contains a `SKILL.md` file with agent-readable instructions and a YAML frontmatter block that defines when the skill activates. The comprehensive `unopim-plugin-development` skill is internally organized into `@`-tagged reference sections.

## License

[MIT](LICENSE)
