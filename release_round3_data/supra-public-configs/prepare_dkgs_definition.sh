#!/bin/bash

function check_command() {
    cmd=$1
    echo -ne "\tChecking '$cmd' ..."
    which $cmd > /dev/null
    if [ 0 -eq $? ]; then
        echo -e "YES"
    else
        echo "NO"
        echo "Please install '${cmd}' before proceeding farther"
        exit 1
    fi
}


echo "Checking prerequisites ..."
check_command shasum
check_command jq

checksum="981bc2b865d0653ce61ca96583c273e1e89ca6fc5d51644ab4346752b0196d30"

dkg_definitions="dkgs_definition.json"
if [ -e ${dkg_definitions} ]
then
    bck="${dkg_definitions}_$(date +"%Y-%m-%dT%T")"
    echo -e "\nBackup previous dkg definitions as:\n\t${bck}\n"
    mv ${dkg_definitions} ${bck}
fi

wget -O dkgs_definition_latest.json https://raw.githubusercontent.com/Entropy-Foundation/supra-nodeops-data/master/release_round3_data/supra-public-configs/dkgs_definition.json
cat dkgs_definition_latest.json >> ${dkg_definitions}


echo -e "Exported ${dkg_definitions} file in current directory:\n\t$PWD/${dkg_definitions}\n"

# Check the checksum

echo "Checking the checksum ..."
echo "Expected: ${checksum}"

actual=$(shasum -a 256 ${dkg_definitions} | cut -d " " -f1)

echo -e "Actual: ${actual}\n"

echo "*********************************************"
if [ "${actual}" != "${checksum}" ]
then
   echo -e "\t[E] Exported invalid dkg definitions"
   echo -e "*********************************************\n"
   exit 1
else
   echo -e "\tExported valid dkg definitions"
   echo -e "*********************************************\n"
fi

echo -e "*** Preparing to copy '${dkg_definitions}' to docker container ...\n"
echo -e "List of running docker containers ...\n"
docker ps
echo ""
while [ 1 ]
do
    read -p "Please specify destination docker container name|ID: " container_name
    echo ""

    docker ps | grep "${container_name}" > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "*** [E] Docker container with name|ID '${container_name}' does not exist\n"
    else
        break
    fi
done

## validate dkg-definition content agains smr_settings.toml and smr_public_key.json
smr_settings="/supra/configs/smr_settings.toml"
smr_public_key="/supra/configs/smr_public_key.json"


## Get ip-address from smr-settings.toml
echo -e "Checking '${dkg_definitions}' content against '${smr_settings}' and '${smr_public_key}' in container '${container_name}' ... \n"

ip_address="$(docker exec -it "${container_name}" cat ${smr_settings} | grep "node_public_addr" | cut -d "\"" -f2 | tr -d " ")"
if [ -z "${ip_address}" ]; then
    smr_settings_base=$(basename ${smr_settings})
    echo -e "[E] Failed to fetch ip address from '${smr_settings}' file"
    echo -e "\tPlease make sure that '${smr_settings}' file exists in docker container '${container_name}'"
    echo -e "\tPlease make sure that 'node_public_addr = \"xxx.xxx.xxx.xxx:25000\"' entry is available in ${smr_settings_base}"
    exit 1
fi

echo -en "\tValidating node public address info consistency ... "

dkg_entry_by_ip_address=$(cat ${dkg_definitions} | jq -r --arg ip_address "${ip_address}" '.[0].committee[] | select(.address == $ip_address)')

if [ -z "${dkg_entry_by_ip_address}" ]; then
    echo "FAILED"
    echo -e "\t[E] No matching entry in '${dkg_definitions}' with address equal to *${ip_address}*" 
    exit 1
fi
echo "SUCCESS"

echo -en "\tValidating public key info consistency ... "

## Get dkg entry pub-keys
dkg_keys=$(echo ${dkg_entry_by_ip_address} | jq '.publickey, .cg_public_key' | xargs echo)
read dkg_ed25519 dkg_cgpublic <<< "${dkg_keys}"

## Get pub-keys from smr-public-key,json
smr_public_key_content=$(docker exec -it "${container_name}" cat ${smr_public_key})
smr_pub_kyes=$(echo ${smr_public_key_content} | jq '(.active) as $active | .list | to_entries | .[] | select(.key == $active) | .value.ed25519, .value.cg_public_key' | xargs echo)
read smr_ed25519 smr_cgpublic <<< "${smr_pub_kyes}"

if [ -z "${dkg_ed25519}" ] || [ "null" == "${dkg_ed25519}" ] || [ "${dkg_ed25519}" != "${smr_ed25519}" ]; then
    echo "FAILED"
    echo -e "\t[E] ED25519 key '${dkg_ed25519}' for '${ip_address}' node in '${dkg_definitions}' file does not correspond to '${smr_ed25519}' in '${smr_public_key}'"
    exit 1
fi

if [ -z "${dkg_cgpublic}" ] || [ "null" == "${dkg_cgpublic}" ] || [ "${dkg_cgpublic}" != "${smr_cgpublic}" ]; then
    echo "FAILED"
    echo -e "\t[E] CG-DKG key '${dkg_cgpublic}' for '${ip_address}' node in '${dkg_definitions}' file does not correspond to '${smr_cgpublic}' in '${smr_public_key}'"
    exit 1
fi
echo -e "SUCCESS\n"

rm dkgs_definition_latest.json
docker cp ${dkg_definitions} "${container_name}":/supra