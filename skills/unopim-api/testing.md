# Testing API endpoints

## Wiring

- Files under `packages/Webkul/AdminApi/tests` are bound to `packages/Webkul/AdminApi/tests/ApiTestCase.php` by `tests/Pest.php`, which brings `ApiHelperTrait` and `CoreAssertions`. The suite is "Api Feature Test" in `phpunit.xml`.
- A test in any other package keeps that package's bound test case and adds the trait at the top of the file: `uses(ApiHelperTrait::class);` — as `packages/Webkul/Measurement/tests/Feature/MeasurementApiTest.php` does. Do not bind `ApiTestCase` over another package's directory.
- Helpers declared at the top level of a Pest file are global functions. Prefix them with the entity (`measurementAclTree()`), or two files collide with a fatal "cannot redeclare".

## Getting a token

`packages/Webkul/AdminApi/tests/Traits/ApiHelperTrait.php`:

```php
beforeEach(function () {
    $this->headers = $this->getAuthenticationHeaders();
});
```

`getAuthenticationHeaders(string $permissionType = 'all', mixed $permissions = null)` creates an admin, a password-grant client with the owner morph, an `api_keys` row, and calls the real `/oauth/token` endpoint. It returns `Authorization` and `Accept: application/json` headers. It also disables `ThrottleRequests` for the test.

- Use it; never `Passport::actingAs()`. `actingAs` skips the `api_keys` row, so `api.scope` returns 403 and the test exercises nothing real.
- Custom-permission caller: `$this->getAuthenticationHeaders('custom', ['api.catalog.{entity}'])`.
- No-permission caller: `$this->getAuthenticationHeaders('custom')`.

## What every endpoint test covers

Model on `packages/Webkul/AdminApi/tests/Feature/Settings/ApiLocaleTest.php` and `packages/Webkul/AdminApi/tests/Feature/Acl/ApiAclTest.php`.

| Case | Assertion |
|---|---|
| List | `assertOk()`, `assertJsonStructure(['data' => ['*' => [...]], 'current_page', 'last_page', 'total', 'links' => ['first', 'last', 'next', 'prev']])`, `total` equals the table count |
| Filter | A registered filter narrows the result. An unregistered field or operator is refused, and the test pins the status. |
| Cursor | With `pagination_type=search_after`: `search_after` and `links.next` present, no `total` |
| Get | `assertJson(['code' => ...])` on a known code; 404 with `success: false` on an unknown code |
| Create | 201, `success: true`, `assertDatabaseHas('{entities}', [...])` with the bare table name |
| Validation | 422 with `errors.<field>` for a duplicate code, a bad code format and an inactive locale in `labels` |
| ACL | 403 for `custom` with no permissions, 200 for `custom` with the entity key — one pair per route |
| Events | `Event::fake([...])` then `Event::assertDispatched('{module}.{entity}.create.after')` when the controller fires the pair |

Call routes by name — `route('admin.api.{entity}.index')` — never by a hardcoded `/api/v1/rest/...` string. The route name is the contract the ACL is keyed on, so the test fails loudly if it changes.

## Permission-map tests

When a package adds or moves `api-acl` entries, assert the map itself, as `packages/Webkul/Measurement/tests/Feature/ApiMeasurementUnitPermissionsTest.php` does:

- every route name in your route file resolves to the intended key via `app('api-acl')->roles[$route]`;
- no route name is claimed by two different keys. `Tree::add()` writes `roles[$route] = $key`, so the last entry wins silently;
- a backfill migration grants the new key to existing custom keys and `down()` removes it — `packages/Webkul/Measurement/tests/Feature/ApiMeasurementUnitPermissionsMigrationTest.php`.

## Engine-level tests

Behaviour of `ApiDataSource` itself (clamping, cursor validation) is tested with an anonymous subclass and no HTTP, as in `packages/Webkul/AdminApi/tests/Feature/ApiDataSourceClampTest.php`. Add one only when you change the base class.

## Running

Through unopim-exec, never against a production database:

```bash
vendor/bin/pest packages/Webkul/AdminApi/tests
vendor/bin/pest packages/Webkul/{Module}/tests --filter=Api
```

CI also runs the suite on PostgreSQL (`phpunit.pgsql.xml`). Assertions on `status` must survive `true`/`false` versus `1`/`0`: cast in `formatData()` and assert the cast value.
