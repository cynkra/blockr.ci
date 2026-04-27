#!/usr/bin/env bats

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../parse-deps/parse-deps.sh"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
  > "$GITHUB_OUTPUT"
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
