#!/bin/bash

set -e
set -u

script="$0"
cd "$(dirname "$script")"

for s in *.sh; do
  # Check if the item is a regular file (skips directories)
  [ -f "$s" ] || continue

  # Skip the runner script itself
  if [ "$s" = "${script##*/}" ]; then
    continue
  fi
  
  # Run the script and check its exit code
  echo "Running healthcheck script '$s'"
  "./$s" || exit 1
done