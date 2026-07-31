# Day-1 Connector Quickstart

Ordered checklist to ship a working UnoPim connector module. Each step names the
reference file that carries the full template. Reference implementation:
`packages/Webkul/AiAgent`.

## Before coding

1. Confirm the external API authentication type (Basic Auth, Bearer token, OAuth).
2. Note the API base URL pattern (`/api/v1/`, `/wp-json/wc/v3/`, …).
3. List the entities to sync (products, categories, attributes) and the direction
   (export only, import only, bidirectional).

## Phase 1 — Scaffold ([package-structure.md](package-structure.md))

- [ ] Create the directory skeleton under `packages/Webkul/{ModuleName}/`.
- [ ] Add the package `composer.json` with PSR-4 `Webkul\{ModuleName}\ => src/`.
- [ ] Add the same PSR-4 mapping to the root `composer.json` autoload block, then run
      `composer dump-autoload`.
- [ ] Write `{ModuleName}ServiceProvider`: routes via `Route::middleware('web')->group()`,
      views, translations, migrations from `Database/Migration/`, config merged with
      menu going into `'menu.admin'`.
- [ ] Write `ModuleServiceProvider extends CoreModuleServiceProvider` listing every
      model in `$models`.
- [ ] Register the provider in `bootstrap/providers.php`.

## Phase 2 — Database and model ([backend.md](backend.md), [credentials.md](credentials.md))

- [ ] Migration in `Database/Migration/` creating `{module}_credentials` with a bare
      table name (`DB_PREFIX` default is empty; Laravel applies whatever is configured).
- [ ] Secret columns are `text` (encrypted payloads outgrow `string`).
- [ ] Contract marker interface in `src/Contracts/`.
- [ ] Credential model: `#[Fillable]`, `#[Hidden]`, `#[Table]`, `casts()` with
      `'encrypted'` for the secret, `HistoryTrait`, the OwenIt `Auditable` contract,
      `PresentableHistoryInterface::getPresenters()`, `$historyTags`, `$auditExclude`.
- [ ] Presenter extending a module-local `AbstractPresenter` that implements
      `HistoryPresenterInterface`.
- [ ] Repository extending `Webkul\Core\Eloquent\Repository`.

## Phase 3 — HTTP client ([http-client.md](http-client.md))

- [ ] `src/Http/Client/ApiClient.php` on native cURL with an SSRF-safe `execute()`.
- [ ] Auth strategy class (`BearerToken` or `BasicAuth`).
- [ ] `ApiException` for transport and HTTP >= 400 failures.
- [ ] Bind the client and any stateful service `scoped()` — never `singleton()`.

## Phase 4 — Controller and routes ([credentials.md](credentials.md), [acl-security.md](acl-security.md))

- [ ] `CredentialForm` FormRequest — no inline `request()->validate()` anywhere,
      including `testConnection()`.
- [ ] `CredentialController`: store/update/destroy return `JsonResponse` with
      `redirect_url` + `message`; edit keeps the stored secret when the submitted
      value is the masked placeholder.
- [ ] `testConnection()` is its own POST route, FormRequest-validated and ACL-gated —
      never called inside `store()`.
- [ ] Routes file under `['admin']` middleware with `prefix => config('app.admin_url')`.
- [ ] A `credentials/get` route returning `[{id, label}]` for async dropdowns.

## Phase 5 — ACL and menu ([acl-security.md](acl-security.md))

- [ ] Flat `Config/acl.php` covering EVERY route name — index, create, store, edit,
      update, destroy, test_connection, get. ACL is fail-open: an uncovered route is
      open to all logged-in admins.
- [ ] `Config/menu.php` entries (key, name, route, sort, icon) — merged into
      `'menu.admin'` by the provider.

## Phase 6 — Admin UI ([admin-ui.md](admin-ui.md))

- [ ] Listing page: `<x-admin::layouts>` + `<x-admin::datagrid>`; DataGrid class per
      the unopim-datagrid skill.
- [ ] Forms are component-first (`x-admin::form.control-group.*`); colors use semantic
      theme tokens only.
- [ ] Follow the CRUD house pattern: modal create on the index page, edit page saves
      through the save bar, history via `<x-admin::layouts.with-history>`.

## Phase 7 — Data transfer wiring

- [ ] `Config/exporters.php`, `Config/quick_exporters.php`, `Config/importers.php`
      merged by the provider.
- [ ] Exporter/Importer classes and `{Entity}JobValidator` classes per the
      unopim-data-transfer skill (base: `Webkul\DataTransfer\Validators\JobInstances\
      Default\JobValidator`; the only real exporter constant is `BATCH_SIZE`).

## Phase 8 — Localization and verification

- [ ] `Resources/lang/en_US/app.php` first (never a bare `en/` — it does not load),
      then propagate natural translations to all 33 locales.
- [ ] Run the unopim-verify gate: Pint, Pest, Larastan, Playwright (UI changed),
      `php artisan unopim:translations:check`.
