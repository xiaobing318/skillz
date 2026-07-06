#!/usr/bin/env bash

json_escape() {
  local value=${1-}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

json_string() {
  printf '"%s"' "$(json_escape "${1-}")"
}

json_bool() {
  if [[ "${1-}" == "true" || "${1-}" == "1" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

join_json_items() {
  local first=true
  local item
  for item in "$@"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ','
    fi
    printf '%s' "$item"
  done
}
