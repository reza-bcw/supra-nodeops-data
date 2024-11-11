#!/bin/bash

SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_configs"
CONFIG_FILE="$(pwd)/operator_config.toml"

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config.toml | awk -F'=' '{print $2}' | tr -d ' "')

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi

# Stop the Docker container if it's running
echo "Stopping supra container"
if ! docker stop supra_$ip_address; then
    echo "Failed to stop supra container. Exiting..."
fi
echo "Supra container stopped"

# Remove the Docker container
echo "Removing supra container"
if ! docker rm supra_rpc_$ip_address; then
    echo "Failed to remove supra container. Exiting..."
fi
echo "supra container removed"


# Remove the old Docker image
echo "Deleting old docker images"
if ! docker rmi asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/validator-node:v6.3.0; then
    echo "Failed to delete old Docker image. Exiting..."
fi
echo "Deleted the old Docker images"

# Run the Docker container
echo "Running new docker image"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

if !  docker run --name "supra_$ip" \
    -v ./supra_configs:/supra/configs \
    --user "$USER_ID:$GROUP_ID" \
    -e "SUPRA_HOME=/supra/configs" \
    -e "SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
    -e "SUPRA_MAX_LOG_FILE_SIZE=400000000" \
    -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
    -e "SUPRA_MAX_LOG_FILES=20" \
    --net=host \
    -itd "asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/validator-node:v6.3.9"; then
    echo "Failed to run new Docker image. Exiting..."
    exit 1
fi
echo "New Docker image created"

#setup Rclone
curl https://rclone.org/install.sh | sudo bash
mkdir -p ~/.config/rclone/
touch ~/.config/rclone/rclone.conf
cat <<EOF > ~/.config/rclone/rclone.conf
[cloudflare-r2]
type = s3
provider = Cloudflare
access_key_id = 229502d7eedd0007640348c057869c90
secret_access_key = 799d15f4fd23c57cd0f182f2ab85a19d885887d745e2391975bb27853e2db949
region = auto
endpoint = https://4ecc77f16aaa2e53317a19267e3034a4.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
EOF


# Set the maximum number of retries
MAX_RETRIES=5
RETRY_DELAY=10  # Delay in seconds before retrying
retry_count=0

# Loop to retry the command if it fails
while [ $retry_count -lt $MAX_RETRIES ]; do
    # Run the rclone command
    rclone sync cloudflare-r2:testnet-snapshot/snapshots/store $SCRIPT_EXECUTION_LOCATION/smr_storage/ --progress

    # Check if the command was successful
    if [ $? -eq 0 ]; then
        echo "rclone command succeeded."
        exit 0
    else
        # Command failed
        echo "rclone command failed. Attempt $((retry_count + 1))/$MAX_RETRIES."
        retry_count=$((retry_count + 1))
        
        # Wait before retrying
        sleep $RETRY_DELAY
    fi
done

function parse_toml() {
    grep -w "$1" "$2" | cut -d'=' -f2- | tr -d ' "'
}


encoded_pswd=$(parse_toml "password" "$CONFIG_FILE")
password=$(echo "$encoded_pswd" | openssl base64 -d -A)

expect << EOF
    spawn docker exec -it supra_$ip_address /supra/supra node smr run
    expect "password:" { send "$password\r" }
    expect eof
EOF
