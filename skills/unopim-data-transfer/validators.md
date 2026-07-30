# Job Validators

Validators check a job's configuration (filters) before it runs. Base class: `packages/Webkul/DataTransfer/src/Validators/JobInstances/Default/JobValidator.php`.

## The real contract

- There is NO `AbstractValidator` class anywhere in the codebase. Extend `Webkul\DataTransfer\Validators\JobInstances\Default\JobValidator`.
- Contract: `validate(array $data, array $options = []): void` — returns nothing and THROWS `Illuminate\Validation\ValidationException` on failure. NEVER write `validate(array $filters): array` returning error strings; the pipeline catches the exception, not a return value.
- Validators are declarative: set `$rules`, `$messages`, `$attributeNames`. The base class runs `Validator::make()` for you. Filter fields are addressed as `filters.{name}`.
- Naming: `{Entity}JobValidator`, in `Validators/JobInstances/Export/` or `Validators/JobInstances/Import/`. Core ships thirteen of each — e.g. `packages/Webkul/DataTransfer/src/Validators/JobInstances/Export/ProductJobValidator.php`.
- Hooks: `preValidationProcess($data)` to normalize input; `getRules($options)` / `getMessages($options)` / `getAttributeNames($options)` to compute values at runtime.

## Declarative template

Sufficient for most connector jobs — no `validate()` override at all.

```php
<?php

namespace Webkul\{ModuleName}\Validators\JobInstances\Export;

use Webkul\DataTransfer\Validators\JobInstances\Default\JobValidator;

class ProductJobValidator extends JobValidator
{
    protected array $rules = [
        'filters.credential' => 'required|integer',
        'filters.locale'     => 'required|string',
        'filters.with_media' => 'nullable|in:1,0',
    ];

    public function __construct()
    {
        $this->attributeNames = [
            'filters.credential' => trans('{module-name}::app.exports.filters.credential'),
            'filters.locale'     => trans('{module-name}::app.exports.filters.locale'),
            'filters.with_media' => trans('{module-name}::app.exports.filters.with-media'),
        ];
    }
}
```

`$attributeNames` is set in the constructor because `trans()` cannot run in a property initializer — the core `ProductJobValidator` does exactly this.

## Custom checks beyond rules

Override `validate()`, call the parent first, then throw `ValidationException::withMessages()` yourself. Exemplar: `packages/Webkul/DataTransfer/src/Validators/JobInstances/Export/ProductJobValidator.php` validates that selected locales/currencies belong to the selected channels after the declarative rules pass.

```php
public function validate(array $data, array $options = []): void
{
    parent::validate($data, $options);

    $this->validateCredentialIsActive($data['filters'] ?? []);
}
```

The custom method throws on failure:

```php
protected function validateCredentialIsActive(array $filters): void
{
    $credential = $this->credentialRepository->find($filters['credential'] ?? null);

    if ($credential?->status) {
        return;
    }

    throw ValidationException::withMessages([
        'filters[credential]' => [trans('{module-name}::app.exports.validation.credential-inactive')],
    ]);
}
```

Message keys for array inputs use the bracket form (`filters[credential]`) so the admin form highlights the right field — the base class converts dotted keys the same way.

## Wiring

Reference the class from the `validator` key of the job's entry in `exporters.php` or `importers.php` (see [exporters.md](exporters.md), [importers.md](importers.md)). The orchestrator resolves it from the container, so constructor dependencies are injected — the core export `ProductJobValidator` takes a `ChannelRepository` this way.

All error messages are translation keys propagated to all 33 locales; never hardcode a user-facing string in a validator.
