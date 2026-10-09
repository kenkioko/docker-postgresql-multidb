#!/bin/bash

set -e
set -u


# validate_array() {
#   # Check for indexed array
#   if [[ ${my_var@a} == *a* ]]; then
#     echo "It's an indexed array"
#   fi

#   # Check for associative array
#   if [[ ${my_var@a} == *A* ]]; then
#     echo "It's an associative array"
#   fi
# }

# Split string using delimiter into an array.
split_string() {
  # $1 = output array name
  # $2 = input string to split
  # $2 = input delimiter to use in split
  
  local -n array="$1"

  local string="${2-}"
  local delimiter="${3-}"

  # Save the original IFS and set comma as the new delimiter
  local old_ifs="$IFS"

  if [ -n "$delimiter" ]; then
    IFS="$delimiter"
  fi

  # Read the split items into an array
  read -ra array <<< "${string// /}"

  # Restore the original IFS
  if [ -n "$delimiter" ]; then
    IFS="$old_ifs"
  fi
}

# Split database user info string into an associative array.
# If 'db_password' is not set then db_password=""
# 
# Database User Input:
#   - db_user
#   - "db_user:"
#   - "db_user:db_password"
# 
# Output:
#   ([db_user]="db_user" [db_password]="db_password")
split_database_user() {
  # $1 = output associative array name
  # $2 = input database user string

  local -n user_output="$1"
  local user="${2-}"

  # split 'user'
  local -a user_info=()
  split_string user_info "$user" ":"

  # populate 'db_user' with default password
  if [[ ${#user_info[@]} -gt 0 ]]; then
    user_output["db_user"]="${user_info[0]}"
    user_output["db_password"]=""
  fi

  # populate 'db_password'
  if [[ ${#user_info[@]} -gt 1 ]]; then
    user_output["db_password"]="${user_info[1]}"
  fi
}

# Split database and user info string to an associative array.
# If 'db_user' is not set then db_user="db_name:"
# 
# Database Input:
#   - db1
#   - "db-1"
#   - "db_name/db_user"
#   - "db_name/db_user:"
#   - "db_name/db_user:db_password"
# 
# Output:
#   ([db_name]="db_name" [db_user]="db_user" [db_password]="db_password")
split_database() {
  # $1 = output associative array name
  # $2 = input database string

  local -n database_output="$1"
  local database="${2-}"
  
  # split 'database'
  local -a database_info=()
  split_string database_info "$database" "/"

  # populate 'db_name' with default 'db_user' and 'db_password'
  if [[ ${#database_info[@]} -gt 0 ]]; then
    database_output["db_name"]="${database_info[0]}"
    database_output["db_user"]="${database_info[0]}"
    database_output["db_password"]=""
  fi

  # split and populate 'db_user', 'db_password'
  if [[ ${#database_info[@]} -gt 1 ]]; then
    local -A user_array=()
    split_database_user user_array "${database_info[1]}"

    database_output["db_user"]="${user_array[db_user]}"
    database_output["db_password"]="${user_array[db_password]}"
  fi
}

# Split multiple databases string to array
# 
# Multiple Databases Input:
# - db1,db2,...
# - "db-1","db-2","..."
# - "db1_name/db1_user:db1_password", "..."
multiple_database() {
  # $1 = output array name
  # $2 = input multiple database string

  local -n multipledb_output="$1"
  local multipledb="${POSTGRES_MULTIPLE_DB:-${2-}}"
  
  # split 'multipledb'
  local -a multipledb_info=()
  split_string multipledb_info "$multipledb" ","

  # update 'multipledb_output'
  multipledb_output=("${multipledb_info[@]}")
}

# Fetch the default database as string
# uses 'multiple_database' function if not set
default_database() {
  # $1 = output array name
  # $2 = input multiple database string

  local -n defaultdb_output="$1"
  local databases="${2-}"

  # from environment variables
	if [ -n "${POSTGRES_DB-}" ]; then
    local db_string="$POSTGRES_DB"

    if [ -n "${POSTGRES_USER-}" ]; then
      db_string="$POSTGRES_DB/$POSTGRES_USER"
    fi

    defaultdb_output="$db_string"
    return
  fi

  # Fetch multiple databases
  local -a multipledb_array=()
  multiple_database multipledb_array "$databases"

  # default as first item in multiple database
  if [ "${#multipledb_array[@]}" -gt 0 ]; then
    defaultdb_output="${multipledb_array[0]}"
    return
  fi
}

# Check health of database by connecting to it
check_database() {
  # $1 = output associative array name
  # $2 = input database string

  local -n checkdb_output="$1"
  local database="${2-}"

  # split 'database'
  local -A db_info
  split_database db_info "$database"

  # check connection with 'db_user'
  if [ "${db_info[db_user]}" != "$POSTGRES_USER" ]; then
    pg_isready -U "${db_info[db_user]}" -d "${db_info[db_name]}" || exit 1
  fi

  # check connection with 'POSTGRES_USER'
  pg_isready -U $POSTGRES_USER -d "${db_info[db_name]}" || exit 1

  # update 'checkdb_output'
  checkdb_output["db_name"]="${db_info[db_name]}"
  checkdb_output["db_user"]="${db_info[db_user]}"
  checkdb_output["healthy"]="true"
}

# Create non default user and database
create_user_and_database() {
  # $1 = output associative array name
  # $2 = input database string

  local -n createdb_output="$1"
  local database="${2-}"

  # split 'database'
  local -A db_info
  split_database db_info "$database"

  # create non default database and database user
  local with_password="$([ -n "${db_info[db_password]}" ] && echo 'true' || echo 'false')"
  local create_db="$([ "${db_info[db_name]}" != "$POSTGRES_DB" ] && echo 'true' || echo 'false')"
  local create_user="$([ "${db_info[db_user]}" != "$POSTGRES_USER" ] && echo 'true' || echo 'false')"
  
  psql \
    -v ON_ERROR_STOP=1 \
    -v with_password="$with_password" \
    -v create_db="$create_db" \
    -v create_user="$create_user" \
    -v db_name="${db_info[db_name]}" \
    -v db_user="${db_info[db_user]}" \
    --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
      -- Conditional execution via psql variable passed from bash
      \echo
      \echo Creating user ":"db_user" and database ":"db_user"

      -- Create user
      \if :create_user
        \if :with_password
          CREATE USER :"db_user" WITH PASSWORD '${db_info[db_password]}';
        \else
          CREATE USER :"db_user";
        \endif
      \endif

      -- Create db
      \if :create_db
        CREATE DATABASE :"db_name";
      \endif

      -- Connect to database
      \c :"db_name"

      -- Grant permissions
      GRANT ALL PRIVILEGES ON DATABASE :"db_name" TO :"db_user";
      GRANT ALL ON SCHEMA public TO :"db_user";

      -- Success message
      \echo Creation success
      \echo

			EOSQL

  # update 'createdb_output'
  createdb_output["db_name"]="${db_info[db_name]}"
  createdb_output["db_user"]="${db_info[db_user]}"
  createdb_output["success"]="true"
}

print_help() {
  echo "Utility functions for database helper."
  echo ""

  echo "Usage:"
  echo "  $0 [OPTION]... [FUNCTION]... STRING1 [STRING2]"
  echo ""

  echo "Options:"
  echo "  -h, --help        Display this help message"
  echo "  -f, --function    The helper function to use"
  echo ""

  echo "Functions:"
  echo "  split             Split database info to 'db_name' and 'db_user'"
  echo "  multiple          Get the comma-separated list of extra databases to build"
  echo "  default           Get the default database to build"
  echo "  check             Check the health of a database "
  echo ""

  echo "Exit status:"
  echo "  0                 if OK,"
  echo "  1                 if an error occured,"
  echo ""
}

print_error() {
  local error="${1:="Missing operand"}"

  echo "Error: $error" >&2
  echo "Try '$0 --help' for more information." >&2
}

# -------- Script Logic Starts Here --------

# Initialize variables with default values
VERBOSE=false
FUNCTION=""
ARGS=""

# Loop through all arguments passed to the script
while [ $# -gt 0 ]; do
  case "$1" in
    # 1. Short and Long Boolean Flags (No values required)
    -v|--verbose)
      VERBOSE=true
      shift # Move to the next argument
      ;;

    # 2. Short and Long Parameters (Accepting values separated by space or '=')
    -f|--function)
      value="${2:+"$2"}"

      if [[ -z "$value" || "$value" == -* ]]; then
      # if [-z "$value"] || ["$value" == -*] ; then
        print_error "Argument for '$1' is missing" >&2
        exit 1
      fi

      FUNCTION="$value"
      shift 2 # Move past the flag and its value
      ;;

    --function=*)
      FUNCTION="${1#*=}" # Extract the value after the '=' character
      shift
      ;;

    # 3. Handle help menu
    -h|--help)
      print_help
      exit 0
      ;;

    # 4. Collect Unknown flags
    -*)
      print_error "Unknown option '$#'" >&2
      exit 1
      ;;

    # Append to a list of arguments (or store in an array if using Bash)
    *)
      if [ -z "$FUNCTION" ]; then
        FUNCTION="$1"
      elif [ -z "$ARGS" ]; then
        ARGS="$1"
      else
        ARGS="$ARGS $1"
      fi
      
      shift
      ;;
  esac
done

# Validate helper function
if [ -z "$FUNCTION" ]; then
  print_error "Helper function is missing."
  exit 1
fi

# Determine helper function
case "$FUNCTION" in
  splitu|split_user)
    declare -A user_array
    split_database_user user_array "$ARGS"

    # print array values as individually quoted strings
    echo "${user_array[db_user]}" "${user_array[db_password]}"
    ;;

  splitdb|split_database)
    declare -A database_array
    split_database database_array "$ARGS"
    
    # print array values as individually quoted strings
    echo "${database_array[db_name]}" "${database_array[db_user]}" "${database_array[db_password]}"
    ;;
    
  multipledb|multiple_database)
    declare -a multipledb_array
    multiple_database multipledb_array "$ARGS"

    # print array values as individually quoted strings
    echo "${multipledb_array[@]}"
    ;;

  defaultdb|default_database)
    declare defaultdb
    default_database defaultdb "$ARGS"

    # print defaultdb string
    echo "${defaultdb-}"
    ;;

  checkdb|check_database)
    declare -A checkdb
    check_database checkdb "$ARGS"
    ;;

  createdb|create_database)
    declare -A createdb
    create_user_and_database createdb "$ARGS"
    ;;
    
  *)
    # print error message
    print_error "Invalid helper function: '$FUNCTION'"
    exit 1
    ;;
esac
