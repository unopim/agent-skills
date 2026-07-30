# Localization

Never output static user-facing text — labels, titles, messages, errors,
placeholders all go through `trans()` / `__('package::file.key')` / `@lang`.
The hooks catch hardcoded literals; this file covers the judgment: where keys
live, and what a correct translation is.

## Locale layout

Translation files live in each package's `Resources/lang/{locale}/` directory
with 33 region-coded locales (see `packages/Webkul/Core/src/Resources/lang`):

```
ar_AE  ca_ES  da_DK  de_DE  en_AU  en_GB  en_NZ  en_US
es_ES  es_VE  fi_FI  fr_FR  hi_IN  hr_HR  id_ID  it_IT
ja_JP  ko_KR  mn_MN  nl_NL  no_NO  pl_PL  pt_BR  pt_PT
ro_RO  ru_RU  sv_SE  tl_PH  tr_TR  uk_UA  vi_VN  zh_CN
zh_TW
```

`en_US` is the canonical source locale and the `fallback_locale`. There is NO
bare `en` directory — keys written to `Resources/lang/en/` never load. Reuse an
existing core key only when it actually exists (verify in the package's
`en_US` files); `admin::app.common.delete`, for instance, does not exist — use
the section-specific key.

## Adding or changing a key

1. Add the key in `en_US` first.
2. Propagate to ALL 33 locales, translated into the actual language of each —
   NEVER copy the English value into a sibling locale.
3. Preserve parameters exactly: `:attribute`, `:count`, `:name` are never
   translated or reordered away.
4. Translate naturally — a value must read like the target language, not a
   word-for-word gloss.

**Good** (`:name` untouched, natural phrasing):

```php
'created' => 'Product :name created successfully',
```

```php
'created' => 'Produit :name créé avec succès',
```

**Bad:** the English string copied into `fr_FR/app.php`, or `:name` translated
to `:nom`.

## Enums, exceptions, JS

- Enum labels return `trans()` keys (see the enum contract in
  [laravel13.md](laravel13.md)) — never a hardcoded English word.
- Exception and JsonResponse messages that reach the UI are keys, not English.
- Vue/Blade component labels and placeholders come in as translated props —
  never string literals inside the component.

## Verification

`php artisan unopim:translations:check`
(`packages/Webkul/Core/src/Console/Commands/TranslationsChecker.php`) audits
every locale against `en_US`; scope with `--package=`, reconcile missing keys
with `--fix`, and enable all quality checks (placeholders, empty, untranslated,
sort, html) with `--strict`. Running the gate is unopim-verify's job — this
command must pass with zero errors before any change is complete.
