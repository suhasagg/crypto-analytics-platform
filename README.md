
# Crypto Analytics Platform

A production-style **Crypto Analytics Platform** built with distributed systems components:

- **Kafka** for event streaming
- **TimescaleDB/PostgreSQL** for time-series analytics
- **Elasticsearch** for search/indexing
- **Redis** for cache/rate limiting
- **Prometheus** for metrics
- **Grafana** for dashboards
- **Go services** for API, ingestion, indexing, and analytics
- Optional **dummy/demo dashboard** for full visual Grafana charts

This project is designed to build a scalable blockchain analytics platform similar to a simplified Dune/Nansen/DefiLlama-style backend.

---

## 1. High-Level Architecture

```text
                    +----------------------+
                    |  Ethereum/Cosmos/    |
                    |  Solana RPC Sources  |
                    +----------+-----------+
                               |
                               v
+-------------+        +---------------+        +----------------+
| RPC Clients | -----> |  Ingestor     | -----> | Kafka Topics   |
+-------------+        +---------------+        +----------------+
                                                        |
                                                        v
                                               +----------------+
                                               | Decoder/Parser |
                                               +----------------+
                                                        |
                                                        v
+-------------+        +---------------+        +----------------+
| Redis Cache | <----> | API Service   | <----> | TimescaleDB    |
+-------------+        +---------------+        +----------------+
                               |
                               v
                        +--------------+
                        | Elasticsearch|
                        +--------------+

Observability:

+-------------+      +--------------+
| Go Metrics  | ---> | Prometheus   |
+-------------+      +--------------+
                            |
                            v
                      +-----------+
                      | Grafana   |
                      +-----------+
```

---

## 2. Main Features

### Blockchain Analytics

The platform is structured to support:

- Block ingestion
- Transaction ingestion
- Decoded events
- Token movement tracking
- DEX volume analytics
- Whale movement detection
- Gas analytics
- Active address analytics
- Top token analytics
- Chain reorg handling
- DLQ topics for poison events

### Distributed Systems Features

- Kafka topic-based decoupling
- Consumer groups
- DLQ handling
- Idempotent writes using DB constraints
- Redis caching
- Elasticsearch indexing
- Materialized views
- Prometheus metrics
- Grafana dashboards

### Demo Dashboard

A full fake/demo Grafana dashboard is included using Grafana TestData DB.

It shows:

- Full time-series graphs
- Stat cards
- Gauges
- Bar gauges
- Pie/donut charts
- Heatmap-style panels
- Crypto-specific fake metrics:
  - TPS
  - Gas price
  - DEX volume
  - Token price
  - API latency
  - Indexer lag
  - Whale transfers
  - DLQ events
  - Chain reorgs

---

## 3. Repository Structure

Expected structure:

```text
crypto-analytics-platform/
├── docker-compose.yml
├── README.md
├── .env
├── db/
│   └── migrations/
│       ├── 001_init.sql
│       └── 002_materialized_views.sql
├── services/
│   ├── api/
│   │   ├── Dockerfile
│   │   ├── go.mod
│   │   ├── go.sum
│   │   └── main.go
│   ├── ingestor/
│   │   ├── Dockerfile
│   │   ├── go.mod
│   │   ├── go.sum
│   │   └── main.go
│   ├── indexer/
│   │   ├── Dockerfile
│   │   ├── go.mod
│   │   ├── go.sum
│   │   └── main.go
│   └── decoder/
│       ├── Dockerfile
│       ├── go.mod
│       ├── go.sum
│       └── main.go
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml
│   └── grafana/
│       ├── provisioning/
│       │   ├── dashboards/
│       │   └── datasources/
│       └── dashboards/
├── k8s/
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── deployments.yaml
│   ├── services.yaml
│   └── hpa.yaml
└── scripts/
```

---

## 4. Prerequisites

Install:

```bash
docker --version
docker compose version
go version
curl --version
```

Recommended:

