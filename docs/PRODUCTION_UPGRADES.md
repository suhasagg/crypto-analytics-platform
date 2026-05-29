# Production upgrades implemented

## 1. Real RPC clients for Ethereum, Cosmos, Solana

`services/ingestor` now has a `ChainClient` interface and chain-specific clients:

- Ethereum: uses `go-ethereum/ethclient` and reads blocks via JSON-RPC.
- Cosmos: typed placeholder for Tendermint/Cosmos RPC enrichment.
- Solana: typed placeholder for Solana RPC enrichment.

Environment variables:

```bash
CHAINS=ethereum,cosmos,solana
ETHEREUM_RPC_URL=https://ethereum-rpc.publicnode.com
COSMOS_RPC_URL=https://rpc.cosmos.network:443
SOLANA_RPC_URL=https://api.mainnet-beta.solana.com
CONFIRMATIONS=12
```

## 2. Kafka consumer groups

The indexer now uses `sarama.ConsumerGroup` with group ID `crypto-indexer-v1`. This allows horizontal scaling with multiple indexer replicas. Kafka partitions are assigned across pods automatically.

## 3. Schema Registry with Protobuf/Avro

Added:

- `schema-registry` service in Docker Compose
- `schemas/proto/chain_event.proto`
- `schemas/avro/transaction_event.avsc`

The current code keeps JSON serialization for easy local execution. Production path is to generate Go types from Protobuf and wire Confluent Schema Registry serializers.

## 4. Chain reorg handling

The ingestor compares expected parent hashes and publishes `chain.reorgs`. The indexer handles reorgs by marking old blocks as `canonical=false` and deleting stale transactions after the reorg point.

## 5. Exactly-once-like idempotency

Implemented with:

- DB primary keys on `(tenant_id, chain_id, tx_hash)`
- block canonical uniqueness per `(tenant_id, chain_id, block_number)`
- `ON CONFLICT DO UPDATE/NOTHING`
- `kafka_offsets` table storing processed offsets
- Kafka consumer commits only after DB/index/cache work succeeds

This is not mathematically exactly-once across Kafka + DB + Elasticsearch, but it is the standard practical idempotent pattern.

## 6. Grafana dashboards

Added Grafana provisioning:

- Prometheus datasource
- TimescaleDB datasource
- dashboard: `crypto-analytics-overview`

Run at:

```text
http://localhost:3000
admin / admin
```

## 7. Kubernetes manifests and HPA

Added manifests under `infra/k8s`:

- namespace
- configmap
- secret
- ingestor deployment/service/HPA
- indexer deployment/service/HPA
- API deployment/service/HPA

Apply:

```bash
kubectl apply -f infra/k8s/
```

## 8. DLQ topics for poison events

The indexer sends failed messages to:

- `blocks.raw.dlq`
- `transactions.raw.dlq`
- `chain.reorgs.dlq`

It also stores poison events in the `poison_events` table.

## 9. API auth and tenant isolation

All `/v1/*` APIs require:

```bash
X-API-Key: demo-key
X-Tenant-ID: demo
```

All tables include `tenant_id`, and API queries filter by tenant.

## 10. Materialized analytics views

Added materialized views:

- `mv_top_tokens`
- `mv_active_addresses`
- `mv_whale_movements`
- `mv_gas_analytics`

Refresh:

```bash
curl -X POST http://localhost:8080/v1/admin/materialized-views/refresh \
  -H 'X-API-Key: demo-key' \
  -H 'X-Tenant-ID: demo'
```
