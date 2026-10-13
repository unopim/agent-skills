# Attribute types

Core registry: `packages/Webkul/Attribute/src/Config/attribute_types.php`, merged under the `attribute_types` config key by `packages/Webkul/Attribute/src/Providers/AttributeServiceProvider.php`. The one complete package-owned type in core is `measurement`, wired by `packages/Webkul/Measurement/src/Providers/MeasurementServiceProvider.php` and `packages/Webkul/Measurement/src/Providers/MeasurementEventServiceProvider.php` — copy that package's shape, layer by layer.

## Contents

- Before you add a type
- Core types
- Layers a type touches
- Procedure: add a type from your package
- What core does not let you extend
- Attribute settings that are fixed at creation

## Before you add a type

A type is expensive: it touches nine layers, and three of them have no extension point. First rule out:

| Need | Use instead |
|---|---|
| URL, e-mail, number, decimal, pattern-checked text | `text` + `validation` (`url`, `email`, `number`, `decimal`, `regex` + `regex_pattern`) — `packages/Webkul/Attribute/src/Rules/ValidationTypes.php` |
| Fixed list of choices, swatches | `select` / `multiselect` + `swatch_type` (`packages/Webkul/Attribute/src/Enums/SwatchTypeEnum.php`) |
| Money per currency | `price` |
| Amount with unit | `measurement` |
| Rich text | `textarea` + `enable_wysiwyg` |
| A file with limits | `file` / `image` + `allowed_extensions`, `max_file_size` |

Add a type only when the stored shape, the editor control, filter operators or index mapping differ from all of the above.

## Core types

`text`, `textarea`, `price`, `boolean`, `select`, `multiselect`, `datetime`, `date`, `image`, `gallery`, `file`, `checkbox` — plus `measurement` from the Measurement package. Type constants live on `packages/Webkul/Attribute/src/Models/Attribute.php` (`TEXT_TYPE`, `PRICE_FIELD_TYPE`, …, `MEASUREMENT_FIELD_TYPE`).

Type validation (`packages/Webkul/Attribute/src/Rules/AttributeTypes.php`) checks `array_keys(config('attribute_types'))`. Its `ATTRIBUTE_TYPES` constant is a stale list (no `measurement`, nothing a package adds); core only indexes into it for `text`/`textarea` in the Elasticsearch `TextFilter`. Never validate or branch a type against it.

## Layers a type touches

| # | Layer | Mechanism | Measurement exemplar |
|---|---|---|---|
| 1 | Registry | `mergeConfigFrom(<your>/Config/attribute_types.php, 'attribute_types')` with `key` + translated `name` | `packages/Webkul/Measurement/src/Config/attribute_types.php` |
| 2 | Attribute settings UI | listen to view render event `unopim.admin.catalog.attributes.edit.card.label.after`, add a template | `packages/Webkul/Measurement/src/Resources/views/catalog/attributes/edit.blade.php` |
| 3 | Per-attribute config storage | own table + listeners on `catalog.attribute.update.before` (validate) and `.after` (persist) | `packages/Webkul/Measurement/src/Listeners/ValidateAttributeMeasurementBeforeUpdate.php`, `packages/Webkul/Measurement/src/Listeners/SaveAttributeMeasurementAfterUpdate.php` |
| 4 | Product editor control | view render event `unopim.admin.products.dynamic-attribute-fields.control.{type}.before` | `packages/Webkul/Measurement/src/Resources/views/catalog/products/edit.blade.php` |
| 5 | Value normalisation / derived data | Eloquent observer on the product (`saving`) | `packages/Webkul/Measurement/src/Observers/ProductObserver.php` |
| 6 | Display formatting (grids, exports) | register a normalizer in `AttributeNormalizerFactory` | `packages/Webkul/Measurement/src/Services/Normalizers/MeasurementNormalizer.php` |
| 7 | Database filter | class extending `AbstractDatabaseAttributeFilter`, tagged `unopim.database.attribute.filters` | `packages/Webkul/Measurement/src/Filter/Database/MeasurementFilter.php` |
| 8 | Elasticsearch filter | class tagged `unopim.elasticsearch.attribute.filters` | `packages/Webkul/Measurement/src/Filter/ElasticSearch/MeasurementFilter.php` |
| 9 | Filter operators in the grid UI | `replaceConfigRecursivelyFrom(<your>/Config/product_filter_operators.php, 'product_filter_operators')` with a group listing your type | `packages/Webkul/Measurement/src/Config/product_filter_operators.php` |

Core's own groups and defaults are in `packages/Webkul/Admin/src/Config/product_filter_operators.php`; the core filter tags are in `packages/Webkul/Product/src/Providers/ProductServiceProvider.php` (`registerTags()`).

