# Catalog events

Event names are dispatched as strings from controllers, repositories and type classes — there is no event class to type-hint. Payloads differ by write path. Read this table before writing a listener, and cover every path your feature cares about.

Full-coverage exemplar: `packages/Webkul/Webhook/src/Providers/EventServiceProvider.php` + `packages/Webkul/Webhook/src/Listeners/Product.php` (admin, API, bulk edit and import, each with the right signature).

## Contents

- How payloads reach your listener
- Product events
- Attribute, option, group and family events
- Association type events
- Writes that fire no catalog.product event
- Eloquent observers on Product
- Listener rules

## How payloads reach your listener

`Event::dispatch($name, $payload)`: an object payload arrives as the single argument; an array payload is spread positionally by its values (keys are ignored). So `['data' => $added, 'removed' => $removed, 'family_id' => $id]` reaches `handle(array $added, array $removed, int $familyId)` — see `packages/Webkul/Completeness/src/Listeners/HandleFamilyAttributeChanges.php`.

## Product events

| Event | Payload | Dispatched from |
|---|---|---|
| `catalog.product.create.before` | none | `packages/Webkul/Admin/src/Http/Controllers/Catalog/ProductController.php`; API `SimpleProductController`, `ConfigurableProductController` |
| `catalog.product.create.after` | `Product` | same; also `packages/Webkul/Product/src/Type/Configurable.php` for every variant / variant group it creates, and API `ProductController` |
| `catalog.product.update.before` | product **id** | admin and API controllers; `ProductRepository::massUpdateStatus()` |
| `catalog.product.update.after` | `Product` — or `(Product, true)` from bulk edit | admin controller (only when `$product->wasDirtyOnUpdate`); API controllers; `ProductRepository::massUpdateStatus()`; `packages/Webkul/DataTransfer/src/Jobs/System/BulkProductUpdate.php` |
| `catalog.product.bulk.edit.after` | `['ids' => int[]]` → `(array $ids)` | `BulkProductUpdate` once per job |
| `catalog.product.delete.before` / `.after` | product **id** from admin and `ProductRepository::massDelete()`; **SKU string** from the API controllers | admin `ProductController`, `packages/Webkul/Product/src/Repositories/ProductRepository.php`, API `SimpleProductController` / `ConfigurableProductController` |

Consequences:

- A `delete` listener must accept `int|string` and resolve either way — or it breaks on the API path.
- An `update.after` listener declares `(Product $product, bool $isBulkEdit = false)`, as `Webkul\Webhook\Listeners\Product::afterUpdate()` does, and decides whether to skip per-product work during bulk edit (the bulk event follows).
- `massDelete()` / `massUpdateStatus()` wrap the loop in `Event::defer(..., ['catalog.product.*.after'])` inside a transaction: `after` listeners run only once the transaction commits. Do the same in any multi-product writer you add, so listeners never queue work against rows that may roll back.
- `catalog.product.update.before` is a veto point: `packages/Webkul/ProductPassport/src/Providers/ProductPassportServiceProvider.php` attaches a GTIN validator there; `catalog.product.delete.before` is used to block deletion in `packages/Webkul/Publication/src/Providers/PublicationServiceProvider.php`. Throwing from a `before` listener aborts the write.

## Attribute, option, group and family events

| Event | Payload | Notes |
|---|---|---|
| `catalog.attribute.create.before` / `.after` | none / `Attribute` | admin `AttributeController`, API `AttributeController` |
| `catalog.attribute.update.before` / `.after` | id / `Attribute` | Measurement validates its per-attribute settings in `.before` and persists them in `.after` |
| `catalog.attribute.delete.before` / `.after` | id | also fired per id by mass delete |
| `catalog.attribute.option.{create,update,delete}.{before,after}` | see `packages/Webkul/Admin/src/Http/Controllers/Catalog/AttributeOptionController.php` and `packages/Webkul/Attribute/src/Repositories/AttributeOptionRepository.php` | |
| `catalog.attribute.group.create.before` / `.after` | | |
| `catalog.attribute.group.update.before` | id | |
| `catalog.attributegroup.update.after` | `AttributeGroup` | core spelling — no dot between `attribute` and `group`. Listen to this exact name; do not "fix" it in a listener |
| `catalog.attribute.group.delete.before` / `.after` | id | |
| `catalog.attribute_family.{create,update,delete}.{before,after}` | none or id / `AttributeFamily` | admin `AttributeFamilyController` |
| `catalog.attribute_family.attributes.changed` | `['data' => added codes, 'removed' => removed codes, 'family_id' => id]` | from `packages/Webkul/Attribute/src/Repositories/AttributeFamilyRepository.php` only when the set changed; completeness prunes settings here |
| `catalog.attribute_family.copied` | `[family, source]` → `(AttributeFamily $family, AttributeFamily $source)` | dispatched inside the copy transaction in `AttributeFamilyRepository`; core copies the variant structure (`packages/Webkul/Product/src/Listeners/CopyVariantStructure.php`) |

