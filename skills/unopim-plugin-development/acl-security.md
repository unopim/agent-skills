# ACL and Security

## Contents

- The fail-open rule (read this first)
- Routes template
- ACL config — complete coverage
- FormRequest authorization
- Uploads
- CSRF
- SSRF and injection
- Secrets and mass assignment

## The fail-open rule (read this first)

The `['admin']` middleware is the Bouncer ACL gate
(`packages/Webkul/User/src/Http/Middleware/Bouncer.php`), and it enforces permissions
**by route name**: any route name absent from every `acl.php` is reachable by ALL
logged-in admins regardless of role. Coverage is therefore a completeness exercise —
diff your routes file against your `acl.php` and close every gap, especially the write
routes agents habitually forget: `store`, `update`, `destroy`, `mass_*`,
`test_connection`, `get`.

Route middleware is `['admin']` only — never `['web', 'admin']` (`web` is already
applied by the provider's `Route::middleware('web')->group()`).

## Routes template

```php
<?php

use Illuminate\Support\Facades\Route;
use Webkul\{ModuleName}\Http\Controllers\CredentialController;

Route::group(['middleware' => ['admin'], 'prefix' => config('app.admin_url')], function (): void {

    Route::prefix('{module}')->name('{module}.')->group(function (): void {

        Route::get('credentials', [CredentialController::class, 'index'])
            ->name('credentials.index');

        Route::post('credentials', [CredentialController::class, 'store'])
            ->name('credentials.store');

        Route::get('credentials/get', [CredentialController::class, 'get'])
            ->name('credentials.get');

        Route::get('credentials/{id}/edit', [CredentialController::class, 'edit'])
            ->name('credentials.edit')
            ->whereNumber('id');

        Route::put('credentials/{id}', [CredentialController::class, 'update'])
            ->name('credentials.update')
            ->whereNumber('id');

        Route::delete('credentials/{id}', [CredentialController::class, 'destroy'])
            ->name('credentials.destroy')
            ->whereNumber('id');

        Route::post('credentials/test-connection', [CredentialController::class, 'testConnection'])
            ->name('credentials.test_connection');
    });

});
```

Exemplar routes file: `packages/Webkul/AiAgent/Routes/ai-agent-routes.php`. Modal-create
house pattern means NO GET `credentials/create` page route ([admin-ui.md](admin-ui.md)).

## ACL config — complete coverage

Flat arrays, no nested `children`. Mass-action keys are snake_case
(`catalog.products.mass_delete`), never hyphenated. Two equivalent ways to cover write
routes, both in the codebase:

1. Repeat the permission key with each route name it authorizes — the dominant pattern
   (exemplar: `packages/Webkul/AiAgent/Config/acl.php`, where one `edit` key maps the
   edit, update and set_default routes).
2. `'also_authorizes' => [...]` binds extra route names to one entry
   (`packages/Webkul/Core/src/Tree.php`; used in `packages/Webkul/Admin/src/Config/acl.php`).

```php
<?php

return [
    [
        'key'   => '{module}',
        'name'  => '{module}::app.acl.{module}',
        'route' => '{module}.credentials.index',
        'sort'  => 8,
    ],
    [
        'key'             => '{module}.credentials',
        'name'            => '{module}::app.acl.credentials',
        'route'           => '{module}.credentials.index',
        'sort'            => 1,
        'also_authorizes' => ['{module}.credentials.get'],
    ],
    [
        'key'             => '{module}.credentials.create',
        'name'            => '{module}::app.acl.create',
        'route'           => '{module}.credentials.store',
        'sort'            => 1,
        'also_authorizes' => ['{module}.credentials.test_connection'],
    ],
    [
        'key'             => '{module}.credentials.edit',
        'name'            => '{module}::app.acl.edit',
        'route'           => '{module}.credentials.edit',
        'sort'            => 2,
        'also_authorizes' => ['{module}.credentials.update'],
    ],
    [
        'key'   => '{module}.credentials.delete',
        'name'  => '{module}::app.acl.delete',
        'route' => '{module}.credentials.destroy',
        'sort'  => 3,
    ],
];
```

A routeless entry registers only an assignable permission checkbox; enforcement is then
YOUR job in the controller:

```php
if (! bouncer()->hasPermission('{module}.credentials')) {
    return new JsonResponse(['error' => trans('{module}::app.common.unauthorized')], 403);
}
```

Exemplar for the in-controller gate:
`packages/Webkul/Admin/src/Http/Controllers/MagicAI/MagicAIController.php`; for a
constructor-middleware gate covering a whole controller:
`packages/Webkul/AiAgent/src/Http/Controllers/CredentialController.php`.

## FormRequest authorization

- Every endpoint validates through a FormRequest — inline `request()->validate()` is
  forbidden, including `testConnection` and AJAX endpoints.
- `authorize(): bool { return true; }` is safe ONLY when the route name is ACL-mapped.
  Otherwise put the bouncer check in `authorize()` (exemplars:
  `packages/Webkul/Admin/src/Http/Requests/TinyMCEUploadRequest.php`,
  `packages/Webkul/AiAgent/src/Http/Requests/CredentialForm.php`).

## Uploads

Extension allowlist + size cap + MIME/extension match; never accept `svg` or `html`
(script carriers). Rule: `packages/Webkul/Core/src/Rules/FileMimeExtensionMatch.php`.

```php
use Webkul\Core\Rules\FileMimeExtensionMatch;

'file' => ['required', 'mimes:csv,xlsx', 'max:10240', new FileMimeExtensionMatch],
```

## CSRF

`App\Http\Middleware\VerifyCsrfToken` DOES NOT EXIST in this codebase. The web group
registers `Illuminate\Foundation\Http\Middleware\PreventRequestForgery`;
`withoutMiddleware()` must name that registered class — excluding the nonexistent
subclass is a silent no-op and the external POST fails with 419. Any CSRF-exempt
webhook endpoint MUST verify an HMAC signature or shared-secret header before touching
data — CSRF exemption without a compensating control is a finding, not a feature.

## SSRF and injection

- Every admin-supplied URL is validated by
  `packages/Webkul/Webhook/src/Validators/SafeWebhookUrl.php` and fetched with its
  pinned-resolve cURL options ([http-client.md](http-client.md)).
- Never interpolate request input into SQL. Query-builder `where()` binds
  automatically; `DB::raw()` containing a variable is forbidden.
- DataGrid closures render raw HTML (the engine `strip_tags()`-sanitizes string cells
  first) — never interpolate unescaped user input into closure markup.
- CSV exports pass through
  `packages/Webkul/DataTransfer/src/Helpers/Formatters/EscapeFormulaOperators.php` —
  keep formula escaping when building custom export output.

## Secrets and mass assignment

- No API keys or tokens in code or config defaults — credentials live in the DB record
  (encrypted cast, [credentials.md](credentials.md)) or `config()` backed by `.env`.
- Never log secrets; keep them in `$auditExclude` AND encrypted at rest.
- Every model declares an explicit `#[Fillable]` allowlist; `$guarded = []` is
  forbidden; never put role/permission/ownership columns in the allowlist.
