# Laravel 13 / PHP 8.4 idiom

The stack is Laravel 13 on PHP 8.4 (`composer.json`: `"php": "^8.4.1"`,
`"laravel/framework": "^13.0"`), with Octane 2.3, Passport 13 and Pest 5.
NEVER write code, config or docs against "Laravel 12", "PHP 8.3" or "Pest 3" —
all stale. Providers register in `bootstrap/providers.php`; `config/app.php` has
no providers array.

Prefer first-party Laravel features over custom code in every case: framework
casts over accessors that decode, `Rule` objects over regex strings, queued
jobs over cron scripts, `match()` over `if/elseif` chains on one subject.

## Constructor property promotion

Every constructor uses typed promoted properties and an empty body. Exemplars:
`packages/Webkul/Core/src/CatalogScope.php`, `packages/Webkul/Core/src/Core.php`.

**Good:**

```php
public function __construct(
    protected LocaleRepository $localeRepository,
    protected ChannelRepository $channelRepository
) {}
```

**Bad:** declared properties plus manual `$this->x = $x` assignment — the
codebase never does this.

## Explicit types everywhere

Every method and closure declares parameter and return types, including
container-binding closures (`fn ($app): CatalogScope => ...` in
`packages/Webkul/Core/src/Providers/CoreServiceProvider.php`).

Sole exception: DataGrid subclass hooks (`prepareQueryBuilder()`,
`prepareColumns()`) stay untyped with a PHPDoc `@return`, because the abstract
base declares them untyped (`packages/Webkul/DataGrid/src/DataGrid.php`). That
exception applies to DataGrid hook overrides ONLY — never generalize it.

## Models: PHP attributes + `casts()`

House style is attribute-based model metadata: `#[Fillable([...])]`,
`#[Table(name: '...')]`, `#[Hidden([...])]`, plus a
`protected function casts(): array` method. 53 model files use `#[Fillable]`.
Nine legacy models still declare the properties — the `Product`
`AssociationType*` family, `Product/src/Models/ProductAssociation.php`,
`HistoryControl/src/Models/History.php`, `AdminApi/src/Models/Apikey.php` —
and they are frozen debt, not precedent: never add a tenth. A new
`protected $fillable`/`$casts`/`$table`/`$hidden` is hook-blocked
(`LEGACY_MODEL_PROPERTY`). Exemplar:
`packages/Webkul/AiAgent/src/Models/Credential.php`.

```php
#[Fillable([
    'label',
    'provider',
    'apiKey',
    'status',
])]
#[Hidden([
    'apiKey',
])]
#[Table(name: 'ai_agent_credentials')]
class Credential extends Model implements AuditableContract, CredentialContract, PresentableHistoryInterface
{
    use HasFactory, HistoryTrait;

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

Array-cast trap: `$model->extras['k'] = $v` never persists (indirect
modification of an overloaded property). Read the whole array, modify, reassign.

## Enums

Any fixed status/type set is a string-backed enum in the package's `src/Enums/`
directory, with behavior methods — a `label(): string` returning a `trans()`
key and domain predicates. Never bare string literals or class constants for a
value set. Exemplars: `packages/Webkul/Publication/src/Enums/PublicationStatus.php`,
`packages/Webkul/DataGrid/src/Enums/ColumnTypeEnum.php`,
`packages/Webkul/DataTransfer/src/Enums/ProductExportScope.php`.

```php
enum PublicationStatus: string
{
    case Draft = 'draft';
    case Published = 'published';

    public function label(): string
    {
        return trans('publication::app.publications.status.'.$this->value);
    }
}
```

## Validation and responses

- Every entry point type-hints a FormRequest — inline `request()->validate()`
  is forbidden everywhere, no exceptions (see [security.md](security.md) for
  the `authorize()` contract). AdminApi requests extend
  `packages/Webkul/AdminApi/src/Http/Requests/ApiFormRequest.php`.
- API payloads go through Eloquent API Resources, never hand-built arrays.
  Exemplars: `packages/Webkul/Admin/src/Http/Resources/Catalog/AssociationTypeLinkResource.php`,
  `packages/Webkul/Admin/src/Http/Resources/Catalog/CategoryTreeResource.php`.
- Admin store/update/delete actions return `JsonResponse`; routes are named,
  and URLs are generated with `route()` — never hardcoded paths.
