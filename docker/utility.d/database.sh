#!/bin/bash

set -e
set -u


# Format database user into associative array.
# If 'db_password' is not set then db_password=""
format_database_user() {
  # $1 = output associative array name
  # $2 = input indexed array name

  local -n userf="$1"
  local -n user="$2"

  # populate 'db_user' and default password
  if (( ${#user[@]} > 0 )); then
    userf["db_user"]="${user[0]}"
    userf["db_password"]=""
  fi

  # populate 'db_password'
  if (( ${#user[@]} > 1 )); then
    userf["db_password"]="${user[1]}"
  fi
}

# Format database into associative array.
# If 'db_user' is not set then db_user="db_name:"
format_database() {
  # $1 = output associative array name
  # $2 = input indexed array name

  local -n databasef="$1"
  local -n database="$2"

  # populate 'db_name' and default user
  if (( ${#database[@]} > 0 )); then
    databasef["db_name"]="${database[0]}"
    databasef["db_user"]="${database[0]}:"
  fi

  # populate 'db_user'
  if (( ${#database[@]} > 1 )); then
    databasef["db_user"]="${database[1]}"
  fi
}

# Split string using delimiter into an array.
split_string() {
  # $1 = output array name
  # $2 = input string to split
  # $2 = input delimiter to use in split
  
  local -n array="$1"
  # local -n string="$2"

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

# Split and format database user info into an associative array.
# 
# Database User Input:
#   - db_user
#   - "db_user:"
#   - "db_user:db_password"
split_database_user() {
  # $1 = output associative array name
  # $2 = input database user string

  local -n user_output="$1"
  local user="${2-}"

  # split 'user'
  local -a user_info=()
  split_string user_info "$user" ":"

  # format 'user_info'
  format_database_user user_output user_info
}

# Split and format database info to array.
# 
# Database Input:
# - db1
# - "db-1"
# - "db_name/db_user"
# - "db_name/db_user:"
# - "db_name/db_user:db_password"
split_database() {
  # $1 = output associative array name
  # $2 = input database string

  local -n database_output="$1"
  local database="${2-}"
  
  # split 'database'
  local -a database_info=()
  split_string database_info "$database" "/"

  # format 'database_info'
  format_database database_output database_info
}

# Split multiple databases to array
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

  # from default database variable
	if [ -n "${POSTGRES_DB=""}" ]; then
    defaultdb_output="$POSTGRES_DB"
    return
  fi

  # Fetch multiple databases
  local -a multipledb_array=()
  multiple_database multipledb_array "$databases"

  # default as first item in multiple database
  if [[ "${#multipledb_array[@]}" -gt 0 ]]; then
    defaultdb_output="${multipledb_array[0]}"
    return
  fi
}

# Check health of database by connecting to it
check_database() {
  # $1 = output associative array name
  # $2 = input multiple database string

  local -n checkdb_output="$1"
  local database="${2-}"

  # split 'database'
  local -A database_array
  split_database database_array "$database"

  # split 'db_user'
  declare -A user_array
  split_database_user user_array "${database_array[db_user]}"

  # check connection with 'db_user'
  if [ "${database_array[db_name]}" != "$POSTGRES_DB" ]; then
    pg_isready -U "${user_array[db_user]}" -d "${database_array[db_name]}" || exit 1
  fi

  # check connection with 'POSTGRES_USER'
  pg_isready -U $POSTGRES_USER -d "${database_array[db_name]}" || exit 1

  # update 'createdb_output'
  checkdb_output["db_name"]="${database_array[db_name]}"
  checkdb_output["db_user"]="${user_array[db_user]}"
  checkdb_output["healthy"]="true"
}

# Create non default user and database
create_user_and_database() {
  # $1 = output associative array name
  # $2 = input multiple database string

  local -n createdb_output="$1"
  local database="${2-}"

  # split 'database'
  local -A database_array
  split_database database_array "$database"

  # split 'db_user'
  declare -A user_array
  split_database_user user_array "${database_array[db_user]}"

  # create non default user and database
  local with_password="$([ -n "${user_array[db_password]}" ] && echo 'true' || echo 'false')"
  local create_db="$([ "${database_array[db_name]}" != "$POSTGRES_DB" ] && echo 'true' || echo 'false')"
  local create_user="$([ "${user_array[db_user]}" != "$POSTGRES_USER" ] && echo 'true' || echo 'false')"
  
  psql \
    -v ON_ERROR_STOP=1 \
    -v with_password="$with_password" \
    -v create_db="$create_db" \
    -v create_user="$create_user" \
    -v db_name="${database_array[db_name]}" \
    -v db_user="${user_array[db_user]}" \
    --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
      -- Conditional execution via psql variable passed from bash

      -- Create user
      \if :create_user
        \if :with_password
          CREATE USER :"db_user" WITH PASSWORD '${user_array[db_password]}';
        \else
          CREATE USER :"db_user";
        \endif
      \endif

      -- Create db
      \if :create_db
        CREATE DATABASE :"db_name";
        GRANT ALL PRIVILEGES ON DATABASE :"db_name" TO :"db_user";
      \endif
			EOSQL

  # update 'createdb_output'
  createdb_output["db_name"]="${database_array[db_name]}"
  createdb_output["db_user"]="${user_array[db_user]}"
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

# Initialize variables with default values
VERBOSE=false
FUNCTION=""
ARGS=""
ALL="$@"

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

# # ---- Script Logic Starts Here ----

# echo "Verbose Mode:  $VERBOSE"
# echo "Function:      $FUNCTION"
# echo "Args:          $ARGS"
# echo "ALL Params     $ALL"
# echo ""

# Validate helper function
if [ -z "$FUNCTION" ]; then
  print_error "Helper function is missing."
  exit 1
fi

# Determine helper function
case "$FUNCTION" in
  splitdb|split_database)
    declare -A database_array
    split_database database_array "$ARGS"
    
    # print array values as individually quoted strings
    echo "${database_array[db_name]}" "${database_array[db_user]}"
    ;;
    
  splitu|split_user)
    declare -A user_array
    split_database_user user_array "$ARGS"

    # print array values as individually quoted strings
    echo "${user_array[db_user]}" "${user_array[db_password]}"
    ;;

  multipledb|multiple_database)
    declare -a multipledb_array
    multiple_database multipledb_array "$ARGS"

    # print array values as individually quoted strings
    echo "${multipledb_array[@]}"
    ;;

  defaultdb|default_database)
    declare -a defaultdb
    default_database defaultdb "$ARGS"

    # print defaultdb string
    echo "${defaultdb}"
    ;;

  checkdb|check_database)
    declare -A checkdb
    check_database checkdb "$ARGS" 
    
    # print success message
    # echo "Created user '${createdb[db_user]}' and database '${createdb[db_name]}'"
    ;;

  createdb|create_database)
    declare -A createdb
    create_user_and_database createdb "$ARGS" 
    
    # print success message
    # echo "Created user '${createdb[db_user]}' and database '${createdb[db_name]}'"
    ;;
    
  *)
    # print error message
    print_error "Invalid helper function: '$FUNCTION'"
    exit 1
    ;;
esac