```text
Docker: 24+
Docker Compose plugin: v2+
Go: 1.25+
RAM: 8 GB minimum
Disk: 10 GB free
```

On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y curl git make
```

Docker install docs:

```bash
docker --version
docker compose version
```

---

## 5. Fresh Setup From Scratch

### Step 1: Unzip project

```bash
unzip crypto-analytics-platform-production-upgrades.zip
cd crypto-analytics-platform
```

---

### Step 2: Fix Postgres port if local Postgres is running

If you see:

```text
bind: address already in use 0.0.0.0:5432
```

change TimescaleDB host port from `5432` to `5433`:

```bash
sed -i 's/5432:5432/5433:5432/g' docker-compose.yml
```

Inside Docker, services should still use:

```text
timescaledb:5432
```

From host machine, use:

```text
localhost:5433
```

---

### Step 3: Fix Go version

Some dependencies require newer Go versions. Use Go 1.25 for Docker builds:

```bash
find ./services -name go.mod -exec go mod edit -go=1.25 {} \;
find ./services -name go.mod -exec sed -i '/^toolchain /d' {} \;
```

Patch Dockerfiles:

```bash
find ./services -name Dockerfile -exec sed -i 's/golang:1.22/golang:1.25/g' {} \;
find ./services -name Dockerfile -exec sed -i 's/golang:1.24/golang:1.25/g' {} \;
```

Ensure `go mod tidy` runs before build:

```bash
find ./services -name Dockerfile -exec sed -i '/RUN CGO_ENABLED=0 GOOS=linux go build/i RUN go mod tidy' {} \;
```

---

### Step 4: Verify Dockerfiles

Each service Dockerfile should look like this:

```dockerfile
FROM golang:1.25 AS build

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM alpine:3.20

WORKDIR /app

RUN apk --no-cache add ca-certificates curl

COPY --from=build /app/server /app/server

EXPOSE 8080 8081 8082 8083

CMD ["/app/server"]
```

Check:

```bash
find ./services -name Dockerfile -exec sh -c 'echo ==== $1; grep -nE "FROM golang|COPY go.mod|go mod download|go mod tidy|go build" "$1"' _ {} \;
```

---

### Step 5: Build and start

```bash
docker compose build --no-cache
docker compose up -d
```

Check status:

```bash
docker compose ps
```

---

## 6. Services and Ports

Typical services:

| Service | Purpose | Port |
|---|---|---|
| API | REST API | `8080` |
| Ingestor | Blockchain/RPC ingestion | `8081` |
| Decoder | Event decoder | `8082` |
| Indexer | DB/Search indexer | `8083` |
| Kafka | Event streaming | `9092` |
| TimescaleDB | Time-series DB | `5433:5432` if host conflict |
| Redis | Cache | `6379` |
| Elasticsearch | Search | `9200` |
| Prometheus | Metrics | `9090` |
| Grafana | Dashboards | `3000` |
| Schema Registry | Avro/Protobuf registry | `8081` or configured port |

---

## 7. Access URLs

```text
API Health:
http://localhost:8080/health

Prometheus:
http://localhost:9090

Prometheus Targets:
http://localhost:9090/targets

Grafana:
http://localhost:3000
```

Grafana login:

```text
admin / admin
```

Elasticsearch:

```text
http://localhost:9200
```

---

## 8. Full Demo Grafana Dashboard

The real services may initially have little data. To immediately show a full fancy dashboard with filled time-series, use the demo dashboard script.

### Step 1: Download/copy script

Place this file in the project root:

```text
grafana-full-demo-dashboard.sh
```

### Step 2: Run it

```bash
chmod +x grafana-full-demo-dashboard.sh
./grafana-full-demo-dashboard.sh
```

### Step 3: Open dashboard

```text
http://localhost:3000/d/crypto-full-demo-dashboard
```

Login:

```text
admin / admin
```

### What this dashboard includes

```text
Full time-series graphs across 6 hours
Stat cards
Gauges
Bar gauges
Pie chart
Donut chart
Heatmap-style panel
Crypto fake metrics
```

Crypto panels include:

```text
TPS by chain
Gas price by chain
DEX volume
Token prices
Indexer lag
API latency
Kafka consumer lag
Chain head height
Whale transfers
DLQ events
Reorg events
Cache hit ratio
Active addresses
```

---

## 9. Prometheus Checks

Check Prometheus health:

```bash
curl http://localhost:9090/-/ready
```

Check targets:

```bash
open http://localhost:9090/targets
```

CLI check:

```bash
curl "http://localhost:9090/api/v1/query?query=up"
```

Expected response should contain:

```json
"status":"success"
```

---

## 10. Kafka Commands

Find Kafka container:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" | grep -i kafka
```

