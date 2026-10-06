#!/bin/bash

set -e
set -u

utility_dir="${SCRIPTS_UTILITY_D:="docker/utility.d"}"
utility_db="$utility_dir/database.sh"

create_user_and_database() {
	local database="$1"
	create_db=$("$utility_db" "--function=createdb" "$database")
	
	echo "$create_db"
}

if [ -f "$utility_db" ]; then
  multiple_db=$("$utility_db" "--function=multipledb")

	if [ -n "$multiple_db" ]; then
		echo "Multiple database creation requested: '$multiple_db'"
		for db in $multiple_db; do
			create_user_and_database "$db"
		done

		echo "Multiple databases created"
		exit 0
	fi
fi