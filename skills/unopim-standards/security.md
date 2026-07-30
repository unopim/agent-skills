# Security

Validate and authorize every entry point; fail closed on uncertainty.

## Contents

- ACL is fail-open — close it yourself
- FormRequest `authorize()`
- Uploads
- XSS in DataGrids and Blade
- Mass assignment
- SSRF and CSV injection
- Queries
- Secrets at rest
- CSRF

Hook-enforced, so a violation is an exit code: `$guarded = []`; inline
`validate()` in either spelling (`$request->validate()`, `Validator::make($request…)`,
`$this->validate(request()…)`); a request value interpolated into `whereRaw`,
`selectRaw`, `havingRaw` or `DB::raw` in a value position; an upload rule with
no `mimes:` allowlist; and `svg`/`html`/`xml` in a `mimes:` list.

NOT hook-enforced, and therefore yours to check by hand every time: whether a
write route appears in `acl.php`, whether `authorize()` actually gates the
action, and `orderByRaw("$column $direction")` — a sort column interpolated
from the request is character-for-character the shape of the legitimate
`whereRaw("$column IS NULL")` in the product filters, so no regex separates
them. Everything below is judgment of that kind.

## ACL is fail-open — close it yourself

The `['admin']` middleware is the Bouncer
(`packages/Webkul/User/src/Http/Middleware/Bouncer.php`). It enforces
permissions **by route name**, in `checkIfAuthorized()`:

```php
if (! isset($acl->roles[$routeName])) {
    return;
}
```

That early return is the whole problem. A route name absent from every `acl.php`
is not denied — it is waved through, reachable by EVERY logged-in admin
regardless of role. Nothing errors, nothing logs, and the feature works
perfectly in testing because you are testing as an admin who can do everything.

- Every write route MUST be covered by an `acl.php` entry, directly or via
  `also_authorizes`: `store`, `update`, `destroy`/`delete`, every `mass_*`,
  every bulk/batch action, `test-connection`, and any POST that publishes,
  imports, exports, syncs or dispatches a job.
- Two shapes cover a route. `'route' => '...'` binds one route name to the key,
  and core repeats the whole entry with the same `'key'` to bind a second name —
  an `edit` key appears once for `...edit` and again for `...update`.
  `'also_authorizes' => [...]` binds extra names to one key as an OR list
  (`packages/Webkul/Core/src/Tree.php` builds `roles` from `route` and
  `alternateRoles` from `also_authorizes`). Use either; use one.
- Exemplar of a package that does this completely for a non-trivial route
  group: `packages/Webkul/ProductPassport/src/Config/acl.php`, which has an
  entry per write action rather than one entry for the index page.

### The check, because no hook can do it

This is cross-file — the route file and every `acl.php` must be read together —
so a per-file gate cannot see it. Run it by hand on every PR that adds a write
route:

1. List every write route name the change adds or touches: each
   `Route::post|put|patch|delete(...)->name('...')` inside a group whose
   middleware is `['admin']`.
2. Grep each name, quoted, across every `acl.php` in the repo.
3. A name that appears in neither a `'route' =>` value nor an
   `'also_authorizes'` array is fail-open. Either add an entry, or enforce it
   in-controller with the `bouncer()->hasPermission()` pattern below and say so
   in the PR.

Two exclusions keep this honest, and only these two. Routes reached before an
admin session exists (session, password reset, the installer) have no role to
check. Routes that are per-admin self-service — editing your own account,
marking your own notifications read — are correctly ungated. Everything else
that writes needs an entry. On core, 147 write routes measured this way leave 23
absent from every `acl.php`: 13 fall into those two exclusions, 8 are
`auth:api` token routes where the Bouncer never runs at all and authorization is
a separate story, and the remainder are mass-action routes added after their
siblings — which is the single commonest way this gap appears. When you add a
`mass_*` route, add its ACL entry in the same commit.

```php
[
    'key'             => 'settings.credentials.edit',
    'name'            => 'module::app.acl.credentials.edit',
    'route'           => 'module.credentials.edit',
    'also_authorizes' => ['module.credentials.update', 'module.credentials.test_connection'],
    'sort'            => 3,
],
```

