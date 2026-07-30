# Admin CRUD house patterns

The shape every admin resource follows. Verified against the UnoPim checkout; each
rule names the file that proves it. Two of these are counter-intuitive and are the
ones newcomers break: the save bar is automatic, and the breadcrumb is not.

## 1. The save bar is the only Save

`x-admin::form` mounts the unsaved-changes tracker automatically — any invocation
with a non-GET method and no `as` attribute is wrapped in `v-unsaved-changes`. There
is nothing to opt into.

The tracker's `removeInFormSave()` **deletes every `button[type="submit"]` inside the
form at runtime**, plus any element outside it that points at the form via
`form="<id>"`. A Save button you write is not merely redundant; it is removed from the
DOM. The bar teleports itself to the bottom of the page and appears once the form is
dirty, carrying Discard and the one real save control.

- MUST let the bar be the only save control.
- NEVER pass `save-label` to `x-admin::layouts.edit-page-header` — that prop is the
  only thing that renders a header Save (`@if ($saveLabel)`), and the tracker deletes
  what it renders.
- Passing `form="<id>"` without `save-label` is a harmless no-op; twelve pages do it.
- Escape hatch, for a button that genuinely must survive (a modal's own submit):
  wrap it in `[data-unsaved-ignore]`.

Exemplar: `packages/Webkul/Admin/src/Resources/views/catalog/categories/edit.blade.php`
— a full edit page with no `type="submit"` anywhere. Pinned by a test in
`packages/Webkul/Admin/tests/Feature/Catalog/CategoryTest.php`, which asserts the page
renders `v-unsaved-changes`.

```blade
<x-slot:pageHeader>
    <x-admin::layouts.edit-page-header
        :title="trans('admin::app.catalog.categories.edit.title')"
        :back-url="route('admin.catalog.categories.index')"
        :back-label="trans('admin::app.catalog.categories.edit.back-btn')"
        form="category-edit-form"
        :sticky="false"
    />
</x-slot>

<x-admin::form
    id="category-edit-form"
    ajax
    :action="route('admin.catalog.categories.update', $category->id)"
    enctype="multipart/form-data"
    method="PUT"
>
```

Nine pages still pass `save-label` and are legacy, not precedent — among them
`packages/Webkul/Admin/src/Resources/views/settings/roles/edit.blade.php` and
`packages/Webkul/Webhook/src/Resources/views/webhooks/edit.blade.php`.

## 2. Create is a modal on the index page

MUST collect only a localizable name plus a `code` derived from it, then redirect to
the edit page where the real work happens. NEVER add a GET create route, a `create()`
action returning a view, or an index link to `.create`.

Reach for `x-admin::catalog.quick-create-modal` first — it is the shared, ready-made
button + form + modal + name/code pair, with optional type, swatch, validation,
locales, currencies and toggles. Hand-roll only when the field set is outside its
props.

The code derivation is two Vue directives, not a watcher and not slugify:

- `v-code-generator="'code'"` on the **name** control writes a generated code into the
  named target on every keystroke, and stops permanently once the user edits the code
  by hand.
- `v-code` on the **code** control sanitizes what is typed: lowercase, non-word
  characters to underscore, 191-character cap.

Both are registered in `packages/Webkul/Admin/src/Resources/assets/js/app.js`; the
derivation itself lives in
`packages/Webkul/Admin/src/Resources/assets/js/utils/code.js`.

Exemplar: `packages/Webkul/Admin/src/Resources/views/catalog/associations/types/create.blade.php`
— the newest implementation, with no GET create route and a test asserting the
full-page route is gone.

```blade
<x-admin::form.control-group.control
    type="text"
    name="{{ $currentLocaleCode }}[name]"
    v-code-generator="'code'"
    :label="trans('admin::app.catalog.association_types.create.name')"
    :placeholder="trans('admin::app.catalog.association_types.create.enter-name')"
/>

<x-admin::form.control-group.error control-name="{{ $currentLocaleCode }}[name]" />
```

`store()` seeds defaults and returns `redirect()->route('<resource>.edit', $record->id)`.
A plain redirect works from inside the modal because
`packages/Webkul/Admin/src/Http/Middleware/ConvertAjaxFormRedirect.php` converts a
cross-path redirect into `{message, redirect_url}` JSON when the request carries the
`X-Ajax-Form` header, which the shared submit handler sets.

Not yet universal: nine resources follow this pattern, while attributes, categories,
channels, roles, imports and exports still register a GET create route. New work
follows the modal; do not copy the legacy resources.

## 3. Breadcrumbs are a per-page step that is regularly forgotten

Two independent things must both be true, and neither fails loudly.

**A header component must render.** `x-admin::layouts` emits no header at all, so a
page that hand-rolls its heading silently has no breadcrumb. Only
`x-admin::page-title` emits the nav, and every header component funnels through it:
`x-admin::layouts.page-header` (preferred for listings),
`x-admin::page-header` (adds a back button), and
`x-admin::layouts.edit-page-header`. The one shell that cannot forget is
`x-admin::layouts.with-history`, which falls back to `x-admin::page-title` when its
`pageHeader` slot is empty.

**The route must sit under a dotted menu key.** The trail comes from
`packages/Webkul/Core/src/Tree.php`, walking the entries in each package's
`src/Config/menu.php`. A top-level key with no dotted child yields an empty
breadcrumb, silently.

- MUST render the title through a header component and register the route in
  `src/Config/menu.php`.
- NEVER hand-roll a `<p class="text-xl … font-bold">` heading where the header
  component belongs.
- NEVER place `<x-admin::breadcrumbs>` yourself — `x-admin::page-title` already does,
  and a second one breaks the e2e invariant of exactly one breadcrumb nav per page.
- `:breadcrumb="false"` is legitimate only inside
  `x-admin::layouts.tab-content-panel`, so an inner tab does not re-emit the crumb.

**Trap:** `diglactic/laravel-breadcrumbs` is installed and auto-discovered, but
`routes/breadcrumbs.php` is empty and nothing registers a definition. `Breadcrumbs::for()`
and `Breadcrumbs::render()` are dead ends — the config throws on an unknown name. The
menu is the registration mechanism.

Sixteen pages currently render no header component and therefore no breadcrumb,
including `packages/Webkul/AiAgent/Resources/views/agents/index.blade.php`.

## 4. The page skeleton

Every route-rendered page is one component tree rooted at `x-admin::layouts`, or
`x-admin::layouts.with-history` for a history-tracked edit page.

Index page — exemplar
`packages/Webkul/Webhook/src/Resources/views/webhooks/index.blade.php`:

```blade
<x-admin::layouts>
    <x-slot:title>
        @lang('webhook::app.webhooks.index.title')
    </x-slot>

    <x-admin::layouts.page-header :title="trans('webhook::app.webhooks.index.title')">
        <x-slot:actions>
            @if (bouncer()->hasPermission('configuration.webhook.create'))
                <v-create-webhook-form></v-create-webhook-form>
            @endif
        </x-slot>
    </x-admin::layouts.page-header>

    <x-admin::datagrid :src="route('webhook.index')" />
</x-admin::layouts>
```

Edit page: `x-admin::layouts.with-history` wrapping an
`x-admin::layouts.edit-page-header` in its `pageHeader` slot, then the section grid,
then an `x-admin::form` — and no Save anywhere.

**Trap:** `x-admin::page` documents itself as "the single template every page uses"
and has zero usages in the repository. It is aspirational dead code; do not cite it.

## 5. The rest of the envelope

- Localized labels use one `x-admin::form.translatable-field` with a locale switcher,
  never one input per locale.
- A history-tracked edit page wraps in `x-admin::layouts.with-history`; the model uses
  `HistoryTrait` and implements the presenter contract.
- Listings embed `x-admin::datagrid`; row and mass actions gate on
  `bouncer()->hasPermission()` with snake_case ACL keys.
- Delete confirmation goes through `x-admin::modal.confirm`.
- `code` is immutable after create.
- Store and update return JSON carrying `redirect_url` and `message`.

## Checklist

- [ ] No `save-label`, no `type="submit"` in the page — the bar is the Save.
- [ ] Create is a modal on the index; no GET create route, no `.create` view.
- [ ] Name control carries `v-code-generator`, code control carries `v-code`.
- [ ] `store()` redirects to the edit page.
- [ ] A header component renders the title, and the route has a dotted `menu.php` key.
- [ ] No hand-rolled heading, no manual `x-admin::breadcrumbs`, no `Breadcrumbs::for()`.
- [ ] Page rooted at `x-admin::layouts` or `x-admin::layouts.with-history`.
- [ ] Localized labels use `translatable-field`; every string comes from `trans()`.
