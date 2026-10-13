# Baseline — unopim-catalog-model (without the skill)

**Run type:** desk-run, not a live agent session. The plan below was written from generic Laravel / Bagisto knowledge BEFORE reading UnoPim catalog code, then checked line by line against UnoPim `origin/master` (head `9f4d9d0a`). It records what an agent without this skill would plausibly produce.

## Task

> In our UnoPim package, add a "URL" attribute type so merchants can store a per-locale manufacturer page link on products, validate it, make it filterable in the product grid, and notify our PIM-sync service whenever a product's manufacturer link changes.

## Plan produced without the skill

1. Add `case Url = 'url';` to an `AttributeTypeEnum` in a new file Attribute/src/Enums/AttributeTypeEnum.php (invented path).
2. Migration: add a nullable `url_value` column to `product_attribute_values` (EAV, as in Bagisto).
3. Store with `$product->attribute_values()->create(['attribute_id' => $id, 'locale' => $locale, 'channel' => null, 'url_value' => $url])`.
4. Validation: add `'url' => 'url'` to the product FormRequest rules.
5. Product edit form: add `<input type="url" name="url_value">` to the product edit Blade.
6. Grid filter: `Product::where('values->url', $value)` in a scope.
7. Sync hook: `Event::listen('catalog.product.save.after', SyncManufacturerLink::class)` reading `$product->values['url']`.
8. Tests: a feature test posting the form and asserting the `product_attribute_values` row.

## What was wrong against UnoPim master

| # | Baseline step | Reality on master | Severity |
|---|---|---|---|
| 1 | `AttributeTypeEnum` | Does not exist. Types are `config('attribute_types')` (`packages/Webkul/Attribute/src/Config/attribute_types.php`); the only enum in that folder is `SwatchTypeEnum`. Fatal: class not found. | blocker |
| 1 | a new type at all | `text` already supports `validation = url` (`packages/Webkul/Attribute/src/Rules/ValidationTypes.php`), rendered and validated by `Attribute::getValidationRules()` / `getValidationsField()`. The whole type was unnecessary. | design |
| 2 | `product_attribute_values` table | No such table. Values live in one JSON column `products.values`. Migration targets a table that does not exist. | blocker |
| 3 | `attribute_values()` relation, `locale`/`channel` columns | No relation. Per-locale values go in `values.locale_specific.{locale}.{code}`, decided by the attribute's `value_per_locale` flag. | blocker |
| 4 | FormRequest rule `'url' => 'url'` | Product values are validated by `packages/Webkul/Product/src/Validator/ProductValuesValidator.php` composing per-scope validators with rules from the attribute; a flat rule on a top-level `url` key never sees the nested value. | silent no-op |
| 5 | raw `<input>` in the edit Blade | Product controls render in `packages/Webkul/Admin/src/Resources/views/components/products/dynamic-attribute-fields.blade.php` from the attribute type; extensions use view-render events. Raw input also fails the RAW_FORM_CONTROL hook. | wrong file + hook fail |
| 6 | `where('values->url', …)` | Wrong JSON path (missing scope and locale) and bypasses the filter system. Grid filtering goes through tagged database AND Elasticsearch filters; a type with neither throws "No matching filter found" (`packages/Webkul/Product/src/Traits/ProductQueryFilter.php`). | runtime exception |
| 7 | `catalog.product.save.after` | Not an event. Real: `catalog.product.update.after` (payload `Product`, or `(Product, true)` from bulk edit) — plus import writes fire only `data_transfer.imports.batch.product.*`. The listener would never run; with the right name it would still miss imports and bulk edit. | silent no-op |
| 7 | `$product->values['url']` | Wrong path; and for a variant the value may be inherited — must read `resolvedValues()`. | wrong data |
| 8 | test asserts EAV row | Asserts a table that does not exist. | test invalid |
| — | (missing) translations | A new type's `name` is a translation key needing 33 locales. Not mentioned. | gate fail |
| — | (missing) Elasticsearch | No mention of ES filter, `{code}-{type}` index keys, or reindex. | ES installs broken |

## Failure summary

Generic EAV assumptions produced a plan where every storage, validation and event step is either fatal or a silent no-op, and it built a type the platform already provides as a validation option. The skill must: (1) state the JSON `values` contract and its bucket keys, (2) force the "do you need a type at all" check, (3) list every layer a real type touches with the Measurement exemplar, and (4) give the real event names, payloads and the write paths that skip them.
