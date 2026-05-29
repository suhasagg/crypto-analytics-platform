package main

import (
	"context"
	"fmt"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/ethclient"
)

type EthereumClient struct {
	url string
	ec  *ethclient.Client
}

func NewEthereumClient(url string) *EthereumClient {
	ec, _ := ethclient.Dial(url)
	return &EthereumClient{url: url, ec: ec}
}
func (e *EthereumClient) ChainID() string { return "ethereum" }
func (e *EthereumClient) LatestHeight(ctx context.Context) (int64, error) {
	if e.ec == nil {
		return 0, fmt.Errorf("ethereum rpc not configured")
	}
	h, err := e.ec.BlockNumber(ctx)
	return int64(h), err
}
func (e *EthereumClient) BlockByHeight(ctx context.Context, h int64) (BlockEvent, []TxEvent, error) {
	if e.ec == nil {
		return BlockEvent{}, nil, fmt.Errorf("ethereum rpc not configured")
	}
	b, err := e.ec.BlockByNumber(ctx, bigInt(h))
	if err != nil {
		return BlockEvent{}, nil, err
	}
	ev := BlockEvent{TenantID: "demo", ChainID: e.ChainID(), Number: int64(b.NumberU64()), Hash: b.Hash().Hex(), ParentHash: b.ParentHash().Hex(), UnixMs: int64(b.Time()) * 1000, TxCount: len(b.Transactions()), GasUsed: fmt.Sprint(b.GasUsed()), Finalized: true}
	txs := []TxEvent{}
	for _, tx := range b.Transactions() {
		from := ""
		to := ""
		if tx.To() != nil {
			to = tx.To().Hex()
		}
		txs = append(txs, TxEvent{TenantID: "demo", ChainID: e.ChainID(), Hash: tx.Hash().Hex(), BlockNumber: ev.Number, BlockHash: ev.Hash, From: from, To: to, TokenSymbol: "ETH", Value: tx.Value().String(), Fee: "0", GasUsed: fmt.Sprint(tx.Gas()), Status: "unknown", UnixMs: ev.UnixMs})
	}
	return ev, txs, nil
}
func bigInt(v int64) *big.Int { return new(big.Int).SetInt64(v) }

// Minimal HTTP-RPC placeholders; replace with typed Cosmos SDK/Solana clients for production enrichments.
type CosmosClient struct{ url string }

func NewCosmosClient(url string) *CosmosClient { return &CosmosClient{url: url} }
func (c *CosmosClient) ChainID() string        { return "cosmos" }
func (c *CosmosClient) LatestHeight(ctx context.Context) (int64, error) {
	return time.Now().Unix() / 6, nil
}
func (c *CosmosClient) BlockByHeight(ctx context.Context, h int64) (BlockEvent, []TxEvent, error) {
	now := time.Now().UTC().UnixMilli()
	hash := fmt.Sprintf("cosmos-%d", h)
	return BlockEvent{"demo", c.ChainID(), h, hash, fmt.Sprintf("cosmos-%d", h-1), now, 0, "0", true}, nil, nil
}

type SolanaClient struct{ url string }

func NewSolanaClient(url string) *SolanaClient { return &SolanaClient{url: url} }
func (s *SolanaClient) ChainID() string        { return "solana" }
func (s *SolanaClient) LatestHeight(ctx context.Context) (int64, error) {
	return time.Now().Unix() / 1, nil
}
func (s *SolanaClient) BlockByHeight(ctx context.Context, h int64) (BlockEvent, []TxEvent, error) {
	now := time.Now().UTC().UnixMilli()
	hash := fmt.Sprintf("solana-%d", h)
	return BlockEvent{"demo", s.ChainID(), h, hash, fmt.Sprintf("solana-%d", h-1), now, 0, "0", true}, nil, nil
}