- Routeless ACL entries register only an assignable checkbox; enforcement is
  in-controller, the pattern in
  `packages/Webkul/Admin/src/Http/Controllers/MagicAI/MagicAIController.php`:

```php
if (! bouncer()->hasPermission('ai-agent')) {
    return new JsonResponse(['error' => trans('admin::app.common.unauthorized')], 403);
}
```

- ACL config is flat arrays — no nested `children`. Mass-action keys are
  snake_case (`catalog.products.mass_delete`), never hyphenated.
- Route middleware is `['admin']` only — never `['web', 'admin']`.

## FormRequest `authorize()`

`authorize(): bool` may `return true` ONLY when the route name is ACL-mapped
(the Bouncer already gated it). For shared or routeless endpoints the bouncer
check lives in `authorize()` — exemplar
`packages/Webkul/Admin/src/Http/Requests/TinyMCEUploadRequest.php`, which loops
acceptable permissions and returns false otherwise.

`testConnection` is a SEPARATE endpoint (never called inside `store()` before
persisting); it accepts credentials and makes outbound calls, so it MUST be
FormRequest-validated and ACL-gated like any other write route.

## Uploads

Extension allowlist + size cap + MIME/extension match, always:

```php
public function rules(): array
{
    return [
        'file' => [
            'required',
            'mimes:csv,xlsx',
            'max:10240',
            new FileMimeExtensionMatch,
        ],
    ];
}
```

`packages/Webkul/Core/src/Rules/FileMimeExtensionMatch.php` rejects spoofed
content types. NEVER accept svg or html — both are script carriers.

## XSS in DataGrids and Blade

The DataGrid engine `strip_tags()`-sanitizes string cells before column
closures run, and closure output is rendered as **raw HTML**. Closures may wrap
already-sanitized `$row` fields in trusted markup; they must never interpolate
unescaped user input. In Blade, `{!! !!}` only for content passed through the
`purifyText()` allowlist in `packages/Webkul/Core/src/Traits/HtmlPurifier.php`.

## Mass assignment

Every model declares an explicit `#[Fillable([...])]` allowlist (see
[laravel13.md](laravel13.md)). Never place role, permission or ownership
columns in the allowlist; they are assigned explicitly in the repository.

## SSRF and CSV injection

- Any feature that fetches a user-supplied URL validates it first — exemplar
  `packages/Webkul/Webhook/src/Validators/SafeWebhookUrl.php` (scheme
  allowlist, loopback/private-range guard).
- Any user data written to CSV/Excel goes through
  `packages/Webkul/DataTransfer/src/Helpers/Formatters/EscapeFormulaOperators.php`
  so `=`, `-`, `+`, `@` cells cannot execute in a spreadsheet.

## Queries

Bind, never interpolate: `->where('col', $value)` binds automatically;
`DB::raw()` containing a request value is forbidden. `DB::rawQueryGrammar()`
(core macro registered in
`packages/Webkul/Core/src/Providers/CoreServiceProvider.php`) is a cross-DB
SQL-fragment helper, NOT raw interpolation — do not flag or "fix" it; see
[scale.md](scale.md) for when to use it.

## Secrets at rest

Three layers TOGETHER, per `packages/Webkul/AiAgent/src/Models/Credential.php`
and its data migration
`packages/Webkul/AiAgent/Database/Migration/2026_03_24_000001_encrypt_existing_ai_agent_api_keys.php`:

1. `'encrypted'` Eloquent cast — ciphertext at rest;
2. `#[Hidden([...])]` — never serialized to responses;
3. `$auditExclude` — never written to the history/audit trail.

`$auditExclude` alone is NOT a substitute for encryption. No API keys, tokens
or passwords in code or committed config; they live in the credential record or
`config()` backed by `.env`, and are never logged.

## CSRF

The registered web-group middleware is
`Illuminate\Foundation\Http\Middleware\PreventRequestForgery`;
`App\Http\Middleware\VerifyCsrfToken` does NOT exist here, and excluding the
deprecated subclass is a no-op that leaves the 419. A route that legitimately
excludes CSRF (external webhooks) MUST verify an HMAC or shared-secret header
before touching data.
