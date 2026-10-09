#!/bin/bash

set -e
set -u

utility_dir="${SCRIPTS_UTILITY_D:="docker/utility.d"}"
utility_db="$utility_dir/database.sh"

function check_database() {
	local database="$1"
	check_db=$("$utility_db" "--function=checkdb" "$database")

	echo "$check_db"
}

if [ -f "$utility_db" ]; then
  default_db=$("$utility_db" "--function=defaultdb")

  if [ -n "$default_db" ]; then
    echo "Default database healthcheck: $default_db"
    check_database $default_db
  fi

  echo "Default databases healthy"
  exit 0
fi