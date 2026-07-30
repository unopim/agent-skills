# Authoring standard

Rules for writing and changing skills in this repository. They are rules, not advice:
`bin/lint-skills.sh` enforces the mechanical half and runs on every pull request via
`.github/workflows/skills-tests.yml`, so a change that breaks one of the lettered checks
below cannot merge.

Run both of these before you open a pull request — CI runs exactly the same two commands:

```bash
bin/lint-skills.sh                    # add --unopim <path-to-unopim-checkout> to check citations
skills/tests/run-tests.sh
```

## 1. The dividing line: judgment vs mechanics

A rule that a regex can decide belongs in `hooks/rules.txt`, where it produces an exit code.
A rule that needs a model to weigh context belongs in skill prose.

| Kind | Example | Goes in |
|---|---|---|
| Mechanics | no raw `<select>`, no `$request->validate(`, no `$guarded = []`, no hex literal, no inline `//` in a method body | `hooks/rules.txt` |
| Judgment | is this the right extension point, is this eager-loaded correctly, is this backward compatible, is this Octane-safe | skill prose |

Prose that restates a mechanical rule is a defect, not redundancy: agents rationalise past prose
and cannot rationalise past an exit code. If you find yourself writing "never use X", check
whether `grep` can decide it. If it can, add the rule and its message to `hooks/rules.txt`, add a
case to the hook's test, and cite the rule id from the skill instead of repeating the rule.

## 2. Frontmatter contract

Every `SKILL.md` opens on line 1 with a `---` delimited YAML block, or the lint reports
`FRONTMATTER_MISSING`:

```yaml
---
name: unopim-datagrid
description: Use when building or changing an UnoPim admin listing page — a DataGrid class with columns, search, filters, sorting, row actions or mass actions, or the Blade view that renders it. Trigger phrases include "datagrid", "admin listing", "add a column", "mass action", "prepareQueryBuilder", "listing page".
requires: unopim-standards, unopim-verify
---
```

| Field | Rule | Lint code |
|---|---|---|
| `name` | Required. Lowercase letters, digits and hyphens only, and identical to the directory name. Unique across the repository. | `NAME_MISSING`, `NAME_FORMAT`, `NAME_MISMATCH`, `DUPLICATE_NAME` |
| `description` | Required. Third person. Begins `Use when`. States triggering conditions only — never a summary of what the skill tells the agent to do. Ends with a `Trigger phrases include "…"` sentence listing the literal phrases a developer would type. At most 900 characters. | `DESCRIPTION_MISSING`, `DESCRIPTION_PREFIX`, `DESCRIPTION_TRIGGERS`, `DESCRIPTION_LENGTH` |
| `requires` | Optional. Comma-separated skill names that must be present for this one to work. Every name must be a real skill directory. `bin/install-skills.sh` resolves the chain transitively, so list only direct dependencies. | `REQUIRES_UNRESOLVED` |

The description is the only thing an agent reads when deciding whether to load the skill. Write it
for that one decision. "Use when building an admin listing page" earns a load; "Comprehensive
DataGrid guide" does not.

## 3. Size

| File | Cap | Lint code |
|---|---|---|
| `SKILL.md` | 150 lines | `SIZE_SKILL` |
| Any other `*.md` in the skill directory | 500 lines | `SIZE_REFERENCE` |

Overflow moves into a reference file in the same directory, linked from `SKILL.md`. A `SKILL.md` is
an index and a decision procedure, not a manual. If a skill genuinely cannot fit — a canon skill
that is one long rule table — add its directory name to `skills/.lint-allow`, one name per line, in
the same pull request that makes it exceed the cap, and say in the description why.

## 4. Links and citations

- Every relative `*.md` link must resolve inside the skill directory (`DANGLING_LINK`).
- Every exemplar path is written as a backticked repository-relative path — `` `packages/Webkul/DataGrid/src/Enums/ColumnTypeEnum.php` `` — and must exist in an UnoPim checkout. CI validates this with `--unopim` (`EXEMPLAR_MISSING`). Citations therefore cannot rot; when upstream moves a file, the build says so.
- Cite a real in-repo file rather than paraphrasing generic Laravel advice. A path an agent can open beats a paragraph it has to trust.
- Never commit a machine-specific path — nothing rooted in a home directory (`/home`, `/Users`) or a server root (`/var/www`), and no hostname, port or credential. This is a public repository. Use a repo-relative path or a documented variable such as `$UNOPIM` (`ABSOLUTE_PATH`).

## 5. A new skill needs a recorded baseline

Before adding a skill, run the task it targets **without** it and record what went wrong: the wrong
file, the missing gate, the hallucinated API, the raw `<input>`. Save that transcript as
`skills/tests/scenarios/<skill-name>/baseline.md`, and the run with the skill loaded as
`with-skill.md` beside it. Link both from the pull request.

No baseline, no skill. A skill that cannot name the failure it prevents is documentation, and
documentation belongs in the UnoPim docs site, not in an agent's context window.

## 6. Naming

- Prefix `unopim-`, then the surface: `unopim-datagrid`, `unopim-data-transfer`.
- Name the domain, not the activity: `unopim-datagrid`, not `unopim-build-a-listing`.
- Names are a public interface. Renaming one breaks every installed checkout, so keep the old
  directory as a stub pointing at the new skill for one release before deleting it.

## 7. Tests

`skills/tests/run-tests.sh` sources every `skills/tests/*.test.sh`. Add checks for anything you add
to `bin/` or `hooks/`, and write the assertion before the implementation — a test you never saw fail
proves nothing. Fixtures live under `skills/tests/fixtures/`; tests resolve every path from
`$REPO_ROOT` and `$FIXTURES` so the suite runs from any checkout.

## 8. Before you open the pull request

- [ ] `bin/lint-skills.sh --unopim <unopim-checkout>` reports `skills lint clean`.
- [ ] `skills/tests/run-tests.sh` exits 0.
- [ ] The README skill list carries the new or changed `description` verbatim.
- [ ] Any mechanical rule you were tempted to write in prose is a rule in `hooks/rules.txt` with a test.
- [ ] A new skill has its baseline scenario committed.
