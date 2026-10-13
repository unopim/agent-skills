---
name: unopim-code-review
description: Use when reviewing UnoPim code changes or a pull request for standards compliance, or when asked about conventions, best practices, violations or code quality in an UnoPim codebase. Trigger phrases include "review", "code review", "PR review", "standards", "conventions", "violations", "code quality".
requires: unopim-standards
---

# UnoPim Code Review

**REQUIRED BACKGROUND:** Use unopim-standards — its reference files (`laravel13.md`, `security.md`, `performance.md`, `scale.md`, `extensibility.md`, `localization.md`, `comments.md`) are the rulebook. This skill is the checklist that applies them to a diff.

## Scope — ratchet, not archaeology

Review the lines the change ADDED or MODIFIED. Legacy violations on untouched lines are at most a remark, never a blocker — whole-file blocking would stall every legacy edit. A newly added violation is always in scope, even when it imitates adjacent legacy code.

## Blocking dimensions (any hit = request changes)

### 1. Comment noise — the #1 developer complaint

- ANY added comment inside a method body, object/array literal, route group, or Blade markup is a blocker — including one-line "why" comments, section dividers (`// Views`, `// ----`), and `{{-- --}}` narration.
- The house baseline is zero: `packages/Webkul/Product/src/Repositories/ProductRepository.php` (20 methods) and `packages/Webkul/Product/src/Type/AbstractType.php` (918 lines) ship 0 inline comments.
- A genuinely non-obvious rationale belongs in the class/method PHPDoc or the commit message. Method PHPDoc: one-line imperative summary; `@param`/`@return` only where no native type hint exists.
- Mechanical sweep: every `git diff -U0` added line matching `^\+\s*(//|/\*|\{\{--)` is a finding.

### 2. Hardcoded colors

- Blockers: hex/rgb literals, `style="..."`, `<style>` blocks, arbitrary values (`bg-[#...]`), default intent scales (`violet-*`, `purple-*`, `red-*`, `green-*`, `blue-*`), and legacy `cherry-*` / `sky-*` / `unopim-primary-*` in new code.
- Required: semantic tokens only — `primary` (+50–900), `primary-hover`, `success`, `warning`, `danger`, `info` — CSS vars in `packages/Webkul/Admin/src/Resources/assets/css/app.css` (`:root` + `.dark`), mapped in `packages/Webkul/Admin/tailwind.config.js`. A literal cannot follow the `.dark` variable swap, so dark mode breaks visibly.
- Neutrals need a dark pairing, e.g. `text-primary-700 dark:text-primary-400`.

### 3. Raw HTML where an `x-admin::` component exists

- Raw `<input>`, `<select>`, `<textarea>`, `<label>` in admin views = blocker: `x-admin::form.control-group` + `.label`/`.control`/`.error` exist.
- Hand-built listing tables = blocker: use `x-admin::datagrid`. Custom fixed/backdrop divs = blocker: use `x-admin::modal` (+ `modal.confirm`) or `x-admin::drawer`.
- ~160 component blades live under `packages/Webkul/Admin/src/Resources/views/components` — check there before accepting hand-rolled markup (switcher, flat-picker, tinymce, tabs, accordion, dropdown, tree, badge, shimmer).
- Selects use `:options="json_encode(...)"` with `track-by`/`label-by` — never `@foreach` over `<option>`.

### 4. Duplication

- A block occurring 2+ times (logic or markup) must be extracted — method, component, or partial. Name the existing location to reuse.

### 5. Scale — assume millions of rows

- Unbounded `->all()`/`->get()`/`->pluck()` on catalog tables = blocker. Batch scans use `chunkById()`/`lazyById()` (`packages/Webkul/Completeness/src/Jobs/BulkProductCompletenessJob.php`).
- **No hook covers most of this dimension — read the diff for it, do not assume an exit code did.** Only `Model::all()`, `$someRepository->all()` and `select('*')` are hook-blocked. A fluent chain ending in a bare `->get()`, a query inside a `foreach`, a missing eager load, a query in a Blade template, and a controller looping the catalogue instead of dispatching a `ShouldQueue` job are ALL invisible to the gate and are blockers here.
- Bulk lookups: `array_chunk($keys, 1000)` + `whereIn` (`packages/Webkul/DataTransfer/src/Helpers/Importers/Product/SKUStorage.php`) — never per-row queries in a loop.
- Export sources stream via id-cursor keyset pagination (`packages/Webkul/DataTransfer/src/Helpers/Sources/Export/ProductCursor.php`); the AbstractExporter `source->all()` default is acceptable only for small entities.
- Multi-batch work is a `ShouldQueue` job, never inline request work. Data migrations stream too (cursor/chunkById).
- New `where`/`orderBy`/filterable DataGrid columns need indexes. No query in loops or Blade. Eager-load every traversed relation.

### 6. Portability — MySQL + PostgreSQL, table prefix, optional Elasticsearch