## Procedure: add a type from your package

1. Confirm the "Before you add a type" table does not already cover it. Write down the stored shape (scalar string, list, or keyed object) — it decides layers 5–8.
2. Register the type (layer 1). The `name` is a translation key in your package namespace; add it to `en_US` and all 33 locales.
3. If the type needs per-attribute settings, add a migration for your own table (bare name, `src/Database/Migrations/`), a model with proxy and contract, a repository, and the two attribute-update listeners (layer 3). Register them in your event provider like `MeasurementEventServiceProvider`.
4. Render the product control (layer 4) with `x-admin::` form components — see unopim-standards for the admin UI rules. The core `@default` branch in `packages/Webkul/Admin/src/Resources/views/components/products/dynamic-attribute-fields.blade.php` still renders `x-admin::form.control-group.control` with your type name; check what that emits for an unknown type before relying on it.
5. Validate and normalise the value in a product observer (layer 5) — `Attribute::fieldTypeValidations()` is a closed `switch`, so a package type gets only the generic `required` / `unique` / `validation` rules from core. Throw `ValidationException` for bad input, as the Measurement observer does. Remember `processValues()` drops falsy values (see [values.md](values.md)).
6. Register a normalizer (layer 6). Core exposes no setter; the Measurement provider uses `$this->app->extend(AttributeNormalizerFactory::class, …)` with a bound closure to add `$normalizers['measurement']`. Copy that exactly; do not subclass or rebind the factory.
7. Ship BOTH filters (layers 7 and 8) and tag them in `register()`. `packages/Webkul/Product/src/Filter/FilterManager.php` picks the tag by `elasticsearch.enabled`, and `packages/Webkul/Product/src/Traits/ProductQueryFilter.php` throws "No matching filter found" when nothing supports the type. Raw JSON SQL uses `DB::rawQueryGrammar()->jsonExtract()`; bind every value.
8. Add the operator group (layer 9) so the product grid offers the right operators and controls.
9. Elasticsearch mapping: the indexer stores your value under `{code}-{type}`; `ProductIndexer::dynamicAttributeMappings()` in `packages/Webkul/ElasticSearch/src/Console/Command/ProductIndexer.php` maps only `text`, `textarea`, `price`, `datetime`, `date` explicitly, so your type is mapped by Elasticsearch from the first document it sees. Make the stored shape stable (always an object, or always a string) and document `php artisan unopim:product:index --fresh` in the release note.
10. Completeness counts a value as present when `! empty($value)` (`packages/Webkul/Completeness/src/Jobs/ProductCompletenessJob.php`). If an empty value of your type is a non-empty structure (e.g. `{"unit": "KG", "amount": null}`), strip it in the observer or completeness will score it filled.
11. Tests: attribute creation through the API request (`packages/Webkul/AdminApi/src/Http/Requests/Catalog/StoreAttributeRequest.php` validates the type), a value in each scope, both filter branches, the normalizer, and the observer's rejection path. Models: `packages/Webkul/Measurement/tests/Feature/MeasurementApiEndpointsTest.php`, `packages/Webkul/Attribute/tests/Unit/Services/AttributeNormalizerFactoryTest.php`.

## What core does not let you extend

These are hard-coded on master. A new type silently falls into the default branch; changing them means a core PR, not a package override.

| Place | Default for an unknown type |
|---|---|
| `Attribute::fieldTypeValidations()` | no type-specific rule |
| `Attribute::getFilterType()` | `string` |
| `packages/Webkul/Admin/src/Resources/views/components/bulkedit/cell.blade.php` `getComponentType()` | `v-spreadsheet-text` (only `measurement` is special-cased) |
| `ProductIndexer::dynamicAttributeMappings()` | Elasticsearch dynamic mapping |
| Product importer / exporter (`packages/Webkul/DataTransfer/src/Helpers/Importers/Product/Importer.php`) | treated as a scalar cell; `measurement` is special-cased — see unopim-data-transfer |
| `AttributeFamily::ALLOWED_VARIANT_OPTION_TYPES` | cannot be a variant axis (only `select`) |

## Attribute settings that are fixed at creation

`packages/Webkul/Admin/src/Http/Controllers/Catalog/AttributeController.php` strips `type`, `code`, `value_per_locale`, `value_per_channel` and `is_unique` from update requests. A feature that needs to "change an attribute's type" or its scope is a data migration (new attribute, copy values across buckets in chunks, reindex), never an update call.

Attributes are audited (`HistoryTrait`, presenters in `packages/Webkul/Attribute/src/Presenters/AttributeHistoryPresenter.php`, which reads `config("attribute_types.{type}")` to label the type). A type removed from config after attributes exist breaks that history label and the create-time type validation — never unregister a type that may have data.
