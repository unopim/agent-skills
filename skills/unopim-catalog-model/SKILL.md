---
name: unopim-catalog-model
description: Use when reading or writing UnoPim product values, adding or changing an attribute type, product type, attribute family, group or association type, working with configurable products, variant groups or variant inheritance, listening to catalog.product.* or catalog.attribute.* events, or reasoning about how channel, locale and currency scoping or completeness react to a catalog change. Trigger phrases include "attribute type", "product type", "product values", "values json", "channel_locale_specific", "value_per_locale", "configurable product", "variant", "variants:resync", "strip-redundant", "attribute family", "association type", "catalog.product.update.after", "completeness".
requires: unopim-standards, unopim-exec, unopim-verify
---

# UnoPim Catalog Model

The catalog is not EAV. Every product is one row in `products` with a single JSON `values` column; attributes, families and groups only describe how that JSON is shaped, validated, rendered, filtered and indexed. A generic-Laravel instinct (a new column, a new table, an `attribute_values` relation, a PHP enum of types) is wrong at every layer here. Read the exemplar before you write.

**REQUIRED BACKGROUND:** unopim-standards for idiom, security, scale, localization and comments. unopim-exec to resolve commands. unopim-verify before calling anything done. Package scaffolding, provider wiring and ACL files: unopim-plugin-development. Import/export of catalog data: unopim-data-transfer. Product grid columns: unopim-datagrid.

## Reference files

| File | Read when |
|---|---|
| [values.md](values.md) | Reading or writing `products.values`, scoping by channel/locale/currency, JSON paths, uniqueness, variant read-time inheritance |
| [attribute-types.md](attribute-types.md) | Adding an attribute type, or deciding you do not need one; every layer a type touches |
| [product-types-variants.md](product-types-variants.md) | `product_types` config, `AbstractType`, configurable / variant_group trees, variant structures, the two variant commands, associations |
| [events.md](events.md) | Hooking a catalog write — which event fires on which path, payload shapes, import and bulk-edit paths that do not fire them |

## Exemplars — copy shape from these

- Values contract and scoping accessors: `packages/Webkul/Attribute/src/Models/Attribute.php`
- Value keys and the update pipeline: `packages/Webkul/Product/src/Type/AbstractType.php`
- A package-owned attribute type, every layer wired: `packages/Webkul/Measurement/src/Providers/MeasurementServiceProvider.php`
- Product type registry: `packages/Webkul/Product/src/Config/product_types.php` + `packages/Webkul/Product/src/Enums/ProductType.php`
- A listener that covers admin, API, bulk-edit and import writes: `packages/Webkul/Webhook/src/Listeners/Product.php`
- Variant inheritance: `packages/Webkul/Product/src/Services/VariantValueResolver.php`

## Decision procedure

1. **Need a new kind of value?** First check whether an existing type plus attribute settings covers it. `text` already accepts `validation` = `number`, `email`, `decimal`, `url` or `regex` (`packages/Webkul/Attribute/src/Rules/ValidationTypes.php`); `select` covers enumerations; `price` covers per-currency amounts. Add a type only when storage shape, editor control, filter semantics or index mapping genuinely differ — then follow [attribute-types.md](attribute-types.md) end to end.
2. **Need a new product type?** Almost never. `simple`, `configurable` and the internal `variant_group` are hard-wired into variant levels, API requests, importers and grids. Read [product-types-variants.md](product-types-variants.md) before proposing one.
3. **Reading a value?** Go through the attribute (`getValueFromProductValues()`, `getJsonPath()`, `getScope()`), and for any product with a `parent_id` read `resolvedValues()`, not `values`. See [values.md](values.md).
4. **Writing a value?** Go through `ProductRepository::update()` → the type's `update()`, never `$product->values = …; save()` from a controller. Variant writes pass `guardVariantLevelWrite()`; skipping it lets a child silently override an axis or an ancestor-owned attribute.
5. **Reacting to a change?** Pick the events from [events.md](events.md) for every write path you must cover — admin and API fire `catalog.product.*`, the product importer fires `data_transfer.imports.batch.product.*`, bulk edit fires `catalog.product.bulk.edit.after`.
6. **Changing what a family contains?** Go through `AttributeFamilyRepository` so `catalog.attribute_family.attributes.changed` fires and completeness settings for removed attributes are pruned.

## Invented API vs real API

