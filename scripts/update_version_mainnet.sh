#!/bin/bash

SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_configs_mainnet"

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config_mainnet.toml | awk -F'=' '{print $2}' | tr -d ' "')

echo "Remove old supra onboarding script"
rm  "$(pwd)/onboarding_mainnet.sh"

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi
# Stop the Docker container if it's running
echo "Stopping supra container"
if ! docker stop supra_mainnet_$ip_address; then
    echo "Failed to stop supra container. Exiting..."
fi
echo "Supra container stopped"

# Remove the Docker container
echo "Removing supra container"
if ! docker rm supra_mainnet_$ip_address; then
    echo "Failed to remove supra container. Exiting..."
fi
echo "Supra container removed"

# Remove the old Docker image
echo "Deleting old docker images"
if ! docker rmi asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/validator-node:v6.4.0.rc2; then
    echo "Failed to delete old Docker image. Exiting..."
fi
echo "Deleted the old Docker images"

# Check if smr_settings.toml exists before creating a new one
echo "Changing the smr settings file"
smr_settings_file="$SCRIPT_EXECUTION_LOCATION/smr_settings.toml"
rm ${smr_settings_file}
if [ -f "${smr_settings_file}" ]; then
    echo "smr_settings.toml already exists. Skipping creation."
else
    # Create smr_settings.toml
    echo "Creating smr_settings.toml"
    cat <<EOF > "${smr_settings_file}"
####################################### PROTOCOL PARAMETERS #######################################

# The below parameters are fixed for the protocol and must be agreed upon by all node operators
# at genesis. They may subsequently be updated via governance decisions. Paths are set relative
# to SUPRA_HOME.

# Core protocol parameters.
[instance]
# A unique identifier for this instance of the Supra protocol. Prevents replay attacks across chains.
chain_id = 7
# The length of an epoch in seconds.
epoch_duration_secs = 7200
# The number of seconds that stake locked in a Stake Pool will automatically be locked up for when
# its current lockup expires, if no request is made to unlock it.
recurring_lockup_duration_secs = 14400
# This parameter no longer has any effect.
voting_duration_secs = 7200
# Determines whether the network will start with a faucet, amongst other things.
is_testnet = false
# Thursday, Oct 10, 2024 12:00:00.000 AM (UTC)
genesis_timestamp_microseconds = 1728518400000000

# Parameters related to the mempool.
[mempool]
# The maximum number of milliseconds that a node will wait before proposing a batch when it has
# at least one transaction to process.
max_batch_delay_ms = 500
# The maximum size of a batch. If max_batch_size_bytes is reached before max_batch_delay_ms
# then a batch will be proposed immediately.
max_batch_size_bytes = 5000000
# The amount of time that a node will wait before repeating a sync request for a batch that it
# is missing.
sync_retry_delay_ms = 2000
# The number of signers of the related batch certificate that a node should ask for a batch
# attempting to retry a sync request.
sync_retry_nodes = 3

# Parameters related to the Moonshot consensus protocol. See https:#arxiv.org/abs/2401.01791.
[moonshot]
# The maximum number of milliseconds that the timestamp of a proposed block may be
# ahead of a node's local time when it attempts to vote for the block. Validators
# must wait until the timestamp of a certified block has passed before advancing to
# the next round and leaders must wait until the timestamp of the parent block has
# passed before proposing, so this limit prevents Byzantine leaders from forcing
# honest nodes to wait indefinitely by proposing blocks with timestamps that are
# arbitrarily far in the future.
block_recency_bound_ms = 500
# Causes the node to stop producing blocks when there are no transactions to be
# processed. If all nodes set this value to true then the chain will not produce
# new blocks when there are no transactions to process, conserving disk space.
halt_block_production_when_no_txs = false
# The type of leader election function to use. This function generates a schedule that ensures
# that every node eventually succeeds every other.
leader_elector = "FairSuccession"
# The delay after which the block proposer will create a new block despite not having any
# payload items to propose. Denominated in ms.
max_block_delay_ms = 2500
# The maximum number of batch availability certificates that may be included in a single
# consensus block.
max_payload_items_per_block = 50
# The number of rounds ahead of self.round for which this node should accept
# Optimistic Proposals, Votes and Timeouts. Must be the same for all nodes.
message_recency_bound_rounds = 20
# The delay after which the node will try to repeat sync requests for missing blocks.
# Denominated in ms. Should be the same for all nodes.
sync_retry_delay_ms = 1000
# The delay after which the node will send a Timeout message for its current Moonshot round,
# measured from the start of the round. Denominated in ms. Must be the same for all nodes.
timeout_delay_ms = 5000

