#!/bin/bash

# Prompt for IP_ADDRESS
read -p "Enter the RPC IP address: " IP_ADDRESS
echo ""

# Define container name
CONTAINER_NAME="supra_rpc_$IP_ADDRESS"

# Function to check if the Docker container is running
is_container_running() {
    docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"
}

# Function to start the Docker container
start_container() {
    echo "Starting Docker container: $CONTAINER_NAME"
    echo ""
    docker start $CONTAINER_NAME
}

# Check if the Docker container is running
if is_container_running; then
    echo "Docker container $CONTAINER_NAME is already running, please stop your container and wait for at least 6 hours then please run this script again."
    exit 1
else
    echo "Docker container $CONTAINER_NAME is not running."
    start_container
    echo ""
fi

# Remove old configuration files and directories
echo "Removing old configuration files..."
sudo rm -rf ./supra_configs/rpc_archive \
            ./supra_configs/rpc_ledger \
            ./supra_configs/snapshot \
            ./supra_configs/rpc_store/* \
            ./supra_configs/rpc_node_logs \
            ./supra_configs/latest_snapshot.zip

# Download the latest snapshot
echo ""
echo "Downloading the latest snapshot..."
wget -O ./supra_configs/latest_snapshot.zip https://testnet-snapshot.supra.com/snapshots/latest_snapshot.zip

# Unzip the latest snapshot
echo ""
echo "Unzipping the latest snapshot..."
unzip ./supra_configs/latest_snapshot.zip -d ./supra_configs/

# Copy snapshot files to rpc_store
echo ""
echo "Copying snapshot files to rpc_store..."
cp -r ./supra_configs/snapshot/snapshot_*/* ./supra_configs/rpc_store/

# Start the rpc_node inside the Docker container
echo ""
echo "Starting the rpc_node inside the Docker container..."
docker exec -itd $CONTAINER_NAME /supra/rpc_node 

echo "Script execution completed and RPC node is started."
