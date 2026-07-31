# Comments

## Contents

- The bar
- What IS allowed
- The measured baseline
- Good vs bad
- Where a real rationale goes
- Templates and generated code

## The bar

The bar is absolute. UnoPim code carries **no inline comments of any kind**:

- No `//` — line-start or trailing, in `.php`, `.js` or `.vue`.
- No `/* ... */` — any block comment that is not a `/** */` docblock, anywhere,
  including inside a method body, an array literal or a config file.
- No `#` — except a PHP 8 attribute (`#[Fillable([...])]`, `#[Table(...)]`).
- No `{{-- ... --}}` — in any Blade template, narration or commented-out markup
  alike.
- No commented-out code, no section dividers (`// Views`, `// ---- X ----`), no
  banners, no `TODO`/`FIXME`/`HACK` notes left in the source.

There is no "one-line why" exemption, no veto-word list, no carve-out for a
comment that names a real constraint. If you remember one, it is stale — this
bar replaced the softer rule on 2026-07-31 by the repository owner's decision.
The reason is not that rationale is worthless; it is that the margin is the
wrong place to keep it.

The docblock survives. `/** ... */` is never matched by any rule, and it is
where every word you wanted to write belongs.

Two hook rules enforce this on the lines an edit ADDS: `INLINE_COMMENT` for
`.php`/`.js`/`.vue`, `BLADE_COMMENT` for `.blade.php`. The ratchet is what makes
an absolute bar liveable — existing comments stay exactly where they are and
block nothing. What they cannot do is grow.

Gate silence is not permission. No regex covers a rule this broad without a
seam somewhere; the bar above is the standard, and a comment that slips past the
hook is still a review blocker.

## What IS allowed

- **A one-line imperative PHPDoc summary on every method** — `Create product.`,
  `Specify model class name.`, `Replace all links for a product.` A sentence,
  ending in a period, describing what the method does.
- **`@param` / `@return` ONLY where the signature lacks a native type hint.**
  Legacy style, two-space aligned (`@param  int  $id`). A fully typed signature
  gets the summary line alone — `@return Collection` above `: Collection`
  restates the signature and is noise.
- **A one-line PHPDoc summary on a class property** — never an inline `//`
  above it.
- **A non-obvious constraint as a second PHPDoc paragraph.** DB-portability
  quirks, ordering requirements, the N+1 an eager load exists to prevent, why a
  binding is `scoped()` and not `singleton()`. It hangs off the signature, so it
  travels with the method through every refactor.
- **The commit message**, for anything with no signature to hang it on — config
  arrays, route files, a migration's ordering.

## The measured baseline

The exemplar files are literally zero:

- `packages/Webkul/Product/src/Repositories/ProductRepository.php` — 18 methods,
  325 lines, **0 inline comments**.
- `packages/Webkul/Product/src/Type/AbstractType.php` — 988 lines,
  **0 inline comments**.

Codebase-wide it is low but not zero, and you should know the real number rather
than discover it and conclude the rule is theatre. Across the 689 non-test PHP
files touched by the last 40 commits, 111 files carry at least one inline
comment, 502 lines in total; those same 40 commits added 678 comment lines
against 82,068 added PHP lines — under 1%. Nearly all of the 502 sit in
Laravel's own shipped config banners (`config/app.php`, `config/repository.php`)
and in the Installer.

So: calibrate to the exemplars, not to your prior of a few comments per file,
and not to the worst file you can find. Existing debt is frozen, not precedent.

Laravel *framework internals* do use narrative inline comments. That is
framework style, not app or package style, and not this codebase's convention —
never cite `vendor/laravel/` as precedent for a comment you want to keep.

## Good vs bad

**Bad — narration that restates the code.** Every one of these lines must be
deleted:

```php
public function create(array $data)
{
    $typeInstance = resolve(config('product_types.'.$data['type'].'.class'));

    return $typeInstance->create($data);
}
```

...written instead with a `//` above each statement announcing "Resolve the
product type instance from config" and "Create and return the product". Both
lines say what the next line already says.

**Good — the actual `ProductRepository::create`:**

```php
/**
 * Create product.
 *
 * @return Product
 */
public function create(array $data)
{
    $typeInstance = resolve(config('product_types.'.$data['type'].'.class'));

    return $typeInstance->create($data);
}
```

The `@return` earns its place because the signature has no return type. Add one
and the tag goes away.

## Where a real rationale goes

A constraint worth keeping is not deleted — it is moved up into the docblock.
`packages/Webkul/Product/src/Repositories/ProductAssociationRepository.php`
does exactly this: the reason the eager load is nested lives in the PHPDoc,
where it survives the next refactor, and the body stays clean.

```php
/**
 * Retrieve all association links for a source product with the
 * association type and related product (plus its attribute family, so
 * `Product::normalizeWithImage()` doesn't trigger a lazy-load per link)
 * eager loaded (no N+1).
 */
public function getLinksForProduct(int $productId): Collection
{
    return $this->model
        ->where('product_id', $productId)
        ->with(['associationType', 'relatedProduct', 'relatedProduct.attribute_family'])
        ->get();
}
```

That is the whole test for any comment you are about to write: if it belongs in
the docblock, put it there; if it does not survive being moved there, it was
narration and the answer is delete.

When the answer is neither — the line genuinely needs explaining — rename the
variable or extract a method until it explains itself. A method named
`prepareRichAssociations()` needs no comment; `$data2` needs three.

## Templates and generated code

Skill files, docs and scaffolding templates must not carry divider or narration
comments either — an agent copies what it sees, and a commented template
teaches commented code. If a code fence needs labelling, the label goes in the
prose around the fence, never inside it.

Before finishing any change, read the diff: every `+` line containing `//`,
`/*` (not `/**`), a non-attribute `#`, or `{{--` must justify itself against the
bar above. The default action is delete.
