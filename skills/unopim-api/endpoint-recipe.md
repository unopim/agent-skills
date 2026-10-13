# Adding an endpoint end to end

Order matters: the route name is the join key between the route file, `api-acl`, `ScopeMiddleware` and the tests. Pick it first and never rename it afterwards — renaming orphans every custom API key that holds its permission.

Placeholders: `{Module}` package namespace, `{module}` translation namespace, `{entity}` URL segment and route-name segment, `{entities}` bare table name.

## 1. Route

Core entity: add a group to the matching `V1/*-routes.php`. If you add a new file, `require` it from `packages/Webkul/AdminApi/src/Routes/admin-api.php` inside the existing group.

Plugin entity: a `Routes/api.php` in the plugin carrying the full outer stack, loaded from the provider's `boot()` the way `packages/Webkul/Measurement/src/Providers/MeasurementServiceProvider.php` does (`Route::prefix('api')->middleware('api')->group(...)`).

```php
Route::group([
    'prefix'     => 'v1/rest',
    'middleware' => [
        'accept.json',
        'auth:api',
        'throttle:rest-api',
        'api.scope',
        'request.locale',
        'cache.headers:private;etag',
    ],
], function (): void {
    Route::controller({Entity}Controller::class)->prefix('{entity}')->group(function (): void {
        Route::get('', 'index')->name('admin.api.{entity}.index');
        Route::get('{code}', 'get')->name('admin.api.{entity}.get');
        Route::post('', 'store')->name('admin.api.{entity}.store');
        Route::put('{code}', 'update')->name('admin.api.{entity}.update');
        Route::patch('{code}', 'partialUpdate')->name('admin.api.{entity}.patch');
        Route::delete('{code}', 'delete')->name('admin.api.{entity}.delete');
    });
});
```

- Address resources by `code` (or `sku`), not by numeric id. Every core endpoint does; ids are not stable across instances.
- Drop `api.scope` from the stack and the route is open to any valid token. It is the only authorization layer.
- Measurement's group omits `cache.headers:private;etag`. Keep it on read-heavy endpoints: conditional GETs return 304 (covered by `packages/Webkul/AdminApi/tests/Feature/StructureCacheAndEtagTest.php`).
- Renaming a URL that clients already call: keep the old path as a second group with `->middleware('api.deprecated:/api/v1/rest/<new-path>')`, as the `configrable-products` loop in `packages/Webkul/AdminApi/src/Routes/V1/catalog-routes.php` does, and give it its own `api-acl` entries.

## 2. Permission entries

Core: `packages/Webkul/AdminApi/src/Config/api-acl.php`. Plugin: its own `Config/api-acl.php`, merged in `register()`:

```php
$this->mergeConfigFrom(dirname(__DIR__).'/Config/api-acl.php', 'api-acl');
```

```php
[
    'key'   => 'api.catalog.{entity}',
    'name'  => '{module}::app.acl.{entity}',
    'route' => 'admin.api.{entity}.index',
    'sort'  => 8,
], [
    'key'   => 'api.catalog.{entity}.create',
    'name'  => 'admin::app.acl.create',
    'route' => 'admin.api.{entity}.store',
    'sort'  => 1,
], [
    'key'   => 'api.catalog.{entity}.edit',
    'name'  => 'admin::app.acl.edit',
    'route' => 'admin.api.{entity}.update',
    'sort'  => 2,
], [
    'key'   => 'api.catalog.{entity}.edit',
    'name'  => 'admin::app.acl.edit',
    'route' => 'admin.api.{entity}.patch',
    'sort'  => 2,
], [
    'key'   => 'api.catalog.{entity}.delete',
    'name'  => 'admin::app.acl.delete',
    'route' => 'admin.api.{entity}.delete',
    'sort'  => 3,
],
```

- One entry per route name. Several routes share a permission by repeating the same `key` with a different `route` — that is how PATCH reuses `edit`.
- `*.get` needs no entry: `ScopeMiddleware::getAclForCurrentRoute()` falls back to the `*.index` entry by string replacement. Any other read verb (`show`, `getOptions`, nested `.../fields`) needs an explicit entry.
- Keys are dotted under `api.settings.*` or `api.catalog.*`, with snake_case segments (`api.catalog.category_fields`). `Tree::add()` in `packages/Webkul/Core/src/Tree.php` nests by splitting the key on dots, so declare the parent key too — Measurement declares `api.catalog.measurements` before `api.catalog.measurements.units`.
- Reuse `admin::app.acl.create|edit|delete` for the verbs. Add only the entity label to your package's `en_US` lang file, then all 33 locales.

