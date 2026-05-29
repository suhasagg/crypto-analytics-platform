package main

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/IBM/sarama"
	elasticsearch "github.com/elastic/go-elasticsearch/v8"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

type BlockEvent struct {
	TenantID   string `json:"tenant_id"`
	ChainID    string `json:"chain_id"`
	Number     int64  `json:"number"`
	Hash       string `json:"hash"`
	ParentHash string `json:"parent_hash"`
	UnixMs     int64  `json:"unix_ms"`
	TxCount    int    `json:"tx_count"`
	GasUsed    string `json:"gas_used"`
	Finalized  bool   `json:"finalized"`
}
type TxEvent struct {
	TenantID     string `json:"tenant_id"`
	ChainID      string `json:"chain_id"`
	Hash         string `json:"hash"`
	BlockNumber  int64  `json:"block_number"`
	BlockHash    string `json:"block_hash"`
	From         string `json:"from"`
	To           string `json:"to"`
	TokenAddress string `json:"token_address"`
	TokenSymbol  string `json:"token_symbol"`
	Value        string `json:"value"`
	Fee          string `json:"fee"`
	GasUsed      string `json:"gas_used"`
	Status       string `json:"status"`
	UnixMs       int64  `json:"unix_ms"`
}
type ReorgEvent struct {
	TenantID       string   `json:"tenant_id"`
	ChainID        string   `json:"chain_id"`
	FromBlock      int64    `json:"from_block"`
	OldHead        string   `json:"old_head"`
	NewHead        string   `json:"new_head"`
	OrphanedHashes []string `json:"orphaned_hashes"`
}

var consumed = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "events_consumed_total", Help: "Kafka events consumed"}, []string{"topic"})
var poison = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "poison_events_total", Help: "Events sent to DLQ"}, []string{"topic"})
var processLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{Name: "event_processing_seconds", Help: "Event processing latency", Buckets: prometheus.DefBuckets}, []string{"topic"})

func env(k, f string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return f
}

type handler struct {
	pg    *pgxpool.Pool
	es    *elasticsearch.Client
	rdb   *redis.Client
	dlq   sarama.SyncProducer
	group string
}

