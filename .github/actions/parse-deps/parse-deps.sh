#!/usr/bin/env bash
# Parse the ```deps block from a PR body.
# Env vars: PR_BODY, PR_NUMBER, GH_TOKEN, PKG, BASE_PACKAGES, GITHUB_OUTPUT

if [[ -n "$PR_NUMBER" && -n "$GH_TOKEN" && -n "$GITHUB_REPOSITORY" ]]; then
  fresh_body=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" --jq '.body' 2>/dev/null || true)
  if [[ -n "$fresh_body" ]]; then
    PR_BODY="$fresh_body"
  fi
fi

declare -A dep_map
dep_keys=()

add_dep() {
  local full_ref="$1"
  local key="${full_ref%%[@#]*}"
  if [[ -z "${dep_map[$key]+x}" ]]; then
    dep_keys+=("$key")
  fi
  dep_map["$key"]="$full_ref"
}

deps=$(echo "$PR_BODY" | tr -d '\r' \
  | sed -n '/^```deps$/,/^```$/p' \
  | grep -v '^```' || true)

if [[ -n "$deps" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    add_dep "$line"
  done <<< "$deps"
fi

extra="$BASE_PACKAGES"
for key in "${dep_keys[@]}"; do
  extra="${extra}
${dep_map[$key]}"
done

ref=""
if [[ -n "$PKG" ]]; then
  if [[ -n "${dep_map[$PKG]+x}" ]]; then
    entry="${dep_map[$PKG]}"
    if echo "$entry" | grep -q '#'; then
      pr_num=$(echo "$entry" | sed 's/.*#\([0-9]*\).*/\1/')
      ref="refs/pull/${pr_num}/head"
    elif echo "$entry" | grep -q '@'; then
      ref=$(echo "$entry" | sed 's/^[^@]*@//')
    fi
  fi
fi

{ echo "extra-packages<<EOF"; echo "$extra"; echo "EOF"; } >> "$GITHUB_OUTPUT"
echo "ref=${ref}" >> "$GITHUB_OUTPUT"
