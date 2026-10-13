# With the skill

**Status: desk-run, not a live session.** Same task as `baseline.md`, re-planned by
following `skills/unopim-ai-agent/SKILL.md` and `tools.md` step by step. Every path
and API named below was checked against UnoPim `origin/master`; the code was not
executed.

## Task

> Add an AI agent chat tool `find_products_missing_attribute` that lists products
> whose value for a given attribute is empty.

## Decision procedure, as followed

1. **Search existing tools.** `DataQualityReport` covers name/description/image/category
   gaps with a fixed list; `SearchProducts` filters by value but not by emptiness.
   Neither takes an arbitrary attribute → a new read tool is justified. Its
   description says "gap reports, not editing" so it does not compete with either.
2. **ACL key.** Read-only catalog data → `catalog.products`, the key the core read
   tools use in `Config/ai-agent.php`.
3. **Class.** `packages/Webkul/AiAgent/src/Chat/Tools/FindProductsMissingAttribute.php`,
   `implements PimTool`, anonymous `ContextualTool`, `use ChecksPermission`, shape
   copied from `DataQualityReport.php`. No constructor dependencies, so nothing is
   captured by the `ToolRegistry` singleton.
4. **Bounded, portable read** (core of `handle()`):

```php
if ($denied = $this->denyUnlessAllowed($this->context, 'catalog.products')) {
    return $denied;
}

$code = $request->string('attribute_code')->toString();
$limit = min(max($request->integer('limit', 20), 1), 100);

if (! preg_match('/^[a-zA-Z0-9_]+$/', $code)) {
    return json_encode(['error' => 'Invalid attribute_code.']);
}

$attribute = DB::table('attributes')
    ->where('code', $code)
    ->first(['code', 'value_per_locale', 'value_per_channel']);

if (! $attribute) {
    return json_encode(['error' => "Attribute '{$code}' not found."]);
}

$path = match (true) {
    $attribute->value_per_locale && $attribute->value_per_channel => ['channel_locale_specific', $this->context->channel, $this->context->locale, $code],
    (bool) $attribute->value_per_locale                           => ['locale_specific', $this->context->locale, $code],
    (bool) $attribute->value_per_channel                          => ['channel_specific', $this->context->channel, $code],
    default                                                       => ['common', $code],
};

$value = GrammarQueryManager::getGrammar()->jsonExtract(DB::getTablePrefix().'p.values', ...$path);

$rows = DB::table('products as p')
    ->whereRaw("COALESCE({$value}, '') = ''")
    ->orderBy('p.id')
    ->limit($limit)
    ->get(['p.id', 'p.sku']);

return json_encode(['result' => [
    'attribute' => $code,
    'scope'     => ['channel' => $this->context->channel, 'locale' => $this->context->locale],
    'total'     => $rows->count(),
    'products'  => $rows->all(),
]]);
```

   - Path resolved per attribute, mirroring `SearchProducts::valuePath()` — `description`
     (seeded `value_per_locale = 1`, `value_per_channel = 1`) is read from
     `channel_locale_specific.{channel}.{locale}`, which the baseline missed.
   - `channel` / `locale` are safe in the path: `ChatContext::__construct()` validates them.
   - Prefix on the alias because Laravel prefixes `products as p`; `COALESCE` is portable.
   - Explicit `orderBy`, clamped `limit`, two columns returned — nothing else leaves
     the database for the model.
   - `valuePath()` is protected inside `SearchProducts`' anonymous class, so it cannot be
     reused directly; the duplication is flagged in the PR as a candidate for a shared
     helper rather than silently copied twice more.
5. **Write tool?** No → `'write' => false`; no `QueuesForApproval`.
6. **Register.** Core change → one line in the `intelligence` block of
   `packages/Webkul/AiAgent/Config/ai-agent.php`:
   `Tools\FindProductsMissingAttribute::class => ['name' => 'find_products_missing_attribute', 'group' => 'intelligence', 'write' => false, 'permission' => 'catalog.products', 'enabled' => true],`.
   Had this been a plugin: `callAfterResolving(ToolRegistry::class, …)` in the plugin
   provider, not `mergeConfigFrom`.
7. **Tests** in `packages/Webkul/AiAgent/tests/Unit/Tools/FindProductsMissingAttributeTest.php`
   (the Unit folder is the only one in a suite), building `ChatContext` like
   `ToolRegistryExtensibilityTest.php` and calling
   `register($context)->handle(new Request([...]))`:
   - denied for a role with explicit permissions lacking `catalog.products`
   - `limit: 5000` returns at most 100
   - `attribute_code: "name' OR 1=1"` returns `error`
   - a product with `description` only under another locale is reported as missing
     for the context locale
   - the tool is absent from `ToolRegistry::build()` for the denied role
   - file added to the source-grep list in `PgsqlCompatibilityTest.php`

## What changed versus the baseline

| Baseline defect | With skill |
|---|---|
| Wrong contract and location | `PimTool` in `packages/Webkul/AiAgent/src/Chat/Tools`, anonymous `ContextualTool` |
| Hallucinated registration | `ai-agent.tools` entry; plugin path via `callAfterResolving` |
| `values->common` only | Path from `value_per_locale` / `value_per_channel` |
| Unvalidated JSON path segment | Regex allow-list + attribute existence check |
| Unbounded `get()`, full models | Clamped limit, `orderBy`, id + SKU only |
| No ACL | `permission` metadata + `denyUnlessAllowed()` |
| Migration folder | Not needed; skill names `Database/Migration/` if it were |
| Test in an unrun folder | `packages/Webkul/AiAgent/tests/Unit/Tools`, run with `--testsuite="AiAgent Unit Test"` |

## Gates that apply

unopim-verify 1 (Pint), 2 (Pest — AiAgent Unit suite; CI runs it on MySQL and
PostgreSQL), 3 (PHPStan), 4 (Rector dry-run), 6 (translations — no new keys, so it
should stay clean). Gate 5 skipped: no widget Blade or JS changed.
