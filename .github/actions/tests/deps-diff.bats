#!/usr/bin/env bats

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../rerun-deps/deps-diff.sh"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
  > "$GITHUB_OUTPUT"
}

get_output() {
  grep "^${1}=" "$GITHUB_OUTPUT" | sed "s/^${1}=//"
}

@test "same deps in both: changed=false" {
  export OLD_BODY='```deps
owner/repo@main
```'
  export NEW_BODY='```deps
owner/repo@main
```'

  run bash "$SCRIPT"
  assert_success
  assert_equal "$(get_output changed)" "false"
}

@test "different deps: changed=true" {
  export OLD_BODY='```deps
owner/repo@main
```'
  export NEW_BODY='```deps
owner/repo@develop
```'

  run bash "$SCRIPT"
  assert_success
  assert_equal "$(get_output changed)" "true"
}

@test "no deps block in either: changed=false" {
  export OLD_BODY="Just a regular PR body."
  export NEW_BODY="Updated PR body, still no deps."

  run bash "$SCRIPT"
  assert_success
  assert_equal "$(get_output changed)" "false"
}

@test "deps block added: changed=true" {
  export OLD_BODY="No deps here."
  export NEW_BODY='Now with deps:
```deps
owner/repo@main
```'

  run bash "$SCRIPT"
  assert_success
  assert_equal "$(get_output changed)" "true"
}

@test "deps block removed: changed=true" {
  export OLD_BODY='Had deps:
```deps
owner/repo@main
```'
  export NEW_BODY="Deps removed."

  run bash "$SCRIPT"
  assert_success
  assert_equal "$(get_output changed)" "true"
}

@test "same deps different order: changed=false" {
  export OLD_BODY='```deps
owner/beta
owner/alpha
```'
  export NEW_BODY='```deps
owner/alpha
owner/beta
```'

  run bash "$SCRIPT"
  assert_success
  assert_equal "$(get_output changed)" "false"
}

@test "different surrounding text same deps: changed=false" {
  export OLD_BODY='Old description
```deps
owner/repo@main
```
Old footer'
  export NEW_BODY='New description entirely rewritten
```deps
owner/repo@main
```
New footer text'

  run bash "$SCRIPT"
  assert_success
  assert_equal "$(get_output changed)" "false"
}
