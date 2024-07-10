#!/bin/bash

if ! command -v unzip &> /dev/null; then
    if [ -f /etc/apt/sources.list ]; then
      package_manager="sudo apt install"
      $package_manager -y unzip
    elif [ -f /etc/yum.repos.d/ ]; then
      package_manager="sudo yum install"
      $package_manager -y unzip
    else
     echo "**WARNING: Could not identify package manager. Please install unzip manually."
     exit 1
    fi
else
    echo ""
fi 

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
docker rmi asia-docker.pkg.dev/supra-devnet-misc/smr-moonshot-devnet/validator-node:v4.1.3
echo
echo "Deleted the old docker image"

# Run the Docker container with the updated configuration
echo
echo "Running new docker image"

    docker run --name "supra_$ip_address" \
        -v ./supra_configs:/supra/configs \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=4000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd  asia-docker.pkg.dev/supra-devnet-misc/smr-moonshot-devnet/validator-node:v4.1.4
echo
echo "New docker Container with image is created"

# Clean old database
sudo rm -rf ./supra_configs/ledger_storage ./supra_configs/smr_storage/* ./supra_configs/supra_node_logs ./supra_configs/latest_snapshot.zip ./supra_configs/snapshot

# Download snapshot 
echo "Downloading the latest snapshot......"
wget -O ./supra_configs/latest_snapshot.zip https://testnet-snapshot.supra.com/snapshots/latest_snapshot.zip

# Unzip snapshot 
unzip ./supra_configs/latest_snapshot.zip -d ./supra_configs/

# Copy snapshot into smr_database
sudo cp ./supra_configs/snapshot/snapshot_*/* ./supra_configs/smr_storage/

# Start validator node
enc_password=$(grep '^password' operator_config.toml | awk -F' = ' '{print $2}' | tr -d '"')
decoded_password=$(echo "$enc_password" | openssl base64 -d -A)
if docker ps --filter "name=supra_$ip_address" --format '{{.Names}}' | grep -q supra_$ip_address; then
        expect << EOF
        spawn docker exec -it supra_$ip_address /supra/supra node smr run
        expect "password:" { send "$decoded_password\r" }
        expect eof
EOF
else
    echo "Your container supra_$ip_address is not running."
fi