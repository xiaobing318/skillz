#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_PATH="$SCRIPT_ROOT/ResolveCodexContext.json"
OUTPUT_JSON_PATH=""
PLATFORM_INFO_SCRIPT="ResolvePlatformInfo.sh"
DEFAULT_ENABLED_SCRIPTS=("$PLATFORM_INFO_SCRIPT")
ALLOWED_ENABLED_SCRIPTS=("$PLATFORM_INFO_SCRIPT")
ENABLED_SCRIPTS=()

print_help() {
  cat <<'EOF'
ResolveCodexContext.sh

Usage:
  bash .codex/HelperScripts/macOS/ResolveCodexContext.sh [--help]
  bash .codex/HelperScripts/macOS/ResolveCodexContext.sh [--config <path>] [--outputJsonPath <path>]

Parameters:
  --help                  Show this help message and exit.
  --config <path>         Read the specified JSON config file. Defaults to ResolveCodexContext.json next to this script.
  --outputJsonPath <path> Write the JSON result to the specified path. Existing files are overwritten. Defaults to terminal output only.

Config:
  EnabledScripts controls which discovery scripts run. Allowed values:
    ResolvePlatformInfo.sh

EOF
}

if [[ $# -eq 1 && "${1-}" == "--help" ]]; then
  print_help
  exit 0
fi

# shellcheck source=../Shared/ShellJsonHelpers.sh
. "$SCRIPT_ROOT/../Shared/ShellJsonHelpers.sh"
# shellcheck source=ResolvePlatformInfo.sh
. "$SCRIPT_ROOT/$PLATFORM_INFO_SCRIPT"

is_absolute_path() {
  local value=${1-}
  [[ "$value" = /* || "$value" =~ ^[A-Za-z]:[\\/] ]]
}

resolve_user_path() {
  local value=$1
  if is_absolute_path "$value"; then
    printf '%s' "$value"
  else
    printf '%s/%s' "$(pwd -P)" "$value"
  fi
}

write_context_output() {
  local context_json=$1
  local output_json_path=${2-}
  if [[ -n "$output_json_path" ]]; then
    local resolved_output
    resolved_output=$(resolve_user_path "$output_json_path")
    mkdir -p "$(dirname "$resolved_output")"
    printf '%s\n' "$context_json" > "$resolved_output"
  else
    printf '%s\n' "$context_json"
  fi
}

write_invalid_input_and_exit() {
  local code=$1
  local text=$2
  local output_json_path=${3-}
  local context_json
  context_json="{\"Status\":\"InvalidInput\",\"Messages\":[{\"Level\":\"Error\",\"Code\":$(json_string "$code"),\"Text\":$(json_string "$text")}]}";
  write_context_output "$context_json" "$output_json_path"
  exit 1
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        print_help
        exit 0
        ;;
      --config)
        if [[ $# -lt 2 || -z "${2-}" || "${2-}" == --* ]]; then
          write_invalid_input_and_exit "MissingConfigPath" "--config requires a path." "$OUTPUT_JSON_PATH"
        fi
        CONFIG_PATH=$(resolve_user_path "$2")
        shift 2
        ;;
      --outputJsonPath)
        if [[ $# -lt 2 || -z "${2-}" || "${2-}" == --* ]]; then
          write_invalid_input_and_exit "MissingOutputJsonPath" "--outputJsonPath requires a path." "$OUTPUT_JSON_PATH"
        fi
        OUTPUT_JSON_PATH="$2"
        shift 2
        ;;
      *)
        write_invalid_input_and_exit "UnknownArgument" "Unknown argument: $1" "$OUTPUT_JSON_PATH"
        ;;
    esac
  done
}

script_name_allowed() {
  local value=$1
  local allowed
  for allowed in "${ALLOWED_ENABLED_SCRIPTS[@]}"; do
    [[ "$value" == "$allowed" ]] && return 0
  done
  return 1
}

script_enabled() {
  local name=$1
  local value
  for value in "${ENABLED_SCRIPTS[@]}"; do
    [[ "$value" == "$name" ]] && return 0
  done
  return 1
}

is_supported_platform() {
  local os_name=$1
  local isa=$2
  case "$os_name/$isa" in
    Windows/AMD64|Windows/ARM64|Linux/AMD64|Linux/ARM64|macOS/ARM64)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_enabled_scripts() {
  local seen="|"
  local output
  local line
  ENABLED_SCRIPTS=()

  if ! command -v python3 >/dev/null 2>&1; then
    write_invalid_input_and_exit "Python3NotFound" "python3 is required to parse ResolveCodexContext.json." "$OUTPUT_JSON_PATH"
  fi

  if ! output=$(python3 - "$CONFIG_PATH" 2>&1 <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8-sig") as handle:
        data = json.load(handle)
except Exception as exc:
    print(f"ConfigInvalid: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print("EnabledScriptsInvalid: Config root must be a JSON object.", file=sys.stderr)
    sys.exit(1)

if "EnabledScripts" not in data:
    print("__DEFAULT__")
    sys.exit(0)

enabled = data["EnabledScripts"]
if not isinstance(enabled, list):
    print("EnabledScriptsInvalid: EnabledScripts must be an array of strings.", file=sys.stderr)
    sys.exit(1)

for item in enabled:
    if not isinstance(item, str) or item.strip() == "":
        print("EnabledScriptsInvalid: EnabledScripts must contain only non-empty strings.", file=sys.stderr)
        sys.exit(1)
    print(item)
PY
  ); then
    local error_code="ConfigInvalid"
    local error_text="$output"
    case "$output" in
      EnabledScriptsInvalid:*)
        error_code="EnabledScriptsInvalid"
        error_text=${output#EnabledScriptsInvalid: }
        ;;
      ConfigInvalid:*)
        error_text=${output#ConfigInvalid: }
        ;;
    esac
    write_invalid_input_and_exit "$error_code" "$error_text" "$OUTPUT_JSON_PATH"
  fi

  if [[ "$output" == "__DEFAULT__" ]]; then
    ENABLED_SCRIPTS=("${DEFAULT_ENABLED_SCRIPTS[@]}")
  else
    while IFS= read -r line; do
      [[ -n "$line" ]] && ENABLED_SCRIPTS+=("$line")
    done <<< "$output"
  fi

  for line in "${ENABLED_SCRIPTS[@]}"; do
    if ! script_name_allowed "$line"; then
      write_invalid_input_and_exit "EnabledScriptsInvalid" "Unsupported EnabledScripts value: $line" "$OUTPUT_JSON_PATH"
    fi
    if [[ "$seen" == *"|$line|"* ]]; then
      write_invalid_input_and_exit "EnabledScriptsInvalid" "Duplicate EnabledScripts value: $line" "$OUTPUT_JSON_PATH"
    fi
    seen="$seen$line|"
  done
}

parse_arguments "$@"

if [[ ! -r "$CONFIG_PATH" ]]; then
  write_invalid_input_and_exit "ConfigNotFound" "Config file not found: $CONFIG_PATH" "$OUTPUT_JSON_PATH"
fi

load_enabled_scripts

STATUS="Ok"
FIELDS=()
MESSAGES=()
PLATFORM_INFO_JSON="{}"
PLATFORM_OS=""
PLATFORM_ISA=""

REPO_ROOT=$(cd "$SCRIPT_ROOT/../../.." && pwd)

if script_enabled "$PLATFORM_INFO_SCRIPT"; then
  resolve_platform_info "$REPO_ROOT"
  FIELDS+=("\"PlatformInfo\":$PLATFORM_INFO_JSON")
  if ! is_supported_platform "$PLATFORM_OS" "$PLATFORM_ISA"; then
    STATUS="Unsupported"
  fi
fi

if [[ ${#ENABLED_SCRIPTS[@]} -eq 0 ]]; then
  MESSAGES+=("{\"Level\":\"Info\",\"Code\":\"NoDiscoveryScriptsEnabled\",\"Text\":\"EnabledScripts is empty, no discovery scripts were executed.\"}")
fi

FIELDS=("\"Status\":$(json_string "$STATUS")" "${FIELDS[@]}")
if [[ ${#MESSAGES[@]} -gt 0 ]]; then
  FIELDS+=("\"Messages\":[$(join_json_items "${MESSAGES[@]}")]")
fi

write_context_output "{$(join_json_items "${FIELDS[@]}")}" "$OUTPUT_JSON_PATH"
