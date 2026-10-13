# Product values

Contract source: `packages/Webkul/Attribute/src/Models/Attribute.php` (scope accessors) and `packages/Webkul/Product/src/Type/AbstractType.php` (key constants, write pipeline). Inheritance: `packages/Webkul/Product/src/Services/VariantValueResolver.php`.

## Contents

- The JSON shape
- Which bucket an attribute lives in
- Per-type value shapes
- Reading a value
- Writing a value
- Querying by value (SQL and Elasticsearch)
- Uniqueness
- Variant read-time inheritance

## The JSON shape

`products.values` is one JSON column, cast `array` on the model. Top-level keys are the `AbstractType` constants:

```json
{
  "common":                  { "sku": "TS-01", "color": "red", "price": { "USD": "19.90", "EUR": "18.50" } },
  "locale_specific":         { "en_US": { "name": "T-shirt" }, "fr_FR": { "name": "Tee-shirt" } },
  "channel_specific":        { "default": { "status_note": "live" } },
  "channel_locale_specific": { "default": { "en_US": { "description": "<p>Soft</p>" } } },
  "categories":              ["summer", "men"],
  "associations":            { "related_products": ["TS-02"], "up_sells": [], "cross_sells": [] }
}
```

| Constant | Key |
|---|---|
| `COMMON_VALUES_KEY` | `common` |
| `LOCALE_VALUES_KEY` | `locale_specific` |
| `CHANNEL_VALUES_KEY` | `channel_specific` |
| `CHANNEL_LOCALE_VALUES_KEY` | `channel_locale_specific` |
| `CATEGORY_VALUES_KEY` | `categories` (category codes) |
| `ASSOCIATION_VALUES_KEY` | `associations` (sections `related_products`, `up_sells`, `cross_sells`) |

Use the constants, never string literals, in new code. `sku` always lives in `common` — `AbstractType::create()` seeds it there.

Channel and locale keys are codes (`default`, `en_US`), not ids. A value under a locale the channel does not enable is rejected by `packages/Webkul/Product/src/Validator/ChannelLocaleValuesValidator.php`; resolve a channel's locales and currencies through `packages/Webkul/Core/src/Repositories/ChannelRepository.php`, not by hard-coding.

## Which bucket an attribute lives in

Decided by two booleans on the attribute, fixed at creation (the admin update strips them):

| `value_per_locale` | `value_per_channel` | Bucket | `getJsonPath()` |
|---|---|---|---|
| 0 | 0 | `common` | `common->{code}` |
| 1 | 0 | `locale_specific.{locale}` | `locale_specific->{locale}->{code}` |
| 0 | 1 | `channel_specific.{channel}` | `channel_specific->{channel}->{code}` |
| 1 | 1 | `channel_locale_specific.{channel}.{locale}` | `channel_locale_specific->{channel}->{locale}->{code}` |

Never re-derive this table. Call the attribute: `getValueFromProductValues()`, `setProductValue()`, `getJsonPath()`, `getScope()`, `getFlatAttributeName()`, `getAttributeInputFieldName()`, `isLocaleBasedAttribute()`, `isChannelBasedAttribute()`.

Variant axes (`super_attributes`) must be `common`: `AttributeFamily::getConfigurableAttributes()` only offers `select` attributes with both flags off (`ALLOWED_VARIANT_OPTION_TYPES` in `packages/Webkul/Attribute/src/Models/AttributeFamily.php`).

## Per-type value shapes

| Type | Stored as |
|---|---|
| `text`, `textarea`, `date` (`Y-m-d`), `datetime` (`Y-m-d H:i:s`) | string; WYSIWYG `textarea` is HTML-purified on write |
| `boolean` | string `"true"` / `"false"`, validated by `packages/Webkul/Core/src/Rules/BooleanString.php` |
| `select` | option code string |
| `multiselect`, `checkbox` | comma-joined option codes (`"red,blue"`) — `processValues()` implodes list arrays |
| `price` | object keyed by currency code (`{"USD": "19.90"}`); common prices merge per currency on update (`processCommonPriceValues()`) |
| `image`, `file` | storage path under `product/{id}/{code}/` |
| `gallery` | list of storage paths |
| `measurement` | object `{unit, amount, family, base_data, base_unit, symbol}` — filters compare `base_data` |

`processValues()` runs `array_filter()` with no callback over the submitted values, so `''`, `null`, `'0'`, `0` and `false` are dropped rather than stored. A type whose legitimate value can be falsy must store a string representation that survives that filter.

