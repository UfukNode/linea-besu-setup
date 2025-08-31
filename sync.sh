#!/usr/bin/env bash

RPC_URL="${1:-http://127.0.0.1:8545}"

echo ">>> RPC URL: $RPC_URL"

SYNC_STATUS=$(curl -s -X POST $RPC_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')

if [[ "$SYNC_STATUS" == *"false"* ]]; then
  echo "✅ Node senkronize oldu."
else
  echo "⏳ Node senkronize oluyor..."
  echo "$SYNC_STATUS" | jq .
fi

BLOCK_NUMBER=$(curl -s -X POST $RPC_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r .result)

if [[ -n "$BLOCK_NUMBER" ]]; then
  echo "- Şu anki blok: $((16#${BLOCK_NUMBER:2}))"
else
  echo "- Blok numarası alınamadı."
fi
