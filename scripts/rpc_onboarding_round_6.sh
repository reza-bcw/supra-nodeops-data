#!/bin/bash

SUPRA_DOCKER_IMAGE=""
SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_rpc_configs"
CONFIG_FILE="$(pwd)/operator_rpc_config.toml"
BASE_PATH="$(pwd)"

create_folder_and_files() {
    touch operator_rpc_config.toml
    if [ ! -d "supra_rpc_configs" ]; then
        mkdir supra_rpc_configs
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
    echo "3. Select Phase III - Re-Start RPC node"
    echo "4. Exit"
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

    USER_ID=$(id -u)
    GROUP_ID=$(id -g)

    docker run --name "supra_rpc_$IP_ADDRESS" \
        -v $SCRIPT_EXECUTION_LOCATION:/supra/configs \
        --user "${USER_ID}:${GROUP_ID}"\
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/rpc_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=400000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
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
    local path_passed="supra_rpc_configs"
    local config_file="${path_passed}/config.toml"
    echo $config_file

    read -p "Enter Validator IP address: " ip_address
    # Create config.toml content
    cat <<EOF > "${config_file}"
bind_addr = "0.0.0.0:27000"
block_provider_is_trusted = false
consensus_client_cert_path = "configs/client_supra_certificate.pem"
consensus_client_private_key_path = "configs/client_supra_key.pem"
consensus_root_ca_cert_path = "configs/ca_certificate.pem"
consensus_rpc = "ws://$ip_address:26000"
resume = true
supra_committees_config = "configs/supra_committees.json"
sync_retry_interval_in_secs = 5

[chain_instance]
chain_id = 6
epoch_duration_secs = 7200
recurring_lockup_duration_secs = 14400
voting_duration_secs = 7200
is_testnet = true
genesis_timestamp_microseconds = 1726574400000000


[database_setup.dbs.archive.rocks_db]
path = "configs/rpc_archive"
enable_snapshots = true

[database_setup.dbs.ledger.rocks_db]
path = "configs/rpc_ledger"

[database_setup.dbs.chain_store.rocks_db]
path = "configs/rpc_store"
enable_snapshots = true

[database_setup.snapshot_config]
depth = 2
interval_in_seconds = 1800
path = "configs/snapshot"
retry_count = 3
retry_interval_in_seconds = 5

[[allowed_origin]]
url = "https://rpc-testnet.supra.com"
description = "RPC For Supra Scan and Faucet"

[[allowed_origin]]
url = "https://rpc-testnet1.supra.com"
description = "RPC For nodeops group1"

[[allowed_origin]]
url = "https://rpc-testnet2.supra.com"
description = "RPC For nodeops group2"

[[allowed_origin]]
url = "https://rpc-testnet3.supra.com"
description = "RPC For nodeops group3"

[[allowed_origin]]
url = "https://rpc-testnet4.supra.com"
description = "RPC For nodeops group4"

[[allowed_origin]]
url = "https://rpc-testnet5.supra.com"
description = "RPC For nodeops group5"

[[allowed_origin]]
url = "http://localhost:27000"
description = "LocalNet"
mode = "Server"

[[allowed_origin]]
url = "https://www.starkey.app"
description = "Starkey domain"
mode = "Cors"

[[allowed_origin]]
url = "chrome-extension://fcpbddmagekkklbcgnjclepnkddbnenp"
description = "Starkey wallet extension"
mode = "Cors"

[[allowed_origin]]
url = "chrome-extension://hcjhpkgbmechpabifbggldplacolbkoh"
description = "Starkey wallet extension"
mode = "Cors"

[[allowed_origin]]
url = "https://supra.com"
description = "Supra domain"
mode = "Cors"

[[allowed_origin]]
url = "https://qa-spa.supra.com"
description = "QA Supra domain"
mode = "Cors"

[[allowed_origin]]
url = "https://qa-api.services.supra.com"
description = "QA API Supra domain"
mode = "Cors"

[[allowed_origin]]
url = "https://prod-api.services.supra.com"
description = "Prod API Supra domain"
mode = "Cors"

[[allowed_origin]]
url = "http://localhost:3000"
description = "Localhost"
mode = "Cors"

[[allowed_origin]]
url = "http://localhost:8080"
description = "Localhost"
mode = "Cors"

EOF
    docker cp $SCRIPT_EXECUTION_LOCATION/config.toml supra_rpc_$IP_ADDRESS:/supra/

    wget -O $SCRIPT_EXECUTION_LOCATION/ca_certificate.pem https://testnet-snapshot.supra.com/certs/ca_certificate.pem
    wget -O $SCRIPT_EXECUTION_LOCATION/client_supra_certificate.pem https://testnet-snapshot.supra.com/certs/client_supra_certificate.pem
    wget -O $SCRIPT_EXECUTION_LOCATION/client_supra_key.pem https://testnet-snapshot.supra.com/certs/client_supra_key.pem
    wget -O $SCRIPT_EXECUTION_LOCATION/genesis_blob.zip https://testnet-snapshot.supra.com/configs/genesis_blob.zip
    wget -O $SCRIPT_EXECUTION_LOCATION/supra_committees.json https://testnet-snapshot.supra.com/configs/supra_committees.json
    
    docker cp supra_rpc_configs/genesis.blob supra_rpc_$IP_ADDRESS:/supra/
}

