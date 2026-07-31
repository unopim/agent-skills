---
name: unopim-dev-cycle
description: Use when running UnoPim tests, linting, static analysis, or asset builds, or when asked whether a change is ready to be called done. Trigger phrases include "run tests", "pest", "pint", "larastan", "phpstan", "playwright", "build assets", "is this done".
requires: unopim-exec, unopim-verify
---

# UnoPim Development Cycle (deprecated)

This skill is superseded and will be removed in the next release.

**REQUIRED SUB-SKILL:** Use unopim-exec to resolve the correct commands for this workspace — the container-versus-host wrapper, the serving port, and any database or Elasticsearch overrides.

**REQUIRED SUB-SKILL:** Use unopim-verify for the completion gate: Pint, Pest, Larastan, Playwright, and the translation check, in that order.