Admin view-render hooks used to extend attribute and product forms are `unopim.admin.catalog.attributes.edit.card.label.after` and `unopim.admin.products.dynamic-attribute-fields.control.{type}.{before|after}` — listened to with `$viewRenderEventManager->addTemplate(...)` in `packages/Webkul/Measurement/src/Providers/MeasurementEventServiceProvider.php`.

## Association type events

`catalog.association_type.{create,update,delete}.{before,after}` from the admin and API association-type controllers. Product association links are written inside `AbstractType::update()` and fire no separate event; react to `catalog.product.update.after`.

## Writes that fire no catalog.product event

| Write path | What fires instead |
|---|---|
| Product import (`packages/Webkul/DataTransfer/src/Helpers/Importers/Product/Importer.php`) | `data_transfer.imports.batch.import.before`, `data_transfer.imports.batch.product.save.before`, `data_transfer.imports.batch.product.save.after` (`['product_id', 'created_ids', 'updated_ids']`), `data_transfer.imports.batch.product.created.after` / `.updated.after` (`['product_id' => ids]` → `(array $ids)`), and `data_transfer.imports.completed` once per job (`packages/Webkul/DataTransfer/src/Helpers/Import.php`) |
| `ProductRepository::updateWithValues()` | none from the repository — the AI-agent tools (`packages/Webkul/AiAgent/src/Chat/Tools/UpdateProduct.php` and siblings) call it directly; check each caller before assuming an event |
| `unopim:variants:strip-redundant --apply` | Eloquent model events only |
| `ProductCompletenessJob` writing `avg_completeness_score` | nothing — raw `UPDATE` |
| Any direct `DB::table('products')` write | nothing — avoid |

A feature that must see every product change listens to the `catalog.product.*` set AND the import batch events, mirroring the Webhook provider.

## Eloquent observers on Product

| Observer | Hooks | Toggle |
|---|---|---|
| `packages/Webkul/Product/src/Observers/ProductObserver.php` | `deleted` — removes `product/{id}` storage | after commit |
| `packages/Webkul/ElasticSearch/src/Observers/Product.php` | `created`, `updated`, `deleted` — index resolved values | static `disable()` / `enable()`; after commit; no-op when `elasticsearch.enabled` is false |
| `packages/Webkul/Completeness/src/Observers/Product.php` | `created`, `updated` — queue `ProductCompletenessJob` | static `disable()` / `enable()` |
| `packages/Webkul/Measurement/src/Observers/ProductObserver.php` | `saving` — validate and derive measurement fields | — |

Observers fire on every Eloquent save regardless of path, including importer saves when not disabled. The two static toggles are process-global: in a queue worker or under Octane a missing `enable()` disables indexing or scoring for every later request. Always pair them in `try { … } finally { …::enable(); }`.

## Listener rules

- Register in your provider's `boot()` with `Event::listen('catalog.product.update.after', [Listener::class, 'method'])` — see unopim-plugin-development backend.md for wiring.
- Do heavy work (HTTP, reindex, recompute) on a queue; a listener runs inside the admin request and, for `before` events, inside the write.
- Fire your own `{domain}.{entity}.{action}.{before|after}` pair around any write your package exposes, so others can extend you — unopim-standards extensibility.md.
- Test the listener against each payload shape it can receive (object, id, SKU string, bulk tuple).
