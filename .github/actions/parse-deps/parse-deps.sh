#!/usr/bin/env bash
# Parse the ```deps block from a PR body.
# Env vars: PR_BODY, PKG, BASE_PACKAGES, GITHUB_OUTPUT

extra="$BASE_PACKAGES"
ref=""
deps=$(echo "$PR_BODY" | tr -d '\r' \
  | sed -n '/^```deps$/,/^```$/p' \
  | grep -v '^```' || true)
if [ -n "$deps" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    extra="${extra}
${line}"
  done <<< "$deps"
  if [ -n "$PKG" ]; then
    line=$(echo "$deps" | grep "^${PKG}" | head -1)
    if [ -n "$line" ]; then
      if echo "$line" | grep -q '#'; then
        pr_num=$(echo "$line" | sed 's/.*#\([0-9]*\).*/\1/')
        ref="refs/pull/${pr_num}/head"
      elif echo "$line" | grep -q '@'; then
        ref=$(echo "$line" | sed 's/^[^@]*@//')
      fi
    fi
  fi
fi
{ echo "extra-packages<<EOF"; echo "$extra"; echo "EOF"; } >> "$GITHUB_OUTPUT"
echo "ref=${ref}" >> "$GITHUB_OUTPUT"
