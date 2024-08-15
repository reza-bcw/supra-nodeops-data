#!/bin/bash

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config.toml | awk -F'=' '{print $2}' | tr -d ' "')

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi

# Stop the Docker container if it's already running
echo "Stopping supra container"
docker stop supra_$ip_address
echo 
echo "Supra container stopped"


# Remove the Docker container if it exists
echo
echo "Removing supra container"
docker rm supra_$ip_address
echo
echo "Supra container removed"

# Remove the old Docker image
echo
echo "Deleting old docker image"
docker rmi asia-docker.pkg.dev/supra-devnet-misc/smr-moonshot-devnet/validator-node:v5.0.0.rc3
echo
echo "Deleted the old docker image"

# Update the configuration in smr_settings.toml
echo
echo "Changing the smr settings file"

    echo ""
    echo "CREATE SMR SETTINGS TOML FILE "
    echo ""
    sudo rm -rf /home/lenovo/nodeops/nodeop-onboarding-script/latest_onboarding_script/smr_settings.toml

    smr_settings_file="/home/lenovo/nodeops/nodeop-onboarding-script/latest_onboarding_script/smr_settings.toml"

    if [ -f "${smr_settings_file}" ]; then
        echo "smr_settings.toml already exists at ${path_passed}. Skipping creation."
        return 0
    fi

    # Create smr_settings.toml content
    cat <<EOF > "${smr_settings_file}"
[instance]
chain_id = 6
epoch_duration_secs = 7200
is_testnet = true
genesis_timestamp_microseconds = 1723660200000000

[mempool]
max_batch_delay_ms = 500
max_batch_size_bytes = 500000
sync_retry_delay_ms = 5000
sync_retry_nodes = 3

[moonshot]
block_recency_bound_ms = 500
halt_block_production_when_no_txs = false
leader_elector = "FairSuccession"
max_block_delay_ms = 2500
max_payload_items_per_block = 100
message_recency_bound_rounds = 10
sync_retry_delay_ms = 2500
timeout_delay_ms = 5000

[node]
connection_refresh_timeout_sec = 20
ledger_storage = "configs/ledger_storage"
epochs_to_retain = 84
resume = true
root_ca_cert_path = "configs/ca_certificate.pem"
rpc_access_port = 26000
server_cert_path = "configs/server_supra_certificate.pem"
server_private_key_path = "configs/server_supra_key.pem"
smr_storage = "configs/smr_storage"
EOF

echo "Changed the smr settings file"


# Run the Docker container with the updated configuration
echo
echo "Running new docker image"

docker run --name supra_$ip_address \
    -v ./supra_configs:/supra/configs \
    -e="SUPRA_HOME=/supra/configs" \
    -e="SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
    -e="SUPRA_MAX_LOG_FILE_SIZE=4000000" \
    -e="SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
    -e="SUPRA_MAX_LOG_FILES=20" \
    --net=host -itd asia-docker.pkg.dev/supra-devnet-misc/smr-moonshot-devnet/validator-node:v5.0.0
echo
echo "New docker image is created"


new_sha=$(sha256sum ./supra_configs/smr_settings.toml | awk '{print $1}')
echo "$new_sha"
sed -i.bak "s|\(smr_settings.toml\s*=\s*\).*|\1\"$new_sha\"|" "./supra_configs/hashmap_phase_1_previous.toml"