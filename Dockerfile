# =========================
# Base image
# =========================
FROM postgres:18-alpine AS base

# Get build args
ARG UTILITY_D="docker/utility.d"
ARG INITDB_D="docker/entrypoint-initdb.d"
ARG HEALTHCHECK_D="docker/healthcheck.d"
ARG HEALTHCHECK_PATH="$HEALTHCHECK_D/healthcheck.sh"

# Set environment variables
ENV SCRIPTS_UTILITY_D="/docker-utility.d"
ENV SCRIPTS_INITDB_D="/docker-entrypoint-initdb.d"
ENV SCRIPTS_HEALTHCHECK_D="/docker-healthcheck.d"
ENV SCRIPTS_HEALTHCHECK_PATH="$SCRIPTS_HEALTHCHECK_D/healthcheck.sh"


##############################
# Build stage
##############################
FROM base AS build

# Mount the scripts
COPY "$UTILITY_D/*" "$SCRIPTS_UTILITY_D/"
COPY "$INITDB_D/*" "$SCRIPTS_INITDB_D/"
COPY "$HEALTHCHECK_D/*" "$SCRIPTS_HEALTHCHECK_D/"
COPY "$HEALTHCHECK_PATH" "$SCRIPTS_HEALTHCHECK_D/"

# Make scripts excecutable
RUN find "$SCRIPTS_UTILITY_D/" -name "*.sh" -exec chmod +x {} +
RUN find "$SCRIPTS_INITDB_D/" -name "*.sh" -exec chmod +x {} +
RUN find "$SCRIPTS_HEALTHCHECK_D/" -name "*.sh" -exec chmod +x {} +

# Healthcheck every five minutes or so
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
  CMD "$SCRIPTS_HEALTHCHECK_PATH" || exit 1