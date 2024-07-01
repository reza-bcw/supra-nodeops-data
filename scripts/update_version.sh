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
docker rmi asia-docker.pkg.dev/supra-devnet-misc/smr-moonshot-devnet/validator-node:v4.0.0
echo
echo "Deleted the old docker image"

# Update the configuration in smr_settings.toml
echo
echo "Changing the smr settings file"

sed -i.bak "s/\("halt_block_production_when_no_txs"\s*=\s*\).*/\1false/" "./supra_configs/smr_settings.toml"

sed -i.bak "s/\("prune_block_max_time_ms"\s*=\s*\).*/\1172800000/" "./supra_configs/smr_settings.toml"

sed -i.bak "s/\("max_block_delay_ms"\s*=\s*\).*/\12500/" "./supra_configs/smr_settings.toml"

sed -i.bak "s/\("epoch_duration_secs"\s*=\s*\).*/\17200/" "./supra_configs/smr_settings.toml"
echo

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
    --net=host -itd asia-docker.pkg.dev/supra-devnet-misc/smr-moonshot-devnet/validator-node:v4.0.2
echo
echo "New docker image is created"


new_sha=$(sha256sum ./supra_configs/smr_settings.toml | awk '{print $1}')
echo "$new_sha"
sed -i.bak "s|\(smr_settings.toml\s*=\s*\).*|\1\"$new_sha\"|" "./supra_configs/hashmap_phase_1_previous.toml"