| Invented (does not exist) | Real |
|---|---|
| `product_attribute_values` table, `$product->attribute_values()` | one JSON column `products.values`, cast `array` on `packages/Webkul/Product/src/Models/Product.php` |
| `values['global']`, `values['default']`, `values[$locale]` | buckets `common`, `locale_specific`, `channel_specific`, `channel_locale_specific` plus `categories` and `associations` — constants on `AbstractType` |
| `AttributeTypeEnum`, `ProductTypeEnum::Bundle` | `config('attribute_types')`; `Webkul\Product\Enums\ProductType` has exactly `Simple`, `Configurable`, `VariantGroup` |
| validating a type against `AttributeTypes::ATTRIBUTE_TYPES` | the rule validates against `array_keys(config('attribute_types'))`; the constant is stale (no `measurement`) |
| `catalog.product.save.after`, `catalog.attribute_group.update.after` | `catalog.product.update.after`; group update fires `catalog.attribute.group.update.before` then `catalog.attributegroup.update.after` (no dot — core spelling, listen to it as is) |
| changing an attribute's `type` or scope flags after create | `type`, `code`, `value_per_locale`, `value_per_channel`, `is_unique` are dropped from the update payload in `packages/Webkul/Admin/src/Http/Controllers/Catalog/AttributeController.php` — immutable |
| `php artisan unopim:variants:sync`, `--dry-run` | `unopim:variants:resync {--product=} {--all}`; `unopim:variants:strip-redundant {--apply} {--product=}` (dry run is the default) |

## UnoPim-specific pitfalls

- **Portability.** Raw JSON SQL goes through `DB::rawQueryGrammar()->jsonExtract()` — exemplar `packages/Webkul/Measurement/src/Filter/Database/MeasurementFilter.php`. Never hand-write `->>`/`JSON_EXTRACT`. PostgreSQL returns booleans and JSON scalars with different types; compare loosely-typed values the way `ProductRepository::variantValueEquals()` does. Attribute codes reach JSON paths unescaped — accept only `^\w+$` codes (`ProductRepository::isUniqueVariantForProduct()` shows the guard).
- **Prefix.** `DB::table('products')` is prefix-safe; a raw fragment naming the table needs `DB::getTablePrefix()` — see unopim-standards.
- **Elasticsearch optional.** A new attribute type needs a database filter AND an Elasticsearch filter tagged in the container; with neither, `ProductQueryFilter::applyFilter()` throws "No matching filter found". Index mapping is per type suffix (`{code}-{type}`); a type absent from `ProductIndexer::dynamicAttributeMappings()` is dynamically mapped by Elasticsearch from the first value it sees. Reindex with `unopim:product:index --fresh` after shipping a type.
- **Octane / queue workers.** `ElasticSearch\Observers\Product::disable()` and `Completeness\Observers\Product::disable()` flip static flags. Re-enable in `finally`, exactly as `packages/Webkul/DataTransfer/src/Helpers/Importers/Product/Importer.php` does, or every later save in the worker stops indexing and scoring.
- **ACL.** Catalog keys are `catalog.attributes.*`, `catalog.families.*`, `catalog.products.*`, `catalog.association_types.*` in `packages/Webkul/Admin/src/Config/acl.php`. Any new catalog route you add must map to one; enforcement is fail-open by route name — see unopim-plugin-development acl-security.md.
- **Localization.** Attribute-type and product-type `name` values are translation keys; a package-owned type uses its own namespace (`measurement::app.attribute.measurement`) and ships all 33 locales.
- **Scale.** `products` holds millions of rows. Variant maintenance runs `chunkById(200)` and queues completeness; any catalog backfill you write does the same — see unopim-standards scale.md.

## Verification

Run unopim-verify. Catalog-specific checks on top of the six gates:

- Pest covers both `elasticsearch.enabled` branches for any filter, and both MySQL and PostgreSQL for any raw JSON SQL (`phpunit.pgsql.xml`).
- A new attribute type has a test that creates an attribute of that type through `Attribute::factory()`, saves a product value in each of the four scopes, and reads it back — model it on `packages/Webkul/Attribute/tests/Unit/Models/AttributeTest.php`.
- Variant changes: `packages/Webkul/Product/tests/Unit/Models/ResolvedValuesTest.php` and the two command tests under `packages/Webkul/Product/tests/Unit/Console/` still pass.
- Product-form changes are UI changes — run the Playwright gate.