### Changing who can reach an existing route

Custom keys store a JSON list of permission keys in `api_keys.permissions`. Moving a route to a new key revokes it from every existing key. Ship a migration that grants the new key to every key holding the old one, with a reversible `down()`. Copy `packages/Webkul/Measurement/src/Database/Migrations/2026_07_29_120000_add_api_measurement_unit_permissions.php`: it walks `DB::table('api_keys')` with `orderBy('id')->each()`, so it is bounded and prefix-safe.

## 3. Listing — a DataSource

Core leaves live in `packages/Webkul/AdminApi/src/ApiDataSource/`; a plugin puts its own under `src/ApiDataSource/`.

```php
<?php

namespace Webkul\{Module}\ApiDataSource;

use Illuminate\Database\Eloquent\ModelNotFoundException;
use Webkul\AdminApi\ApiDataSource;
use Webkul\{Module}\Repositories\{Entity}Repository;

class {Entity}DataSource extends ApiDataSource
{
    public function __construct(protected {Entity}Repository ${entity}Repository) {}

    /**
     * Register the supported filters and return the base query.
     */
    public function prepareApiQueryBuilder()
    {
        $this->addFilter('code', ['=', 'IN', 'NOT IN']);
        $this->addFilter('status', ['=']);
        $this->addFilter('updated_at', ['>', '>=', '<', '<=', 'BETWEEN'], null, 'datetime');

        return $this->{entity}Repository->queryBuilder();
    }

    /**
     * Shape each row of the current page.
     */
    public function formatData(): array
    {
        return array_map(fn (array $row): array => $this->format($row), $this->paginator->toArray()['data'] ?? []);
    }

    /**
     * Fetch one record by code.
     *
     * @throws ModelNotFoundException
     */
    public function getByCode(string $code): array
    {
        $this->prepareForSingleData();

        $this->queryBuilder = $this->processRequestedFilters(['code' => [['operator' => '=', 'value' => $code]]]);

        $row = $this->queryBuilder->first()?->toArray();

        if (! $row) {
            throw new ModelNotFoundException(trans('{module}::app.api.{entity}.not-found', ['code' => $code]));
        }

        return $this->format($row);
    }

    protected function format(array $row): array
    {
        return [
            'code'   => $row['code'],
            'status' => (int) $row['status'],
            'labels' => $this->getTranslations($row),
        ];
    }
}
```

