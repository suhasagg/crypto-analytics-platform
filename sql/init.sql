CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS tenants (
  tenant_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO tenants(tenant_id,name) VALUES ('demo','Demo Tenant') ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS api_keys (
  key_hash TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL REFERENCES tenants(tenant_id),
  role TEXT NOT NULL DEFAULT 'reader',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- dev key: demo-key. In prod store only bcrypt/argon2 hash in Vault/KMS.
INSERT INTO api_keys(key_hash,tenant_id,role) VALUES ('demo-key','demo','admin') ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS blocks (
  tenant_id TEXT NOT NULL DEFAULT 'demo',
  chain_id TEXT NOT NULL,
  block_number BIGINT NOT NULL,
  block_hash TEXT NOT NULL,
  parent_hash TEXT NOT NULL,
  block_time TIMESTAMPTZ NOT NULL,
  tx_count INT NOT NULL,
  gas_used NUMERIC NOT NULL DEFAULT 0,
  canonical BOOLEAN NOT NULL DEFAULT TRUE,
  ingest_partition INT,
  ingest_offset BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(tenant_id, chain_id, block_number, block_hash)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_blocks_canonical_height ON blocks(tenant_id, chain_id, block_number) WHERE canonical;
SELECT create_hypertable('blocks','block_time', if_not_exists => TRUE);

CREATE TABLE IF NOT EXISTS transactions (
  tenant_id TEXT NOT NULL DEFAULT 'demo',
  chain_id TEXT NOT NULL,
  tx_hash TEXT NOT NULL,
  block_number BIGINT NOT NULL,
  block_hash TEXT NOT NULL,
  from_address TEXT,
  to_address TEXT,
  token_address TEXT,
  token_symbol TEXT,
  value NUMERIC NOT NULL DEFAULT 0,
  fee NUMERIC NOT NULL DEFAULT 0,
  gas_used NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  tx_time TIMESTAMPTZ NOT NULL,
  ingest_partition INT,
  ingest_offset BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(tenant_id, chain_id, tx_hash)
);
SELECT create_hypertable('transactions','tx_time', if_not_exists => TRUE);

CREATE TABLE IF NOT EXISTS token_transfers (
  tenant_id TEXT NOT NULL DEFAULT 'demo',
  chain_id TEXT NOT NULL,
  tx_hash TEXT NOT NULL,
  log_index INT NOT NULL DEFAULT 0,
  block_number BIGINT NOT NULL,
  block_hash TEXT NOT NULL,
  token_address TEXT NOT NULL,
  token_symbol TEXT,
  from_address TEXT NOT NULL,
  to_address TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  transfer_time TIMESTAMPTZ NOT NULL,
  PRIMARY KEY(tenant_id, chain_id, tx_hash, log_index)
);
SELECT create_hypertable('token_transfers','transfer_time', if_not_exists => TRUE);

CREATE TABLE IF NOT EXISTS chain_heads (
  tenant_id TEXT NOT NULL DEFAULT 'demo',
  chain_id TEXT NOT NULL,
  block_number BIGINT NOT NULL,
  block_hash TEXT NOT NULL,
  finalized_number BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(tenant_id, chain_id)
);

CREATE TABLE IF NOT EXISTS kafka_offsets (
  consumer_group TEXT NOT NULL,
  topic TEXT NOT NULL,
  partition INT NOT NULL,
  last_committed_offset BIGINT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(consumer_group, topic, partition)
);

CREATE TABLE IF NOT EXISTS poison_events (
  topic TEXT NOT NULL,
  partition INT NOT NULL,
  offset_id BIGINT NOT NULL,
  payload JSONB,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(topic, partition, offset_id)
);

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_top_tokens AS
SELECT tenant_id, chain_id, COALESCE(token_symbol, token_address, 'NATIVE') AS token,
       count(*) AS tx_count, sum(value) AS volume
FROM transactions
WHERE tx_time > now() - interval '24 hours'
GROUP BY tenant_id, chain_id, COALESCE(token_symbol, token_address, 'NATIVE');

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_active_addresses AS
SELECT tenant_id, chain_id, address, count(*) AS activity_count
FROM (
  SELECT tenant_id, chain_id, from_address AS address FROM transactions WHERE tx_time > now() - interval '24 hours'
  UNION ALL
  SELECT tenant_id, chain_id, to_address AS address FROM transactions WHERE tx_time > now() - interval '24 hours'
) x
WHERE address IS NOT NULL
GROUP BY tenant_id, chain_id, address;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_whale_movements AS
SELECT tenant_id, chain_id, tx_hash, block_number, from_address, to_address, value, token_symbol, tx_time
FROM transactions
WHERE value >= 1000000 OR fee >= 10000;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_gas_analytics AS
SELECT tenant_id, chain_id, time_bucket('5 minutes', tx_time) AS bucket,
       count(*) AS tx_count, avg(fee) AS avg_fee, percentile_cont(0.95) WITHIN GROUP (ORDER BY fee) AS p95_fee,
       sum(gas_used) AS gas_used
FROM transactions
GROUP BY tenant_id, chain_id, time_bucket('5 minutes', tx_time);

CREATE INDEX IF NOT EXISTS idx_blocks_latest ON blocks(tenant_id, chain_id, block_number DESC) WHERE canonical;
CREATE INDEX IF NOT EXISTS idx_tx_address_from ON transactions(tenant_id, chain_id, from_address, tx_time DESC);
CREATE INDEX IF NOT EXISTS idx_tx_address_to ON transactions(tenant_id, chain_id, to_address, tx_time DESC);
CREATE INDEX IF NOT EXISTS idx_tx_time ON transactions(tenant_id, chain_id, tx_time DESC);
