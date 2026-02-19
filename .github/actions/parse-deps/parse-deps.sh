#!/usr/bin/env bash
# Parse the ```deps block from a PR body with layered dependency resolution.
# Env vars: PR_BODY, PKG, BASE_PACKAGES, DESCRIPTION_PATH, DEFAULT_DEPS,
#           REGISTRY, GITHUB_OUTPUT

# --- helpers ----------------------------------------------------------------

extract_r_deps() {
  awk '
    /^(Depends|Imports|Suggests):/ { in_field = 1; sub(/^[^:]*:/, ""); buf = $0; next }
    /^[[:space:]]/ && in_field { buf = buf " " $0; next }
    { if (in_field) { print buf; in_field = 0; buf = "" } }
    END { if (in_field) print buf }
  ' "$1" \
    | tr ',' '\n' \
    | sed 's/([^)]*)//g; s/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -v '^$' \
    | grep -v '^R$'
}

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

# --- layer 1: registry ------------------------------------------------------

if [[ -n "$DESCRIPTION_PATH" && -f "$DESCRIPTION_PATH" && -n "$REGISTRY" && -f "$REGISTRY" ]]; then
  while IFS= read -r pkg_name; do
    [[ -z "$pkg_name" ]] && continue
    registry_ref=$(grep "^${pkg_name}=" "$REGISTRY" | head -1 | sed "s/^${pkg_name}=//")
    if [[ -n "$registry_ref" ]]; then
      add_dep "$registry_ref"
    fi
  done < <(extract_r_deps "$DESCRIPTION_PATH")
fi

# --- layer 2: default-deps --------------------------------------------------

if [[ -n "$DEFAULT_DEPS" ]]; then
  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$line" ]] && continue
    add_dep "$line"
  done <<< "$DEFAULT_DEPS"
fi

# --- layer 3: PR body deps block --------------------------------------------

deps=$(echo "$PR_BODY" | tr -d '\r' \
  | sed -n '/^```deps$/,/^```$/p' \
  | grep -v '^```' || true)

if [[ -n "$deps" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    add_dep "$line"
  done <<< "$deps"
fi

# --- build output ------------------------------------------------------------

extra="$BASE_PACKAGES"
for key in "${dep_keys[@]}"; do
  extra="${extra}
${dep_map[$key]}"
done

ref=""
if [[ -n "$PKG" ]]; then
  pkg_key="$PKG"
  if [[ -n "${dep_map[$pkg_key]+x}" ]]; then
    entry="${dep_map[$pkg_key]}"
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
