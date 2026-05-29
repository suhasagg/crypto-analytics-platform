#!/usr/bin/env python3
import math
import random
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

START = time.time()
CHAINS = ["ethereum", "cosmos", "solana", "base", "arbitrum", "polygon"]
TOKENS = ["ETH", "ATOM", "SOL", "USDC", "WBTC", "ARB", "MATIC"]
DEXES = ["uniswap", "osmosis", "raydium", "curve", "balancer"]
TENANTS = ["tenant-a", "tenant-b", "tenant-c"]

def wave(period, amp=1.0, phase=0.0):
    t = time.time() - START
    return amp * (1 + math.sin((t / period) + phase)) / 2

def metrics():
    now = int(time.time())
    lines = []
    lines.append("# HELP crypto_blocks_indexed_total Dummy indexed blocks")
    lines.append("# TYPE crypto_blocks_indexed_total counter")
    lines.append("# HELP crypto_transactions_indexed_total Dummy indexed txs")
    lines.append("# TYPE crypto_transactions_indexed_total counter")
    lines.append("# HELP crypto_tps Current dummy transactions per second")
    lines.append("# TYPE crypto_tps gauge")
    lines.append("# HELP crypto_chain_head_height Current dummy chain head height")
    lines.append("# TYPE crypto_chain_head_height gauge")
    lines.append("# HELP crypto_indexer_lag_blocks Dummy indexer lag blocks")
    lines.append("# TYPE crypto_indexer_lag_blocks gauge")
    lines.append("# HELP crypto_gas_price_gwei Dummy gas price")
    lines.append("# TYPE crypto_gas_price_gwei gauge")
    lines.append("# HELP crypto_whale_transfers_total Dummy whale movement counter")
    lines.append("# TYPE crypto_whale_transfers_total counter")
    lines.append("# HELP crypto_dex_volume_usd Dummy DEX volume")
    lines.append("# TYPE crypto_dex_volume_usd gauge")
    lines.append("# HELP crypto_token_price_usd Dummy token price")
    lines.append("# TYPE crypto_token_price_usd gauge")
    lines.append("# HELP crypto_active_addresses Dummy active addresses")
    lines.append("# TYPE crypto_active_addresses gauge")
    lines.append("# HELP crypto_api_latency_ms Dummy API latency")
    lines.append("# TYPE crypto_api_latency_ms gauge")
    lines.append("# HELP crypto_cache_hit_ratio Dummy cache hit ratio")
    lines.append("# TYPE crypto_cache_hit_ratio gauge")
    lines.append("# HELP crypto_kafka_lag Dummy Kafka consumer lag")
    lines.append("# TYPE crypto_kafka_lag gauge")
    lines.append("# HELP crypto_dlq_events_total Dummy DLQ events")
    lines.append("# TYPE crypto_dlq_events_total counter")
    lines.append("# HELP crypto_reorg_events_total Dummy chain reorg counter")
    lines.append("# TYPE crypto_reorg_events_total counter")
    lines.append("# HELP crypto_tenant_requests_total Dummy tenant request counter")
    lines.append("# TYPE crypto_tenant_requests_total counter")

    elapsed = max(1, int(time.time() - START))

    base_heights = {
        "ethereum": 21000000,
        "cosmos": 24000000,
        "solana": 310000000,
        "base": 16000000,
        "arbitrum": 290000000,
        "polygon": 72000000,
    }

    for i, chain in enumerate(CHAINS):
        phase = i * 0.8
        tps = 30 + wave(10 + i, 120, phase) + random.random() * 8
        lag = max(0, int(20 * wave(13 + i, 1, phase) + random.randint(0, 4)))
        gas = 3 + wave(15 + i, 80, phase) + random.random() * 4
        active = int(5000 + wave(20 + i, 50000, phase) + random.randint(0, 3000))
        head = base_heights[chain] + elapsed * (i + 1)

        lines.append(f'crypto_tps{{chain="{chain}"}} {tps:.2f}')
        lines.append(f'crypto_chain_head_height{{chain="{chain}"}} {head}')
        lines.append(f'crypto_indexer_lag_blocks{{chain="{chain}"}} {lag}')
        lines.append(f'crypto_gas_price_gwei{{chain="{chain}"}} {gas:.2f}')
        lines.append(f'crypto_active_addresses{{chain="{chain}"}} {active}')
        lines.append(f'crypto_blocks_indexed_total{{chain="{chain}"}} {elapsed * (i + 2) * 5}')
        lines.append(f'crypto_transactions_indexed_total{{chain="{chain}"}} {elapsed * int(tps)}')
        lines.append(f'crypto_whale_transfers_total{{chain="{chain}"}} {elapsed * (i + 1) + random.randint(0, 20)}')
        lines.append(f'crypto_kafka_lag{{consumer_group="indexer",chain="{chain}"}} {lag * random.randint(1, 5)}')
        lines.append(f'crypto_reorg_events_total{{chain="{chain}"}} {elapsed // (200 + i * 50)}')

    prices = {
        "ETH": 3200,
        "ATOM": 9,
        "SOL": 170,
        "USDC": 1,
        "WBTC": 68000,
        "ARB": 1.4,
        "MATIC": 0.8,
    }

    for i, token in enumerate(TOKENS):
        price = prices[token] * (0.95 + wave(30 + i, 0.12, i))
        lines.append(f'crypto_token_price_usd{{token="{token}"}} {price:.4f}')

    for i, dex in enumerate(DEXES):
        for j, chain in enumerate(CHAINS[:4]):
            vol = 100000 + wave(18 + i + j, 2000000, i + j) + random.randint(0, 50000)
            lines.append(f'crypto_dex_volume_usd{{dex="{dex}",chain="{chain}"}} {vol:.2f}')

    endpoints = ["/search", "/analytics/top-tokens", "/analytics/whales", "/analytics/gas", "/health"]
    for i, ep in enumerate(endpoints):
        latency = 20 + wave(12 + i, 250, i) + random.random() * 15
        lines.append(f'crypto_api_latency_ms{{endpoint="{ep}"}} {latency:.2f}')

    lines.append(f'crypto_cache_hit_ratio{{cache="redis_search"}} {0.70 + wave(20, 0.25):.4f}')
    lines.append(f'crypto_cache_hit_ratio{{cache="redis_token_metadata"}} {0.80 + wave(25, 0.18, 2):.4f}')
    lines.append(f'crypto_dlq_events_total{{topic="decoded.events.dlq"}} {elapsed // 60}')
    lines.append(f'crypto_dlq_events_total{{topic="raw.blocks.dlq"}} {elapsed // 90}')

    for i, tenant in enumerate(TENANTS):
        lines.append(f'crypto_tenant_requests_total{{tenant="{tenant}"}} {elapsed * (50 + i * 30)}')

    return "\n".join(lines) + "\n"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = b"ok\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path.startswith("/metrics"):
            body = metrics().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        return

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 9109), Handler)
    print("dummy crypto metrics exporter listening on :9109")
    server.serve_forever()