Set container variable:

```bash
KAFKA_CONTAINER=$(docker ps --format '{{.Names}}' | grep kafka | head -1)
```

List topics:

```bash
docker exec -it "$KAFKA_CONTAINER" kafka-topics \
  --bootstrap-server localhost:9092 \
  --list
```

Create topics:

```bash
docker exec -it "$KAFKA_CONTAINER" kafka-topics \
  --bootstrap-server localhost:9092 \
  --create \
  --if-not-exists \
  --topic raw.blocks \
  --partitions 6 \
  --replication-factor 1
```

Produce test event:

```bash
docker exec -it "$KAFKA_CONTAINER" kafka-console-producer \
  --bootstrap-server localhost:9092 \
  --topic raw.blocks
```

Paste:

```json
{"chain":"ethereum","height":1,"hash":"0xabc","timestamp":"2026-05-29T00:00:00Z"}
```

Exit producer:

```bash
Ctrl + D
```

Consume:

```bash
docker exec -it "$KAFKA_CONTAINER" kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic raw.blocks \
  --from-beginning
```

---

## 11. TimescaleDB Commands

If host port is mapped to `5433`:

```bash
psql postgresql://analytics:analytics@localhost:5433/analytics
```

Inside Docker network:

```text
postgresql://analytics:analytics@timescaledb:5432/analytics
```

Run migrations:

```bash
docker exec -i crypto-analytics-platform-timescaledb-1 psql \
  -U analytics \
  -d analytics < db/migrations/001_init.sql
```

If container name differs:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}" | grep -i timescale
```

Then:

```bash
TIMESCALE_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i timescale | head -1)

docker exec -i "$TIMESCALE_CONTAINER" psql \
  -U analytics \
  -d analytics < db/migrations/001_init.sql
```

Refresh materialized views:

```bash
docker exec -it "$TIMESCALE_CONTAINER" psql \
  -U analytics \
  -d analytics \
  -c "REFRESH MATERIALIZED VIEW top_tokens_mv;"
```

---

## 12. Elasticsearch Commands

Check health:

```bash
curl http://localhost:9200
```

List indices:

```bash
curl http://localhost:9200/_cat/indices?v
```

Search:

```bash
curl "http://localhost:9200/_search?pretty"
```

---

## 13. Redis Commands

Check Redis:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}" | grep -i redis
```

```bash
REDIS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i redis | head -1)
docker exec -it "$REDIS_CONTAINER" redis-cli ping
```

Expected:

```text
PONG
```

List keys:

```bash
docker exec -it "$REDIS_CONTAINER" redis-cli keys '*'
```

---

## 14. API Usage

Health:

```bash
curl http://localhost:8080/health
```

Search:

```bash
curl "http://localhost:8080/search?q=swap" \
  -H "Authorization: Bearer dev-token" \
  -H "X-Tenant-ID: tenant-a"
```

Top tokens:

```bash
curl "http://localhost:8080/analytics/top-tokens" \
  -H "Authorization: Bearer dev-token" \
  -H "X-Tenant-ID: tenant-a"
```

Active addresses:

```bash
curl "http://localhost:8080/analytics/active-addresses" \
  -H "Authorization: Bearer dev-token" \
  -H "X-Tenant-ID: tenant-a"
```

