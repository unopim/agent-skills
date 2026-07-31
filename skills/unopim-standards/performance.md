# Performance

Keep request work minimal: no repeated queries, no recomputed aggregates, no
state that outlives its request. Scale-of-data rules (chunking, cursors,
indexes) live in [scale.md](scale.md).

## Eager loading

Eager load every relationship the code path traverses, with nested relation
arrays where needed — exemplar
`packages/Webkul/Product/src/Repositories/ProductRepository.php` and
`packages/Webkul/Product/src/Repositories/ProductAssociationRepository.php`.
A lazy load inside a loop is an N+1 and a review blocker.

No hook can see that a lazy load sits inside a loop — grep-gate matches single
added lines, with no block or scope awareness, so `$row->relation->name` is
indistinguishable from a correct eager-loaded read. The same limit applies to a
missing eager load, to a fluent `->get()` whose table is named four lines up,
and to a controller looping the catalogue instead of dispatching a job. N+1 is
caught by review (skills/unopim-code-review section 5), never by an exit code:
treat it as a mandatory self-check before claiming a change is done. What IS
hook-blocked here is narrow and worth knowing so you do not assume the rest is
covered: `select('*')`, `Model::all()`, and `$someRepository->all()`.

## No query in loops or Blade

Queries live in repositories, resolved before the view renders. A query inside
a `foreach` becomes a chunked `whereIn` preload; a query inside a Blade partial
moves to the controller/composer. Never call a repository or `DB::` from a view.

## Cache expensive aggregates

`Cache::remember` with a named key and a class-constant TTL — exemplar
`packages/Webkul/Admin/src/Helpers/Dashboard.php`:

```php
public function getTotalCatalogs(): array
{
    return Cache::remember('dashboard.total_catalogs', self::CACHE_TTL, function () {
        return [
            'totalCategories' => $this->category->getTotalCategories(),
            'totalProducts'   => $this->productReporting->getTotalProducts(),
        ];
    });
}
```

Invalidate by key when the underlying data changes; never cache per-user data
under a shared key.

## Per-request memoization: `RequestMemo`, never statics

Within-request reuse goes through the scoped
`packages/Webkul/Core/src/RequestMemo.php` — fresh for every HTTP request
(including under Octane) and reset between queue jobs. Memoizing in a static
property or a singleton's field is an Octane leak: the value survives into the
next admin's request.

## Container bindings: the decision table

This stack runs Octane (`laravel/octane ^2.3`). A singleton outlives the
request, so the binding choice is a correctness decision, not a style one.
Exemplar: `packages/Webkul/Core/src/Providers/CoreServiceProvider.php` binds
`CatalogScope`, `RequestMemo` and the locales helper `scoped()`;
`packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php` scopes its
credential-configured services;
`packages/Webkul/Webhook/src/Providers/WebhookServiceProvider.php` keeps its
stateless `EventRegistry` a singleton.

| Binding | Use for | Never for |
|---|---|---|
| `scoped()` | Anything holding per-request state: catalog scope, per-credential API clients, request memos | — |
| `singleton()` | Genuinely stateless, process-global infra: registries, factories, pure helpers | Anything a request mutates or configures |
| `bind()` | State that must not survive same-request mutation — each resolve gets a fresh instance | Heavy objects resolved many times per request |

**Bad:** `$this->app->singleton(ApiClient::class)` followed by
`$client->configure($credential)` per request — under Octane this answers the
next request with the previous admin's credentials. **Good:**
`$this->app->scoped(ApiClient::class)`.

## Narrow the work

- `select()` only the columns the code reads; no `SELECT *` in DataGrid
  builders or bulk scans.
- Push filtering, sorting and aggregation into SQL — never fetch a Collection
  and filter it in PHP.
- Anything heavier than one batch of records leaves the request: see the
  queued-job rules in [scale.md](scale.md).
