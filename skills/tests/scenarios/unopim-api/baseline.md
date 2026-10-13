# Baseline — unopim-api (without the skill)

**Run type:** desk-run, not a live agent session. The plan below was written from generic Laravel 13 / Passport knowledge *before* reading `packages/Webkul/AdminApi`, then checked line by line against UnoPim `origin/master` (9f4d9d0a). It records what an agent with no UnoPim-specific API guidance produces.

## Task

> "Integrators need measurement families over the REST API: a paginated, filterable list and a get-by-code. Add it with tests."

## Plan produced without the skill

1. `routes/api.php`:
   ```php
   Route::middleware('auth:api')->prefix('v1')->group(function () {
       Route::apiResource('measurement-families', MeasurementFamilyController::class)->only(['index', 'show']);
   });
   ```
2. `app/Http/Controllers/Api/MeasurementFamilyController.php`:
   ```php
   public function index(Request $request)
   {
       return MeasurementFamilyResource::collection(
           MeasurementFamily::query()
               ->when($request->code, fn ($q) => $q->where('code', $request->code))
               ->paginate($request->integer('per_page', 15))
       );
   }

   public function show(MeasurementFamily $measurementFamily)
   {
       return new MeasurementFamilyResource($measurementFamily);
   }
   ```
3. `app/Http/Resources/MeasurementFamilyResource.php` returning `id`, `code`, `name`, `labels`, `units`.
4. No permission declaration — "any authenticated token can read".
5. Test:
   ```php
   Passport::actingAs(User::factory()->create());
   $this->getJson('/api/v1/measurement-families')
       ->assertOk()
       ->assertJsonStructure(['data', 'links', 'meta']);
   ```
6. Setup notes for the PR: "run `php artisan passport:install`, then `php artisan passport:client --password`".

## What was wrong, checked against master

| # | Baseline did | Reality on master | Impact |
|---|---|---|---|
| 1 | Added a new endpoint | Measurement already ships `/api/v1/rest/measurement` and `/units` (`packages/Webkul/Measurement/src/Routes/measurement-routes.php`), route names `admin.api.measurement.index` / `.show` | Duplicate, divergent endpoint for the same data |
| 2 | `routes/api.php`, prefix `v1` | Package routes are loaded by the package provider under `api` + `v1/rest`. `routes/api.php` is not where any package endpoint lives. | Wrong URL (`/api/v1/...` vs `/api/v1/rest/...`), code outside the package |
| 3 | `app/Http/Controllers/...`, `App\` namespace | Code lives in `packages/Webkul/Measurement/src/...` under `Webkul\Measurement\` | Breaks the Concord package model |
| 4 | Middleware `auth:api` only | Stack is `accept.json, auth:api, throttle:rest-api, api.scope, request.locale` (+ `cache.headers` in core) | No rate limit, no per-key authorization |
| 5 | No `api-acl` entry, unnamed resource routes | `api.scope` is fail-closed: a route with no `api-acl` entry is 403 for every key, `all` keys included | Endpoint dead in production. Had `api.scope` been omitted instead, it would be open to every token. |
| 6 | `Route::apiResource` → `measurement-families.show` | Names must be `admin.api.{entity}.{verb}`; only `*.get` inherits `*.index` permission | Even with ACL entries the names would not match the convention |
| 7 | `MeasurementFamily::query()` in the controller, route-model binding by id | All reads go through repositories (`MeasurementFamilyRepository`); API addresses resources by `code` | Bypasses the repository and proxy-model layer; ids leak |
| 8 | `paginate(per_page)` with no cap; `?code=` ad-hoc filter | List engine `ApiDataSource`: `limit` clamped 1..100, `filters` JSON grammar with registered operators, `search_after` cursor mode | Unbounded page size; filter grammar inconsistent with every other endpoint |
| 9 | `JsonResource::collection` → `{data, links, meta}` | AdminApi lists return `{data, current_page, last_page, total, links}`; the existing Measurement list returns `{success, count, data}` | Third envelope for one domain |
| 10 | `Passport::actingAs(User::factory())` | The API user is `Admin`; tests use `ApiHelperTrait::getAuthenticationHeaders()`, which creates the `api_keys` row `api.scope` needs | Test either fatals (no `User` model) or, fixed to `Admin`, gets 403 and asserts nothing real |
| 11 | No ACL test | Core tests pair a 403 (custom, no permission) with a 200 (custom, with key) per route (`ApiAclTest.php`) | Permission regressions ship silently |
| 12 | `passport:install`, `passport:client --password` | UnoPim ships `unopim:passport:keys` (keys in `storage/app/private/oauth` / `UNOPIM_OAUTH_KEY_PATH`) and `unopim:passport:client --user_name=<admin email>`; real credentials come from Configuration → Integrations | Stock keys land where UnoPim does not read them; a stock client has no `api_keys` row and gets 403 everywhere |
| 13 | No mention of response-cache or BC | Changing the shipped `{success, count, data}` envelope is a breaking change for existing integrators | Silent client breakage |

## Failure classes the skill must prevent

- Not discovering an existing endpoint in the owning package.
- Treating AdminApi as a stock Laravel API (routes file, `apiResource`, `JsonResource::collection`, `actingAs`).
- Missing `api-acl` entries — fail-closed, so the endpoint silently 403s.
- Hand-rolled pagination and filters instead of `ApiDataSource`.
- Stock Passport commands instead of the `unopim:passport:*` pair.
- Changing a shipped envelope without flagging the break.
