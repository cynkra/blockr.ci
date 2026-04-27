#!/usr/bin/env bash
# Parse the ```deps block from a PR body.
# Env vars: PR_BODY, PR_NUMBER, GH_TOKEN, PKG, BASE_PACKAGES, GITHUB_OUTPUT
#
# The deps block is for per-PR revdep ref overrides ONLY: each entry tells
# the revdep job which branch / PR of a downstream package to check out.
# Forward-dep overrides belong in DESCRIPTION's Remotes: field, not here.
#
# Implications:
#   * Deps-block entries are never added to extra-packages.
#   * If an entry's package name matches a forward dep of the package under
#     test (Imports/Depends/LinkingTo/Suggests, or a Remotes: line), that's
#     a misuse — error out with a pointer to Remotes:.

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

# Locate DESCRIPTION. Most jobs check the package out at the repo root; the
# revdep job checks it out under ./pkg.
desc=""
for candidate in DESCRIPTION pkg/DESCRIPTION; do
  if [[ -f "$candidate" ]]; then
    desc="$candidate"
    break
  fi
done

dcf_field() {
  local field="$1" file="$2"
  awk -v F="$field" '
    /^[[:alpha:]][[:alnum:]._-]*:/ {
      name = $0; sub(/:.*/, "", name)
      if (capture) exit
      if (name == F) {
        capture = 1
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val)
      }
      next
    }
    capture && /^[[:space:]]/ {
      line = $0; sub(/^[[:space:]]+/, "", line)
      val = val " " line
    }
    END { if (capture) print val }
  ' "$file"
}

forward_deps=""
if [[ -n "$desc" ]]; then
  tmp=""
  for f in Imports Depends LinkingTo Suggests; do
    val=$(dcf_field "$f" "$desc")
    if [[ -n "$val" ]]; then
      names=$(echo "$val" | tr ',' '\n' \
        | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]*\(.*$//')
      tmp+=$'\n'"$names"
    fi
  done
  remotes_val=$(dcf_field "Remotes" "$desc")
  if [[ -n "$remotes_val" ]]; then
    names=$(echo "$remotes_val" | tr ',' '\n' \
      | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[@#].*$//; s|^.*/||')
    tmp+=$'\n'"$names"
  fi
  forward_deps=$(echo "$tmp" | sort -u | grep -v '^$\|^R$' || true)
else
  echo "::warning::parse-deps: no DESCRIPTION found at ./ or pkg/; skipping forward-dep validation" >&2
fi

errors=()
for key in "${dep_keys[@]}"; do
  pkg_name="${key##*/}"
  if [[ -n "$forward_deps" ]] && grep -qFx "$pkg_name" <<< "$forward_deps"; then
    errors+=("'${dep_map[$key]}' targets '$pkg_name', which is a forward dependency. The deps block is for revdep refs only; forward-dep overrides belong in DESCRIPTION's Remotes: field.")
  fi
done

if [[ ${#errors[@]} -gt 0 ]]; then
  {
    echo "parse-deps: invalid deps block"
    for e in "${errors[@]}"; do
      echo "  - $e"
    done
  } >&2
  exit 1
fi

# extra-packages = base only. Deps-block entries are never deps.
extra="$BASE_PACKAGES"

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
