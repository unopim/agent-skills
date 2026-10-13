# unopim-setup — with the skill

Same task, same fresh clone. Desk-run.

1. Session card printed `AI tooling gaps (unopim-setup skill)` with
   `MISSING Laravel Boost MCP server is not configured (.mcp.json)` and
   "Laravel Boost is required … before writing code".
2. Agent loaded unopim-setup, stopped, and asked to run `doctor.sh --fix`.
3. `--fix` ran `php artisan boost:install --mcp --guidelines --skills --no-interaction`
   through the wrapper unopim-exec detected; on the container workspace doctor then
   warned that `.mcp.json` launches host php and printed the wrapper command to use.
4. After a session restart `/mcp` listed `laravel-boost` connected. The agent read the
   table with `database-schema` and checked the migration API with `search-docs`.
5. Recommended gaps (superpowers, code-review, Playwright MCP) were listed with their
   install commands and left for the user to approve.