Whale movements:

```bash
curl "http://localhost:8080/analytics/whale-movements" \
  -H "Authorization: Bearer dev-token" \
  -H "X-Tenant-ID: tenant-a"
```

Gas analytics:

```bash
curl "http://localhost:8080/analytics/gas" \
  -H "Authorization: Bearer dev-token" \
  -H "X-Tenant-ID: tenant-a"
```

---

## 15. Start, Stop, Restart

### Start

```bash
docker compose up -d
```

Then re-import demo dashboard:

```bash
./grafana-full-demo-dashboard.sh
```

### Stop

```bash
docker compose down
```

### Stop and delete data

```bash
docker compose down -v
```

### Restart

```bash
docker compose restart
```

### Rebuild everything

```bash
docker compose build --no-cache
docker compose up -d
```

---

## 16. Full Reset From Scratch

```bash
docker compose down -v
docker rm -f crypto-dummy-exporter-force 2>/dev/null || true
docker system prune -f
```

Then:

```bash
docker compose build --no-cache
docker compose up -d
./grafana-full-demo-dashboard.sh
```

Open:

```text
http://localhost:3000/d/crypto-full-demo-dashboard
```

---

## 17. Troubleshooting

### Problem: Port 5432 already in use

Error:

```text
bind: address already in use 0.0.0.0:5432
```

Fix:

```bash
sed -i 's/5432:5432/5433:5432/g' docker-compose.yml
docker compose up -d
```

---

### Problem: `go.mod requires go >= 1.25`

Fix:

```bash
find ./services -name go.mod -exec go mod edit -go=1.25 {} \;
find ./services -name go.mod -exec sed -i '/^toolchain /d' {} \;
find ./services -name Dockerfile -exec sed -i 's/golang:1.22/golang:1.25/g' {} \;
find ./services -name Dockerfile -exec sed -i 's/golang:1.24/golang:1.25/g' {} \;
```

---

### Problem: `go mod tidy` required

Error:

```text
go: updates to go.mod needed; to update it:
go mod tidy
```

Fix Dockerfiles:

```bash
find ./services -name Dockerfile -exec sed -i '/RUN CGO_ENABLED=0 GOOS=linux go build/i RUN go mod tidy' {} \;
docker compose build --no-cache
```

---

### Problem: Kafka container not named `kafka`

Find actual name:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" | grep -i kafka
```

Use:

```bash
KAFKA_CONTAINER=$(docker ps --format '{{.Names}}' | grep kafka | head -1)
```

---

### Problem: Grafana says dashboard has no data

Use the demo dashboard:

```bash
./grafana-full-demo-dashboard.sh
```

Open:

```text
http://localhost:3000/d/crypto-full-demo-dashboard
```

This uses Grafana TestData DB, so it does not require real blockchain data.

---

### Problem: Grafana service name not found

Error:

```text
no such service: grafana
```

Find containers:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" | grep -i grafana
```

Restart by container name:

```bash
docker restart $(docker ps --format '{{.Names}}' | grep -i grafana)
```

---

### Problem: Port 9109 already allocated

Old dummy exporter is running.

Fix:

```bash
docker rm -f crypto-dummy-exporter-force 2>/dev/null || true
docker rm -f $(docker ps --format '{{.Names}}' | grep -i dummy) 2>/dev/null || true
```

---

## 18. Production Upgrades Included/Planned

### 1. Real RPC Clients

Replace simulated ingestion with:

```text
Ethereum JSON-RPC
Cosmos Tendermint RPC
Solana RPC
```

### 2. Kafka Consumer Groups

Use consumer groups for scalable ingestion/indexing.

### 3. Schema Registry

Use Avro or Protobuf schemas for event contracts.

### 4. Reorg Handling

Track canonical chain:

```text
chain_id
block_height
block_hash
parent_hash
canonical_status
```

### 5. Idempotency

Use DB uniqueness constraints:

