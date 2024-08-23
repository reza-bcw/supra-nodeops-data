#!/bin/bash

SUPRA_DOCKER_IMAGE=""
SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_configs"
CONFIG_FILE="$(pwd)/operator_rpc_config.toml"
BASE_PATH="$(pwd)"

create_folder_and_files() {
    touch operator_rpc_config.toml
    if [ ! -d "supra_configs" ]; then
        mkdir supra_configs
    else
        echo ""
    fi
}

extract_ip() {
    local ip=$(grep -oP 'ip_address\s*=\s*"\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$CONFIG_FILE")
    echo "$ip"
}

display_questions() {
    echo "1. Select Phase I - Setup RPC node"
    echo "2. Select Phase II - Start RPC node"
    echo "3. Exit"
}

check_permissions() {
    folder_path="$1"
    if [ ! -w "$folder_path" ]; then
        echo ""
        echo ""
        echo ""
        echo "Please check write permissions."
        echo ""
        echo "TERMINATING SCRIPT"

        exit 1
    fi
}

# Check if Docker is installed
check_docker_installed() {
    if ! command -v docker &>/dev/null; then
        echo "Docker is not installed. Please install Docker before proceeding."
        echo "Terminating Script"
        echo " "
        exit 1
    fi
}

# Check if gCloud is installed
check_gcloud_installed() {
    if ! command -v gcloud &>/dev/null; then
        echo "gCloud is not installed. Please install gCloud before proceeding."
        exit 1
    fi
}

# Check if the user is not root
# check_not_root() {
#     if [ "$(id -u)" = "0" ]; then
#         echo "You are running as root. Please run as a non-root user."
#         echo ""
#         exit 1
#     fi
# }

check_toml_cli() {
    if ! command -v toml &> /dev/null
    then
        echo "toml-cli could not be found. Please install it to proceed."
        echo "command : pip install toml-cli"
        exit 1
    fi

}

check_sha256sum_installed() {
    if command -v sha256sum >/dev/null 2>&1; then

        return 0
    else
        echo "sha256sum is not installed."
        exit 1
    fi
}

check_openssl_installed() {
    if command -v openssl >/dev/null 2>&1; then

        return 0
    else
        echo "openssl is not installed."
        exit 1
    fi
}

check_expect_installation() {
  if ! command -v expect &> /dev/null; then
    if [ -f /etc/apt/sources.list ]; then
      package_manager="sudo apt install"
    elif [ -f /etc/yum.repos.d/ ]; then
      package_manager="sudo yum install"
    else
      echo "**WARNING: Could not identify package manager. Please install expect manually."
      exit 1
    fi

    echo "Expect is not installed. Install it with:"
    echo "$package_manager expect"
  else
    echo ""
  fi
}

prerequisites() {
    echo ""
    echo "CHECKING PREREQUISITES"
    echo ""
    # check_not_root
    check_expect_installation
    check_sha256sum_installed
    check_docker_installed
    check_gcloud_installed
    check_openssl_installed
    echo "All Checks Passed: ✔ "
}

function configure_operator() {
    echo ""

    local valid_ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

    function validate_ip() {
        local ip=$1
        if [[ $ip =~ $valid_ip_regex ]]; then
            IFS='.' read -r -a octets <<< "$ip"
            for octet in "${octets[@]}"; do
                if ((octet < 0 || octet > 255)); then
                    return 1
                fi
            done
            return 0
        else
            return 1
        fi
    }

    while true; do
        read -p "Enter RPC IP address: " ip_address
        if validate_ip "$ip_address"; then
            break
        else
            echo "Invalid IP address. Please enter a valid IP address."
        fi
    done

    toml_file="$CONFIG_FILE"
    tmp_file=$(mktemp)

    grep -v '^ip_address' "$toml_file" | grep -v '^password' > "$tmp_file"

    echo "ip_address = \"$ip_address\"" >> "$tmp_file"
    mv "$tmp_file" "$toml_file"
}

function create_supra_container() {
    echo ""
    echo "CREATE DOCKER CONTAINER"
    echo ""

    IP_ADDRESS=$(extract_ip "operator_rpc_config.toml")
    read -p "Enter docker Image: " supra_docker_image

    docker run --name "supra_rpc_$IP_ADDRESS" \
        -v ./supra_configs:/supra/configs \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/rpc_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=400000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=10" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd "$supra_docker_image"


    if [[ $? -eq 0 ]]; then
        echo "Docker container 'supra_rpc_$IP_ADDRESS' created successfully."
    else
        echo "Failed to create Docker container 'supra_rpc_$IP_ADDRESS'."
        return 1
    fi
}

create_config_toml() {
    IP_ADDRESS=$(extract_ip "operator_rpc_config.toml")
    echo ""
    echo "CREATE CONFIG TOML FILE "
    echo ""
    local path_passed="supra_configs"
    local config_file="${path_passed}/config.toml"
    echo $config_file

    read -p "Enter Validator IP address: " ip_address
    # Create config.toml content
    cat <<EOF > "${config_file}"
archive_path = "configs/rpc_archive"
bind_addr = "0.0.0.0:27000"
block_provider_is_trusted = false
consensus_client_cert_path = "configs/client_supra_certificate.pem"
consensus_client_private_key_path = "configs/client_supra_key.pem"
consensus_root_ca_cert_path = "configs/ca_certificate.pem"
consensus_rpc = "ws://$ip_address:26000"
ledger_path = "configs/rpc_ledger"
resume = true
secret_key = "b519924c4da2745bc76c713a187be63b30ff62a0ecf23ccb7bf9f06c03cd59db"
snapshot_interval_in_seconds = 3600
snapshot_path = "configs/snapshot"
store_path = "configs/rpc_store"
supra_committees_config = "configs/supra_committees.json"
sync_retry_interval_in_secs = 2

[chain_instance]
chain_id = 6
epoch_duration_secs = 7200
is_testnet = true
genesis_timestamp_microseconds = 1723660200000000

EOF
    docker cp ./supra_configs/config.toml supra_rpc_$IP_ADDRESS:/supra/

    wget -O ./supra_configs/ca_certificate.pem https://testnet-snapshot.supra.com/certs/ca_certificate.pem

    wget -O ./supra_configs/client_supra_certificate.pem https://testnet-snapshot.supra.com/certs/client_supra_certificate.pem

    wget -O ./supra_configs/client_supra_key.pem https://testnet-snapshot.supra.com/certs/client_supra_key.pem

    wget -O ./supra_configs/genesis.blob https://testnet-snapshot.supra.com/configs/genesis.blob

    wget -O ./supra_configs/supra_committees.json https://testnet-snapshot.supra.com/configs/supra_committees.json

    docker cp supra_configs/genesis.blob supra_rpc_$IP_ADDRESS:/supra/

    # Clean old database
    rm -rf ./supra_configs/rpc_archive ./supra_configs/rpc_ledger ./supra_configs/snapshot ./supra_configs/rpc_store

    # Download snapshot
    echo "Downloading the latest snapshot......"
    wget -O ./supra_configs/latest_snapshot.zip https://testnet-snapshot.supra.com/snapshots/latest_snapshot.zip

    # Unzip snapshot
    unzip ./supra_configs/latest_snapshot.zip -d ./supra_configs/

    # Making rpc_store directory
    mkdir ./supra_configs/rpc_store

    # Copy snapshot into smr_database
    cp ./supra_configs/snapshot/snapshot_*/* ./supra_configs/rpc_store/


    echo ""
    echo "_________________________________________________________________________________________________________________"
    echo ""
    echo "                                         ✔ Phase 1: Completed Successfully                                       "
    echo ""
    echo "_________________________________________________________________________________________________________________"
    echo ""
    echo ""      
}

start_supra_rpc_node() {
    IP_ADDRESS=$(extract_ip "operator_rpc_config.toml")

    echo "Starting the RPC node......."

    /usr/bin/expect <<EOF
    spawn docker exec -it supra_rpc_$IP_ADDRESS /supra/rpc_node
    expect "Starting logger runtime"
    send "\r"
    expect eof

EOF
    echo ""
    echo "RPC Node started"
    echo "_________________________________________________________________________________________________________________"
    echo ""
    echo "                                         ✔ Phase 2: Completed Successfully                                       "
    echo ""
    echo "1. Please share your RPC IP Address: $IP_ADDRESS with Supra Team over Discord" 
    echo "" 
    echo "_________________________________________________________________________________________________________________"
    echo ""
    echo ""   
}

while true; do

    create_folder_and_files
    prerequisites
    echo ""
    display_questions
    echo ""
    read -p "Enter your choice: " choice

    case $choice in
        1)
            check_permissions "$SCRIPT_EXECUTION_LOCATION"
            configure_operator
            create_supra_container
            create_config_toml
            ;;
        2)
            start_supra_rpc_node
            ;;
        3)
            echo "Exit the script"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 3."
            ;;

    esac
    echo ""
    # Pause before displaying the menu again
    read -p "Press Enter to continue..."
done