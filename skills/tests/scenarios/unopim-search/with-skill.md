# With skill — unopim-search loaded

**Nature of this record:** a desk-run of the same task as [baseline.md](baseline.md), following `skills/unopim-search/SKILL.md` and its reference files step by step. Paths were verified against UnoPim `origin/master`; no live agent session or cluster was used.

## Task

Same as the baseline: an *Updated at* range filter that works with Elasticsearch on, and nightly SQL-synced products that must be correct in search.

## Step 1 — classify (SKILL.md "Decision procedure")

Two requests:

- Filter by something → filters.md. The skill says to check `registerTags()` first. `DateTimeFilter` is tagged in both property tags and supports `updated_at` with `RANGE`. The grid exposes it through `ProductPropertyFilters::UPDATED_AT` as a `date_range` column, offered by "Add Filter".
- "Not correct in search" → indexing.md "Why a write is not visible".

**Result: no new filter class.** The first request is already met on master; the deliverable is a regression test proving it on both branches.

## Step 2 — diagnose the sync (indexing.md)

- The sync writes with SQL → the product observer never fires (Eloquent events only).
- The incremental `unopim:product:index` re-sends only rows whose `updated_at` differs from the indexed one. The sync does not touch `updated_at` → those rows are skipped even after a nightly reindex.

Fix, in the sync job (repository/`DB::table()` per unopim-standards, chunked per scale.md):

```php
DB::table('products')
    ->whereIn('id', $chunkIds)
    ->update([
        'values'     => ...,
        'updated_at' => now(),
    ]);
```

then, after the sync finishes, schedule the incremental indexer:

```php
Schedule::command('unopim:product:index')->dailyAt('03:30')->withoutOverlapping();
```

Rejected alternatives the skill rules out: `scout:import` (does not exist), `--fresh` every night (drops the index; the grid shows a partial catalogue while it rebuilds, and it is unnecessary once `updated_at` moves), per-product `ElasticSearch::index()` calls in a loop (two HTTP round-trips per row, see "Cost of a facade call"). The indexer is a no-op exiting 0 when `ELASTICSEARCH_ENABLED` is false — correct for ES-off installs, and why the schedule needs no guard of its own.

## Step 3 — tests on both branches (filters.md "Tests")

New file ProductUpdatedAtFilterTest.php in the Admin package Feature/Catalog tests, shaped like `ProductMediaEmptinessFilterTest.php`:

```php
describe('elasticsearch', function () {
    beforeEach(function () {
        config([
            'elasticsearch.enabled'                     => true,
            'elasticsearch.prefix'                      => 'testing',
            'elasticsearch.connection'                  => 'default',
            'elasticsearch.connections.default.hosts.0' => 'testhost:9200',
        ]);

        ElasticSearch::shouldReceive('makeConnection')
            ->andReturn(Mockery::mock('Webkul\ElasticSearch\Client\Fake\FakeElasticClient'));

        $this->loginAsAdmin();
    });

    it('sends updated_at as a range clause', function () {
        ElasticSearch::shouldReceive('search')
            ->once()
            ->withArgs(function ($args) {
                $filters = $args['body']['query']['constant_score']['filter']['bool']['filter'] ?? [];

                expect(collect($filters)->pluck('range')->filter()->keys())->not->toBeEmpty();

                return true;
            })
            ->andReturn(['hits' => ['hits' => [], 'total' => ['value' => 0]]]);

        $this->withHeaders(['X-Requested-With' => 'XMLHttpRequest'])
            ->json('GET', route('admin.catalog.products.index'), [
                'filters' => ['updated_at' => [['2026-01-01', '2026-01-31']]],
            ])
            ->assertOk();
    });
});

describe('database', function () {
    beforeEach(function () {
        config(['elasticsearch.enabled' => false]);
        $this->loginAsAdmin();
    });

    it('returns only products updated inside the range', function () {
        $inside = Product::factory()->create(['updated_at' => '2026-01-15 10:00:00']);
        Product::factory()->create(['updated_at' => '2026-03-01 10:00:00']);

        $this->withHeaders(['X-Requested-With' => 'XMLHttpRequest'])
            ->json('GET', route('admin.catalog.products.index'), [
                'filters' => ['updated_at' => [['2026-01-01', '2026-01-31']]],
            ])
            ->assertOk()
            ->assertJsonPath('records.0.sku', $inside->sku)
            ->assertJsonCount(1, 'records');
    });
});
```

The exact request shape for a `date_range` filter and the record JSON keys must be read from `ProductDataGrid::getOperatorAndValue()` and an existing grid test before running — the snippet is the structure, not a verified payload. `->once()` is kept so a missing ES filter (grid silently falling back to the database) fails the ES test. Plus a unit test for the sync job asserting it sets `updated_at`.

## Step 4 — verification (SKILL.md "Verification")

- unopim-exec first: no cluster on the workstation → `PEST_ENV` carries `ELASTICSEARCH_ENABLED=false`; the ES `describe` block sets its own config and mocks the facade, so it still runs.
- unopim-verify: pint, pest (MySQL and the PostgreSQL suite — the DB block compares timestamps), phpstan, rector-dry, translations (no new strings), Playwright skipped with the reason stated (no view/JS change).
- PR description notes: "No mapping change. Operators: none required; the nightly schedule runs the incremental indexer after the sync."

## Delta from the baseline

| Baseline | With skill |
|---|---|
| Scout installed, second index | No new dependency; core indexer and observer |
| New duplicate filter class | Existing `DateTimeFilter` pair reused, regression-tested |
| Rows rendered from hits | Grid contract untouched (ids from ES, rows from DB) |
| Sync products still stale | Root cause fixed: `updated_at` bumped, incremental indexer scheduled |
| Live-cluster flaky test, ES only | Mocked-facade ES test plus a real-row DB test over the same filter |
