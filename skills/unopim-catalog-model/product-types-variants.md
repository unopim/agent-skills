# Product types, variants and associations

Registry: `packages/Webkul/Product/src/Config/product_types.php` (merged under `product_types` by `packages/Webkul/Product/src/Providers/ProductServiceProvider.php`). Type keys: `packages/Webkul/Product/src/Enums/ProductType.php`. Base class: `packages/Webkul/Product/src/Type/AbstractType.php`.

## Contents

- The three types
- How a type is resolved
- AbstractType surface
- Adding a product type — read before proposing one
- Variant trees and variant structures
- The variant commands
- Completeness interaction
- Associations

## The three types

| Key | Class | Variant level | Notes |
|---|---|---|---|
| `simple` | `packages/Webkul/Product/src/Type/Simple.php` | `variant` (when it has a parent) | empty subclass |
| `configurable` | `packages/Webkul/Product/src/Type/Configurable.php` | `common` (root) | `$hasVariants = true`; owns `super_attributes` and `variant_structure_id` |
| `variant_group` | `packages/Webkul/Product/src/Type/VariantGroup.php` | `sub_parent` | `'internal' => true` — hidden from the create dropdown in `packages/Webkul/Admin/src/Resources/views/catalog/products/index.blade.php`; only created as the middle node of a 2-level tree |

`ProductType::VARIANT_PARENT_VALUES` (`configurable`, `variant_group`), `VARIANT_CHILD_VALUES` (`variant_group`, `simple`) and `VARIANT_LEVEL_BY_TYPE` are the lookup tables every variant code path uses; levels and their order are `packages/Webkul/Product/src/Enums/VariantLevel.php`.

## How a type is resolved

`ProductRepository::create()` and `Product::getTypeInstance()` both do `resolve(config('product_types.'.$type.'.class'))`. The instance is container-resolved, so constructor injection works; `getTypeInstance()` throws if the class is not an `AbstractType`. `packages/Webkul/Product/src/Helpers/ProductType.php` answers `hasVariants()`, `getAllTypesHavingVariants()`, `isProductType()` from the config.

## AbstractType surface

Override points a type may change — keep the signatures exactly as declared on the base:

| Member | Default | Purpose |
|---|---|---|
| `$hasVariants` | `false` | `true` makes the type a variant parent in helpers and grids |
| `$canBeCopied` | `true` | gates the admin copy action |
| `$isChildrenCalculated` | `false` | read through `isChildrenCalculated()` |
| `$skipAttributes` | `[]` | attribute codes hidden from the edit form |
| `$additionalViews` | `[]` | extra Blade views rendered on the edit page |
| `create(array $data)` | seeds `values.common.sku`, saves | |
| `update(array $data, $id, $attribute = 'id')` | values pipeline, association sync, variant-level guard | call `parent::update()` if you override |
| `getTypeValidationRules()` | `[]` | extra rules merged into the product form |
| `getChildrenIds()` | `[]` | |
| `copy()` / `copyRelationships()` | media + relationship copy | |

The `wasDirtyOnUpdate` flag set in `update()` gates `catalog.product.update.after` and the completeness job in the admin controller — an override that saves without setting it suppresses both.

## Adding a product type — read before proposing one

The registry is a config array, so a package *can* add a type with `mergeConfigFrom(..., 'product_types')` and a class extending `AbstractType`. In practice the three keys are hard-wired well beyond the registry:

- `ProductType` is a backed enum with exactly three cases; variant code reads its constant maps (`VARIANT_LEVEL_BY_TYPE`, …) and `ProductType::tryFrom()`, none of which know a fourth key.
- The API accepts only `ProductType::VARIANT_PARENT_VALUES` for configurable creation (`packages/Webkul/AdminApi/src/Http/Requests/Catalog/StoreConfigurableProductRequest.php`).
- The product importer, exporter, Elasticsearch type filter and grids branch on the literal keys.

A new *simple-like* type (no variants) is feasible: register it, extend `AbstractType`, add the translated `name` in 33 locales, and test create, update, copy, export and both search branches. Anything that participates in variant trees is a core change, not a package feature — raise it upstream.

## Variant trees and variant structures

Shapes on master:

- 1-level: `configurable` → `simple` variants.
- 2-level: `configurable` → `variant_group` → `simple`.

Children point at their parent through `products.parent_id`; `Product::variants()` is the inverse. The tree's rules live in a **variant structure** attached to the root (`products.variant_structure_id`):

- `packages/Webkul/Product/src/Models/VariantStructure.php` — per attribute family; `levels` (integer), `axes()` and `placements()`.
- `packages/Webkul/Product/src/Models/VariantStructureAxis.php` — `attribute_id`, `level`, `position`: which `select` attribute distinguishes children at each level.
- `packages/Webkul/Product/src/Models/VariantStructureAttribute.php` — `attribute_id`, `level`: at which level a non-axis attribute is maintained. Unplaced attributes are `common` (owned by the root).

