import time
import requests
import json
from datetime import datetime
import argparse
from typing import Dict, List
from urllib.parse import urljoin


NANO_SECONDS_IN_ONE_SECOND = 1000000

DEFAULT_RPC_URL = "https://rpc-mainnet.supra.com/"
DEFAULT_TOTAL_EPOCHS = 10
DEFAULT_LOG_FILE_PATH = "tracking_data.txt"

FRAMEWORK_ADDRESS = "0x1"
BLOCK_RESOURCE_TYPE = "0x0000000000000000000000000000000000000000000000000000000000000001::block::BlockResource"
CONFIGURATION_RESOURCE_TYPE = "0x0000000000000000000000000000000000000000000000000000000000000001::reconfiguration::Configuration"
VALIDATOR_CONFIG_RESOURCE_TYPE = "0x0000000000000000000000000000000000000000000000000000000000000001::stake::ValidatorConfig"
VALIDATOR_PERFORMANCE_RESOURCE_TYPE = "0x0000000000000000000000000000000000000000000000000000000000000001::stake::ValidatorPerformance"


def log_response(log_file_path: str, label: str, response_data: any):
    timestamp = datetime.utcnow().isoformat()
    with open(log_file_path, "a") as f:
        f.write(f"\n--- {label} at {timestamp} UTC ---\n")
        f.write(json.dumps(response_data, indent=2))
        f.write("\n")


def get_account_resource_data(
    rpc_url: str, account_address: str, resource_type: str
) -> Dict[str, any]:
    return requests.request(
        method="GET",
        url=urljoin(
            rpc_url, f"rpc/v1/accounts/{account_address}/resources/{resource_type}"
        ),
    ).json()["result"][0]


def invoke_view_function(
    rpc_url: str, function_sig: str, type_arguments: List[str], arguments: List[str]
) -> Dict[str, any]:
    payload = {
        "function": function_sig,
        "type_arguments": type_arguments,
        "arguments": arguments,
    }
    return requests.request(
        method="POST",
        url=urljoin(rpc_url, "rpc/v1/view"),
        json=payload,
    ).json()


def take_delegator_stake_and_validator_performance_snapshot(
    rpc_url: str,
    total_epochs: int,
    pool_address: str,
    delegator_address: str,
    buffer_time: int,
    log_file_path: str,
):
    epoch_duration = int(
        int(
            get_account_resource_data(rpc_url, FRAMEWORK_ADDRESS, BLOCK_RESOURCE_TYPE)[
                "epoch_interval"
            ]
        )
        / NANO_SECONDS_IN_ONE_SECOND
    )
    last_epoch_change_time = int(
        int(
            get_account_resource_data(
                rpc_url, FRAMEWORK_ADDRESS, CONFIGURATION_RESOURCE_TYPE
            )["last_reconfiguration_time"]
        )
        / NANO_SECONDS_IN_ONE_SECOND
    )

    next_epoch_change_time = last_epoch_change_time + epoch_duration
    cur_time = int(time.time())
    remaining_time_for_epoch_change = next_epoch_change_time - cur_time
    if remaining_time_for_epoch_change > buffer_time:
        wait_time = remaining_time_for_epoch_change - buffer_time
    else:
        wait_time = remaining_time_for_epoch_change + (epoch_duration - buffer_time)

    print(f"Waiting for {wait_time} seconds")
    time.sleep(wait_time)

    validator_index = int(
        get_account_resource_data(
            rpc_url, pool_address, VALIDATOR_CONFIG_RESOURCE_TYPE
        )["validator_index"]
    )

    for i in range(total_epochs):
        print(f"\nRound {i + 1} of {total_epochs}")
        log_response(log_file_path, f"Round {i+1}", "")
        try:
            delegator_stake = invoke_view_function(
                rpc_url,
                "0x1::pbo_delegation_pool::get_stake",
                [],
                [
                    pool_address,
                    delegator_address,
                ],
            )
            log_response(log_file_path, "Delegator Stake", delegator_stake)

            stake_pool_total_stake = invoke_view_function(
                rpc_url,
                "0x1::stake::get_stake",
                [],
                [
                    pool_address,
                ],
            )
            log_response(
                log_file_path, "Stake Pool Total Stake", stake_pool_total_stake
            )

            validator_performance = get_account_resource_data(
                rpc_url, FRAMEWORK_ADDRESS, VALIDATOR_PERFORMANCE_RESOURCE_TYPE
            )["validators"][validator_index]
            log_response(log_file_path, "Validator Performance", validator_performance)

        except Exception as err:
            log_response(log_file_path, "ERROR", {"error": str(err)})

        if i < (total_epochs - 1):
            print(f"Sleeping for {epoch_duration} seconds")
            time.sleep(epoch_duration)


def main():
    parser = argparse.ArgumentParser(
        description="A tool to take snapshot of delegator stake and validator performance for N epochs",
        epilog="Thanks for using this tool",
    )
    parser.add_argument(
        "--rpc-url",
        type=str,
        default=DEFAULT_RPC_URL,
        help="RPC node REST endpoint URL",
    )
    parser.add_argument(
        "--total-epochs",
        type=int,
        default=DEFAULT_TOTAL_EPOCHS,
        help="Number of epochs to consider for snapshots",
    )
    parser.add_argument(
        "--pool-address",
        type=str,
        required=True,
        help="PBO delegation pool address",
    )
    parser.add_argument(
        "--delegator-address",
        type=str,
        required=True,
        help="PBO delegation pool delegator address",
    )
    parser.add_argument(
        "--buffer-time",
        type=int,
        required=True,
        help="Time before epoch change to take snapshot of states",
    )
    parser.add_argument(
        "--log-file-path",
        type=str,
        default=DEFAULT_LOG_FILE_PATH,
        help="Path of the log file in which snapshot will be emitted",
    )
    args = parser.parse_args()
    print("Args: ", args)
    take_delegator_stake_and_validator_performance_snapshot(
        args.rpc_url,
        args.total_epochs,
        args.pool_address,
        args.delegator_address,
        args.buffer_time,
        args.log_file_path,
    )


if __name__ == "__main__":
    main()
