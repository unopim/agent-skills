# Admin UI: Components, Theme Tokens, CRUD Pattern

## Contents

- Component-first (MANDATORY)
- Theme color tokens (STRICT)
- CRUD house pattern
- Controller/view contract
- Checklist

## Component-first (MANDATORY)

~160 component blades live under `packages/Webkul/Admin/src/Resources/views/components/`.
Search there before writing any markup.

- Wrap every field in `x-admin::form.control-group` with `.label`, `.control`, `.error`.
- NEVER raw `<input>`, `<select>`, `<textarea>`, `<label>` in admin forms.
- Modals via `x-admin::modal`; confirm dialogs via `x-admin::modal.confirm`; drawers via
  `x-admin::drawer`; toggles via `x-admin::form.switcher`; dates via
  `x-admin::flat-picker.date`; rich text via `x-admin::tinymce`; tabs via
  `x-admin::tabs`; menus via `x-admin::dropdown`; collapsibles via
  `x-admin::accordion`; status pills via `x-admin::badge` (or the prebuilt
  `label-active` / `label-info` classes); trees via `x-admin::tree`; loading
  states via `x-admin::shimmer`. A hand-rolled div that reproduces any of these
  is a blocker even when it looks like plain Tailwind — a `fixed inset-0`
  overlay and a template that computes its own `previousPageUrl`/`nextPageUrl`
  are both hook-blocked (`RAW_OVERLAY`, `RAW_LISTING`).
- Listing pages use `<x-admin::layouts>` + `<x-slot:title>` + `<x-admin::datagrid>`
  (exemplar: `packages/Webkul/AiAgent/Resources/views/credentials/index.blade.php`).
  `admin::layouts.master` and `@extends` DO NOT EXIST.
- Media fields (image, file, gallery) render through `x-admin::media.image`,
  `x-admin::media.files` and `x-admin::media.gallery` — never a hand-rolled
  uploader. Serving a stored file back to the browser goes through the named
  route `admin.media.download`
  (`packages/Webkul/Admin/src/Http/Controllers/MediaController.php`), which
  authorizes the request against the root-to-permission map in
  `packages/Webkul/Admin/src/Config/media.php`. A new downloadable root needs an
  entry there or the download is refused; linking a storage path directly
  bypasses the ACL entirely.
- Every label, placeholder and message is a `trans()`/`@lang` key with `en_US` first.

Select fields use the component select with an options payload:

```blade
@php
    $options = collect($providers)->map(fn ($provider) => [
        'id'    => $provider['value'],
        'label' => $provider['label'],
    ])->values();
@endphp

<x-admin::form.control-group>
    <x-admin::form.control-group.label class="required">
        @lang('{module}::app.credentials.provider')
    </x-admin::form.control-group.label>

    <x-admin::form.control-group.control
        type="select"
        name="provider"
        rules="required"
        ::value="form.provider"
        :label="trans('{module}::app.credentials.provider')"
        :options="json_encode($options)"
        track-by="id"
        label-by="label"
        @input="onProviderChange($event)"
    />

    <x-admin::form.control-group.error control-name="provider" />
</x-admin::form.control-group>
```

## Theme color tokens (STRICT)

Source of truth: `packages/Webkul/Admin/tailwind.config.js` and
`packages/Webkul/Admin/src/Resources/assets/css/app.css` (CSS vars in `:root`,
re-declared under `.dark`). The admin theme must stay re-skinnable by overriding one CSS
var, so every color resolves through a token.

NEVER in Blade/Vue/CSS/JS:

- Hex or `rgb()` literals, `style="..."`, `<style>` blocks.
- Arbitrary Tailwind values: `bg-[#7C3AED]`.
- Default intent scales for brand/status UI: `violet-*`, `purple-*`, `red-*`,
  `green-*`, `blue-*`.
- Legacy baked-hex families in new code: `cherry-*`, `sky-*`, `unopim-primary-*`.

ALWAYS:

- Brand/action: the semantic `primary` scale (`bg-primary-600`, `text-primary-700`,
  `border-primary-500`) and `primary-hover`.
- Status/intent: `success`, `warning`, `danger`, `info` (e.g. `text-danger`,
  `bg-success/10`) — dark-aware for free.
- Prebuilt classes before utility soup: `primary-button`, `secondary-button`,
  `transparent-button`, `danger-button`, `label-active`, `label-info`.
- Neutrals (`gray-*`, `white`) are fine for text/surfaces but MUST carry `dark:`
  variants — pair like `text-primary-700 dark:text-primary-400`.
- Charts/JS read the CSS vars (`--chart-1..6`, `--c-primary-*`) — no hex arrays.

```blade
<button type="submit" class="primary-button">
    @lang('{module}::app.credentials.save-btn')
</button>

<span class="text-danger">
    @lang('{module}::app.credentials.test-failed')
</span>
```

## CRUD house pattern

Full rules, exemplars and traps: [crud-patterns.md](crud-patterns.md). The four that
are broken most often:

| Pattern | Rule |
|---|---|
| The save bar is the only Save | `x-admin::form` mounts the unsaved-changes tracker automatically, and the tracker DELETES every in-form `type="submit"` at runtime. Never pass `save-label` to `x-admin::layouts.edit-page-header` — it renders a button that is then removed, so the page ships dead markup. Exemplar: `packages/Webkul/Admin/src/Resources/views/catalog/categories/edit.blade.php`. |
| Create = modal on the index page | Localizable name carrying `v-code-generator="'code'"` plus a `v-code` code field; no GET create route, no `.create` view; `store()` seeds defaults and redirects to the EDIT page. Reach for `x-admin::catalog.quick-create-modal` first. Exemplar: `packages/Webkul/Admin/src/Resources/views/catalog/associations/types/create.blade.php`. |
| Breadcrumbs are NOT automatic | `x-admin::layouts` renders no header, so a hand-rolled heading means no breadcrumb. Render the title through a header component AND give the route a dotted key in `src/Config/menu.php`. `Breadcrumbs::for()` is a dead end here — `routes/breadcrumbs.php` is empty. |
| Localized labels use one field | `x-admin::form.translatable-field` (single control with a locale switcher) — never one input per locale. Component: `packages/Webkul/Admin/src/Resources/views/components/form/translatable-field.blade.php`. |
| Edit page carries history | Wrap in `<x-admin::layouts.with-history>` (model uses `HistoryTrait`). Exemplar: `packages/Webkul/Admin/src/Resources/views/catalog/attributes/edit.blade.php`. |

## Controller/view contract

- `index()` answers `request()->ajax()` with the DataGrid `toJson()`, otherwise the
  Blade view.
- store/update/destroy return `JsonResponse` with `redirect_url` + `message` — the
  ajax `x-admin::form` consumes it.
- Gate action buttons in Blade with `bouncer()->hasPermission('{module}.credentials.create')`
  so users without the permission never see the control.

## Checklist

- [ ] Zero raw form controls; component equivalents everywhere.
- [ ] Zero hex/`style=`/arbitrary/intent-scale/legacy color classes; `dark:` pairs on
      neutrals.
- [ ] Modal create on index; save-bar edit; `translatable-field`; `with-history`.
- [ ] All user-facing text via translation keys, `en_US` first, 33 locales propagated.