```sql
UNIQUE(chain_id, tx_hash)
UNIQUE(chain_id, block_height, block_hash)
UNIQUE(kafka_topic, kafka_partition, kafka_offset)
```

### 6. DLQ Topics

Use:

```text
raw.blocks.dlq
raw.transactions.dlq
decoded.events.dlq
```

### 7. API Auth and Tenant Isolation

Use:

```text
Authorization: Bearer <token>
X-Tenant-ID: tenant-a
```

### 8. Materialized Views

Analytics views:

```text
top_tokens_mv
active_addresses_mv
whale_movements_mv
gas_analytics_mv
```

### 9. Kubernetes

Deployments and HPA:

```bash
kubectl apply -f k8s/
```

### 10. Observability

Metrics:

```text
http_requests_total
http_request_duration_seconds
kafka_messages_consumed_total
kafka_messages_produced_total
dlq_events_total
chain_head_height
```

---

# Quick Start (Copy/Paste Run Steps)

## 1. Unzip and enter project

```bash
unzip crypto-analytics-platform-production-upgrades.zip
cd crypto-analytics-platform
```

## 2. Fix Postgres port conflict

```bash
sed -i 's/5432:5432/5433:5432/g' docker-compose.yml
```

## 3. Fix Go versions

```bash
find ./services -name go.mod -exec go mod edit -go=1.25 {} \;
find ./services -name go.mod -exec sed -i '/^toolchain /d' {} \;
```

## 4. Fix Dockerfiles

```bash
find ./services -name Dockerfile -exec sed -i 's/golang:1.22/golang:1.25/g' {} \;
find ./services -name Dockerfile -exec sed -i 's/golang:1.24/golang:1.25/g' {} \;
find ./services -name Dockerfile -exec sed -i '/RUN CGO_ENABLED=0 GOOS=linux go build/i RUN go mod tidy' {} \;
```

## 5. Build and start

```bash
docker compose build --no-cache
docker compose up -d
```

## 6. Verify

```bash
docker compose ps
```

## 7. Install full demo dashboard

```bash
chmod +x grafana-full-demo-dashboard.sh
./grafana-full-demo-dashboard.sh
```

## 8. Open Grafana

```text
http://localhost:3000/d/crypto-full-demo-dashboard
```

Login:

```text
admin / admin
```

## Stop

```bash
docker compose down
```

## Full reset

```bash
docker compose down -v
docker system prune -f
```

## Restart

```bash
docker compose up -d
./grafana-full-demo-dashboard.sh
```

---

## 20. Common Commands Summary

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Reset
docker compose down -v

# Build
docker compose build --no-cache

# Status
docker compose ps

# Logs
docker compose logs -f

# API health
curl http://localhost:8080/health

# Prometheus
open http://localhost:9090

# Grafana
open http://localhost:3000

# Demo dashboard
./grafana-full-demo-dashboard.sh
open http://localhost:3000/d/crypto-full-demo-dashboard
```

---

## 21. Recommended Next Improvements

- Add real Ethereum RPC ingestion with `eth_getBlockByNumber`
- Add Cosmos RPC ingestion using `/block` and `/tx_search`
- Add Solana RPC ingestion using `getBlock`
- Add schema registry with Protobuf
- Add Kafka retry topics
- Add OpenTelemetry traces
- Add JWT-based auth
- Add tenant-level quotas
- Add Elasticsearch index templates
- Add Timescale continuous aggregates
- Add Grafana panels based on real service metrics
- Add k6 load tests
- Add CI/CD with GitHub Actions
- Add Helm charts
- Add Terraform for cloud deployment

  ## Grafana Dashboard Screenshots

<p align="center">
  <img src="./grafana-dashboard-overview.png" width="900">
</p>

<p align="center">
  <img src="./grafana-timeseries.png" width="900">
</p>

<p align="center">
  <img src="./grafana-gauges-stats.png" width="900">
</p>

<p align="center">
  <img src="./grafana-crypto-panels.png" width="900">
</p>
