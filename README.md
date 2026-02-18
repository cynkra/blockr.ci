# blockr.ci

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

## Required secrets

- `BLOCKR_PAT` — GitHub PAT with access to private blockr repos
- `CODECOV_TOKEN` — for coverage uploads
