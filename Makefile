.DEFAULT_GOAL := help

include .env
export

# PSQL domain source name string
PSQL_DSN ?= $(POSTGRES_USER):$(POSTGRES_PASSWORD)@$(POSTGRES_HOST):$(POSTGRES_PORT)/$(POSTGRES_DB)

.PHONY: help
## help: shows this help message
help:
	@ echo "Usage: make [target]\n"
	@ sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'

# ==============================================================================
# DB

.PHONY: dsn
## dsn: shows the psql dsn string
dsn:
	@ echo $(PSQL_DSN)

.PHONY: start-psql
## start-psql: starts postgres instance
start-psql:
	@ docker-compose up -d $(POSTGRES_DATABASE_CONTAINER_NAME)
	@ echo "Waiting for Postgres to start..."
	@ until PGPASSWORD=$(POSTGRES_PASSWORD) psql -h $(POSTGRES_HOST) -p $(POSTGRES_PORT) -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT 1;" >/dev/null 2>&1; do \
		echo "Postgres not ready, sleeping for 5 seconds..."; \
		sleep 5; \
	done
	@ echo "Postgres is up and running."

.PHONY: start-pgbouncer
## start-pgbouncer: starts pgbouncer instance
start-pgbouncer:
	@ docker-compose up -d $(PGBOUNCER_CONTAINER_NAME)
	@ echo "Waiting for PgBouncer to start..."
	@ until PGPASSWORD=$(POSTGRES_PASSWORD) psql -h $(POSTGRES_HOST) -p $(PGBOUNCER_PORT) -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT 1;" >/dev/null 2>&1; do \
		echo "PgBouncer not ready, sleeping for 5 seconds..."; \
		sleep 5; \
	done
	@ echo "PgBouncer is up and running."

.PHONY: stop-psql
## stop-psql: stops postgres instance
stop-psql:
	@ docker-compose down $(POSTGRES_DATABASE_CONTAINER_NAME)

.PHONY: stop-pgbouncer
## stop-pgbouncer: stops pgbouncer instance
stop-pgbouncer:
	@ docker-compose down $(PGBOUNCER_CONTAINER_NAME)

.PHONY: psql-console
## psql-console: opens psql terminal
psql-console: export PGPASSWORD=$(POSTGRES_PASSWORD)
psql-console: start-psql
	@ docker exec -it $(POSTGRES_DATABASE_CONTAINER_NAME) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

# ==============================================================================
# Monitoring

.PHONY: start-monitoring
## start-monitoring: starts monitoring stack (Prometheus, Grafana, exporters)
start-monitoring: start-psql start-pgbouncer
	@ docker-compose up -d \
		$(PROMETHEUS_CONTAINER_NAME) \
		$(GRAFANA_CONTAINER_NAME) \
		$(GRAFANA_RENDERER_CONTAINER_NAME) \
		$(POSTGRES_EXPORTER_CONTAINER_NAME) \
		$(PGBOUNCER_EXPORTER_CONTAINER_NAME)
	@ echo "Monitoring stack is up."
	@ echo "Grafana:    http://localhost:3000"
	@ echo "Prometheus: http://localhost:$(PROMETHEUS_PORT)"

.PHONY: stop-monitoring
## stop-monitoring: stops monitoring stack
stop-monitoring:
	@ docker-compose down -v \
		$(PROMETHEUS_CONTAINER_NAME) \
		$(GRAFANA_CONTAINER_NAME) \
		$(GRAFANA_RENDERER_CONTAINER_NAME)

# ==============================================================================
# benchmark

.PHONY: setup
## setup: full setup - cleans, starts stack, and initializes pgbench data (run once before benchmarks)
setup: clean start-monitoring
	@ echo "Initializing pgbench with scale factor $(SCALE_FACTOR)..."
	@ PGPASSWORD=$(POSTGRES_PASSWORD) pgbench -h $(POSTGRES_HOST) -p $(POSTGRES_PORT) -U $(POSTGRES_USER) -i -s $(SCALE_FACTOR) $(POSTGRES_DB)
	@ echo "Setup complete. You can now run 'make benchmark-direct' or 'make benchmark-pgbouncer'."

.PHONY: reset
## reset: resets pgbench schema and re-initializes data (run between benchmarks)
reset:
	@ echo "Resetting pgbench schema..."
	@ docker exec $(POSTGRES_DATABASE_CONTAINER_NAME) psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) \
		-c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
	@ PGPASSWORD=$(POSTGRES_PASSWORD) pgbench -h $(POSTGRES_HOST) -p $(POSTGRES_PORT) -U $(POSTGRES_USER) \
		-i -s $(SCALE_FACTOR) $(POSTGRES_DB)
	@ echo "Reset complete."

.PHONY: benchmark-direct
## benchmark-direct: runs pgbench directly against postgres (no pooler)
benchmark-direct: export PGPASSWORD=$(POSTGRES_PASSWORD)
benchmark-direct:
	@ echo "Running direct Postgres benchmark ($(PSQL_NUMBER_OF_CLIENTS) clients, $(NUMBER_OF_THREADS) threads)..."
	@ echo "Watch Grafana at http://localhost:3000 — Ctrl-C to stop."
	@ pgbench -h $(POSTGRES_HOST) -p $(POSTGRES_PORT) -U $(POSTGRES_USER) \
		-c $(PSQL_NUMBER_OF_CLIENTS) -j $(NUMBER_OF_THREADS) -T 999999999 \
		-M simple $(POSTGRES_DB)

.PHONY: benchmark-pgbouncer
## benchmark-pgbouncer: runs pgbench through pgbouncer
benchmark-pgbouncer: export PGPASSWORD=$(POSTGRES_PASSWORD)
benchmark-pgbouncer:
	@ echo "Running PgBouncer benchmark ($(PGBOUNCER_NUMBER_OF_CLIENTS) clients, $(NUMBER_OF_THREADS) threads)..."
	@ echo "Watch Grafana at http://localhost:3000 — Ctrl-C to stop."
	@ pgbench -h $(POSTGRES_HOST) -p $(PGBOUNCER_PORT) -U $(POSTGRES_USER) \
		-c $(PGBOUNCER_NUMBER_OF_CLIENTS) -j $(NUMBER_OF_THREADS) -T 999999999 \
		-M simple $(POSTGRES_DB)

# ==============================================================================
# unit tests

.PHONY: test
## test: run unit tests
test:
	@ go test -v ./... -count=1

# ==============================================================================
# cleaning

.PHONY: clean
## clean: removes all containers and volumes
clean:
	@ docker-compose down -v