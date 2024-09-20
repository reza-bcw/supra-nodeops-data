#!/bin/bash
SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_configs"

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config.toml | awk -F'=' '{print $2}' | tr -d ' "')

export api_key=AIzaSyD2Byf2_yWYngvHnv6Ib7V6C2EpHY3LL0E 

echo "Remove old supra onboarding script"
rm  "$(pwd)/onboarding_round_6.sh"

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi

# Stop the Docker container if it's running
echo "Stopping supra container"
if ! docker stop supra_$ip_address; then
    echo "Failed to stop supra container. Exiting..."
    exit 1
fi
echo "Supra container stopped"

# Remove the Docker container
echo "Removing supra container"
if ! docker rm supra_$ip_address; then
    echo "Failed to remove supra container. Exiting..."
    exit 1
fi
echo "Supra container removed"

# Remove the old Docker image
echo "Deleting old docker image"
if ! docker rmi asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/validator-node:v6.0.0.rc15; then
    echo "Failed to delete old Docker image. Exiting..."
    exit 1
fi
echo "Deleted the old Docker image"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

if !     docker run --name "supra_$ip_address" \
        -v $SCRIPT_EXECUTION_LOCATION:/supra/configs \
        --user "$USER_ID:$GROUP_ID" \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=400000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/validator-node:v6.0.0; then
    echo "Failed to run new Docker image. Exiting..."
    exit 1
fi
echo "New Docker image created"

wget -O "$(pwd)/onboarding_round_6.sh" https://raw.githubusercontent.com/Entropy-Foundation/supra-nodeops-data/refs/heads/master/scripts/onboarding_round_6.sh
chmod +x "$(pwd)/onboarding_round_6.sh"