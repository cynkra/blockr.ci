# blockr.ci

[![ci](https://github.com/cynkra/blockr.ci/actions/workflows/ci.yaml/badge.svg)](https://github.com/cynkra/blockr.ci/actions/workflows/ci.yaml)

Reusable GitHub Actions CI workflows for the [blockr](https://bristolmyerssquibb.github.io/blockr-site/) ecosystem.

## Usage

Replace your repo's `.github/workflows/` contents with two files:

### `.github/workflows/ci.yaml`

```yaml
on:
  push:
    branches: main
  pull_request:
  merge_group:

name: ci

jobs:
  ci:
    uses: cynkra/blockr.ci/.github/workflows/ci.yaml@main
    secrets: inherit
    permissions:
      contents: write
```

### `.github/workflows/deps-rerun.yaml`

```yaml
on:
  pull_request:
    branches: main
    types: [edited]

name: deps-rerun

jobs:
  rerun:
    uses: cynkra/blockr.ci/.github/workflows/deps-rerun.yaml@main
    secrets: inherit
```

## Pipeline

```
lint → smoke → check       (multi-platform, merge queue + push)
             → coverage
             → revdep      (if configured)
             → pkgdown
```

All steps are mandatory — a consumer gets the full pipeline or none of it.

## Inputs

| Input | Type | Default | Purpose |
|---|---|---|---|
| `revdep-packages` | newline-separated list | `''` | Downstream packages to reverse-dep check. Empty skips the job. |
| `lintr-exclusions` | newline-separated list | `''` | File paths to exclude from linting |
| `skip-pkgdown` | boolean | `false` | Skip pkgdown for repos with custom site builds |
| `default-deps` | newline-separated list | `''` | Extra pak refs always included in dependency resolution (e.g., `cynkra/g6R`). Overrides registry; overridden by PR body deps block. |

### Example with all inputs

```yaml
jobs:
  ci:
    uses: cynkra/blockr.ci/.github/workflows/ci.yaml@main
    with:
      revdep-packages: |
        cynkra/blockr.dock
        cynkra/blockr.dag
      lintr-exclusions: |
        vignettes/foo.qmd
        vignettes/bar.qmd
      default-deps: |
        cynkra/g6R
    secrets: inherit
    permissions:
      contents: write
```

## What's included

- **Lint** with a canonical lintr config (`object_name_linter = NULL`)
- **Smoke test** — single-platform R CMD check (PR gate)
- **Full check** — 4-platform matrix (macOS, Windows, Ubuntu devel, Ubuntu oldrel), merge queue + push
- **Coverage** via covr + codecov
- **Reverse-dependency checks** against configurable downstream packages
- **pkgdown** site build + deploy to gh-pages
- **parse-deps** — override dependency versions via a `` ```deps `` block in the PR body
- **deps-rerun** — automatically re-run affected jobs when the deps block changes

## Dependency resolution

Dependencies on internal blockr.\* packages are resolved automatically via three layers (lowest to highest priority):

### 1. Package registry (automatic)

A central registry file (`.github/actions/registry.txt`) maps R package names to GitHub refs:

```
blockr.core=BristolMyersSquibb/blockr.core
blockr.dock=BristolMyersSquibb/blockr.dock
blockr.dag=BristolMyersSquibb/blockr.dag
```

When a consumer package lists `blockr.core` in its DESCRIPTION `Imports`, `Depends`, or `Suggests`, CI automatically adds `BristolMyersSquibb/blockr.core` to the install list. No `Remotes:` field needed.

### 2. `default-deps` workflow input (per-repo)

For dependencies not in the registry (e.g., `cynkra/g6R`), pass them via the `default-deps` input:

```yaml
jobs:
  ci:
    uses: cynkra/blockr.ci/.github/workflows/ci.yaml@main
    with:
      default-deps: |
        cynkra/g6R
```

These override registry entries for the same `owner/repo`.

### 3. PR body `deps` block (per-PR override)

Add a fenced `deps` block to the PR body to override any dependency for that specific PR:

````markdown
```deps
BristolMyersSquibb/blockr.core@my-feature-branch
BristolMyersSquibb/blockr.dock#42
```
````

Each line is a pak ref. Two override syntaxes are supported:

- **`owner/repo@branch`** — install from a specific branch
- **`owner/repo#123`** — install from a pull request

PR body deps override both registry and `default-deps` entries for the same `owner/repo`. These refs are passed to `r-lib/actions/setup-r-dependencies` as extra packages. For revdep checks, the `#123` and `@branch` syntax also controls which ref of the downstream package gets checked out.

### How it works

The **parse-deps** composite action resolves dependencies on every CI run using the three layers above, deduplicating by `owner/repo` prefix (higher-priority layers win). The **deps-rerun** workflow watches for PR body edits — when the `deps` block changes, it automatically re-runs the smoke and revdep jobs without needing a new push.

### Example

You're working on `blockr.dock` and need it tested against an in-progress PR on `blockr.core`:

1. Open your PR on `blockr.dock`
2. `blockr.core` is already auto-resolved from the registry (installed from default branch)
3. To test against a specific PR, add to the PR body:

   ````markdown
   ```deps
   BristolMyersSquibb/blockr.core#87
   ```
   ````

4. CI installs `blockr.core` from PR #87 instead of the default branch
5. If you later change the deps block (e.g., point to a different PR), the affected jobs re-run automatically

## Secrets

- `BLOCKR_PAT` (optional) — GitHub PAT with access to private blockr repos. Falls back to `GITHUB_TOKEN` if not set, which is sufficient for public repos.
- `CODECOV_TOKEN` — for coverage uploads