- Raw SQL fragments (`DB::raw`, `selectRaw`, `whereRaw`, `orderByRaw`) naming tables must prepend `DB::getTablePrefix()` (`packages/Webkul/Measurement/src/DataGrids/UnitDataGrid.php`). Hardcoded `wk_` = blocker — no such prefix exists; `DB_PREFIX` defaults to empty.
- MySQL-only SQL (GROUP_CONCAT, backticks, DATE_FORMAT, CAST AS SIGNED) = blocker. Cross-DB via `DB::rawQueryGrammar()` (`packages/Webkul/Core/src/Helpers/Database/Grammars/MySQLGrammar.php`, `packages/Webkul/Core/src/Helpers/Database/Grammars/PostgresGrammar.php`) or a `DB::getDriverName() === 'pgsql'` branch.
- Three drivers ship, not two: `mysql`, `mariadb`, `pgsql`. A branch that decides on `'mysql'` without naming `mariadb` = blocker — Laravel reports MariaDB under its own driver name, so `match ($driver) { 'mysql' => …, 'pgsql' => … }` throws and `=== 'mysql' ? … : …` takes the PostgreSQL path. Group the family (`'mysql', 'mariadb' => …`) as `packages/Webkul/Core/src/Helpers/Database/GrammarQueryManager.php` does. MariaDB has no CI matrix; `packages/Webkul/Core/tests/Unit/DatabaseDriverCoverageTest.php` is the only automated catch.
- Any Elasticsearch call not gated on `config('elasticsearch.enabled')` with a DB fallback = blocker (`packages/Webkul/Product/src/Factories/ProductQueryBuilderFactory.php`).

### 7. Security

- ACL is fail-open by route name (`packages/Webkul/User/src/Http/Middleware/Bouncer.php`): a write route — store, update, destroy, `mass_*` (snake_case keys), test-connection — absent from every acl.php is reachable by ALL logged-in admins = blocker. Bind write routes via `'also_authorizes'` (`packages/Webkul/Core/src/Tree.php`).
- FormRequest on every endpoint; inline `request()->validate()` = blocker. `authorize(): true` only when the route name is ACL-gated; otherwise a bouncer check in `authorize()` (`packages/Webkul/Admin/src/Http/Requests/TinyMCEUploadRequest.php`). Shared/routeless endpoints gate in-controller (`packages/Webkul/Admin/src/Http/Controllers/MagicAI/MagicAIController.php`).
- Uploads: mimes allowlist + max size + `FileMimeExtensionMatch` (`packages/Webkul/Core/src/Rules/FileMimeExtensionMatch.php`); accepting svg/html = blocker (script carriers).
- Mass assignment: explicit `#[Fillable]` allowlist, no privilege columns in it; `$guarded = []` = blocker. Secrets at rest need `'encrypted'` cast + `#[Hidden]` + `$auditExclude` together (`packages/Webkul/AiAgent/src/Models/Credential.php`) — `$auditExclude` alone is not encryption.
- Outbound URLs validated against SSRF (`packages/Webkul/Webhook/src/Validators/SafeWebhookUrl.php`); CSV export escapes formula operators (`packages/Webkul/DataTransfer/src/Helpers/Formatters/EscapeFormulaOperators.php`). No request input interpolated into SQL or DataGrid closure HTML.
- **Two of the blockers above have no hook and are yours alone: ACL route coverage (a cross-file question — the route file and every `acl.php` must be read together, which a per-file gate cannot do) and `orderByRaw("$column $direction")` (identical on one line to the legitimate `whereRaw("$column IS NULL")` in the product filters).** Open `acl.php` and match it against the route file on every PR that adds a write route; do not accept "the hooks passed" as evidence for either.

### 8. Localization

- Any hardcoded user-facing string = blocker — including placeholders, tooltips, JS alerts, and "Loading…" status text. `trans()`/`@lang` with keys in `Resources/lang/en_US/` first, then all 33 locales, translated naturally (no English copies), `:placeholders` preserved.
- Keys in a bare `en` directory = blocker — they never load; fallback locale is `en_US`.

### 9. Octane safety

- A `singleton()` binding holding request or credential state = blocker; bind `scoped()` instead (`packages/Webkul/Core/src/Providers/CoreServiceProvider.php`, `packages/Webkul/Core/src/RequestMemo.php`). `singleton()` is for stateless infra only.

### 10. Verification evidence

- The PR must show the gates actually ran: `vendor/bin/pint --test`, `composer test` (Pest v5, MySQL and PgSQL), `composer phpstan`, `composer rector-dry`, Playwright for UI/admin changes, `php artisan unopim:translations:check`. "Should pass" with no output = not verified — request the run.
- New `ignoreErrors` or `withSkip` entries added to make a gate pass = blocker.

## High (fix before merge, not an instant block)

- New model without Concord proxy/contract, or direct `new Model()` where a repository exists; repository not extending `Webkul\Core\Eloquent\Repository`.
- Laravel 13 / PHP 8.4 idiom gaps: missing promoted constructor properties, return types, enums, `casts()` method, `#[Fillable]`/`#[Table]` attributes on models.
- Migrations in the wrong folder — core packages use `src/Database/Migrations/` (plural); only plugin-style packages use root-level `Database/Migration/` (singular).
- Provider not loading routes, config merges (menu under `'menu.admin'`, acl, importers/exporters), migrations, or translation/view namespaces.
- No tests for new behavior; missing `assertDatabaseHas`/`assertDatabaseMissing`; not Pest `it()`/`describe()` style.
- Event names not `{domain}.{entity}.{action}.{before|after}`; route names not dot-separated.

## Verdict format

```text
[Dimension] [Blocker|High|Medium]: one-sentence statement of the violation
Location: file:line (added/changed line)
Standard: unopim-standards/<reference file>   e.g. comments.md, security.md, scale.md
Pattern: a real exemplar path under packages/Webkul showing the correct form
Fix: the minimal change
```

Every verdict MUST cite both the standards reference file and a real exemplar path. Group related findings; give the reason a standard exists in one clause, not a paragraph.