func main() {
	prometheus.MustRegister(consumed, poison, processLatency)
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("OK")) })
		log.Fatal(http.ListenAndServe(":8082", mux))
	}()
	ctx := context.Background()
	pg, err := pgxpool.New(ctx, env("PG_DSN", "postgres://postgres:postgres@localhost:5432/crypto_analytics?sslmode=disable"))
	if err != nil {
		log.Fatal(err)
	}
	es, _ := elasticsearch.NewClient(elasticsearch.Config{Addresses: []string{env("ES_URL", "http://localhost:9200")}})
	rdb := redis.NewClient(&redis.Options{Addr: env("REDIS_ADDR", "localhost:6379")})
	cfg := sarama.NewConfig()
	cfg.Version = sarama.V2_8_0_0
	cfg.Consumer.Group.Rebalance.GroupStrategies = []sarama.BalanceStrategy{sarama.NewBalanceStrategyRange()}
	cfg.Consumer.Offsets.Initial = sarama.OffsetOldest
	cfg.Producer.Return.Successes = true
	cfg.Producer.RequiredAcks = sarama.WaitForAll
	brokers := strings.Split(env("KAFKA_BROKERS", "localhost:9092"), ",")
	dlq, _ := sarama.NewSyncProducer(brokers, cfg)
	group, err := sarama.NewConsumerGroup(brokers, env("KAFKA_GROUP_ID", "crypto-indexer-v1"), cfg)
	if err != nil {
		log.Fatal(err)
	}
	h := &handler{pg: pg, es: es, rdb: rdb, dlq: dlq, group: env("KAFKA_GROUP_ID", "crypto-indexer-v1")}
	topics := []string{"blocks.raw", "transactions.raw", "chain.reorgs"}
	for {
		if err := group.Consume(ctx, topics, h); err != nil {
			log.Println("consume error", err)
			time.Sleep(time.Second)
		}
	}
}
func (h *handler) Setup(s sarama.ConsumerGroupSession) error   { return nil }
func (h *handler) Cleanup(s sarama.ConsumerGroupSession) error { return nil }
func (h *handler) ConsumeClaim(sess sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for msg := range claim.Messages() {
		start := time.Now()
		if err := h.process(sess.Context(), msg); err != nil {
			h.sendDLQ(msg, err)
			poison.WithLabelValues(msg.Topic).Inc()
		} else {
			h.pg.Exec(sess.Context(), `INSERT INTO kafka_offsets(consumer_group,topic,partition,last_committed_offset) VALUES($1,$2,$3,$4) ON CONFLICT(consumer_group,topic,partition) DO UPDATE SET last_committed_offset=EXCLUDED.last_committed_offset,updated_at=now()`, h.group, msg.Topic, msg.Partition, msg.Offset)
			sess.MarkMessage(msg, "")
			consumed.WithLabelValues(msg.Topic).Inc()
		}
		processLatency.WithLabelValues(msg.Topic).Observe(time.Since(start).Seconds())
	}
	return nil
}
func (h *handler) process(ctx context.Context, msg *sarama.ConsumerMessage) error {
	switch msg.Topic {
	case "blocks.raw":
		var b BlockEvent
		if err := json.Unmarshal(msg.Value, &b); err != nil {
			return err
		}
		return h.upsertBlock(ctx, b, msg)
	case "transactions.raw":
		var t TxEvent
		if err := json.Unmarshal(msg.Value, &t); err != nil {
			return err
		}
		return h.upsertTx(ctx, t, msg)
	case "chain.reorgs":
		var r ReorgEvent
		if err := json.Unmarshal(msg.Value, &r); err != nil {
			return err
		}
		return h.applyReorg(ctx, r)
	default:
		return nil
	}
}
func (h *handler) upsertBlock(ctx context.Context, b BlockEvent, msg *sarama.ConsumerMessage) error {
	tm := time.UnixMilli(b.UnixMs).UTC()
	_, err := h.pg.Exec(ctx, `INSERT INTO blocks(tenant_id,chain_id,block_number,block_hash,parent_hash,block_time,tx_count,gas_used,canonical,ingest_partition,ingest_offset) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT(tenant_id,chain_id,block_number,block_hash) DO UPDATE SET canonical=true, ingest_partition=EXCLUDED.ingest_partition, ingest_offset=EXCLUDED.ingest_offset`, nz(b.TenantID), b.ChainID, b.Number, b.Hash, b.ParentHash, tm, b.TxCount, b.GasUsed, true, msg.Partition, msg.Offset)
	if err != nil {
		return err
	}
	h.index("blocks", b.ChainID+":"+b.Hash, b)
	h.rdb.Del(ctx, "latest_blocks:"+nz(b.TenantID)+":"+b.ChainID)
	return nil
}
func (h *handler) upsertTx(ctx context.Context, t TxEvent, msg *sarama.ConsumerMessage) error {
	tm := time.UnixMilli(t.UnixMs).UTC()
	_, err := h.pg.Exec(ctx, `INSERT INTO transactions(tenant_id,chain_id,tx_hash,block_number,block_hash,from_address,to_address,token_address,token_symbol,value,fee,gas_used,status,tx_time,ingest_partition,ingest_offset) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16) ON CONFLICT(tenant_id,chain_id,tx_hash) DO UPDATE SET block_number=EXCLUDED.block_number, block_hash=EXCLUDED.block_hash, ingest_partition=EXCLUDED.ingest_partition, ingest_offset=EXCLUDED.ingest_offset`, nz(t.TenantID), t.ChainID, t.Hash, t.BlockNumber, t.BlockHash, t.From, t.To, t.TokenAddress, t.TokenSymbol, t.Value, t.Fee, t.GasUsed, t.Status, tm, msg.Partition, msg.Offset)
	if err != nil {
		return err
	}
	h.index("transactions", t.ChainID+":"+t.Hash, t)
	h.rdb.Del(ctx, "address:"+nz(t.TenantID)+":"+t.ChainID+":"+t.From, "address:"+nz(t.TenantID)+":"+t.ChainID+":"+t.To)
	return nil
}
func (h *handler) applyReorg(ctx context.Context, r ReorgEvent) error {
	_, err := h.pg.Exec(ctx, `UPDATE blocks SET canonical=false WHERE tenant_id=$1 AND chain_id=$2 AND block_number >= $3 AND block_hash <> $4`, nz(r.TenantID), r.ChainID, r.FromBlock, r.NewHead)
	_, _ = h.pg.Exec(ctx, `DELETE FROM transactions WHERE tenant_id=$1 AND chain_id=$2 AND block_number >= $3 AND block_hash <> $4`, nz(r.TenantID), r.ChainID, r.FromBlock, r.NewHead)
	h.rdb.FlushDB(ctx)
	return err
}
func (h *handler) sendDLQ(msg *sarama.ConsumerMessage, err error) {
	payload := map[string]any{"topic": msg.Topic, "partition": msg.Partition, "offset": msg.Offset, "error": err.Error(), "payload": json.RawMessage(msg.Value)}
	b, _ := json.Marshal(payload)
	h.dlq.SendMessage(&sarama.ProducerMessage{Topic: msg.Topic + ".dlq", Key: sarama.ByteEncoder(msg.Key), Value: sarama.ByteEncoder(b)})
	h.pg.Exec(context.Background(), `INSERT INTO poison_events(topic,partition,offset_id,payload,error) VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`, msg.Topic, msg.Partition, msg.Offset, string(msg.Value), err.Error())
}
func (h *handler) index(index, id string, doc any) {
	b, _ := json.Marshal(doc)
	res, err := h.es.Index(index, bytes.NewReader(b), h.es.Index.WithDocumentID(id))
	if err == nil && res != nil {
		res.Body.Close()
	}
}
func nz(v string) string {
	if v == "" {
		return "demo"
	}
	return v
}
