# Strict Mode — the two gates a diff scan cannot catch

Every other UnoPim rule is either regex-decidable (a hook blocks the added line)
or judgment (a skill argues it). These two are neither: they need a runtime or a
static-analysis setting, and the codebase does not have it turned on yet. Both
are ratchets — turn them on for one package at a time, never as a flag day.

## No N+1: `Model::preventLazyLoading()`

A skill telling an agent to eager-load is advisory, and advice gets ignored.
Laravel ships the enforcement: in the testing environment only, register

```php
use Illuminate\Database\Eloquent\Model;

Model::preventLazyLoading();
```

so any lazy load throws `LazyLoadingViolationException` and Pest fails on the
N+1 instead of shipping it. `tests/Pest.php` already performs global test setup
and is the natural place; a service provider guarded by
`$this->app->environment('testing')` works too.

`preventLazyLoading` and `shouldBeStrict` appear nowhere in the UnoPim codebase
today (zero matches across `app/`, `packages/`, `tests/`, `bootstrap/`,
`config/`), which is why "no N+1" has never been enforceable. Never enable it in
production — there it turns a performance smell into an outage.

Expect existing failures on first enablement. Ratchet: enable it, record the
failing tests, fix them package by package. Reverting the flag to get green is
the one response that guarantees the debt keeps growing.

## Explicit types: the Larastan ratchet

`phpstan.neon` sits at `level: 2` and ignores:

- `#Access to an undefined property#`
- `#Call to an undefined method#`
- `#has invalid type#`

plus two narrower Concord entries for proxy models and package facades. The
first three swallow most of what Larastan would report, so raising the level
alone catches almost nothing. The ratchet has two dials, applied to one package
at a time:

1. Raise the level for the named package via a per-package override.
2. Narrow the ignore list for that same package, so the level increase can
   actually report something.

Level 6 is where missing parameter and return types start to surface, which is
the rule this gate exists to enforce.

## Two configuration defects to fix while you are in there

Both verified against the checkout at the time of writing:

- **The `composer phpstan` script description claims level 1** ("Run PHPStan
  static analysis at level 1 against the application") while `phpstan.neon` says
  `level: 2`. The script itself runs `./vendor/bin/phpstan analyse
  --memory-limit=2G`, so the level comes from the config and the description is
  simply wrong. Correct the description, not the config.
- **One `excludePaths` entry matches nothing.** `phpstan.neon` excludes
  `packages/*/src/Database/Migration/*` (singular). Fourteen packages ship
  `src/Database/Migrations/` (plural), and the single `Database/Migration/`
  directory that does exist is not under `src/`. The intended exclusion has
  never applied, so migrations have been analysed all along — fix the pattern
  deliberately rather than discovering it as a level bump regresses.
