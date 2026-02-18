# blockr.ci

[![ci](https://github.com/cynkra/blockr.ci/actions/workflows/ci.yaml/badge.svg)](https://github.com/cynkra/blockr.ci/actions/workflows/ci.yaml)

Reusable GitHub Actions CI workflows for the [blockr](https://github.com/blockr-org) ecosystem.

## Usage

Replace your repo's `.github/workflows/` contents with two files:

### `.github/workflows/ci.yaml`

```yaml
on:
  push:
    branches: main
  pull_request:
    branches: main

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
lint → smoke → check       (multi-platform, push only)
             → coverage
             → revdep      (if configured)
             → pkgdown
```

All steps are mandatory — a consumer gets the full pipeline or none of it.

## Inputs

| Input | Type | Default | Purpose |
|---|---|---|---|
| `revdep-packages` | JSON array string | `'[]'` | Downstream packages to reverse-dep check. Empty skips the job. |
| `extra-pkgdown-packages` | string | `''` | Additional pak refs for pkgdown (e.g. `github::DivadNojnarg/DiagrammeR`) |
| `lintr-exclusions` | string | `''` | Comma-separated file paths to exclude from linting |
| `skip-pkgdown` | boolean | `false` | Skip pkgdown for repos with custom site builds |

### Example with all inputs

```yaml
jobs:
  ci:
    uses: cynkra/blockr.ci/.github/workflows/ci.yaml@main
    with:
      revdep-packages: '["cynkra/blockr.dock", "cynkra/blockr.dag"]'
      extra-pkgdown-packages: "github::DivadNojnarg/DiagrammeR"
      lintr-exclusions: "vignettes/foo.qmd, vignettes/bar.qmd"
    secrets: inherit
    permissions:
      contents: write
```

## What's included

- **Lint** with a canonical lintr config (`object_name_linter = NULL`)
- **Smoke test** — single-platform R CMD check (PR gate)
- **Full check** — 4-platform matrix (macOS, Windows, Ubuntu devel, Ubuntu oldrel), push only
- **Coverage** via covr + codecov
- **Reverse-dependency checks** against configurable downstream packages
- **pkgdown** site build + deploy to gh-pages
- **parse-deps** — override dependency versions via a `` ```deps `` block in the PR body
- **deps-rerun** — automatically re-run affected jobs when the deps block changes

## Overriding dependency refs in PRs

When developing across blockr packages, you often need CI to test against a branch or PR of an upstream dependency rather than the released version. Add a fenced `deps` block to the PR body to override what gets installed during smoke, check, and revdep jobs:

````markdown
```deps
cynkra/blockr.core@my-feature-branch
cynkra/blockr.dock#42
```
````

Each line is a pak ref. Two override syntaxes are supported:

- **`owner/repo@branch`** — install from a specific branch
- **`owner/repo#123`** — install from a pull request

These refs are passed to `r-lib/actions/setup-r-dependencies` as extra packages and override whatever version would normally be installed. For revdep checks, the `#123` and `@branch` syntax also controls which ref of the downstream package gets checked out.

### How it works

The **parse-deps** composite action extracts the `deps` block from the PR body on every CI run. The **deps-rerun** workflow watches for PR body edits — when the `deps` block changes, it automatically re-runs the smoke and revdep jobs without needing a new push.

### Example

You're working on `blockr.dock` and need it tested against an in-progress PR on `blockr.core`:

1. Open your PR on `blockr.dock`
2. Add to the PR body:

   ````markdown
   ```deps
   cynkra/blockr.core#87
   ```
   ````

3. CI installs `blockr.core` from PR #87 instead of the default branch
4. If you later change the deps block (e.g., point to a different PR), the affected jobs re-run automatically

## Required secrets

- `BLOCKR_PAT` — GitHub PAT with access to private blockr repos
- `CODECOV_TOKEN` — for coverage uploads
