#!/usr/bin/env bash
#
# Copyright (C) 2020 Vy
#
# Distributed under terms of the MIT license.
#
# Script that can be used to replace placeholders in files.

set -euo pipefail
IFS=$'\n\t'

main() {
  local placeholders values search_files timestamp \
    i placeholder value f
  placeholders=()
  values=()
  while [ -n "${1:-}" ]; do
    case "$1" in
      --*) placeholders+=("${1#"--"}"); shift; if test -n "${1:-}"; then values+=("$1"); shift; else echo "Missing placeholder value"; exit 1; fi;;
      *) echo "Unknown parameter format '$1'"; exit 1 ;;
    esac
  done
  search_files=()
  while read -r -d ''; do
    search_files+=("$REPLY")
  done < <(find . -type f \( -wholename "*/terraform/*/main.tf" \) -print0)
  timestamp="$(date +%s)"
  for i in "${!placeholders[@]}"; do
    placeholder="${placeholders[i]}"
    value="${values[i]}"
    for f in "${search_files[@]}"; do
      # GNU and FreeBSD sed work in different ways. This command should work for both
      sed -i."${timestamp}.tmp" "s/<$placeholder>/$value/g" "$f" && test -f "$f.$timestamp.tmp" && rm "$f.$timestamp.tmp"
    done
  done
}

main "$@"