- The repository's `queryBuilder()` returns the repository with its eager loads, as `packages/Webkul/Attribute/src/Repositories/AttributeGroupRepository.php` does (`return $this->with(['translations']);`). Add one to your repository; `with()` is what prevents an N+1 in `formatData()`.
- One shaping method serves both list and single-record responses, so the two shapes cannot drift.
- `toArray()` drops model accessors that are not appended. When the payload comes from accessors (Measurement's legacy `labels`/`units`), map `$this->paginator->getCollection()` models instead, with the relations those accessors read eager-loaded.
- Cast booleans and integers explicitly (`(int) $row['status']`). PostgreSQL returns `true`/`false` where MySQL and MariaDB return `1`/`0`, and clients compare the JSON.
- A fixed type constraint (only simple products, only one family's structures) goes in `setDefaultFilters()` — see `packages/Webkul/AdminApi/src/ApiDataSource/Catalog/SimpleProductDataSource.php`.
- Joins: set `$sortColumn` (and `$primaryColumn` if the cursor must follow it) to a table-qualified column, as `packages/Webkul/AdminApi/src/ApiDataSource/Catalog/ProductDataSource.php` sets `products.id`.
- Per-row extras (completeness, associations) are loaded in one batched query per page — see `ProductDataSource::formatData()` — never one query per row.

## 4. Controller

Extend `Webkul\AdminApi\Http\Controllers\API\ApiController`; it brings the `ApiResponse` trait. Inject repositories, never models.

```php
public function index(): JsonResponse
{
    try {
        return app({Entity}DataSource::class)->toJson();
    } catch (\Exception $e) {
        return $this->storeExceptionLog($e);
    }
}

public function get(string $code): JsonResponse
{
    try {
        return response()->json(app({Entity}DataSource::class)->getByCode($code));
    } catch (\Exception $e) {
        return $this->storeExceptionLog($e);
    }
}

public function store(Store{Entity}Request $request): JsonResponse
{
    try {
        Event::dispatch('{module}.{entity}.create.before');
        ${entity} = $this->{entity}Repository->create($this->setLabels($request->only(['code', 'status', 'labels'])));
        Event::dispatch('{module}.{entity}.create.after', ${entity});

        return $this->successResponse(trans('{module}::app.api.{entity}.create-success'), Response::HTTP_CREATED);
    } catch (\Exception $e) {
        return $this->storeExceptionLog($e);
    }
}
```

- `storeExceptionLog()` maps validation to 422, `ModelNotFoundException` to 404, `HttpExceptionInterface` to its own status, and logs anything else as a 500 without leaking the message. `LocaleController::index()` returns a bare 400 instead — legacy, do not copy.
- Look the record up by code first and return `modelNotFoundResponse(trans(...))` on a miss, as `AttributeGroupController::update()` does.
- Fire the **same event names** the admin controller for the entity fires. Grep the admin controller; never invent new ones. Other packages listen to them: outbound webhooks hang off `catalog.product.create.after` / `catalog.product.update.after` in `packages/Webkul/Webhook/src/Providers/EventServiceProvider.php`, Measurement off `catalog.attribute.update.*` in `packages/Webkul/Measurement/src/Providers/MeasurementEventServiceProvider.php`. An API write that skips the pair silently skips them.
- `setLabels()` turns `{"labels": {"en_US": "…"}}` into the repository's translation shape.
- `partialUpdate()` may delegate to `update()` when the update request is all `sometimes` rules, as `AttributeGroupController` does.
- Domain refusals (in use, last remaining record) answer `validateErrorResponse(['code' => [trans(...)]], trans(...))` — 422, never 500.

## 5. Validation

```php
class Store{Entity}Request extends ApiFormRequest
{
    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'code'   => ['required', 'unique:{entities},code', new Code],
            'status' => ['sometimes', 'boolean'],
            'labels' => ['sometimes', 'array'],
        ];
    }
}
```

- `ApiFormRequest::authorize()` returns true on purpose: `api.scope` already authorized the route. Do not add a Bouncer check — integration users are provisioned with no admin role (`packages/Webkul/AdminApi/src/Services/ApiUserProvisioner.php`), so a `bouncer()` check has no role to read.
- `failedValidation()` returns the API's 422 envelope. A plain `FormRequest` would redirect or emit Laravel's default shape.
- `Webkul\Core\Rules\Code` (`packages/Webkul/Core/src/Rules/Code.php`) is the code-format rule every create endpoint uses.
- The update request leaves `code` out of the rules and the controller's `only()`. Fields that must not change after create are rejected with 422, not silently dropped — `type` on attributes and category fields, covered by `packages/Webkul/AdminApi/tests/Feature/Catalog/ApiImmutableFieldsTest.php`.

## 6. Messages and translations

Every success, not-found and refusal message is a `trans()` key in the owning package, in `en_US` first and then all 33 locales (unopim-standards localization.md). Then run `php artisan unopim:translations:check` through unopim-exec.

## Review checklist

- [ ] Route named `admin.api.{entity}.{verb}`, under a group carrying `api.scope`
- [ ] Every route name has an `api-acl` entry, or is a `*.get` whose `*.index` has one
- [ ] Permission moved or split → backfill migration with `down()`
- [ ] Listing goes through an `ApiDataSource`; no hand-built paginator or envelope
- [ ] Filters declared with `addFilter()`; datetime filters typed `'datetime'`
- [ ] `$structureCacheGroup` null, or set with invalidation wired
- [ ] Writes use an `ApiFormRequest` subclass, a repository, and the admin event pair
- [ ] All messages through `trans()`, 33 locales
- [ ] Tests cover success, 404, 422 and the 403 for a custom key without the permission
