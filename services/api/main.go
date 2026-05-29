package main

import (
	"bytes"
	"context"
	"encoding/json"
	elasticsearch "github.com/elastic/go-elasticsearch/v8"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
	"net/http"
	"os"
	"time"
)

func env(k, f string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return f
}

type deps struct {
	pg  *pgxpool.Pool
	es  *elasticsearch.Client
	rdb *redis.Client
	ctx context.Context
}

func main() {
	ctx := context.Background()
	pg, _ := pgxpool.New(ctx, env("PG_DSN", "postgres://postgres:postgres@localhost:5432/crypto_analytics?sslmode=disable"))
	es, _ := elasticsearch.NewClient(elasticsearch.Config{Addresses: []string{env("ES_URL", "http://localhost:9200")}})
	rdb := redis.NewClient(&redis.Options{Addr: env("REDIS_ADDR", "localhost:6379")})
	d := deps{pg, es, rdb, ctx}
	r := gin.Default()
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))
	r.GET("/health", func(c *gin.Context) { c.JSON(200, gin.H{"status": "UP"}) })
	v1 := r.Group("/v1", d.auth())
	v1.GET("/chains/:chain/blocks/latest", d.latestBlocks)
	v1.GET("/chains/:chain/address/:addr/txs", d.addressTxs)
	v1.GET("/search/transactions", d.searchTx)
	v1.GET("/analytics/top-tokens", d.mv("mv_top_tokens", "volume DESC"))
	v1.GET("/analytics/active-addresses", d.mv("mv_active_addresses", "activity_count DESC"))
	v1.GET("/analytics/whale-movements", d.mv("mv_whale_movements", "tx_time DESC"))
	v1.GET("/analytics/gas", d.mv("mv_gas_analytics", "bucket DESC"))
	v1.POST("/admin/materialized-views/refresh", d.refreshViews)
	r.Run(":8080")
}
func (d deps) auth() gin.HandlerFunc {
	return func(c *gin.Context) {
		key := c.GetHeader("X-API-Key")
		tenant := c.GetHeader("X-Tenant-ID")
		if tenant == "" {
			tenant = "demo"
		}
		var dbTenant, role string
		err := d.pg.QueryRow(c, `SELECT tenant_id,role FROM api_keys WHERE key_hash=$1`, key).Scan(&dbTenant, &role)
		if err != nil || dbTenant != tenant {
			c.AbortWithStatusJSON(401, gin.H{"error": "invalid api key or tenant"})
			return
		}
		c.Set("tenant_id", tenant)
		c.Set("role", role)
		c.Next()
	}
}
func tenant(c *gin.Context) string {
	v, _ := c.Get("tenant_id")
	if s, ok := v.(string); ok && s != "" {
		return s
	}
	return "demo"
}
func (d deps) latestBlocks(c *gin.Context) {
	chain := c.Param("chain")
	key := "latest_blocks:" + tenant(c) + ":" + chain
	if v, _ := d.rdb.Get(d.ctx, key).Result(); v != "" {
		c.Data(200, "application/json", []byte(v))
		return
	}
	rows, _ := d.pg.Query(c, `SELECT block_number,block_hash,block_time,tx_count,gas_used FROM blocks WHERE tenant_id=$1 AND chain_id=$2 AND canonical=true ORDER BY block_number DESC LIMIT 20`, tenant(c), chain)
	defer rows.Close()
	out := []gin.H{}
	for rows.Next() {
		var n int64
		var gas string
		var h string
		var tm time.Time
		var txc int
		rows.Scan(&n, &h, &tm, &txc, &gas)
		out = append(out, gin.H{"number": n, "hash": h, "time": tm, "tx_count": txc, "gas_used": gas})
	}
	b, _ := json.Marshal(out)
	d.rdb.Set(d.ctx, key, b, 30*time.Second)
	c.Data(200, "application/json", b)
}
func (d deps) addressTxs(c *gin.Context) {
	chain := c.Param("chain")
	addr := c.Param("addr")
	key := "address:" + tenant(c) + ":" + chain + ":" + addr
	if v, _ := d.rdb.Get(d.ctx, key).Result(); v != "" {
		c.Data(200, "application/json", []byte(v))
		return
	}
	rows, _ := d.pg.Query(c, `SELECT tx_hash,block_number,block_hash,from_address,to_address,value,fee,status,tx_time FROM transactions WHERE tenant_id=$1 AND chain_id=$2 AND (from_address=$3 OR to_address=$3) ORDER BY tx_time DESC LIMIT 50`, tenant(c), chain, addr)
	defer rows.Close()
	out := []gin.H{}
	for rows.Next() {
		var h, bh, from, to, status, value, fee string
		var bnum int64
		var tm time.Time
		rows.Scan(&h, &bnum, &bh, &from, &to, &value, &fee, &status, &tm)
		out = append(out, gin.H{"hash": h, "block_number": bnum, "block_hash": bh, "from": from, "to": to, "value": value, "fee": fee, "status": status, "time": tm})
	}
	b, _ := json.Marshal(out)
	d.rdb.Set(d.ctx, key, b, 30*time.Second)
	c.Data(200, "application/json", b)
}
func (d deps) searchTx(c *gin.Context) {
	q := c.Query("q")
	body := map[string]any{"query": map[string]any{"multi_match": map[string]any{"query": q, "fields": []string{"Hash", "From", "To", "TokenSymbol", "ChainID"}}}}
	b, _ := json.Marshal(body)
	res, err := d.es.Search(d.es.Search.WithIndex("transactions"), d.es.Search.WithBody(bytes.NewReader(b)))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer res.Body.Close()
	var m map[string]any
	json.NewDecoder(res.Body).Decode(&m)
	c.JSON(200, m)
}
func (d deps) mv(name, order string) gin.HandlerFunc {
	return func(c *gin.Context) {
		chain := c.Query("chain")
		if chain == "" {
			chain = "ethereum"
		}
		rows, err := d.pg.Query(c, `SELECT row_to_json(x) FROM (SELECT * FROM `+name+` WHERE tenant_id=$1 AND chain_id=$2 ORDER BY `+order+` LIMIT 50) x`, tenant(c), chain)
		if err != nil {
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()
		out := []json.RawMessage{}
		for rows.Next() {
			var raw []byte
			rows.Scan(&raw)
			out = append(out, raw)
		}
		c.JSON(200, out)
	}
}
func (d deps) refreshViews(c *gin.Context) {
	role, _ := c.Get("role")
	if role != "admin" {
		c.JSON(403, gin.H{"error": "admin role required"})
		return
	}
	for _, v := range []string{"mv_top_tokens", "mv_active_addresses", "mv_whale_movements", "mv_gas_analytics"} {
		_, _ = d.pg.Exec(c, "REFRESH MATERIALIZED VIEW "+v)
	}
	c.JSON(200, gin.H{"status": "refreshed"})
}
