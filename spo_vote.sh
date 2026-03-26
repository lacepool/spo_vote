#!/usr/bin/env bash

set -euo pipefail

############################################
# CONFIG
############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SPO_VOTE_CONFIG:-}"

if [ -z "$CONFIG_FILE" ]; then
  for candidate in \
    "$SCRIPT_DIR/spo_vote.conf" \
    "/etc/spo_vote.conf"
  do
    if [ -f "$candidate" ]; then
      CONFIG_FILE="$candidate"
      break
    fi
  done
fi

if [ -z "$CONFIG_FILE" ]; then
  echo "Error: No config file found."
  echo "Set SPO_VOTE_CONFIG or create spo_vote.conf next to the script or at /etc/spo_vote.conf."
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

: "${NETWORK:=mainnet}"
: "${WORKDIR:=/var/lib/spo-vote}"
: "${TMP_DIR:=/tmp/spo-vote}"
: "${KEYS_DIR:=$WORKDIR/keys}"
: "${TX_DIR:=$WORKDIR/tx}"
: "${COLD_VKEY:=$KEYS_DIR/node.vkey}"
: "${COLD_SKEY:=$KEYS_DIR/node.skey}"
: "${PAYMENT_SKEY:=$KEYS_DIR/payment.skey}"

case "$NETWORK" in
  mainnet|preprod|preview)
    NETWORK_FLAG="--$NETWORK"
    ;;
  *)
    echo "Error: Unsupported NETWORK value '$NETWORK'. Use mainnet, preprod, or preview."
    exit 1
    ;;
esac

mkdir -p "$TX_DIR" "$TMP_DIR"

############################################
# Ensure TTY (gum requires it)
############################################

if [ ! -t 0 ]; then
  echo "Error: gum requires an interactive TTY. Run container with -it."
  exit 1
fi

############################################
# Dependency Checks
############################################

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: Required dependency '$1' not found in PATH."
    exit 1
  fi
}

require_command gum
require_command jq
require_command cardano-cli

for required_file in "$COLD_VKEY" "$COLD_SKEY" "$PAYMENT_SKEY"; do
  if [ ! -f "$required_file" ]; then
    echo "Error: Required file not found: $required_file"
    exit 1
  fi
done

############################################
# Gather Governance Action Information
############################################

gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "🗳  SPO Governance Action Vote"
echo

gov_action_tx_ref=$(gum input \
  --placeholder "Governance Action TxRef (txhash#index)" \
  --prompt "TxRef: ")

if [[ ! "$gov_action_tx_ref" =~ ^([[:xdigit:]]+)#([0-9]+)$ ]]; then
  gum style --foreground 1 "Invalid TxRef. Expected format: txhash#index"
  exit 1
fi

gov_action_tx="${BASH_REMATCH[1]}"
gov_action_index="${BASH_REMATCH[2]}"

if [ -n "${PAYMENT_ADDRESS:-}" ]; then
  payment_addr="$PAYMENT_ADDRESS"
else
  payment_addr=$(gum input \
    --placeholder "Payment address (addr1...)" \
    --prompt "Payment Address: ")
fi

vote_choice=$(gum choose "yes" "no" "abstain" \
  --header "Select your vote")

############################################
# Map Vote Choice to CLI Flag
############################################

case "$vote_choice" in
  yes) vote_flag="--yes" ;;
  no) vote_flag="--no" ;;
  abstain) vote_flag="--abstain" ;;
  *) echo "Invalid vote option"; exit 1 ;;
esac

vote_file_name="${gov_action_tx}_${gov_action_index}_${vote_choice}_vote"
vote_file_path="${TMP_DIR}/${vote_file_name}"

############################################
# Create Vote File
############################################

gum spin --spinner dot --title "Creating vote file..." -- \
cardano-cli conway governance vote create \
  "$vote_flag" \
  --governance-action-tx-id "$gov_action_tx" \
  --governance-action-index "$gov_action_index" \
  --cold-verification-key-file "$COLD_VKEY" \
  --out-file "$vote_file_path"

############################################
# Query UTXOs
############################################

gum spin --spinner dot --title "Querying UTXOs..." -- \
cardano-cli conway query utxo \
  --address "$payment_addr" \
  "$NETWORK_FLAG" \
  --out-file "$TMP_DIR/utxos.json"

utxo_list=$(jq -r '
  to_entries[] |
  ((.value.value.lovelace / 1000000) | tostring) + " ADA | " + .key
' "$TMP_DIR/utxos.json")

if [ -z "$utxo_list" ]; then
  gum style --foreground 1 "No UTXOs found."
  exit 1
fi

selected_utxo=$(echo "$utxo_list" | gum choose --header "Select UTXO")
tx_in=$(echo "$selected_utxo" | cut -d'|' -f2 | xargs)

############################################
# Build Transaction
############################################

raw_tx_file="${TX_DIR}/${vote_file_name}.raw"
signed_tx_file="${TX_DIR}/${vote_file_name}.signed"

gum spin --spinner dot --title "Building transaction..." -- \
cardano-cli conway transaction build \
  "$NETWORK_FLAG" \
  --tx-in "$tx_in" \
  --change-address "$payment_addr" \
  --vote-file "$vote_file_path" \
  --witness-override 2 \
  --out-file "$raw_tx_file"

############################################
# Sign Transaction
############################################

gum spin --spinner dot --title "Signing transaction..." -- \
cardano-cli conway transaction sign \
  --tx-body-file "$raw_tx_file" \
  --signing-key-file "$COLD_SKEY" \
  --signing-key-file "$PAYMENT_SKEY" \
  --out-file "$signed_tx_file"

############################################
# Confirm + Submit
############################################

gum style --bold "Review Vote Details"
echo
echo "TxRef:         $gov_action_tx_ref"
echo "Vote:          $vote_choice"
echo "Payment Addr:  $payment_addr"
echo "UTXO:          $tx_in"
echo

if gum confirm "Submit vote to $NETWORK?"; then
  gum spin --spinner dot --title "Submitting transaction..." -- \
  cardano-cli conway transaction submit \
    --tx-file "$signed_tx_file" \
    "$NETWORK_FLAG"

  gum style --bold --foreground 10 "✅ Vote submitted"
else
  gum style --foreground 3 "Submission cancelled."
fi
