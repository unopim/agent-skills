# With skill — unopim-catalog-model

**Run type:** desk-run, not a live agent session. Same task as [baseline.md](baseline.md), worked by following `skills/unopim-catalog-model/SKILL.md` and its reference files, checked against UnoPim `origin/master` (head `9f4d9d0a`).

## Task

> In our UnoPim package, add a "URL" attribute type so merchants can store a per-locale manufacturer page link on products, validate it, make it filterable in the product grid, and notify our PIM-sync service whenever a product's manufacturer link changes.

## Decision procedure applied

1. **Need a new type?** (SKILL.md step 1, attribute-types.md "Before you add a type".) URL is listed: `text` + `validation = url`. No new type. Report this to the requester instead of building one.
2. **Storage.** Create the attribute, not a column: `code = manufacturer_url`, `type = text`, `validation = url`, `value_per_locale = 1`, `value_per_channel = 0`. Scope flags are fixed at creation (attribute-types.md last section), so decide locale-vs-channel now. Ship it as data: an installer/seed migration or documented admin step, assigned to the families that need it through `AttributeFamilyRepository` so `catalog.attribute_family.attributes.changed` fires.
3. **Where the value lives** (values.md): `values.locale_specific.{locale}.manufacturer_url`; JSON path from `$attribute->getJsonPath(null, $locale)`.
4. **Validation.** Already handled: `Attribute::getValidationRules()` appends `url` to the rules `ProductValuesValidator` applies to that bucket; the admin editor gets `url: true` from `getValidationsField()`.
5. **Editor control.** Already rendered by `dynamic-attribute-fields.blade.php` as a `text` control. No Blade change.
6. **Grid filter.** `text` is covered by the core database `TextFilter` and Elasticsearch `TextFilter`, both tagged in `ProductServiceProvider::registerTags()`, and by the `text` operator group. Works with `elasticsearch.enabled` true and false. No filter code.
7. **Change notification** (events.md). Cover every write path:

```php
Event::listen('catalog.product.update.after', [ManufacturerLinkListener::class, 'afterUpdate']);
Event::listen('catalog.product.create.after', [ManufacturerLinkListener::class, 'afterCreate']);
Event::listen('catalog.product.bulk.edit.after', [ManufacturerLinkListener::class, 'afterBulkEdit']);
Event::listen('data_transfer.imports.batch.product.created.after', [ManufacturerLinkListener::class, 'afterImport']);
Event::listen('data_transfer.imports.batch.product.updated.after', [ManufacturerLinkListener::class, 'afterImport']);
```

   Signatures copied from `packages/Webkul/Webhook/src/Listeners/Product.php`: `afterUpdate(Product $product, bool $isBulkEdit = false)` returning early when `$isBulkEdit`; `afterBulkEdit(array $ids)`; `afterImport(array $ids)`. Each queues a job; none does HTTP inline.
8. **Reading the value in the job.** For each product, `$values = $product->parent_id ? $product->resolvedValues() : $product->values;` then `$attribute->getValueFromProductValues($values, $channel, $locale)`. For id batches use `VariantValueResolver::resolveBatch()` and fall back to own `values` for rows it omits.
9. **Change detection.** Only `update.after` carries a model; compare against the previous value the job stored, not against `getOriginal()` (the event fires after save).

## Result compared with baseline

| Baseline defect | With skill |
|---|---|
| Invented `AttributeTypeEnum` | not needed — `text` + `validation = url` |
| `product_attribute_values` migration | no schema change; one attribute record |
| `attribute_values()` relation | `values.locale_specific.{locale}.{code}` via `Attribute` accessors |
| Flat FormRequest rule | core `ProductValuesValidator` applies the attribute's `url` rule |
| Raw `<input>` | core `text` control |
| `where('values->url')` | core text filters, both search branches |
| `catalog.product.save.after` | real create/update/bulk/import events with correct signatures |
| `$product->values['url']` | `resolvedValues()` + `getValueFromProductValues()` |
| No translations | none required — no new type name; the attribute's label is entered per locale as attribute translation data |
| No Elasticsearch handling | `text` already mapped (`{code}-text`) |

## Verification gate

unopim-verify, plus from SKILL.md: Pest tests for the listener against each payload shape (object, bulk tuple, id list), and a value round-trip in `locale_specific` with `elasticsearch.enabled` both true and false. No Blade or JS change, so the Playwright gate is skipped with the reason stated.

## Residual risk

This is a desk-run. A live run should confirm the agent actually stops at step 1 instead of building the type anyway when the requester insists on a "URL type" by name.
