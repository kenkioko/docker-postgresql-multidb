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
  multiple_db=$("$utility_db" "--function=multipledb")

	if [ -n "$multiple_db" ]; then
		echo "Multiple database healthcheck: '$multiple_db'"
		for db in $multiple_db; do
			check_database "$db"
		done
		
		echo "Multiple databases healthy"
		exit 0
	fi
fi