#!/bin/bash
# Validate necessary environment variables
for var in DB_SCHEMAS MYSQL_USER MYSQL_PASSWORD MYSQL_ROOT_PASSWORD; do
  if [ -z "${!var}" ]; then
    echo -e "\033[1;31m Error: Environment variable $var is not defined. \033[0m\n"
    exit 1
  fi
done

# Read databases from the environment variable
IFS=',' read -r -a SCHEMAS <<< "$DB_SCHEMAS"

# Create databases and grant permissions
for schema in "${SCHEMAS[@]}"; do
  if ! MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --user=root -e "USE \`$schema\`;" 2>/dev/null; then
    if MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --user=root -e "CREATE SCHEMA \`$schema\`;" &&
       MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --user=root -e "
       GRANT ALL PRIVILEGES ON \`$schema\`.* TO '${MYSQL_USER}'@'%';
       FLUSH PRIVILEGES;"; then
      echo -e "\033[1;32m Success: Database '$schema' was created and permissions were assigned to ${MYSQL_USER} \033[0m"
    else
      echo -e "\033[1;31m Error: Could not create database '$schema' or assign permissions. \033[0m\n"
      exit 1
    fi
  else
    echo -e "\033[1;33m The database '$schema' already exists. \033[0m"
  fi
done

# Grant SUPER privilege
if MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --user=root -e "
  GRANT SUPER ON *.* TO '${MYSQL_USER}'@'%';
  GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION;
  FLUSH PRIVILEGES;"; then
  echo -e "\033[1;32m Success: Granted SUPER privilege to ${MYSQL_USER} \033[0m\n"
else
  echo -e "\033[1;31m Error: Failed to grant SUPER privilege to ${MYSQL_USER} \033[0m\n"
  exit 1
fi
