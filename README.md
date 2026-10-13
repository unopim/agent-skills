# unopim/agent-skills

Agent skills for [UnoPim](https://unopim.com) — a Laravel-based open-source Product Information Management (PIM) system.

These skills provide domain-specific, reusable context for AI agents (Claude Code, Cursor, Windsurf, etc.) working inside an UnoPim codebase. They encode UnoPim's modular Concord architecture, connector conventions, and coding standards so agents generate correct code on the first try.

Each entry below is the skill's frontmatter `description`, verbatim — the README and the frontmatter cannot drift.

## Available Skills

### `unopim-standards`

Use when writing or changing any UnoPim code — the canonical rules for Laravel 13 and PHP 8.4 idiom, security, performance, scale, extensibility, localization and comments. Trigger phrases include "best practice", "standards", "laravel 13", "security", "performance", "scalable", "localization", "comments".

### `unopim-exec`

Use when running any UnoPim shell command — resolves whether the workspace serves from a container or the host, the serving port, and database or Elasticsearch host overrides before any artisan, composer, pest or npm invocation. Trigger phrases include "run command", "artisan", "composer", "which port", "docker or host", "environment".

### `unopim-verify`

Use when a change is about to be called done, or when asked to run the UnoPim verification gates — formatting, tests, static analysis, refactoring checks, end-to-end tests and translation completeness. Trigger phrases include "verify", "is this done", "run the gates", "pint", "pest", "larastan", "rector", "playwright", "translations check".

### `unopim-plugin-development`

Use when creating a new UnoPim package, module or third-party connector — service providers, models, repositories, controllers, routes, ACL, menus, migrations, credential storage, cURL clients or attribute mapping. Trigger phrases include "new module", "new package", "connector", "scaffold module", "service provider", "credentials", "attribute mapping", "WooCommerce", "Shopify", "Shopware".

### `unopim-datagrid`

Use when building or changing an UnoPim admin listing page — a DataGrid class with columns, search, filters, sorting, row actions or mass actions, or the Blade view that renders it. Trigger phrases include "datagrid", "admin listing", "add a column", "mass action", "prepareQueryBuilder", "listing page".

### `unopim-data-transfer`

Use when configuring an UnoPim import or export, building an Exporter, Importer or Validator class, debugging a queued data-transfer job, or wiring exporters.php, quick_exporters.php or importers.php. Trigger phrases include "import", "export", "data transfer", "exporter", "importer", "CSV", "queued job", "batch".

### `unopim-code-review`

Use when reviewing UnoPim code changes or a pull request for standards compliance, or when asked about conventions, best practices, violations or code quality in an UnoPim codebase. Trigger phrases include "review", "code review", "PR review", "standards", "conventions", "violations", "code quality".

### `unopim-git`

Use when creating an UnoPim branch, writing a commit message, or opening a pull request against the UnoPim repository. Trigger phrases include "branch", "commit", "commit message", "PR", "pull request", "changelog".

### `unopim-setup`

Use when preparing an UnoPim checkout or a developer machine for AI-assisted work, when the session card lists "AI tooling gaps", when the Laravel Boost MCP server is absent or disconnected, or when deciding which Claude Code plugins and MCP servers an UnoPim developer should have. Trigger phrases include "setup", "laravel boost", "boost mcp", "mcp server", "superpowers", "plugins", "playwright mcp", "doctor", "AI tooling", "onboarding".

### `unopim-ai-agent`

Use when adding, changing or debugging an UnoPim AI agent chat tool — a PimTool class, its ToolRegistry entry or the ai-agent.tools config — or when running, scheduling or extending the ai-agent:* console commands, or provisioning Magic AI platforms with the unopim:magic-ai:platform:* commands. Trigger phrases include "AI agent", "chat tool", "PimTool", "ToolRegistry", "agentic PIM", "agent tool", "Magic AI platform", "quality-monitor", "embeddings:index", "magic-ai:platform".

### `unopim-api`

Use when adding or changing an UnoPim REST API v1 endpoint under /api/v1/rest — AdminApi routes, api-acl.php permissions, an ApiDataSource listing with filters and pagination, ApiFormRequest validation, OAuth tokens, integrations and API keys, the unopim:passport:keys or unopim:passport:client commands, or Pest tests on ApiTestCase — including a plugin package that exposes its own REST endpoints. Trigger phrases include "REST API", "api endpoint", "v1/rest", "api-acl", "ApiDataSource", "passport", "oauth token", "API key", "integration", "This action is unauthorized".

### `unopim-search`

Use when touching UnoPim product or category search — Elasticsearch indexing, the unopim:product:index, unopim:category:index or unopim:elastic:clear commands, config/elasticsearch.php, the ElasticSearch observers, a product filter or sort that must work with Elasticsearch on and off, or a product that saves but does not show up in the grid. Trigger phrases include "elasticsearch", "reindex", "index products", "unopim:product:index", "elastic:clear", "search not updating", "add a filter", "filterable field", "ES enabled", "ES disabled".

### `unopim-catalog-model`

Use when reading or writing UnoPim product values, adding or changing an attribute type, product type, attribute family, group or association type, working with configurable products, variant groups or variant inheritance, listening to catalog.product.* or catalog.attribute.* events, or reasoning about how channel, locale and currency scoping or completeness react to a catalog change. Trigger phrases include "attribute type", "product type", "product values", "values json", "channel_locale_specific", "value_per_locale", "configurable product", "variant", "variants:resync", "strip-redundant", "attribute family", "association type", "catalog.product.update.after", "completeness".

### `unopim-install-upgrade`

Use when installing UnoPim, running or changing unopim:install or unopim:upgrade, writing a migration that must land on existing installs (schema change, data backfill, index on a large table), editing the Installer package's upgrade config, seeders or BackupManager, registering a new package so its migrations and seeders run, or planning post-upgrade steps on host or Docker. Trigger phrases include "install", "unopim:install", "upgrade", "unopim:upgrade", "migration", "data migration", "backfill", "seeder", "backup", "maintenance window", "irreversible", "release upgrade", "migrate --force".

## Install

`skills` needs a subcommand — `npx skills unopim/agent-skills` on its own exits with
`Unknown command: unopim/agent-skills`. Use `add`:

```bash
npx skills add unopim/agent-skills --all
```

`--all` is shorthand for `--skill '*' --agent '*' -y`: every skill, every detected agent,
no prompts. Without it the CLI opens a picker with **every box unticked** — that default is
hard-coded in the `skills` CLI and a repository cannot change it; press `a` to toggle all,
or pass `-y` to take every skill and still choose agents. A multi-agent install keeps one copy in `.agents/skills/` and symlinks it into
each agent's own directory; a single-agent install writes straight into that agent's
directory (`.claude/skills/`, `.cursor/skills/`, …). Add `-g` to install into the
user-level directory instead, and `--copy` where a symlink out of the project tree does
not resolve (containers, images).

> **Note:** `npx skills add unopim/unopim` installs nothing — the UnoPim application repository has no `skills/` directory. The skills ship from `unopim/agent-skills` only.

List what the repository ships without installing anything:

```bash
npx skills add unopim/agent-skills --list
```

Install a specific skill only:

```bash
npx skills add unopim/agent-skills --skill "unopim-plugin-development"
```

Install for a specific agent:

```bash
npx skills add unopim/agent-skills -a claude-code -s '*' -y
npx skills add unopim/agent-skills -a cursor -s '*' -y
```

Note that `npx skills add` does not resolve the `requires:` chain — asking for one skill
installs exactly that skill. Name the dependencies yourself (`-s "unopim-plugin-development,unopim-standards,unopim-verify"`),
or use `bin/install-skills.sh` below, which resolves them.

Inspect and refresh an existing install:

```bash
npx skills list                  # what is installed, and where
npx skills update -y             # update every installed skill to its latest version
npx skills remove unopim-git     # remove one
```

### From a clone

`bin/install-skills.sh` installs from a checkout of this repository and resolves the
`requires:` chain, so asking for one skill brings everything it depends on — installing
`unopim-plugin-development` also installs `unopim-standards`, `unopim-datagrid`,
`unopim-data-transfer`, `unopim-exec` and `unopim-verify`.

```bash
bin/install-skills.sh --list                              # available skill names
bin/install-skills.sh -a claude unopim-plugin-development  # one skill and its dependencies
bin/install-skills.sh -a claude                            # every skill
bin/install-skills.sh -a claude --copy                     # copy instead of symlink
```

Run it from the project you want the skills in. Agents map to their own directory —
`claude` to `.claude`, `codex` to `.codex`, `copilot` to `.github`, `cursor` to `.cursor`,
`gemini` to `.gemini`, `junie` to `.junie`, `opencode` to `.opencode` — and the target is
resolved from `--agent`, then `$UNOPIM_SKILLS_AGENT`, then whichever agent directory
already exists, then a prompt. Skills are symlinked so a `git pull` here updates every
project at once; use `--copy` inside containers and images where a symlink out of the
project tree does not resolve, and `--global` to install into `~/<agent-dir>/skills`.

## Required AI tooling

The skills assume the agent can query the running app. **Laravel Boost and its MCP
server are required**; four more tools are recommended. `bin/doctor.sh` checks all of
them and the session card repeats the check at every session start.

| Tool | Status | Install |
|---|---|---|
| `laravel/boost` + its MCP server | Required | `bin/doctor.sh /path/to/unopim --fix` (runs `composer` and `php artisan boost:install --mcp --guidelines --skills`) |
| superpowers plugin | Recommended | `/plugin install superpowers@claude-plugins-official` |
| laravel-boost plugin | Recommended | `/plugin install laravel-boost@claude-plugins-official` |
| code-review plugin | Recommended | `/plugin install code-review@claude-plugins-official` |
| Playwright MCP server | Recommended | `claude mcp add playwright -- npx -y @playwright/mcp@latest` |

```bash
bin/doctor.sh /path/to/unopim          # report; exits 1 when Boost is missing
bin/doctor.sh /path/to/unopim --fix    # install Boost and wire its MCP server
```

UnoPim git-ignores `.mcp.json`, `boost.json`, `CLAUDE.md` and `AGENTS.md`, so every fresh
clone needs `--fix` (or `php artisan boost:install`) once. `bin/install-hooks.sh` runs
`doctor.sh --fix` for you. Restart the agent afterwards so the MCP server loads. See
`skills/unopim-setup` for why each tool is there and the container caveat.

## Enforcement

The skills carry the judgment. The hooks carry the mechanics — the rules a regex can
decide are exit codes rather than paragraphs, because an agent can rationalise past a
paragraph and cannot rationalise past a non-zero exit.

| Hook | Fires on | Blocks |
|---|---|---|
| `pint-gate.sh` | writing a `*.php` file | Nothing — runs Pint in fix mode and reports what it changed |
| `grep-gate.sh` | writing `*.php`, `*.blade.php`, `*.vue`, `*.js`, `*.css` | Raw `<input>`/`<select>`/`<textarea>`/`<label>` where an `x-admin::form` component belongs, a raw `<table>` or hand-rolled pagination where a DataGrid belongs, hand-rolled modal markup and `fixed inset-0` overlays, a new `.css`/`.scss`/`.less` file and colour literals inside a tracked one, `style="`, `<style>`, hex, short-hex and `rgb()` literals in Blade/Vue/JS *and* in markup built in PHP, arbitrary values (`bg-[#…]`, `bg-[rgb(…)]`), default intent scales, legacy `unopim-primary-*` classes, user-facing text without `trans()`, inline validation in all three spellings, `$guarded = []`, legacy `protected $fillable`/`$casts`/`$table` on a model, `whereRaw`/`selectRaw`/`DB::raw` with an interpolated value, uploads with no `mimes:` allowlist and `mimes:` lists containing `svg`/`html`, `Model::all()`, `$someRepository->all()`, `select('*')`, and any comment |
| `i18n-gate.sh` | writing under `Resources/lang/**` | Any locale below 100% — the key must land in all 33 |
| `verify-gate.sh` | a completion claim | Calling work done when PHP, Blade, JS or lang files changed since the verification gates last passed |
| `sweep-gate.sh` | session start (`--baseline`) and a completion claim | Every rule in the table applied to all lines the session added, whatever wrote them — a file written by `sed -i`, a Bash redirect or a script never reaches the edit-time hooks, and a block message that was read but not acted on leaves the violation on disk. Baselines at session start so only what this session adds is reported |
| `session-card.sh` | session start | Nothing — prints the resolved environment: container or host, port, database and Elasticsearch overrides, plus any AI tooling gap from `doctor.sh` |

Every block names the rule, the fix, and the skill section that explains it.

What the hooks deliberately do **not** decide, so that reading this table is not
mistaken for coverage: N+1 and queries in loops, an unbounded `->get()` at the end of a
fluent chain, bulk work left inline in a controller, duplication, ACL route coverage, and
`orderByRaw("$column $direction")`. Each is either a cross-file or a multi-line property
that a per-file line matcher cannot see, or is character-identical on one line to code
that is correct. They are blocking dimensions in `skills/unopim-code-review` instead, and
each standards reference names itself as unhooked so nobody assumes an exit code covered it.

### The ratchet rule

Hooks judge **only the lines an edit adds or changes**, never the whole file. Legacy
violations do not block edits to the files that contain them — dozens of view files
already carry a `style="` or a raw `<input>`, so whole-file blocking would fail nearly
every legacy edit and the hooks would be switched off within a day. You can still edit any file in the
codebase; you just cannot add more of the same debt. The direction of travel is enforced,
not the current state.

### Installing enforcement

```bash
bin/install-hooks.sh /path/to/unopim                   # Claude Code hooks + settings.json + Boost
bin/install-hooks.sh /path/to/unopim --with-git-hook   # and a git pre-commit hook
bin/install-hooks.sh /path/to/unopim --skip-tooling    # hooks only, no composer/boost:install
```

Three paths, and most teams want all three:

1. **`bin/install-skills.sh`** — the skills themselves, for any agent.
2. **`bin/install-hooks.sh`** — the same rules as Claude Code hooks, enforced per edit.
3. **`--with-git-hook`** — the same rules again as a git `pre-commit` hook, for Codex,
   Cursor, Copilot and humans, who never run Claude Code hooks. With a pre-commit hook in
   place nobody has to remember to invoke anything.

All three run the same rule table, so an agent and a developer get the same answer.

## Repository Structure

```
agent-skills/
├── bin/
│   ├── doctor.sh                      # required + recommended AI tooling, --fix installs Boost
│   ├── install-skills.sh              # skills into any agent, dependencies resolved
│   ├── install-hooks.sh               # hooks + pre-commit into an UnoPim checkout
│   ├── lint-skills.sh                 # the authoring standard, enforced
│   └── skills-conformance-scan.sh     # the rule table over a diff or a tree
├── hooks/                       # the mechanical rules, shared by every install path
├── skills/
│   ├── CONTRIBUTING.md          # the authoring standard, written down
│   ├── unopim-standards/
│   ├── unopim-exec/
│   ├── unopim-verify/
│   ├── unopim-plugin-development/
│   ├── unopim-datagrid/
│   ├── unopim-data-transfer/
│   ├── unopim-code-review/
│   ├── unopim-git/
│   ├── unopim-setup/
│   ├── unopim-ai-agent/
│   ├── unopim-api/
│   ├── unopim-search/
│   ├── unopim-catalog-model/
│   ├── unopim-install-upgrade/
│   └── tests/
├── AGENTS.md                    # thin router into the skills
├── LICENSE
└── README.md
```

Each skill folder contains a `SKILL.md` with YAML frontmatter (`name`, `description`, optional `requires:` dependencies) and a body of at most 150 lines; depth lives in reference files inside the same folder. `bin/lint-skills.sh` enforces the authoring standard and `.github/workflows/skills-tests.yml` runs it, plus `skills/tests/run-tests.sh`, on every pull request. Before contributing, read [skills/CONTRIBUTING.md](skills/CONTRIBUTING.md).

## License

[MIT](LICENSE)
