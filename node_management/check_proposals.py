import argparse
import gzip
import json
import os
import re
import shutil
import sys


"""
This script parses the given log file or directory to find the block proposals made by this validator
and classify them as either committed or not committed.

If your node is consistently producing proposals that are marked with `committed: False`, then either:
    1. Your local consensus key might not match the key that is registered on chain, or:
    2. Your node is not able to deliver its proposal to enough of the members of the current
       validator committee within the (as of 2025-05-15) 3.5s consensus timeout. This might happen
       if your node is under-provisioned, or if you are running multiple nodes on the same machine,
       or if your node is experiencing network issues.

In the former case, please use the `supra node rotate-consensus-key` command to register a new consensus
key on-chain and wait for the next epoch to begin. If the transaction was successful then your node
should start generating committed proposals again.

In the latter case, please review your node's configuration and ensure that it matches the outlined in
your SLA. If issues persist, please contact Supra support via Discord.

Example usage:
```
python3 check_proposals.py <host_supra_home>/supra_node_logs/
```

Example usage with decompression:
```
python3 check_proposals.py <host_supra_home>/supra_node_logs/ --decompress
```
"""


JSON_INDENT = 4


def extract_proposal_info(line: str):
    proposal_match = re.search(r'proposal:\s+([a-f0-9]{64})', line)
    epoch_match = re.search(r'epoch:\s+(\d+)', line)
    round_match = re.search(r'round:\s+(\d+)', line)
    height_match = re.search(r'height:\s+(\d+)', line)
    local_dt_match = re.search(r'local_date_time:\s+"([^"]+)"', line)

    if proposal_match and epoch_match and round_match and height_match and local_dt_match:
        return {
            "hash": proposal_match.group(1),
            "epoch": int(epoch_match.group(1)),
            "round": int(round_match.group(1)),
            "height": int(height_match.group(1)),
            "local_date_time": local_dt_match.group(1)
        }


def extract_committed_block_info(line: str):
    block_match = re.search(r'block:\s+([a-f0-9]{64})', line)
    epoch_match = re.search(r'epoch:\s+(\d+)', line)
    round_match = re.search(r'round:\s+(\d+)', line)
    height_match = re.search(r'height:\s+(\d+)', line)

    if block_match and epoch_match and round_match and height_match:
        return {
            "hash": block_match.group(1),
            "epoch": int(epoch_match.group(1)),
            "round": int(round_match.group(1)),
            "height": int(height_match.group(1))
        }


def maybe_decompress_log(filepath):
    if not filepath.endswith('.gz'):
        return None

    try:
        with gzip.open(filepath, 'rb') as f_in:
            decompressed_path = filepath[:-3]

            with open(decompressed_path, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)

        return decompressed_path
    except Exception as e:
        print(f"Error decompressing file {filepath}: {e}")


def delete_decompressed_log(filepath):
    try:
        os.remove(filepath)
    except Exception as e:
        print(f"Error deleting decompressed file {filepath}: {e}")


def parse_log_file(filepath, proposals, committed_blocks, decompress_logs):
    decompressed_filepath = None

    try:
        if decompress_logs:
            decompressed_filepath = maybe_decompress_log(filepath)

            if decompressed_filepath:
                filepath = decompressed_filepath

        with open(filepath, 'r') as f:
            for line in f:
                if "Proposing" in line and "SmrBlock" in line:
                    info = extract_proposal_info(line)
                    if info:
                        proposals[info["local_date_time"]] = info["hash"], info["epoch"], info["round"], info["height"]
                elif "Committing" in line and "CertifiedBlock" in line:
                    info = extract_committed_block_info(line)
                    if info:
                        committed_blocks.add((info["hash"], info["epoch"], info["round"], info["height"]))

        # If it was decompressed, delete the decompressed file after processing
        if decompressed_filepath:
            delete_decompressed_log(decompressed_filepath)

    except Exception as e:
        print(f"Error reading file {filepath}: {e}")


def main(path, decompress_logs, output_file_path):
    proposals = {}
    committed_blocks = set()
    
    # If the path is a directory, get all files
    if os.path.isdir(path):
        filepaths = [os.path.join(path, f) for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))]
    elif os.path.isfile(path):
        filepaths = [path]
    else:
        print(f"Error: {path} is not a valid file or directory.")
        sys.exit(1)

    for filepath in filepaths:
        parse_log_file(filepath, proposals, committed_blocks, decompress_logs)

    # Sort by height
    proposals = sorted(proposals.items(), key=lambda e: e[1][3])
    records = []

    # Report all proposals with committed status
    for local_date_time, (block_hash, epoch, round, height) in proposals:
        is_committed = (block_hash, epoch, round, height) in committed_blocks
        record = {
            "block_timestamp_local_date_time": local_date_time,
            "block_hash": block_hash,
            "epoch": epoch,
            "round": round,
            "height": height,
            "committed": is_committed
        }
        records.append(record)

    if output_file_path:
        with open(output_file_path, 'a') as f:
            json.dump(records, f, indent=JSON_INDENT)
    else:
        print(json.dumps(records, indent=JSON_INDENT))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Process Supra block proposal logs.'
    )
    parser.add_argument('path', help='Path to the log file or directory')
    parser.add_argument('--decompress', action='store_true', help='Decompress .gz files before parsing')
    parser.add_argument('--output-file', help='Path of the file in which to write the output')
    args = parser.parse_args()
    main(args.path, args.decompress, args.output_file)
