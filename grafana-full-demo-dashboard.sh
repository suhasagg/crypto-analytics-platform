#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# grafana-full-demo-dashboard.sh
#
# Forces a FULL, fancy Grafana dashboard with instantly-filled
# demo time series using Grafana's built-in TestData DB datasource.
#
# This creates:
#   - Stat cards
#   - Gauges
#   - Bar gauges
#   - Pie/donut charts
#   - Heatmap-style panel
#   - Multiple full-width time series
#   - Crypto-specific fake metrics panels:
#       TPS, gas price, indexed blocks, DEX volume,
#       token prices, whale transfers, API latency,
#       indexer lag, DLQ/reorg events, tenant load
#
# It does NOT depend on Prometheus data history, so charts are full
# immediately across the selected time range.
#
# Run from project root or anywhere:
#
#   chmod +x grafana-full-demo-dashboard.sh
#   ./grafana-full-demo-dashboard.sh
#
# Open:
#   http://localhost:3000/d/crypto-full-demo-dashboard
#
# Login:
#   admin / admin
# ============================================================

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"
DASH_UID="crypto-full-demo-dashboard"

log() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

info() {
  echo "[INFO] $1"
}

fail() {
  echo "[ERROR] $1"
  exit 1
}

wait_for_grafana() {
  log "Waiting for Grafana"

  for i in $(seq 1 60); do
    if curl -fsS "$GRAFANA_URL/api/health" >/dev/null 2>&1; then
      info "Grafana is ready"
      return 0
    fi
    sleep 2
  done

  fail "Grafana not reachable at $GRAFANA_URL"
}

create_testdata_datasource() {
  log "Creating TestData DB datasource"

  curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -H "Content-Type: application/json" \
    -X POST "$GRAFANA_URL/api/datasources" \
    -d '{
      "name": "Crypto Demo TestData",
      "uid": "crypto-demo-testdata",
      "type": "testdata",
      "access": "proxy",
      "isDefault": false,
      "jsonData": {}
    }' >/dev/null 2>&1 || true

  info "Datasource ready: Crypto Demo TestData"
}

