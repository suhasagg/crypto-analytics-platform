package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/IBM/sarama"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
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
	TokenAddress string `json:"token_address,omitempty"`
	TokenSymbol  string `json:"token_symbol,omitempty"`
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

type ChainClient interface {
	ChainID() string
	LatestHeight(ctx context.Context) (int64, error)
	BlockByHeight(ctx context.Context, h int64) (BlockEvent, []TxEvent, error)
}

var produced = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "events_produced_total", Help: "Kafka events produced"}, []string{"topic", "chain"})
var rpcErrors = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "rpc_errors_total", Help: "RPC errors"}, []string{"chain"})
var ingestorLag = prometheus.NewGaugeVec(prometheus.GaugeOpts{Name: "ingestor_block_lag", Help: "Latest minus ingested height"}, []string{"chain"})

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	prometheus.MustRegister(produced, rpcErrors, ingestorLag)
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("OK")) })
		log.Fatal(http.ListenAndServe(":8081", mux))
	}()

	cfg := sarama.NewConfig()
	cfg.Producer.Return.Successes = true
	cfg.Producer.Idempotent = true
	cfg.Net.MaxOpenRequests = 1
	cfg.Producer.RequiredAcks = sarama.WaitForAll
	producer, err := sarama.NewSyncProducer(strings.Split(env("KAFKA_BROKERS", "localhost:9092"), ","), cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer producer.Close()

	clients := buildClients()
	for _, c := range clients {
		go ingestLoop(context.Background(), c, producer)
	}
	select {}
}

func buildClients() []ChainClient {
	chains := strings.Split(env("CHAINS", "ethereum,cosmos,solana"), ",")
	out := []ChainClient{}
	for _, c := range chains {
		switch strings.TrimSpace(c) {
		case "ethereum":
			out = append(out, NewEthereumClient(env("ETHEREUM_RPC_URL", "")))
		case "cosmos":
			out = append(out, NewCosmosClient(env("COSMOS_RPC_URL", "")))
		case "solana":
			out = append(out, NewSolanaClient(env("SOLANA_RPC_URL", "")))
		}
	}
	if len(out) == 0 {
		out = append(out, NewSimClient("simulated-chain"))
	}
	return out
}

func ingestLoop(ctx context.Context, c ChainClient, p sarama.SyncProducer) {
	poll, _ := strconv.Atoi(env("POLL_INTERVAL_MS", "5000"))
	conf, _ := strconv.Atoi(env("CONFIRMATIONS", "12"))
	var last int64 = 0
	parent := map[int64]string{}
	for {
		latest, err := c.LatestHeight(ctx)
		if err != nil {
			rpcErrors.WithLabelValues(c.ChainID()).Inc()
			log.Println("latest error", c.ChainID(), err)
			time.Sleep(time.Duration(poll) * time.Millisecond)
			continue
		}
		target := latest - int64(conf)
		if target < 1 {
			time.Sleep(time.Duration(poll) * time.Millisecond)
			continue
		}
		ingestorLag.WithLabelValues(c.ChainID()).Set(float64(latest - last))
		for h := last + 1; h <= target; h++ {
			b, txs, err := c.BlockByHeight(ctx, h)
			if err != nil {
				rpcErrors.WithLabelValues(c.ChainID()).Inc()
				break
			}
			if exp, ok := parent[h]; ok && exp != b.Hash {
				publish(p, "chain.reorgs", fmt.Sprintf("%s:%d", c.ChainID(), h), ReorgEvent{TenantID: "demo", ChainID: c.ChainID(), FromBlock: h, OldHead: exp, NewHead: b.Hash, OrphanedHashes: []string{exp}})
			}
			parent[h+1] = b.Hash
			publish(p, "blocks.raw", fmt.Sprintf("%s:%d", b.ChainID, b.Number), b)
			for _, tx := range txs {
				publish(p, "transactions.raw", fmt.Sprintf("%s:%s", tx.ChainID, tx.Hash), tx)
			}
			last = h
		}
		time.Sleep(time.Duration(poll) * time.Millisecond)
	}
}

func publish(p sarama.SyncProducer, topic, key string, v any) {
	b, _ := json.Marshal(v) // production: replace JSON with Protobuf/Avro serializer using Schema Registry.
	_, _, err := p.SendMessage(&sarama.ProducerMessage{Topic: topic, Key: sarama.StringEncoder(key), Value: sarama.ByteEncoder(b)})
	if err != nil {
		log.Println("publish error", topic, err)
		return
	}
	chain := "unknown"
	if m, ok := v.(interface{ GetChainID() string }); ok {
		chain = m.GetChainID()
	}
	produced.WithLabelValues(topic, chain).Inc()
}
func (b BlockEvent) GetChainID() string { return b.ChainID }
func (t TxEvent) GetChainID() string    { return t.ChainID }

// Sim fallback for local dev.
type SimClient struct {
	id string
	h  int64
}

func NewSimClient(id string) *SimClient                          { return &SimClient{id: id} }
func (s *SimClient) ChainID() string                             { return s.id }
func (s *SimClient) LatestHeight(context.Context) (int64, error) { s.h++; return s.h + 20, nil }
func (s *SimClient) BlockByHeight(ctx context.Context, h int64) (BlockEvent, []TxEvent, error) {
	now := time.Now().UTC().UnixMilli()
	hash := fmt.Sprintf("0xblock%08d", h)
	b := BlockEvent{"demo", s.id, h, hash, fmt.Sprintf("0xblock%08d", h-1), now, rand.Intn(6) + 1, "21000", true}
	txs := []TxEvent{}
	for i := 0; i < b.TxCount; i++ {
		txs = append(txs, TxEvent{"demo", s.id, fmt.Sprintf("0xtx%08d_%02d", h, i), h, hash, fmt.Sprintf("0xfrom%02d", rand.Intn(50)), fmt.Sprintf("0xto%02d", rand.Intn(50)), "", "NATIVE", fmt.Sprint(rand.Intn(2000000)), fmt.Sprint(rand.Intn(500)), "21000", "success", now})
	}
	return b, txs, nil
}
