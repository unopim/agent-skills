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

### `unopim-dev-cycle` (deprecated)

Use when running UnoPim tests, linting, static analysis, or asset builds, or when asked whether a change is ready to be called done. Trigger phrases include "run tests", "pest", "pint", "larastan", "phpstan", "playwright", "build assets", "is this done".

Superseded by `unopim-exec` + `unopim-verify`; kept as a stub for one release, then removed.

## Install

Install all skills from this repo into your AI agent:

```bash
npx skills unopim/agent-skills
```

> **Note:** `npx skills unopim/unopim` installs nothing — the UnoPim application repository has no `skills/` directory. The skills ship from `unopim/agent-skills` only.

Install a specific skill only:

```bash
npx skills unopim/agent-skills --skill "unopim-plugin-development"
```

Install for a specific agent:

```bash
npx skills unopim/agent-skills -a claude-code
npx skills unopim/agent-skills -a cursor
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
| `session-card.sh` | session start | Nothing — prints the resolved environment: container or host, port, database and Elasticsearch overrides |

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
bin/install-hooks.sh /path/to/unopim                   # Claude Code hooks + settings.json
bin/install-hooks.sh /path/to/unopim --with-git-hook   # and a git pre-commit hook
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
│   ├── install-skills.sh        # skills into any agent, dependencies resolved
│   ├── install-hooks.sh         # hooks + pre-commit into an UnoPim checkout
│   └── lint-skills.sh           # the authoring standard, enforced
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
│   ├── unopim-dev-cycle/        # deprecation stub
│   └── tests/
├── AGENTS.md                    # thin router into the skills
├── LICENSE
└── README.md
```

Each skill folder contains a `SKILL.md` with YAML frontmatter (`name`, `description`, optional `requires:` dependencies) and a body of at most 150 lines; depth lives in reference files inside the same folder. `bin/lint-skills.sh` enforces the authoring standard and `.github/workflows/skills-tests.yml` runs it, plus `skills/tests/run-tests.sh`, on every pull request. Before contributing, read [skills/CONTRIBUTING.md](skills/CONTRIBUTING.md).

## License

[MIT](LICENSE)