## Reading a value

- Single product, attribute model in hand: `$attribute->getValueFromProductValues($product->values, $channel, $locale)`.
- Product with `parent_id` (variant or variant group): read `$product->resolvedValues()` — own `values` holds only overrides.
- Many rows (grids, exports, indexers): `resolve(VariantValueResolver::class)->resolveBatch($rows)` — one ancestor query per depth instead of one per row. Rows without a parent are omitted from the result; fall back to the row's own `values`.
- Display formatting per type: `AttributeNormalizerFactory::getNormalizer($type)->normalize($value, $attribute, ['format' => 'datagrid', ...])` — `packages/Webkul/Attribute/src/Services/AttributeNormalizerFactory.php`.

## Writing a value

Route every write through `packages/Webkul/Product/src/Repositories/ProductRepository.php`:

| Call | Use for |
|---|---|
| `update($data, $id)` | form-shaped payload; runs `prepareProductValues()` (merge with stored values, file storage, purification, price merge) |
| `updateWithValues($data, $id)` | an already-complete `values` array (API, AI agent, connectors) |
| `updateStatus()` / `massUpdateStatus()` | status only; mass variant wraps a transaction and defers `after` events until commit |

`prepareProductValues()` processes only the **requested** channel and locale (`core()->getRequestedChannelCode()` / `getRequestedLocaleCode()`) for the three scoped buckets; other channels or locales in the payload are ignored. To write several locales in one call, pass `$currentLocaleCode` / `$currentChannelCode` per call or use `updateWithValues()`.

Validate before writing with the product validators in `packages/Webkul/Product/src/Validator/` — `ProductValuesValidator` composes `CommonValuesValidator`, `LocaleValuesValidator`, `ChannelValuesValidator`, `ChannelLocaleValuesValidator`; per-attribute rules come from `Attribute::getValidationRules()`.

## Querying by value

- **Database branch.** Use the attribute filters (`packages/Webkul/Product/src/Filter/Database/`) via `ProductQueryBuilderFactory` rather than hand-written JSON SQL. If you must write raw JSON SQL, build the path with `DB::rawQueryGrammar()->jsonExtract(...)` (`packages/Webkul/Core/src/Helpers/Database/Grammars/MySQLGrammar.php`, `packages/Webkul/Core/src/Helpers/Database/Grammars/PostgresGrammar.php`) so MySQL, MariaDB and PostgreSQL all work.
- **Elasticsearch branch.** The indexer renames each attribute key to `{code}-{type}` (`packages/Webkul/ElasticSearch/src/Indexing/Normalizer/ProductNormalizer.php`), and variants are indexed with their resolved values. Query field names must carry that suffix.
- Both branches must return the same ids, order and pagination — `packages/Webkul/Product/src/Factories/ProductQueryBuilderFactory.php` picks the branch.

## Uniqueness

`is_unique` attributes get `unique:products,values->{jsonPath}` on the database branch and `packages/Webkul/Product/src/Validator/Rule/Elasticsearch/UniqueAttributeValue.php` on the Elasticsearch branch. The `sku` check is separate (`packages/Webkul/Core/src/Rules/Sku.php`). Variant-axis uniqueness under one parent is `ProductRepository::isUniqueVariantForProduct()`, which rejects attribute codes outside `[A-Za-z0-9_]` before they reach a JSON path.

## Variant read-time inheritance

A child stores only what differs from its ancestors. `VariantValueResolver::mergeChain()` walks root → leaf:

- `common`: `array_merge`, descendant wins by key presence.
- `locale_specific` / `channel_specific` / `channel_locale_specific`: merged per scope key at their depth, descendant wins.
- `categories`: the deepest node that has the key wins.
- `associations` and anything else: taken from the leaf unchanged.

The interface docblock in `packages/Webkul/Product/src/Contracts/VariantValueResolver.php` still says non-common scopes come from the leaf only — the implementation above is authoritative.

Writes to a child go through `ProductRepository::guardVariantLevelWrite()`: a submitted `common` value for an attribute the variant structure places at another level must equal the inherited value, or the save throws `ValidationException` (`immutable`). Own-level axis renames run a locked uniqueness check. Calling `$variant->save()` directly bypasses both.

Legacy children that copied every parent value can be cleaned with `unopim:variants:strip-redundant` — see [product-types-variants.md](product-types-variants.md).
