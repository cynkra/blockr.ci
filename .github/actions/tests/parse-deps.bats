#!/usr/bin/env bats

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../parse-deps/parse-deps.sh"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
  > "$GITHUB_OUTPUT"

  # New inputs default to empty (backward compat with existing tests)
  export DESCRIPTION_PATH=""
  export DEFAULT_DEPS=""
  export REGISTRY=""
}

get_output() {
  local key="$1"
  if grep -q "^${key}<<EOF" "$GITHUB_OUTPUT"; then
    sed -n "/^${key}<<EOF$/,/^EOF$/p" "$GITHUB_OUTPUT" | sed '1d;$d'
  else
    grep "^${key}=" "$GITHUB_OUTPUT" | sed "s/^${key}=//"
  fi
}

@test "no deps block: extra-packages = base-packages only, ref empty" {
  export PR_BODY="Just a regular PR body with no deps."
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output extra-packages)" "any::rcmdcheck"
  assert_equal "$(get_output ref)" ""
}

@test "single dep appended to base-packages" {
  export PR_BODY='Some text
```deps
owner/repo
```
More text'
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
owner/repo"
  assert_equal "$(get_output ref)" ""
}

@test "multiple deps all appended in order" {
  export PR_BODY='```deps
owner/alpha
owner/beta
owner/gamma
```'
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
owner/alpha
owner/beta
owner/gamma"
}

@test "PR number syntax: ref = refs/pull/N/head" {
  export PR_BODY='```deps
owner/repo#42
```'
  export PKG="owner/repo"
  export BASE_PACKAGES="any::rcmdcheck"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output ref)" "refs/pull/42/head"
}

@test "branch syntax: ref = branch name" {
  export PR_BODY='```deps
owner/repo@feature-branch
```'
  export PKG="owner/repo"
  export BASE_PACKAGES="any::rcmdcheck"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output ref)" "feature-branch"
}

@test "PKG not matching any dep: ref empty" {
  export PR_BODY='```deps
owner/other@main
```'
  export PKG="owner/repo"
  export BASE_PACKAGES="any::rcmdcheck"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output ref)" ""
}

@test "PKG not set: ref empty" {
  export PR_BODY='```deps
owner/repo@main
```'
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output ref)" ""
}

@test "Windows line endings stripped" {
  export PR_BODY=$'```deps\r\nowner/repo@main\r\n```\r\n'
  export PKG="owner/repo"
  export BASE_PACKAGES="any::rcmdcheck"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output ref)" "main"
  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
owner/repo@main"
}

@test "blank lines in deps block are skipped" {
  export PR_BODY='```deps
owner/alpha

owner/beta
```'
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
owner/alpha
owner/beta"
}

@test "custom base-packages used instead of default" {
  export PR_BODY='```deps
owner/repo
```'
  export PKG=""
  export BASE_PACKAGES="custom::pkg1
custom::pkg2"

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "custom::pkg1
custom::pkg2
owner/repo"
}

# ── Registry resolution tests ──────────────────────────────────────────

@test "registry: DESCRIPTION dep resolved via registry" {
  export PR_BODY=""
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"

  # Create a DESCRIPTION file listing blockr.core in Imports
  export DESCRIPTION_PATH="$BATS_TEST_TMPDIR/DESCRIPTION"
  cat > "$DESCRIPTION_PATH" <<'DESC'
Package: mypkg
Title: Test
Imports:
    shiny,
    blockr.core
DESC

  # Create a registry file
  export REGISTRY="$BATS_TEST_TMPDIR/registry.txt"
  cat > "$REGISTRY" <<'REG'
blockr.core=BristolMyersSquibb/blockr.core
blockr.dock=BristolMyersSquibb/blockr.dock
REG

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
BristolMyersSquibb/blockr.core"
}

@test "registry: dep not in registry is not added" {
  export PR_BODY=""
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"

  export DESCRIPTION_PATH="$BATS_TEST_TMPDIR/DESCRIPTION"
  cat > "$DESCRIPTION_PATH" <<'DESC'
Package: mypkg
Title: Test
Imports:
    shiny,
    ggplot2
DESC

  export REGISTRY="$BATS_TEST_TMPDIR/registry.txt"
  cat > "$REGISTRY" <<'REG'
blockr.core=BristolMyersSquibb/blockr.core
REG

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output extra-packages)" "any::rcmdcheck"
}

@test "default-deps: extra deps added to extra-packages" {
  export PR_BODY=""
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"
  export DEFAULT_DEPS="cynkra/g6R
owner/extra"

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
cynkra/g6R
owner/extra"
}

@test "override: default-deps overrides registry" {
  export PR_BODY=""
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"

  export DESCRIPTION_PATH="$BATS_TEST_TMPDIR/DESCRIPTION"
  cat > "$DESCRIPTION_PATH" <<'DESC'
Package: mypkg
Imports: blockr.core
DESC

  export REGISTRY="$BATS_TEST_TMPDIR/registry.txt"
  echo "blockr.core=BristolMyersSquibb/blockr.core" > "$REGISTRY"

  export DEFAULT_DEPS="BristolMyersSquibb/blockr.core@dev"

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
BristolMyersSquibb/blockr.core@dev"
}

@test "override: PR body overrides default-deps" {
  export PR_BODY='```deps
cynkra/g6R@feature
```'
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"
  export DEFAULT_DEPS="cynkra/g6R@main"

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
cynkra/g6R@feature"
}

@test "override: PR body overrides registry" {
  export PR_BODY='```deps
BristolMyersSquibb/blockr.core@feature
```'
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"

  export DESCRIPTION_PATH="$BATS_TEST_TMPDIR/DESCRIPTION"
  cat > "$DESCRIPTION_PATH" <<'DESC'
Package: mypkg
Imports: blockr.core
DESC

  export REGISTRY="$BATS_TEST_TMPDIR/registry.txt"
  echo "blockr.core=BristolMyersSquibb/blockr.core" > "$REGISTRY"

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
BristolMyersSquibb/blockr.core@feature"
}

@test "ref extraction: PKG from registry (bare ref)" {
  export PR_BODY=""
  export PKG="BristolMyersSquibb/blockr.core"
  export BASE_PACKAGES="any::rcmdcheck"

  export DESCRIPTION_PATH="$BATS_TEST_TMPDIR/DESCRIPTION"
  cat > "$DESCRIPTION_PATH" <<'DESC'
Package: mypkg
Imports: blockr.core
DESC

  export REGISTRY="$BATS_TEST_TMPDIR/registry.txt"
  echo "blockr.core=BristolMyersSquibb/blockr.core" > "$REGISTRY"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output ref)" ""
}

@test "ref extraction: PKG from default-deps with @branch" {
  export PR_BODY=""
  export PKG="cynkra/g6R"
  export BASE_PACKAGES="any::rcmdcheck"
  export DEFAULT_DEPS="cynkra/g6R@develop"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output ref)" "develop"
}

@test "no description-path: backward compat, no registry resolution" {
  export PR_BODY='```deps
owner/repo
```'
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"
  export DESCRIPTION_PATH=""
  export DEFAULT_DEPS=""

  run bash "$SCRIPT"
  assert_success

  result=$(get_output extra-packages)
  assert_equal "$result" "any::rcmdcheck
owner/repo"
}

@test "DESCRIPTION file missing: graceful no-op" {
  export PR_BODY=""
  export PKG=""
  export BASE_PACKAGES="any::rcmdcheck"
  export DESCRIPTION_PATH="$BATS_TEST_TMPDIR/nonexistent_DESCRIPTION"
  export REGISTRY="$BATS_TEST_TMPDIR/registry.txt"
  echo "blockr.core=BristolMyersSquibb/blockr.core" > "$REGISTRY"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(get_output extra-packages)" "any::rcmdcheck"
  assert_equal "$(get_output ref)" ""
}
