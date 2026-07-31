---
name: unopim-exec
description: Use when running any UnoPim shell command — resolves whether the workspace serves from a container or the host, the serving port, and database or Elasticsearch host overrides before any artisan, composer, pest or npm invocation. Trigger phrases include "run command", "artisan", "composer", "which port", "docker or host", "environment".
---

# UnoPim Exec

Resolve the workspace environment BEFORE prescribing or running any shell command. A command that is correct on one workspace (`vendor/bin/pest` against a host MySQL) fails on another (`.env` pointing at a container hostname, a different serving port, Elasticsearch disabled).

## Usage

Run once per session, from anywhere, against the project root:

```bash
skills/unopim-exec/detect-env.sh "$PROJECT_ROOT"
```

It prints exactly five `KEY=VALUE` lines and nothing else, so it is safe to parse:

| Key | Meaning |
|---|---|
| `WRAPPER` | Command prefix — `php`, or a `docker compose exec -T <service> php` form when the host has no PHP |
| `APP_URL` | The URL this checkout is actually served on; use it for Playwright's `BASE_URL` too |
| `DB_OVERRIDE` | `DB_HOST=127.0.0.1` when the configured `DB_HOST` does not resolve from this shell |
| `ES_OVERRIDE` | `ELASTICSEARCH_ENABLED=false` when the Elasticsearch host does not resolve and the checkout has not already disabled it |
| `PEST_ENV` | The two overrides joined, ready to prefix a command: `env $PEST_ENV vendor/bin/pest` |

An empty value means "no override needed" — not "unknown". The script exits 0
even when the checkout has no `.env`, so a missing file is never a hard stop.

If `detect-env.sh` is unavailable, do the same reading by hand before the first
command: `.env` for `APP_URL`, `DB_HOST`, `DB_PORT`, `DB_PREFIX`,
`ELASTICSEARCH_ENABLED` and `ELASTICSEARCH_HOST`; `docker-compose.yml` (and
`docker-compose.apache.yml` if present) for which services are containerized.
State which configuration you detected, and why, before running anything.

## Common Mistakes

- **Assuming `127.0.0.1:8000`.** Several checkouts of one branch are often served side by side on one machine. Read `APP_URL`; never guess a port.
- **Overriding the database but not Elasticsearch.** Model observers fire on category and product writes, so an unreachable Elasticsearch host fails tests that never mention search.
- **Treating an unresolvable hostname as an application bug.** `getaddrinfo for … failed` and `NoNodeAvailableException` are environment faults; re-run with `PEST_ENV`, do not "fix" the code.
- **Baking a detected value into a skill, a script, or any committed file.** Detection is portable; hosts, ports and credentials are not, and must never be committed.
