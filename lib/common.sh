#!/usr/bin/env bash
# Shared logging, validation, and LIFO cleanup helpers.
_c_reset=$'\e[0m'; _c_blue=$'\e[34m'; _c_green=$'\e[32m'
_c_yellow=$'\e[33m'; _c_red=$'\e[31m'
log()  { printf '%s==>%s %s\n' "$_c_blue" "$_c_reset" "$*"; }
ok()   { printf '%s==>%s %s\n' "$_c_green" "$_c_reset" "$*"; }
warn() { printf '%s==>%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
die()  { printf '%s==> error:%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; exit 1; }

require_root() { [[ ${EUID} -eq 0 ]] || die "must run as root"; }
require_cmds() {
  local missing=() command
  for command in "$@"; do command -v "${command}" >/dev/null 2>&1 || missing+=("${command}"); done
  ((${#missing[@]} == 0)) || die "missing commands: ${missing[*]}"
}

_cleanup_stack=()
push_cleanup() { _cleanup_stack+=("$1"); }
run_cleanup() {
  local i
  for ((i=${#_cleanup_stack[@]}-1; i>=0; i--)); do
    eval "${_cleanup_stack[i]}" || warn "cleanup failed: ${_cleanup_stack[i]}"
  done
}
trap run_cleanup EXIT
