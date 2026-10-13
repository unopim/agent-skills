# Authentication, integrations and API permissions

## The request path

Every v1 request passes the stack declared in `packages/Webkul/AdminApi/src/Routes/admin-api.php`, in order:

| Middleware alias | Class | Rejects with |
|---|---|---|
| `accept.json` | `packages/Webkul/AdminApi/src/Http/Middleware/EnsureAcceptsJson.php` | 406 when the `Accept` header excludes JSON |
| `auth:api` | Passport guard `api`, provider `admins` (`config/auth.php`) | 401, missing or expired bearer token |
| `throttle:rest-api` | limiter registered in `AdminApiServiceProvider::registerRateLimiter()` | 429, keyed by user id, `REST_API_RATE_LIMIT` per minute (default 120) |
| `api.scope` | `packages/Webkul/AdminApi/src/Http/Middleware/ScopeMiddleware.php` | 403 `{"error": "This action is unauthorized"}` |
| `request.locale` | `packages/Webkul/AdminApi/src/Http/Middleware/LocaleMiddleware.php` | 422 when a `labels` / `locale_specific` key names an inactive locale |
| `cache.headers:private;etag` | Laravel | 304 on a matching `If-None-Match` |

Aliases are registered in `packages/Webkul/AdminApi/src/Providers/AdminApiServiceProvider.php` (`$middlewareAliases`), along with `api.deprecated`. A plugin route file uses the aliases as they are; it never re-registers them.

## Who the caller is

The API user is an `Admin` (`packages/Webkul/User/src/Models/Admin.php`), not a `User`. Passport's password grant is rebound to admins by `packages/Webkul/AdminApi/src/Repositories/UserRepository.php`. What the caller may do is decided by the admin's `apiKey` relation (`packages/Webkul/AdminApi/src/Models/Apikey.php`, table `api_keys`):

- `permission_type = 'all'` passes every route that has an `api-acl` entry.
- `permission_type = 'custom'` passes a route only when `permissions` (a JSON list) contains the route's key. An empty list denies everything.
- `revoked = true`, or an admin with `status = 0`, denies everything (`packages/Webkul/AdminApi/tests/Feature/RevokedApiKeyScopeTest.php`, `packages/Webkul/AdminApi/tests/Feature/DeactivatedAdminTokenTest.php`).
- No `api_keys` row at all also denies everything.

## `api.scope` resolution — fail-closed

`ScopeMiddleware::getAclForCurrentRoute()` looks the current route name up in `app('api-acl')->roles` (route name → permission key, built from the merged `api-acl` config), then tries the name with `.get` replaced by `.index`. When neither is found, the request is refused **before** the key type is checked.

Consequences:

- A new route with no `api-acl` entry is dead for every client, `all` keys included. A 403 on a brand-new endpoint for a full-access key means a missing entry, nothing else.
- This is the inverse of the admin panel, where a route absent from `acl.php` is open to every logged-in admin (unopim-standards security.md). Do not carry admin-ACL instincts across: there is no `also_authorizes` handling here, and Bouncer is never consulted.
- An unnamed route has no entry by definition. Name every route.
- The `.get` → `.index` fallback is a plain `str_replace`, so it rewrites any `.get` in the name. Prefer explicit entries for nested reads such as `admin.api.attribute_options.get`, as core does.

`app('api-acl')` is built once per process from config — the `createACL()` memo in the provider — so merge your `api-acl` config in `register()`, never lazily during a request.

## Integrations (the normal way to get credentials)

Admin panel: Configuration → Integrations. Routes in `packages/Webkul/AdminApi/src/Routes/integrations-routes.php`, controller `packages/Webkul/AdminApi/src/Http/Controllers/Integrations/ApiKeysController.php`, gated by the admin ACL keys `configuration.integrations.*` in `packages/Webkul/Admin/src/Config/acl.php`.

