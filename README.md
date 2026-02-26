# pgbouncer-demo

A hands-on demonstration of PgBouncer's connection pooling benefits, using pgbench for load
generation, Prometheus for metrics collection, and Grafana for visualization.

This project accompanies the article: [article link]

## Overview

The demo runs two benchmarks and lets you observe the results in real time through Grafana:

- **Direct benchmark** — pgbench connects directly to Postgres with 80 clients
- **PgBouncer benchmark** — pgbench connects through PgBouncer with 200 clients

The goal is to show how PgBouncer reduces Postgres connection utilization and memory pressure
while serving significantly more clients.

## Requirements

- [Docker](https://www.docker.com/)
- [Docker Compose](https://docs.docker.com/compose/)
- [pgbench](https://www.postgresql.org/docs/current/pgbench.html) (included with PostgreSQL client tools)
- [psql](https://www.postgresql.org/docs/current/app-psql.html) (included with PostgreSQL client tools)

## Stack

| Service | Image | Port |
|---------|-------|------|
| PostgreSQL 17 | `postgres:17` | 5432 |
| PgBouncer | `edoburu/pgbouncer` | 6432 |
| postgres_exporter | `quay.io/prometheuscommunity/postgres-exporter` | 9187 |
| pgbouncer_exporter | `prometheuscommunity/pgbouncer-exporter` | 9127 |
| Prometheus | `prom/prometheus` | 9090 |
| Grafana | `grafana/grafana` | 3000 |

## Project Structure

```
pgbouncer-demo/
├── .env
├── docker-compose.yaml
├── Makefile
├── grafana/
│   ├── dashboards/
│   │   ├── dashboards.yaml
│   │   ├── pgbouncer_benchmark.json
│   │   └── psql_benchmark.json
│   └── datasources/
│       └── datasources.yaml
└── prometheus/
    └── prometheus.yml
```

## Getting Started

### 1. Run setup

This cleans any existing state, starts all services, and initializes the pgbench schema:

```bash
make setup
```

### 2. Open Grafana

Navigate to [http://localhost:3000](http://localhost:3000) and log in with the credentials
defined in `.env` (default: `admin` / `admin123`).

Two dashboards are pre-provisioned: **PSQL benchmark** and **PgBouncer benchmark**.

### 3. Run the direct benchmark

```bash
make benchmark-direct
```

Watch the **PSQL benchmark** dashboard in Grafana. Stop with `Ctrl-C` when done.

### 4. Reset between benchmarks

```bash
make reset
```

This drops and re-initializes the pgbench schema so both benchmarks start from the same state.

### 5. Run the PgBouncer benchmark

```bash
make benchmark-pgbouncer
```

Watch the **PgBouncer benchmark** dashboard in Grafana. Stop with `Ctrl-C` when done.

### 6. Clean up

```bash
make clean
```

This removes all containers and volumes.

## Makefile Reference

```
make setup               clean start + initialize pgbench data (run once)
make benchmark-direct    run pgbench directly against Postgres
make benchmark-pgbouncer run pgbench through PgBouncer
make reset               reset pgbench schema between benchmarks
make start-monitoring    start the full stack without reinitializing data
make stop-monitoring     stop monitoring services
make psql-console        open a psql terminal inside the Postgres container
make clean               remove all containers and volumes
```

## Configuration

Key environment variables in `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_MAX_CONNECTIONS` | `100` | Postgres `max_connections` |
| `POOL_MODE` | `transaction` | PgBouncer pool mode |
| `DEFAULT_POOL_SIZE` | `25` | Max server connections per pool |
| `MAX_CLIENT_CONN` | `300` | Max client connections to PgBouncer |
| `PSQL_NUMBER_OF_CLIENTS` | `80` | pgbench clients for direct benchmark |
| `PGBOUNCER_NUMBER_OF_CLIENTS` | `200` | pgbench clients for PgBouncer benchmark |
| `NUMBER_OF_THREADS` | `8` | pgbench threads for both benchmarks |
| `SCALE_FACTOR` | `50` | pgbench scale factor (~7.2M rows) |

## Dashboards

Both dashboards are provisioned automatically and track the same metrics for easy comparison:

- **Postgres Connections by State** — active and idle client connections in Postgres
- **Connections Used** — percentage of `max_connections` in use (gauge)
- **Max Connections** — static reference value for `max_connections`
- **TPS** — committed transactions per second
- **Buffers Allocated** — rate of shared memory buffer allocations
- **Buffers Cleaned by bgwriter** — bgwriter activity under memory pressure

The PgBouncer dashboard additionally includes:

- **Server Connections Pool** — clients active, clients waiting, server connections active,
  server connections idle — showing the multiplexing effect in real time

## Notes

- `pgbouncer_exporter` connects to PgBouncer's internal virtual database (`pgbouncer`), not
  the application database. The user must be listed in `STATS_USERS` or `ADMIN_USERS` in
  PgBouncer's configuration.
- Both benchmarks use `-M simple` (simple query protocol). PgBouncer in transaction mode does
  not support protocol-level prepared statements.
- Grafana credentials are set via `GF_SECURITY_ADMIN_USER` and `GF_SECURITY_ADMIN_PASSWORD`
  in `.env`.