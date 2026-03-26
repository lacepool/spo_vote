# `spo_vote`

Interactive Bash script for creating, signing, and submitting a Cardano SPO governance vote with `cardano-cli`.

This repository is intended for SPO environments running Cardano infrastructure on Linux.

## Features

- prompts for a governance action `TxRef` in `txhash#index` format
- optionally uses a configured payment address
- shows spendable UTXOs in ADA for easier selection
- creates and signs the vote transaction before submission confirmation
- supports installation into standard system paths

## Requirements

The script expects these commands to be available on `PATH`:

- `gum`
- `jq`
- `cardano-cli`

It also expects access to:

- a cold verification key
- a cold signing key
- a payment signing key

You can verify command dependencies with:

```bash
./install.sh check
```

Optional helper for installing `gum`:

```bash
./scripts/install-gum.sh
```

This helper supports:

- Linux `x86_64`
- Linux `arm64`

It is only for `gum`. You still need to install `jq` and `cardano-cli` yourself.

## Installation

One-line install from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/lacepool/spo_vote/main/install.sh | bash
```

This installer:

- installs `spo_vote` to `/usr/local/bin/spo_vote`
- installs a default config to `/etc/spo_vote.conf` if one does not already exist
- creates `/var/lib/spo-vote/keys`, `/var/lib/spo-vote/tx`, and `/tmp/spo-vote`
- leaves dependency installation to you

Common local installation from a checked-out repo:

```bash
sudo ./install.sh install
```

This installs:

- executable: `/usr/local/bin/spo_vote`
- config: `/etc/spo_vote.conf`

The default config layout assumes:

- persistent data: `/var/lib/spo-vote`
- temporary files: `/tmp/spo-vote`

For staged installs or packaging:

```bash
DESTDIR=/tmp/package-root ./install.sh install
```

To remove the installed script and config:

```bash
sudo ./install.sh uninstall
```

## Configuration

Copy and adjust the example config:

```bash
sudo cp spo_vote.conf.example /etc/spo_vote.conf
sudo editor /etc/spo_vote.conf
```

The script loads config from the first available location:

1. `SPO_VOTE_CONFIG`
2. `spo_vote.conf` next to the script
3. `/etc/spo_vote.conf`

Typical config values:

- `NETWORK`
- `WORKDIR`
- `TMP_DIR`
- `KEYS_DIR`
- `TX_DIR`
- `COLD_VKEY`
- `COLD_SKEY`
- `PAYMENT_SKEY`
- `PAYMENT_ADDRESS`

Set `NETWORK` to `mainnet`, `preprod`, or `preview`.

If `PAYMENT_ADDRESS` is set, the script will not prompt for it.

You can verify the installed config exists with:

```bash
./install.sh check-config
```

## Usage

Run:

```bash
spo_vote
```

The script will:

1. ask for the governance action `TxRef` as `txhash#index`
2. use the configured payment address or prompt for one
3. ask for the vote choice: `yes`, `no`, or `abstain`
4. query UTXOs for the payment address
5. let you choose a UTXO, displayed as `ADA | txhash#index`
6. build and sign the transaction
7. show a final confirmation prompt before submission

## Notes

- the script requires an interactive TTY because it uses `gum`
- generated transaction files are written under the configured `TX_DIR`
- temporary files such as the vote file and queried UTXOs are written under the configured `TMP_DIR`
- the script performs runtime checks for required commands and key files before doing any work

## Development

Useful commands:

```bash
bash -n spo_vote.sh
bash -n install.sh
./install.sh check
DESTDIR=/tmp/package-root ./install.sh install
```
