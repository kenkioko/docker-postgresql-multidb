# Using multiple databases with the official PostgreSQL Docker image

The [official recommendation](https://hub.docker.com/_/postgres/) for creating
multiple databases is as follows:

*If you would like to do additional initialization in an image derived from
this one, add one or more `*.sql`, `*.sql.gz`, or `*.sh` scripts under
`/docker-entrypoint-initdb.d` (creating the directory if necessary). After the
entrypoint calls `initdb` to create the default `postgres` user and database,
it will run any `*.sql` files and source any `*.sh` scripts found in that
directory to do further initialization before starting the service.*

This project provides a reusable PostgreSQL database image that automatically creates multiple databases and users during container initialization. It is designed for projects that need a dedicated database service with a custom bootstrap flow, health checks, and easy Docker-based startup.

> The compose file included in this repository is an example configuration for a downstream project. It is not meant to be the only supported deployment pattern, but it demonstrates how this database image can be wired into a real application stack.

## What this project does

The image is built from PostgreSQL 18 Alpine and adds:

- automatic creation of the default database and superuser
- creation of additional databases from `POSTGRES_MULTIPLE_DB`
- optional per-database users and passwords
- health checks for the default and extra databases
- a Dockerized setup suitable for local development and integrations

## Project structure

- `Dockerfile` – custom PostgreSQL image setup
- `docker/entrypoint-initdb.d/01-init-multiple-db.sh` – runs after PostgreSQL initialization and creates extra databases
- `docker/utility.d/database.sh` – parses database/user definitions and executes SQL helpers
- `docker/healthcheck.d/01-check-default-db.sh` – verifies the default database
- `docker/healthcheck.d/02-check-multiple-db.sh` – verifies all configured extra databases
- `docker/healthcheck.d/healthcheck.sh` – runs the health checks in order
- `docker-compose.yaml` – example service definition using PostgreSQL + Adminer
- `.env.example` – template for local environment configuration

## Environment variables

Copy `.env.example` to `.env` and set the values that fit your project.

Example:

```env
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=app_default
POSTGRES_MULTIPLE_DB="sports_db/sports_user:sports_pass,analytics_db/analytics_user:analytics_pass"
```

The supported formats for `POSTGRES_MULTIPLE_DB` are:

- `db1`
- `db-1`
- `db_name/db_user`
- `db_name/db_user:db_password`
- `db1,db2`
- `"db1_name/db1_user:db1_password","db2_name/db2_user:db2_password"`

The script will:

- create the extra database if it does not exist
- create the matching user if needed
- grant all privileges on that database to that user
- keep the default PostgreSQL database and user behaviour intact

## Running with Docker Compose

From the project root:

```bash
cp .env.example .env

docker compose up --build
```

This will start:

- PostgreSQL on port `5432`
- Adminer on port `8888`

The example compose file uses:

```yaml
services:
  postgres:
    container_name: multipledb-postgres
    build:
      context: .
      dockerfile: Dockerfile
    env_file:
      - path: .env
    ports:
      - "5432:5432"

  adminer:
    image: adminer:latest
    ports:
      - "8888:8080"
```

## Adminer access

After startup, open:

- http://localhost:8888

Use the PostgreSQL service name or host as needed by your environment:

- server: the configured PostgreSQL host e.g `multipledb-postgres`
- username: the configured PostgreSQL user
- password: the configured PostgreSQL password
- database: the default or target database

## Example usage in another project

This repository is intended to be reusable. In another project, you can copy the same pattern and point the database service to a different app-specific service name or environment.

Example:

```yaml
services:
  postgres:
    build:
      context: ./database
      dockerfile: Dockerfile
    env_file:
      - ./database/.env
    ports:
      - "5432:5432"
```

The included `docker-compose.yaml` is a concrete example of that pattern, but the actual values should be adapted to your project.

## Notes

- This project uses a custom image rather than a third-party multi-db image.
- It is especially useful when multiple application schemas or services need isolated PostgreSQL databases.
- Health checks are included to ensure the database is ready before dependent containers start using it.

## Useful commands

```bash
docker compose up --build
docker compose ps
docker compose logs -f postgres
docker compose down -v
```