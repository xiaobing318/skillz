#!/usr/bin/env bash

resolve_platform_info() {
  local repo_root=$1
  local os_name="Linux"
  local os_version
  local raw_arch
  local isa

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_version=${PRETTY_NAME:-Linux}
  else
    os_version=$(uname -sr 2>/dev/null || printf 'Linux')
  fi

  raw_arch=$(uname -m 2>/dev/null || printf 'unknown')
  case "$raw_arch" in
    x86_64|amd64) isa="AMD64" ;;
    aarch64|arm64) isa="ARM64" ;;
    *) isa="$raw_arch" ;;
  esac

  PLATFORM_INFO_JSON="{\"OS\":$(json_string "$os_name"),\"OSVersion\":$(json_string "$os_version"),\"ISA\":$(json_string "$isa"),\"RawArchitecture\":$(json_string "$raw_arch")}"
  PLATFORM_OS="$os_name"
  PLATFORM_ISA="$isa"
}