download_snapshot() {
    # Clean old database
    rm -rf $SCRIPT_EXECUTION_LOCATION/rpc_archive $SCRIPT_EXECUTION_LOCATION/rpc_ledger $SCRIPT_EXECUTION_LOCATION/snapshot $SCRIPT_EXECUTION_LOCATION/rpc_store $SCRIPT_EXECUTION_LOCATION/latest_snapshot_rpc.zip

    # Download snapshot
    echo "Downloading the latest snapshot......"
    wget -O $SCRIPT_EXECUTION_LOCATION/latest_snapshot_rpc.zip https://testnet-snapshot.supra.com/snapshots/latest_snapshot_rpc.zip

    # Unzip snapshot
    unzip $SCRIPT_EXECUTION_LOCATION/latest_snapshot_rpc.zip -d $SCRIPT_EXECUTION_LOCATION/

    # Making rpc_store directory
    mkdir $SCRIPT_EXECUTION_LOCATION/rpc_store/
    mkdir $SCRIPT_EXECUTION_LOCATION/rpc_archive/


    # Copy snapshot into smr_database
    cp $SCRIPT_EXECUTION_LOCATION/snapshot/snapshot_*/store/* $SCRIPT_EXECUTION_LOCATION/rpc_store/
    cp $SCRIPT_EXECUTION_LOCATION/snapshot/snapshot_*/archive/* $SCRIPT_EXECUTION_LOCATION/rpc_archive/
    wget -O $SCRIPT_EXECUTION_LOCATION/genesis_blob.zip https://testnet-snapshot.supra.com/configs/genesis_blob.zip
    unzip $SCRIPT_EXECUTION_LOCATION/genesis_blob.zip -d $SCRIPT_EXECUTION_LOCATION/
    cp $SCRIPT_EXECUTION_LOCATION/genesis_blob/genesis.blob $SCRIPT_EXECUTION_LOCATION/
}

start_rpc_node(){
IP_ADDRESS=$(extract_ip "operator_rpc_config.toml")
echo "Starting the RPC node......."

/usr/bin/expect <<EOF
spawn docker exec -it supra_rpc_$IP_ADDRESS /supra/rpc_node
expect "Starting logger runtime"
send "\r"
expect eof
EOF
}

start_supra_container(){
    IP_ADDRESS=$(extract_ip "operator_rpc_config.toml")
    echo "Starting supra rpc container"
    if ! docker start supra_rpc_$IP_ADDRESS; then
        echo "Failed to start the container."
    else
        docker cp "$SCRIPT_EXECUTION_LOCATION/config.toml" supra_rpc_$IP_ADDRESS:/supra/
        rm "$SCRIPT_EXECUTION_LOCATION/genesis_blob.zip"
        rm -rf "$SCRIPT_EXECUTION_LOCATION/genesis_blob"
        echo "Started the RPC Node container."
    fi

}

stop_supra_container(){
IP_ADDRESS=$(extract_ip "operator_rpc_config.toml")
echo "Stopping supra rpc container"
if ! docker stop supra_rpc_$IP_ADDRESS; then
    echo "Failed to stop supra container. Exiting..."
    exit 1
fi
}

start_supra_rpc_node() {

    IP_ADDRESS=$(extract_ip "operator_rpc_config.toml")

    # Check if container is running
    if docker ps --filter "name=supra_rpc_$IP_ADDRESS" --format '{{.Names}}' | grep -q supra_rpc_$IP_ADDRESS; then

        # Prompt for either IP address or DNS name
        while true; do
            echo "Please select the appropriate option to start the rpc node:"
            echo "1. Start your rpc node within 4 hour window of network start"
            echo "2. Start your rpc node after 4 hour window of the network start using snapshot"
            read -p "Enter your choice (1 or 2): " choice

            case $choice in
                1)
                    while true; do
                        start_rpc_node
                        break
                    done
                    break
                    ;;
                2)
                    while true; do
                    
                        download_snapshot
                        start_rpc_node
                        break
                    done
                    break
                    ;;
                *)
                    echo "Invalid choice. Please select 1 for node without snapshot or 2 using the snapshot."
                    ;;
            esac
        done
    else
        echo "Your container supra_rpc_$IP_ADDRESS is not running."
    fi

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
            download_snapshot
            echo ""
            echo "_________________________________________________________________________________________________________________"
            echo "                                                                                                                 "
            echo "                                         ✔ Phase 1: Completed Successfully                                       "
            echo "                                                                                                                 "
            echo "                                           Please Open port 27000 publicly                                       "
            echo "_________________________________________________________________________________________________________________"
            echo ""     
            ;;
        2)
            start_supra_rpc_node
            ;;
        3)
            stop_supra_container
            download_snapshot
            start_supra_container
            start_rpc_node
            ;;
        4)
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