# Credential Storage, Encryption and History

Credentials store API connection details for a third-party integration. Everything here
mirrors the working implementation in `packages/Webkul/AiAgent` — copy from it, not from
memory.

## Contents

- Non-negotiables
- Migration
- Credential model — the complete working pattern
- Presenter
- FormRequest
- Controller
- Checklist

## Non-negotiables

- The secret is encrypted at rest via the `'encrypted'` Eloquent cast AND hidden via
  `#[Hidden]` AND excluded from audit via `$auditExclude` — all three together.
  `$auditExclude` alone stores plaintext (the codebase shipped
  `packages/Webkul/AiAgent/Database/Migration/2026_03_24_000001_encrypt_existing_ai_agent_api_keys.php`
  to repair exactly that mistake). Never `Crypt::encryptString()` by hand in
  controllers.
- The secret column is `text`, not `string` — encrypted payloads outgrow 255 chars.
- The history/audit pattern has three fatal-if-missing parts, verified against
  `packages/Webkul/HistoryControl/src/Interfaces/PresentableHistoryInterface.php` and
  `packages/Webkul/HistoryControl/src/Traits/HistoryTrait.php`:
  1. `PresentableHistoryInterface` requires `public static function getPresenters(): array`
     — omit it and the class fatals at load.
  2. `HistoryTrait` registers OwenIt's `AuditableObserver`, whose methods type-hint
     `OwenIt\Auditing\Contracts\Auditable` — a model not implementing that contract
     throws a TypeError on first save.
  3. `HistoryTrait::generateTags()` returns `$this->historyTags` unguarded — leave the
     property undefined and every save throws a TypeError.

## Migration

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('{module}_credentials', function (Blueprint $table): void {
            $table->id();
            $table->string('label');
            $table->string('apiUrl', 500);
            $table->text('apiKey');
            $table->json('extras')->nullable();
            $table->boolean('status')->default(true);
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('{module}_credentials');
    }
};
```

## Credential model — the complete working pattern

Exemplar: `packages/Webkul/AiAgent/src/Models/Credential.php`.

```php
<?php

namespace Webkul\{ModuleName}\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Attributes\Table;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use OwenIt\Auditing\Contracts\Auditable as AuditableContract;
use Webkul\{ModuleName}\Contracts\Credential as CredentialContract;
use Webkul\{ModuleName}\Presenters\CredentialPresenter;
use Webkul\HistoryControl\Interfaces\PresentableHistoryInterface;
use Webkul\HistoryControl\Traits\HistoryTrait;

#[Fillable([
    'label',
    'apiUrl',
    'apiKey',
    'extras',
    'status',
])]
#[Hidden([
    'apiKey',
])]
#[Table(name: '{module}_credentials')]
class Credential extends Model implements AuditableContract, CredentialContract, PresentableHistoryInterface
{
    use HasFactory, HistoryTrait;

    /**
     * Tags for history/audit.
     *
     * @var array
     */
    protected $historyTags = ['{module}-credential'];

    /**
     * Fields excluded from history audit — sensitive values.
     *
     * @var array
     */
    protected $auditExclude = [
        'apiKey',
    ];

    /**
     * History auditable attributes.
     *
     * @var array
     */
    protected $historyAuditable = [
        'label',
        'apiUrl',
        'status',
    ];

    /**
     * {@inheritdoc}
     */
    public static function getPresenters(): array
    {
        return [
            'common' => CredentialPresenter::class,
        ];
    }

    /**
     * Casts.
     */
    protected function casts(): array
    {
        return [
            'extras' => 'array',
            'status' => 'boolean',
            'apiKey' => 'encrypted',
        ];
    }
}
```

## Presenter

There is NO `BasePresenter` class and NO `getTitle()` method anywhere in the codebase.
Presenters implement `Webkul\HistoryControl\Interfaces\HistoryPresenterInterface` with
`public static function representValueForHistory(mixed $old, mixed $new, string $fieldName): array`.
Copy the module-local abstract from
`packages/Webkul/AiAgent/src/Presenters/AbstractPresenter.php` and extend it:

```php
<?php

namespace Webkul\{ModuleName}\Presenters;

/**
 * Presenter for Credential model in history audit UI.
 */
class CredentialPresenter extends AbstractPresenter
{
}
```

## FormRequest

Exemplar: `packages/Webkul/AiAgent/src/Http/Requests/CredentialForm.php` — note the
bouncer check in `authorize()` and the SSRF validation on the user-supplied URL.

```php
<?php

namespace Webkul\{ModuleName}\Http\Requests;

use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Webkul\Webhook\Validators\SafeWebhookUrl;

class CredentialForm extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        return bouncer()->hasPermission('{module}.credentials');
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'label'  => ['required', 'string', 'max:255'],
            'apiUrl' => ['required', 'url', 'max:500', function (string $attribute, mixed $value, Closure $fail): void {
                if (! SafeWebhookUrl::validate($value)['valid']) {
                    $fail(trans('admin::app.configuration.platform.message.unsafe-api-url'));
                }
            }],
            'apiKey' => ['required', 'string', 'max:500'],
            'status' => ['sometimes', 'boolean'],
        ];
    }
}
```

## Controller

Exemplar: `packages/Webkul/AiAgent/src/Http/Controllers/CredentialController.php`. Rules:

- store/update/destroy return `JsonResponse` with `redirect_url` + `message`.
- The edit form renders the secret masked; `update()` keeps the stored key when the
  submitted value is the masked placeholder (`resolveApiKey()` in the exemplar) so
  editing never wipes it.
- `testConnection(CredentialForm $request)` is a SEPARATE POST endpoint — FormRequest
  type-hinted, ACL-covered, never invoked inside `store()` before persisting. Inline
  `request()->validate()` is forbidden here as everywhere.
- `get()` returns `[{id, label}]` of active credentials for async dropdowns
  (`getActiveList()` on the repository).

```php
    /**
     * Test connectivity with the provider.
     */
    public function testConnection(CredentialForm $request): JsonResponse
    {
        $data = $request->validated();

        $this->apiClient->configure($data['apiUrl'], $data['apiKey']);

        $result = $this->apiClient->testConnection();

        return new JsonResponse([
            'success' => $result['success'],
            'message' => $result['success']
                ? trans('{module}::app.credentials.test-success')
                : trans('{module}::app.credentials.test-failed'),
        ]);
    }
```

## Checklist

- [ ] Secret column is `text`; cast `'encrypted'`; `#[Hidden]`; in `$auditExclude`.
- [ ] Model implements `AuditableContract` + module contract + `PresentableHistoryInterface`.
- [ ] `getPresenters()` defined; `$historyTags` defined; presenter implements
      `HistoryPresenterInterface` (no `BasePresenter`, no `getTitle()`).
- [ ] Model listed in `ModuleServiceProvider::$models`.
- [ ] Masked-secret edit flow keeps the stored key.
- [ ] `testConnection` is its own FormRequest-validated, ACL-gated route.