import_dashboard() {
  log "Importing full fancy dashboard"

  cat > /tmp/crypto-full-demo-dashboard.json <<'JSON'
{
  "dashboard": {
    "id": null,
    "uid": "crypto-full-demo-dashboard",
    "title": "Crypto Analytics FULL Demo Dashboard",
    "tags": ["crypto", "demo-data"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "refresh": "5s",
    "time": {
      "from": "now-6h",
      "to": "now"
    },
    "panels": [
      {
        "id": 1,
        "type": "stat",
        "title": "Total Network TPS",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "Total TPS"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "ops",
            "min": 0,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "blue", "value": null},
                {"color": "green", "value": 50},
                {"color": "purple", "value": 100}
              ]
            }
          },
          "overrides": []
        },
        "options": {
          "colorMode": "background",
          "graphMode": "area",
          "justifyMode": "center",
          "orientation": "auto",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""}
        },
        "gridPos": {"x": 0, "y": 0, "w": 6, "h": 4}
      },
      {
        "id": 2,
        "type": "stat",
        "title": "Indexed Transactions",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "Indexed Transactions"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "green", "value": null},
                {"color": "blue", "value": 50},
                {"color": "purple", "value": 100}
              ]
            }
          },
          "overrides": []
        },
        "options": {
          "colorMode": "background",
          "graphMode": "area",
          "justifyMode": "center",
          "orientation": "auto",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""}
        },
        "gridPos": {"x": 6, "y": 0, "w": 6, "h": 4}
      },
      {
        "id": 3,
        "type": "gauge",
        "title": "Redis Cache Hit Ratio",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "Cache Hit %"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "red", "value": null},
                {"color": "orange", "value": 40},
                {"color": "green", "value": 70}
              ]
            }
          },
          "overrides": []
        },
        "options": {
          "orientation": "auto",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""},
          "showThresholdLabels": true,
          "showThresholdMarkers": true
        },
        "gridPos": {"x": 12, "y": 0, "w": 6, "h": 4}
      },
      {
        "id": 4,
        "type": "stat",
        "title": "Whale Transfers",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "Whale Transfers"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "orange", "value": null},
                {"color": "red", "value": 60},
                {"color": "purple", "value": 100}
              ]
            }
          },
          "overrides": []
        },
        "options": {
          "colorMode": "background",
          "graphMode": "area",
          "justifyMode": "center",
          "orientation": "auto",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""}
        },
        "gridPos": {"x": 18, "y": 0, "w": 6, "h": 4}
      },

      {
        "id": 5,
        "type": "timeseries",
        "title": "TPS by Chain - Full Time Series",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "ethereum"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "cosmos"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "solana"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "base"},
          {"refId": "E", "scenarioId": "random_walk", "alias": "arbitrum"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "ops",
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "smooth",
              "lineWidth": 3,
              "fillOpacity": 35,
              "gradientMode": "scheme",
              "showPoints": "never"
            }
          },
          "overrides": []
        },
        "options": {
          "legend": {"displayMode": "table", "placement": "right", "showLegend": true},
          "tooltip": {"mode": "multi", "sort": "desc"}
        },
        "gridPos": {"x": 0, "y": 4, "w": 12, "h": 8}
      },
      {
        "id": 6,
        "type": "timeseries",
        "title": "Gas Price by Chain - Bar Time Series",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "ethereum gas"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "polygon gas"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "arbitrum gas"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "base gas"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "custom": {
              "drawStyle": "bars",
              "lineInterpolation": "linear",
              "lineWidth": 1,
              "fillOpacity": 70,
              "gradientMode": "hue",
              "showPoints": "never"
            }
          },
          "overrides": []
        },
        "options": {
          "legend": {"displayMode": "table", "placement": "right", "showLegend": true},
          "tooltip": {"mode": "multi", "sort": "desc"}
        },
        "gridPos": {"x": 12, "y": 4, "w": 12, "h": 8}
      },

      {
        "id": 7,
        "type": "bargauge",
        "title": "Indexer Lag by Chain - Bar Gauge",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "ethereum lag"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "cosmos lag"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "solana lag"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "base lag"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "green", "value": null},
                {"color": "orange", "value": 40},
                {"color": "red", "value": 80}
              ]
            }
          },
          "overrides": []
        },
        "options": {
          "displayMode": "gradient",
          "orientation": "horizontal",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""},
          "showUnfilled": true
        },
        "gridPos": {"x": 0, "y": 12, "w": 8, "h": 8}
      },
      {
        "id": 8,
        "type": "piechart",
        "title": "Active Addresses Share - Donut",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "ethereum"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "cosmos"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "solana"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "base"},
          {"refId": "E", "scenarioId": "random_walk", "alias": "arbitrum"}
        ],
        "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
        "options": {
          "displayLabels": ["name", "percent"],
          "legend": {"displayMode": "table", "placement": "right", "showLegend": true},
          "pieType": "donut",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""},
          "tooltip": {"mode": "single", "sort": "desc"}
        },
        "gridPos": {"x": 8, "y": 12, "w": 8, "h": 8}
      },
      {
        "id": 9,
        "type": "gauge",
        "title": "Average API Latency",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "latency"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "ms",
            "min": 0,
            "max": 200,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "green", "value": null},
                {"color": "orange", "value": 80},
                {"color": "red", "value": 150}
              ]
            }
          },
          "overrides": []
        },
        "options": {
          "orientation": "auto",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""},
          "showThresholdLabels": true,
          "showThresholdMarkers": true
        },
        "gridPos": {"x": 16, "y": 12, "w": 8, "h": 8}
      },

      {
        "id": 10,
        "type": "timeseries",
        "title": "DEX Volume by Chain/DEX - Full Width",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "uniswap / ethereum"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "osmosis / cosmos"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "raydium / solana"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "curve / ethereum"},
          {"refId": "E", "scenarioId": "random_walk", "alias": "balancer / arbitrum"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "currencyUSD",
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "smooth",
              "lineWidth": 2,
              "fillOpacity": 45,
              "gradientMode": "scheme",
              "showPoints": "never"
            }
          },
          "overrides": []
        },
        "options": {
          "legend": {"displayMode": "table", "placement": "bottom", "showLegend": true},
          "tooltip": {"mode": "multi", "sort": "desc"}
        },
        "gridPos": {"x": 0, "y": 20, "w": 24, "h": 9}
      },

      {
        "id": 11,
        "type": "timeseries",
        "title": "Token Price Time Series",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "ETH"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "ATOM"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "SOL"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "ARB"},
          {"refId": "E", "scenarioId": "random_walk", "alias": "MATIC"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "currencyUSD",
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "smooth",
              "lineWidth": 3,
              "fillOpacity": 15,
              "gradientMode": "opacity",
              "showPoints": "never"
            }
          },
          "overrides": []
        },
        "options": {
          "legend": {"displayMode": "table", "placement": "right", "showLegend": true},
          "tooltip": {"mode": "multi", "sort": "desc"}
        },
        "gridPos": {"x": 0, "y": 29, "w": 12, "h": 8}
      },
      {
        "id": 12,
        "type": "timeseries",
        "title": "API Latency by Endpoint",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "/search"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "/analytics/top-tokens"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "/analytics/whales"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "/analytics/gas"},
          {"refId": "E", "scenarioId": "random_walk", "alias": "/health"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "ms",
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "smooth",
              "lineWidth": 2,
              "fillOpacity": 25,
              "gradientMode": "scheme",
              "showPoints": "never"
            }
          },
          "overrides": []
        },
        "options": {
          "legend": {"displayMode": "table", "placement": "right", "showLegend": true},
          "tooltip": {"mode": "multi", "sort": "desc"}
        },
        "gridPos": {"x": 12, "y": 29, "w": 12, "h": 8}
      },

      {
        "id": 13,
        "type": "timeseries",
        "title": "Kafka Consumer Lag - Bars",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "indexer ethereum"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "indexer cosmos"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "indexer solana"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "indexer arbitrum"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "custom": {
              "drawStyle": "bars",
              "lineWidth": 1,
              "fillOpacity": 65,
              "gradientMode": "hue",
              "showPoints": "never"
            }
          },
          "overrides": []
        },
        "options": {
          "legend": {"displayMode": "table", "placement": "right", "showLegend": true},
          "tooltip": {"mode": "multi", "sort": "desc"}
        },
        "gridPos": {"x": 0, "y": 37, "w": 12, "h": 8}
      },
      {
        "id": 14,
        "type": "timeseries",
        "title": "Chain Head Height",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "ethereum"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "cosmos"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "solana"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "polygon"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "smooth",
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "opacity",
              "showPoints": "never"
            }
          },
          "overrides": []
        },
        "options": {
          "legend": {"displayMode": "table", "placement": "right", "showLegend": true},
          "tooltip": {"mode": "multi", "sort": "desc"}
        },
        "gridPos": {"x": 12, "y": 37, "w": 12, "h": 8}
      },

      {
        "id": 15,
        "type": "heatmap",
        "title": "Heatmap Style - Security Risk / Chain Activity",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "security risk"}
        ],
        "fieldConfig": {
          "defaults": {"unit": "short"},
          "overrides": []
        },
        "options": {
          "calculate": true,
          "calculation": {
            "xBuckets": {"mode": "size", "value": "30s"},
            "yBuckets": {"mode": "count", "value": "12"}
          },
          "cellGap": 1,
          "cellValues": {"unit": "short"},
          "color": {"mode": "scheme", "scheme": "Oranges", "steps": 64},
          "exemplars": {"color": "rgba(255,0,255,0.7)"},
          "filterValues": {"le": 1e-9},
          "legend": {"show": true},
          "rowsFrame": {"layout": "auto"},
          "tooltip": {"show": true, "yHistogram": false}
        },
        "gridPos": {"x": 0, "y": 45, "w": 12, "h": 8}
      },
      {
        "id": 16,
        "type": "piechart",
        "title": "Whale Transfers by Chain - Pie",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "ethereum"},
          {"refId": "B", "scenarioId": "random_walk", "alias": "cosmos"},
          {"refId": "C", "scenarioId": "random_walk", "alias": "solana"},
          {"refId": "D", "scenarioId": "random_walk", "alias": "base"},
          {"refId": "E", "scenarioId": "random_walk", "alias": "arbitrum"}
        ],
        "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
        "options": {
          "displayLabels": ["name", "value"],
          "legend": {"displayMode": "table", "placement": "right", "showLegend": true},
          "pieType": "pie",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""},
          "tooltip": {"mode": "single", "sort": "desc"}
        },
        "gridPos": {"x": 12, "y": 45, "w": 6, "h": 8}
      },
      {
        "id": 17,
        "type": "stat",
        "title": "DLQ Events",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "DLQ"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "green", "value": null},
                {"color": "orange", "value": 50},
                {"color": "red", "value": 90}
              ]
            }
          },
          "overrides": []
        },
        "options": {
          "colorMode": "background",
          "graphMode": "area",
          "justifyMode": "center",
          "orientation": "auto",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""}
        },
        "gridPos": {"x": 18, "y": 45, "w": 3, "h": 8}
      },
      {
        "id": 18,
        "type": "stat",
        "title": "Reorg Events",
        "datasource": {"type": "testdata", "uid": "crypto-demo-testdata"},
        "targets": [
          {"refId": "A", "scenarioId": "random_walk", "alias": "Reorg"}
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "green", "value": null},
                {"color": "orange", "value": 50},
                {"color": "red", "value": 90}
              ]
            }
          },
          "overrides": []
        },
        "options": {
          "colorMode": "background",
          "graphMode": "area",
          "justifyMode": "center",
          "orientation": "auto",
          "reduceOptions": {"values": false, "calcs": ["lastNotNull"], "fields": ""}
        },
        "gridPos": {"x": 21, "y": 45, "w": 3, "h": 8}
      }
    ]
  },
  "overwrite": true,
  "folderUid": ""
}
JSON

  curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -H "Content-Type: application/json" \
    -X POST "$GRAFANA_URL/api/dashboards/db" \
    --data-binary @/tmp/crypto-full-demo-dashboard.json >/dev/null

  info "Dashboard imported"
}

main() {
  wait_for_grafana
  create_testdata_datasource
  import_dashboard

  log "DONE"

  cat <<EOF
Open full demo dashboard:

  $GRAFANA_URL/d/$DASH_UID

Login:

  $GRAFANA_USER / $GRAFANA_PASS

What you should see:
  - Full time-series graphs across 6 hours
  - Stat cards
  - Gauges
  - Bar gauges
  - Pie/donut charts
  - Heatmap-style panel
  - Crypto fake metrics: TPS, gas, DEX volume, token prices, latency, lag, whales, DLQ, reorgs
EOF
}

main "$@"
