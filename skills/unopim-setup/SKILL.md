---
name: unopim-setup
description: Use when preparing an UnoPim checkout or a developer machine for AI-assisted work, when the session card lists "AI tooling gaps", when the Laravel Boost MCP server is absent or disconnected, or when deciding which Claude Code plugins and MCP servers an UnoPim developer should have. Trigger phrases include "setup", "laravel boost", "boost mcp", "mcp server", "superpowers", "plugins", "playwright mcp", "doctor", "AI tooling", "onboarding".
requires: unopim-exec
---

# UnoPim AI tooling setup

The other unopim-* skills assume a specific toolchain. This skill says what it is,
why each piece is there, and how to get it in place. `bin/doctor.sh` checks it all;
the session card runs the same check at every session start.

## Required vs recommended

| Tool | Status | Why UnoPim work needs it |
|---|---|---|
| `laravel/boost` (composer, dev) | **Required** | Version-matched Laravel 13 docs and live app introspection — the "verify, do not recall" tier in unopim-standards |
| Boost MCP server (`.mcp.json` → `artisan boost:mcp`) | **Required** | Exposes the Boost tools to the agent; without the entry the package does nothing for it |
| `superpowers` plugin | Recommended | Brainstorm → plan → TDD → systematic debugging → verify-before-done process skills; they sit above the unopim-* domain skills |
| `laravel-boost` plugin | Recommended | The Claude Code packaging of Boost's guidance next to the project MCP server |
| `code-review` plugin | Recommended | Diff/PR review engine; pair it with unopim-code-review for the house rules |
| Playwright MCP server | Recommended | Drives the admin UI to see a Blade/Vue change render — the manual half of the playwright gate in unopim-verify |

A required gap blocks: do not write UnoPim code until it is fixed. A recommended gap
is reported once; carry on.

## Procedure

1. Run the check from the UnoPim root (installed copy, or the skills clone):
   `.claude/hooks/doctor.sh` or `<agent-skills>/bin/doctor.sh <unopim-root>`.
2. Required gap → `doctor.sh --fix`. It installs `laravel/boost` (`composer install`
   when `composer.json` already lists it, `composer require --dev` otherwise) and runs
   `artisan boost:install --mcp --guidelines --skills --no-interaction` through the php
   wrapper unopim-exec detects, so a container workspace installs inside the container.
3. Restart the agent session — MCP servers load at start — and confirm
   `laravel-boost` shows as connected (`/mcp` in Claude Code).
4. Recommended gaps → ask the user before installing anything into their agent;
   the fix line printed by doctor is the exact command:
   - `/plugin install superpowers@claude-plugins-official`
   - `/plugin install laravel-boost@claude-plugins-official`
   - `/plugin install code-review@claude-plugins-official`
   - `claude mcp add playwright -- npx -y @playwright/mcp@latest`
5. `bin/install-hooks.sh <unopim-root>` runs step 2 for you after installing the
   hooks; pass `--skip-tooling` only in CI fixtures that have no composer.

## Why every clone needs step 2

UnoPim's `.gitignore` excludes `.mcp.json`, `boost.json`, `CLAUDE.md` and `AGENTS.md`
— each developer generates their own with `boost:install`, which also detects which
agents (Claude Code, Codex, Copilot, Cursor …) to write MCP config for. A fresh clone
therefore has the composer package and no MCP server. Never commit those files.

## Container workspaces

`boost:install` writes `"command": "php"`. When unopim-exec reports a container
wrapper, the MCP server would start on the host php with the wrong `.env`; doctor
warns, and the fix is to set the `laravel-boost` entry's command and args in
`.mcp.json` to the wrapper (for example `docker compose exec -T <service> php artisan
boost:mcp`, the `-T` because MCP speaks over stdio with no TTY).

## Using Boost once it is connected

| Need | Boost tool | Instead of |
|---|---|---|
| Laravel/Pest/Passport/Octane API for the installed major | `search-docs` (broad topic queries, no package names in the query) | Recalling Laravel 10-era syntax |
| Table and column shape before a migration or model | `database-schema` | Reading old migrations |
| Read-only data check | `database-query` | `tinker` with raw SQL |
| Installed package versions, PHP and DB driver | `application-info` | Guessing from `composer.json` constraints |
| The real admin URL (scheme, host, port) | `get-absolute-url` | Hardcoding `localhost:8000` |
| Latest exception / log lines / browser console | `last-error`, `read-log-entries`, `browser-logs` | Tailing `storage/logs` by hand |

Boost's own skills (`pest-testing`, `laravel-best-practices`, `octane-development`,
`passport-development`, …) install beside the unopim-* skills. They are generic
Laravel; where one disagrees with an unopim-* skill — repository over Eloquent in
controllers, the comment bar, `DB_PREFIX`-safe raw SQL, PostgreSQL portability — the
unopim-* skill wins.

## Other agents

Boost's MCP config and guidelines cover every agent `boost:install` detects. The
superpowers, laravel-boost and code-review plugins are Claude Code plugins; under
Codex, Cursor or Copilot doctor's plugin lines are informational, and the git
pre-commit hook from `install-hooks.sh --with-git-hook` carries the enforcement.
