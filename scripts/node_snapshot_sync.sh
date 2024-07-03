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

# Clean old database
rm -rf ./supra_configs/ledger_storage ./supra_configs/smr_storage/* ./supra_configs/supra_node_logs

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

# Download snapshot 
echo "Downloading the latest snapshot......"
wget -O ./supra_configs/latest_snapshot.zip https://testnet-snapshot.supra.com/snapshots%2Flatest_snapshot.zip

# Unzip snapshot 
unzip ./supra_configs/latest_snapshot.zip -d ./supra_configs/

# Copy snapshot into smr_database
cp ./supra_configs/snapshot/snapshot_*/* ./supra_configs/smr_storage/

# Start container 
echo "Start supra container"
docker start supra_$ip_address
echo 
echo "Supra container started"

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