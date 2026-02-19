#!/usr/bin/env bash
# Compare ```deps blocks between two PR body versions.
# Env vars: OLD_BODY, NEW_BODY, GITHUB_OUTPUT

extract_deps() {
  echo "$1" | tr -d '\r' \
    | sed -n '/^```deps$/,/^```$/p' \
    | grep -v '^```' \
    | sort
}
if [ "$(extract_deps "$OLD_BODY")" = "$(extract_deps "$NEW_BODY")" ]; then
  echo "changed=false" >> "$GITHUB_OUTPUT"
else
  echo "changed=true" >> "$GITHUB_OUTPUT"
fi
