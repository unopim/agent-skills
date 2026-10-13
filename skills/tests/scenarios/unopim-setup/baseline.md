# unopim-setup — baseline (without the skill)

Desk-run against a fresh UnoPim master clone, recorded while the skill was written.
Not a captured live session.

## Task

"Add a `sort_order` column to `measurement_families` and expose it in the listing."

## What happened without the skill

- The clone had `laravel/boost` in `composer.lock` but no `.mcp.json`: UnoPim's
  `.gitignore` excludes `.mcp.json`, `boost.json`, `CLAUDE.md` and `AGENTS.md`, so the
  Boost MCP server never starts on a fresh clone. Nothing told the agent.
- unopim-standards said "Never make a tool a precondition", so the agent fell back
  to recall: it wrote the migration against a remembered column list instead of
  `database-schema`, and took schema-builder API from memory instead of
  `search-docs` for the installed Laravel 13.
- On a container workspace a `.mcp.json` written by `boost:install` launches host
  `php`, which boots the app against the host `.env`; nothing flagged that the
  database tools would then reach the wrong (or no) database.
- No check reported that superpowers, the code-review plugin or a Playwright MCP
  server were absent, so the UI half of the change was never looked at in a browser.

## Failure the skill must prevent

Writing UnoPim code with the Boost MCP server absent, and doing so silently.
