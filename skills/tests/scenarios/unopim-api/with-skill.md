# With skill — unopim-api

**Run type:** desk-run, not a live agent session. Same task as [baseline.md](baseline.md), worked by following `skills/unopim-api/SKILL.md` and its reference files against UnoPim `origin/master` (9f4d9d0a). The code below is the plan the procedure yields; it has not been executed.

## Task

> "Integrators need measurement families over the REST API: a paginated, filterable list and a get-by-code. Add it with tests."

## Decision procedure, step by step

1. **Does it exist?** `git grep -n "admin.api.measurement" -- packages` finds `packages/Webkul/Measurement/src/Routes/measurement-routes.php`: `GET measurement` (`admin.api.measurement.index`) and `GET measurement/{code}` (`admin.api.measurement.show`). Both are mapped in `packages/Webkul/Measurement/src/Config/api-acl.php` to `api.catalog.measurements`. **No new route, no new permission.** The real gap: `MeasurementFamilyApiController::index()` is an unbounded `$this->repository->all()` with no filters or pagination.
2. **Where does it live?** Stays in the Measurement package. The route file already carries `accept.json, auth:api, throttle:rest-api, api.scope, request.locale`, loaded by `MeasurementServiceProvider` under `api` + `v1/rest`. Nothing in AdminApi is edited.
3. **Route names.** Unchanged. `.show` is not a `.get`, so it keeps its explicit `api-acl` entry, which already exists.
4. **ACL.** No change, so no backfill migration.
5. **Listing → `ApiDataSource`.**
6. **Contract check — stop and flag.** `packages/Webkul/Measurement/tests/Feature/MeasurementApiEndpointsTest.php` asserts `{success, count, data}`. Moving the list to the DataSource envelope `{data, current_page, last_page, total, links}` breaks shipped clients. Per contract.md, this goes to the user before any code is written:
   > The existing list returns `{success, count, data}`; paging it through `ApiDataSource` changes the envelope. Either (a) accept the break, update the tests and note it in the changelog, or (b) keep the old shape on `admin.api.measurement.index` and add paging as a new route. Which do you want?

   For the rest of this run, assume the user chose (a).

## Resulting change

`packages/Webkul/Measurement/src/Repositories/MeasurementFamilyRepository.php` gets an eager-loading entry point, mirroring `AttributeGroupRepository::queryBuilder()`:

```php
public function queryBuilder()
{
    return $this->with(['translations', 'units.translations', 'units.conversions']);
}
```

New `src/ApiDataSource/MeasurementFamilyDataSource.php` (Measurement package):

```php
class MeasurementFamilyDataSource extends ApiDataSource
{
    public function __construct(protected MeasurementFamilyRepository $measurementFamilyRepository) {}

    public function prepareApiQueryBuilder()
    {
        $this->addFilter('code', ['=', 'IN', 'NOT IN']);

        return $this->measurementFamilyRepository->queryBuilder();
    }

    public function formatData(): array
    {
        return $this->paginator->getCollection()
            ->map(fn (MeasurementFamily $family): array => $this->format($family))
            ->all();
    }
}
```

`getByCode()` follows endpoint-recipe.md §3. `format()` takes the model, not `toArray()` output, because the legacy `labels`/`units` shapes come from model accessors (`MeasurementFamily::labels()`, `getUnitsAttribute()`) that `toArray()` does not emit. Those accessors read already-loaded relations through `loadedOrQueried()`, so the eager load above keeps a page at a fixed number of queries instead of one per family. `format()` keeps the existing keys (`code`, `name`, `standard_unit`, `symbol`, `labels`, `units`), so single-record clients see no change. `$structureCacheGroup` stays null: Measurement has no `StructureCache` bump wired, so caching would serve stale lists.

`MeasurementFamilyApiController::index()` becomes:

```php
try {
    return app(MeasurementFamilyDataSource::class)->toJson();
} catch (\Exception $e) {
    return $this->storeExceptionLog($e);
}
```

The controller now extends `Webkul\AdminApi\Http\Controllers\API\ApiController` to get `storeExceptionLog()`. `show()` is left alone in this change.

Out of scope, reported rather than fixed: the controller's `store()`/`update()` call `$request->validate()`, which the `INLINE_VALIDATE` hook rule flags on any edited line. Moving them to `ApiFormRequest` subclasses is a follow-up.

## Tests (Measurement package, `uses(ApiHelperTrait::class);`)

- list: `getJson(route('admin.api.measurement.index'))` → `assertJsonStructure(['data' => ['*' => ['code', 'labels', 'units']], 'current_page', 'last_page', 'total', 'links'])`; old `count` assertions updated deliberately.
- `limit=1000` → at most 100 rows; `pagination_type=search_after` → `search_after` and `links.next`, no `total`.
- `filters={"code":[{"operator":"IN","value":["length","weight"]}]}` narrows; `{"name":[...]}` is refused (422).
- ACL: `getAuthenticationHeaders('custom')` → 403; `getAuthenticationHeaders('custom', ['api.catalog.measurements'])` → 200.
- PostgreSQL: no boolean in the payload, nothing to cast.

## Verification plan

unopim-verify gates 1–4 and 6, run through unopim-exec: `vendor/bin/pest packages/Webkul/Measurement/tests` and `vendor/bin/pest packages/Webkul/AdminApi/tests` on MySQL and PostgreSQL. No new translation keys: the existing `measurement::app.messages.family.not_found` is reused. Gate 5 is skipped — no view changed.

## Baseline failures resolved

| Baseline # | Resolved by |
|---|---|
| 1, 2, 3 | Step 1 found the existing package endpoint; the change stays in `packages/Webkul/Measurement` |
| 4, 5, 6 | Existing stack and `api-acl` entries reused; names untouched |
| 7, 8, 9 | Repository `queryBuilder()` + `ApiDataSource` (clamped `limit`, `filters` grammar, cursor mode) |
| 10, 11 | `ApiHelperTrait` headers, 403/200 permission pair |
| 12 | No stock Passport commands; credentials come from Integrations |
| 13 | Envelope break surfaced to the user before coding; tests changed on purpose |
