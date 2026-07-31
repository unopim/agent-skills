# Connector Attribute Mapping

A connector maps remote fields (EAN, name, description, images) to UnoPim attributes.
Keep the surface minimal: two tabs — Attribute Mapping and History — nothing else.

## Data model

Two tables, both through the standard model/contract/repository pattern
([backend.md](backend.md)):

- `{module}_attribute_mappings`: `id`, `attribute_code` (remote field key),
  `unopim_attribute_id` (FK), `default_value` (json, nullable), timestamps. Unique
  index on `attribute_code`. Multi-image fields store an array of attribute ids in a
  json column.
- Mapping history: either give the mapping model the full history pattern from
  [credentials.md](credentials.md) (preferred — free UI via
  `<x-admin::layouts.with-history>`), or a dedicated snapshot table
  (`action_type`, `user_id`, `payload` json) when the whole mapping saves as one unit.

## Type-compatibility validation (MANDATORY)

Each remote field accepts only specific UnoPim attribute types. Declare the matrix once
and validate on save in the FormRequest — mismatches fail with the field name in the
message:

```php
protected const ALLOWED_TYPES = [
    'ean'         => ['text'],
    'product_code' => ['text', 'number'],
    'vendor'      => ['select', 'text'],
    'name'        => ['text'],
    'description' => ['textarea'],
    'pictures'    => ['image'],
];
```

- Validate that every submitted attribute id exists and its `type` is allowed for the
  field; reject duplicates per `attribute_code`.
- Required remote fields (whatever the target API mandates) must be mapped before save
  — block with a validation error listing the missing fields.
- Image fields accept only image-type attributes and allow multi-select.

## Controllers and routes

- `AttributeMappingController`: `index` + `store` (upsert). `MappingHistoryController`:
  `index` only. Repository-injected; no DB logic in controllers; store returns
  `JsonResponse` with `message`.
- Routes under `['admin']` + `config('app.admin_url')` prefix; both route names covered
  in `Config/acl.php` — store included (fail-open rule,
  [acl-security.md](acl-security.md)).

## UI

- Component-first ([admin-ui.md](admin-ui.md)): table of
  remote field | UnoPim attribute | default value, selects via the component select
  with `:options="json_encode(...)"`, `track-by`/`label-by`.
- Attribute options come from an async `list_route` endpoint returning
  `[{code, label}]` filtered to the allowed types for that field.
- All labels via `trans('{module}::app.mapping.…')`, `en_US` first.
