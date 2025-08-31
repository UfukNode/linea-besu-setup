#!/usr/bin/env bash

RPC_URL="${1:-http://127.0.0.1:8545}"

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

echo -e "${CYAN}>>> RPC URL:${RESET} $RPC_URL"

SYNC_STATUS=$(curl -s -X POST $RPC_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | grep -o "false")

if [[ "$SYNC_STATUS" == "false" ]]; then
  echo -e "${GREEN}- Node senkronize oldu.${RESET}"
else
  echo -e "${YELLOW}- Node senkronize oluyor...${RESET}"
fi

BLOCK_NUMBER=$(curl -s -X POST $RPC_URL \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | grep -o '"result":"0x[0-9a-f]\+"' | cut -d'"' -f4)

if [[ -n "$BLOCK_NUMBER" ]]; then
  echo -e "${GREEN}- Şu anki blok:${RESET} $((16#${BLOCK_NUMBER:2}))"
else
  echo -e "${RED}- Blok numarası alınamadı.${RESET}"
fi
