#!/bin/bash

SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_rpc_configs"

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_rpc_config.toml | awk -F'=' '{print $2}' | tr -d ' "')

echo "Remove old rpc onboarding script"
rm  "$(pwd)/rpc_onboarding_round_6.sh"

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi
# Stop the Docker container if it's running
echo "Stopping rpc container"
if ! docker stop supra_rpc_$ip_address; then
    echo "Failed to stop rpc container. Exiting..."
fi
echo "Supra container stopped"

# Remove the Docker container
echo "Removing rpc container"
if ! docker rm supra_rpc_$ip_address; then
    echo "Failed to remove rpc container. Exiting..."
fi
echo "rpc container removed"

rm -rf $SCRIPT_EXECUTION_LOCATION/rpc_archive/* $SCRIPT_EXECUTION_LOCATION/rpc_ledger/*  $SCRIPT_EXECUTION_LOCATION/rpc_store/* $SCRIPT_EXECUTION_LOCATION/rpc_node_logs $SCRIPT_EXECUTION_LOCATION/latest_snapshot.zip $SCRIPT_EXECUTION_LOCATION/snapshot/*

# Remove the old Docker image
echo "Deleting old docker images"
if ! docker rmi asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/rpc-node:v6.0.0; then
    echo "Failed to delete old Docker image. Exiting..."
fi
echo "Deleted the old Docker images"

# Run the Docker container
echo "Running new docker image"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

if !     docker run --name "supra_rpc_$ip_address" \
        -v $SCRIPT_EXECUTION_LOCATION:/supra/configs \
        --user "$USER_ID:$GROUP_ID" \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/rpc_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=4000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/rpc-node:v6.3.0; then
    echo "Failed to run new Docker image. Exiting..."
    exit 1
fi
echo "New Docker image created"
rm -rf $SCRIPT_EXECUTION_LOCATION/genesis.blob

wget -O "$(pwd)/rpc_onboarding_round_6.sh" https://raw.githubusercontent.com/Entropy-Foundation/supra-nodeops-data/refs/heads/master/scripts/rpc_onboarding_round_6.sh
chmod +x "$(pwd)/rpc_onboarding_round_6.sh"