1. Create an integration. `packages/Webkul/AdminApi/src/Services/ApiUserProvisioner.php` provisions a dedicated robot admin (`type = 'api'`, no role, random 32-character password) and stores the `api_keys` row with the chosen permissions. The username and password are flashed once.
2. Generate a key: a confidential password-grant client owned by the robot. The client id and secret are returned once.
3. The client calls `POST /oauth/token` with `grant_type=password`, `client_id`, `client_secret`, `username` (robot email), `password`. That endpoint is throttled by the `oauth-token` limiter (`OAUTH_TOKEN_RATE_LIMIT`, default 10 per minute per username and IP).
4. Regenerating the secret or the robot password revokes every access token of that client.

The permission tree on the integration edit page is the same `api-acl` config, rendered with each `name` passed through `trans()`. That is why every `name` must be a translation key present in all 33 locales.

## The two console commands

Both live in `packages/Webkul/AdminApi/src/Console/`. Run them through unopim-exec.

| Command | Does | Notes |
|---|---|---|
| `unopim:passport:keys` | Creates the RSA signing pair in `storage/app/private/oauth`, or in `UNOPIM_OAUTH_KEY_PATH` when set | Idempotent and never rotates: rotating invalidates every issued token. The installer (`packages/Webkul/Installer/src/Console/Commands/Installer.php`) and upgrader (`packages/Webkul/Installer/src/Console/Commands/Upgrade.php`) run it, and so does the Docker setup script. It adopts a pair left at the pre-move package path. Exits non-zero when the directory is not writable or OpenSSL fails. |
| `unopim:passport:client --user_name=<admin email> --name=<client name>` | Creates a confidential password-grant client for an existing admin, sets `owner_type`/`owner_id` and the legacy `user_id` column | Prompts for missing options. It does **not** create an `api_keys` row, so the client's tokens authenticate and then get 403 from `api.scope` on every route. Use it for an admin that already has an integration, or create the integration instead. |

Never call Laravel's stock `passport:keys` or `passport:client`. The first writes keys where UnoPim does not read them (`packages/Webkul/AdminApi/src/Services/OauthKeyStore.php` owns the path). The second creates a client without the legacy `user_id` column that the integrations grid (`packages/Webkul/AdminApi/src/DataGrids/Integrations/ApiKeysDataGrid.php`) joins on.

## Configuration

`packages/Webkul/AdminApi/src/Config/api.php`, merged as `api`:

| Env | Default | Effect |
|---|---|---|
| `ACCESS_TOKEN_TTL` / `REFRESH_TOKEN_TTL` | 3600 s | Token lifetimes, applied as relative intervals so they stay correct under Octane |
| `REST_API_RATE_LIMIT` | 120 | Requests per minute per API user |
| `OAUTH_TOKEN_RATE_LIMIT` | 10 | Token requests per minute per username and IP |
| `UNOPIM_OAUTH_KEY_PATH` | `storage/app/private/oauth` | Shared key directory. Point every replica at the same volume. |
| `UNOPIM_API_STRUCTURE_CACHE` / `_TTL` | true / 3600 | List-response cache for structure entities; see [contract.md](contract.md) |

Under several replicas, the keypair must be shared (same `UNOPIM_OAUTH_KEY_PATH` volume). Otherwise a token issued by one node fails signature checks on the next.

## Diagnosing a refusal

| Symptom | Check, in order |
|---|---|
| 406 | Client `Accept` header |
| 401 | Token expired (1 h default), revoked by a secret or password regeneration, or signed by a different keypair (replicas, regenerated keys) |
| 403 on every route | No `api_keys` row (CLI-made client), key revoked, or robot admin deactivated |
| 403 on one route, `all` key | That route name has no `api-acl` entry, or the plugin merged `api-acl` too late |
| 403 on one route, `custom` key | Key lacks the permission. After a permission split, check that the backfill migration ran. |
| 429 | Rate limiter. Tests call `withoutMiddleware(ThrottleRequests::class)` inside the helper. |