`packages/Webkul/Product/src/Services/VariantStructurePlanner.php` (contract `packages/Webkul/Product/src/Contracts/VariantStructurePlanner.php`) answers `levelOf()`, `structureFor()`, `ownsAttribute()`, `ownsAtOwnLevel()`, `placementOf()`, `axisCodesByLevel()`. It memoises per product, which is why `ProductServiceProvider::registerBindings()` binds it (fresh per resolve), not as a singleton or scoped — keep it that way, and call `primeStructuresFor()` before looping over many products.

Copying a family copies its structure via `catalog.attribute_family.copied` → `packages/Webkul/Product/src/Listeners/CopyVariantStructure.php`.

Write rules (see [values.md](values.md) for inheritance):

- Children store only overrides; read with `resolvedValues()` / `resolveBatch()`.
- Child writes pass `ProductRepository::guardVariantLevelWrite()`; ancestor-owned attributes are immutable on the child.
- Axis-combination uniqueness: `ProductRepository::isUniqueVariantForProduct()` with an optional `$type` to separate `variant_group` siblings from `simple` siblings.
- Variant-level create/update entry points: `Configurable::createVariantGroup()`, `createVariant()`, `updateVariant()`, `updateVariantGroupValues()`. Each fires `catalog.product.create.after` for nodes it creates.

## The variant commands

Both live in `packages/Webkul/Product/src/Console/`, are registered in `ProductServiceProvider::boot()` for console only, and walk configurable roots with `chunkById(200)`.

| Command | Options | Does |
|---|---|---|
| `unopim:variants:resync` (`ResyncVariantsCommand.php`) | `--product=<id>` or `--all` — one is required, else exit 1 | collects root + children + grandchildren ids and queues one `ProductCompletenessJob`. It does not rewrite `values`, and although its description mentions the search index, on master the job only writes completeness scores (raw SQL, no model events) — reindex separately with `unopim:product:index`. |
| `unopim:variants:strip-redundant` (`StripRedundantVariantValuesCommand.php`) | `--apply` (omit = dry-run report), `--product=<id>` | for each direct child of a configurable, removes `common` keys whose value equals the resolved ancestor value; keeps `sku` and the root's super-attribute codes. Saves with `$variant->save()`. |

Run `strip-redundant` without `--apply` first and review the per-SKU report. Observations from the source, to check before relying on it for a 2-level tree: it iterates `$parent->variants` only (the `variant_group` nodes, not their `simple` children), compares only the `common` bucket, and compares with strict `===`. After an `--apply` run, requeue scores for the touched trees with `unopim:variants:resync --product=<id>` (or `--all`); `$variant->save()` already fires the Eloquent observers that reindex each saved child.

Tests: `packages/Webkul/Product/tests/Unit/Console/ResyncVariantsCommandTest.php`, `packages/Webkul/Product/tests/Unit/Console/StripRedundantVariantValuesCommandTest.php`.

## Completeness interaction

- Settings are per family × attribute × channel (`packages/Webkul/Completeness/src/Models/CompletenessSetting.php`); scores per product × channel × locale in `product_completeness`, plus an average on `products`.
- `packages/Webkul/Completeness/src/Observers/Product.php` queues `ProductCompletenessJob` on every Eloquent `created` / `updated` of a product. The job resolves variant inheritance and only scores attributes the variant owns.
- Removing attributes from a family (through `AttributeFamilyRepository`) fires `catalog.attribute_family.attributes.changed`; `packages/Webkul/Completeness/src/Listeners/HandleFamilyAttributeChanges.php` deletes the orphaned settings and queues `BulkProductCompletenessJob` for the family.
- Recompute by hand: `unopim:completeness:recalculate {--family=} {--product=} {--products=*} {--all}` (`packages/Webkul/Completeness/src/Console/RecalculateCompletenessCommand.php`). Queue name: `config('completeness.queue')`.
- Bulk writers that disable the observer must queue the job themselves and re-enable in `finally` — the product importer is the exemplar.

## Associations

Two stores, written together:

- Legacy: `values.associations.{related_products|up_sells|cross_sells}` — SKU lists.
- Rich: `product_associations` rows (`packages/Webkul/Product/src/Models/ProductAssociation.php`: `product_id`, `association_type_id`, `related_product_id`, `position`, `additional_data` array).

`AbstractType::update()` validates and SKU-resolves a submitted `associations` payload BEFORE saving (`prepareRichAssociations()`), then dual-writes (`syncAssociationLinks()`, `syncRichAssociations()`). A write path that bypasses `update()` must call those public methods itself, in that order.

Association types (`packages/Webkul/Product/src/Models/AssociationType.php`: `code`, `status`, `position`, `is_user_defined`, translated `name`) carry custom fields whose `type` is validated against `config('association_field_types')` (`packages/Webkul/Product/src/Config/association_field_types.php`: `text`, `boolean`). The config's own docblock says re-enabling a richer field type is done by merging its entry from an extending package. Admin CRUD fires `catalog.association_type.{create|update|delete}.{before|after}` and is gated by `catalog.association_types.*` ACL keys. Repositories: `packages/Webkul/Product/src/Repositories/AssociationTypeRepository.php`, `packages/Webkul/Product/src/Repositories/ProductAssociationRepository.php`.
