#!/bin/bash

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config.toml | awk -F'=' '{print $2}' | tr -d ' "')

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi

container_id="supra_${ip_address}"

# Stop the Docker container if it's running
echo "Stopping supra container $container_id if running"
if docker ps | grep "$container_id" > /dev/null; then
  if ! docker stop "$container_id"; then
      echo "Failed to stop supra container."
  fi
  echo "Supra container stopped"
else
  echo "Supra container is not running."
fi

# Remove the Docker container
echo "Removing supra container"
if ! docker rm "$container_id"; then
    echo "Failed to remove supra container."
fi
echo "Supra container removed"

# Remove the old Docker image
echo "Deleting old docker image"
if ! docker rmi asia-docker.pkg.dev/supra-devnet-misc/smr-moonshot-devnet/validator-node:v5.0.0; then
    echo "Failed to delete old Docker image."
fi
echo "Deleted the old Docker image"

# Run the Docker container
echo "Running new docker image"
if ! docker run --name "$container_id" \
    -v ./supra_configs:/supra/configs \
    -e="SUPRA_HOME=/supra/configs" \
    -e="SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
    -e="SUPRA_MAX_LOG_FILE_SIZE=4000000" \
    -e="SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
    -e="SUPRA_MAX_LOG_FILES=20" \
    --net=host -itd asia-docker.pkg.dev/supra-devnet-misc/smr-moonshot-devnet/validator-node:v5.0.1; then
    echo "Failed to run new Docker image."
    exit 1
fi
echo "New Docker image created"