# Parameters related to the MoveVM. Primarily related to governance features.
[move_vm]
# Initially false until the network matures.
allow_new_validators = false
# The maximum stake that may be allocated to a Supra Validator. We are not currently doing
# stake-weighted voting, so this value does not impact our decentralization quotient. This
# may change in the future. Initially set to 100_000_000_000 SUPRA; i.e., the total supply.
# Measured in Quants (1 Quant = 10^-8 SUPRA).
max_stake = 10000000000000000000
# The minimum stake required to run a Supra Validator. 55_000_000 SUPRA.
# Measured in Quants (1 Quant = 10^-8 SUPRA).
min_stake = 5500000000000000
# The number of tokens initially allocated to node operators. Tokens will be earned through block
# rewards.
operator_account_balance = 0
# The time at which all accounts with allocations at genesis will be able to unlock their initial
# amounts.
#
# Monday, Oct 28, 2024 12:00:00.000 AM (UTC)
remaining_balance_lockup_cliff_period_in_seconds = 1555200000000
# The amount of SUPRA required to qualify as a proposer (this parameter is currently unused).
required_proposer_stake = 0
# The annual percent yield for validators, proportional to their stake. Specified as a percentage
# with 2 decimals of precision in u64 format due to limitations in the MoveVM. The below value
# represents 12.85%.
rewards_apy_percentage = 1285
# The percentage of staking rewards earned by Supra Foundation controlled nodes that will be paid
# to the corresponding node operators. Specified as a percentage with 2 decimals of precision in
# u64 format due to limitations in the MoveVM. The below value represents 37.74%.
validator_commission_rate_percentage = 3774
# The percentage of new stake relative to the current total stake that can join the validator
# set in a single epoch. This is not relevant until allow_new_validators is set to true.
voting_power_increase_limit = 33


######################################### NODE PARAMETERS #########################################

# The below parameters are node-specific and may be configured as required by the operator. Paths
# are set relative to SUPRA_HOME.

[node]
# The duration in seconds that a node waits between polling its connections to its peers.
connection_refresh_timeout_sec = 1
# If true, all components will attempt to load their previous state from disk. Otherwise,
# all components will start in their default state. Should always be `true` for testnet and
# mainnet.
resume = true
# The path to the TLS root certificate authority certificate.
root_ca_cert_path = "configs/ca_certificate.pem"
# The port on which to listen for connections from the associated RPC node. Each validator
# may serve at most one RPC node.
rpc_access_port = 29000
# The path to the TLS certificate for this node.
server_cert_path = "configs/server_supra_certificate.pem"
# The path to the private key to be used when negotiating TLS connections.
server_private_key_path = "configs/server_supra_key.pem"

# Parameters for the blockchain database.
[node.database_setup.dbs.chain_store.rocks_db]
# The path at which the database should be created.
path = "configs/smr_storage"
# Whether the database should be pruned. If true, data that is more than epochs_to_retain
# old will be deleted.
enable_pruning = true

# Parameters for the DKG database.
[node.database_setup.dbs.ledger.rocks_db]
# The path at which the database should be created.
path = "configs/ledger_storage"

# Parameters related to database pruning.
[node.database_setup.prune_config]
# Data stored more than epochs_to_retain ago will be pruned if enable_pruning = true.
epochs_to_retain = 84
EOF
    echo "smr_settings.toml created"
fi

# Run the Docker container
echo "Running new docker image"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

if !     docker run --name "supra_mainnet_$ip_address" \
        -v $SCRIPT_EXECUTION_LOCATION:/supra/configs \
        --user "$USER_ID:$GROUP_ID" \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=4000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd asia-docker.pkg.dev/supra-devnet-misc/supra-mainnet/validator-node:v7.1.0; then
    echo "Failed to run new Docker image. Exiting..."
    exit 1
fi
echo "New Docker image created"

# Update hash in hashmap_phase_1_previous.toml
new_sha=$(sha256sum $SCRIPT_EXECUTION_LOCATION/smr_settings.toml | awk '{print $1}')
if ! sed -i.bak "s|\(smr_settings.toml\s*=\s*\).*|\1\"$new_sha\"|" "$SCRIPT_EXECUTION_LOCATION/hashmap_phase_1_previous.toml"; then
    echo "Failed to update hashmap_phase_1_previous.toml. Exiting..."
    exit 1
fi
echo "Updated smr_settings.toml hash"

wget -O $SCRIPT_EXECUTION_LOCATION/ca_certificate.pem https://gist.githubusercontent.com/sjadiya-supra/a25596f90a24ff5c4e2b3ebe9cfb57df/raw/5910a4322c90fd9f13ca804c316fcda7221d94ac/ca_certificate.pem
wget -O $SCRIPT_EXECUTION_LOCATION/server_supra_certificate.pem https://gist.githubusercontent.com/sjadiya-supra/f39dda12625b7155e4dbf3c8f6bdc891/raw/6b4bdcf8ccd5e348f5f2988ad757199ed88b6197/server_supra_certificate.pem
wget -O $SCRIPT_EXECUTION_LOCATION/server_supra_key.pem https://gist.githubusercontent.com/sjadiya-supra/e05d37d0cb9e72f806dc965d168c8c41/raw/a5e51ec29ec04f6a7d9e03e0fe08b64fbdfdbb03/server_supra_key.pem
wget -O $SCRIPT_EXECUTION_LOCATION/genesis_configs.json https://testnet-snapshot.supra.com/configs/genesis_configs.json
wget -O "$(pwd)/onboarding_mainnet.sh" https://raw.githubusercontent.com/Entropy-Foundation/supra-nodeops-data/refs/heads/master/scripts/onboarding_mainnet.sh
chmod +x "$(pwd)/onboarding_mainnet.sh"