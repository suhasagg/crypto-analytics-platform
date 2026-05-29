#!/usr/bin/env bash
set -euo pipefail
BROKER=${BROKER:-localhost:9092}
for t in blocks.raw transactions.raw chain.reorgs blocks.raw.dlq transactions.raw.dlq chain.reorgs.dlq; do
  kafka-topics --bootstrap-server "$BROKER" --create --if-not-exists --topic "$t" --partitions 12 --replication-factor 1
 done
