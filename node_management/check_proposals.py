import os
import re
import sys
import gzip
import shutil
import argparse


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
    return None


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
    return None

def decompress_log(filepath):
    """Decompress the gzipped log file and return the decompressed file path"""
    if not filepath.endswith('.gz'):
        return None  # Return None if the file is not a .gz file

    decompressed_file = filepath[:-3]  # Remove .gz extension to get the decompressed file name
    try:
        with gzip.open(filepath, 'rb') as f_in:
            with open(decompressed_file, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)
        return decompressed_file
    except Exception as e:
        print(f"Error decompressing file {filepath}: {e}")
        return None

def delete_decompressed_log(filepath):
    """Delete the decompressed log file"""
    try:
        os.remove(filepath)
        print(f"Deleted decompressed log: {filepath}")
    except Exception as e:
        print(f"Error deleting decompressed file {filepath}: {e}")

def parse_log_file(filepath, proposals, committed_blocks, decompress_logs):
    decompressed_file = None
    try:
        # Call decompress_log, which handles the .gz file check internally
        if decompress_log:
            decompressed_file = decompress_log(filepath)
            if decompressed_file:
                filepath = decompressed_file

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
        if decompressed_file:
            delete_decompressed_log(decompressed_file)


    except Exception as e:
        print(f"Error reading file {filepath}: {e}")

def write_output_to_file(output, output_file="proposals.log"):
    """Writes output to a file"""
    with open(output_file, 'a') as file:  # Open in append mode ('a') to not overwrite existing content
        file.write(output + '\n')

def main(path, decompress_logs):
    proposals = {}
    committed_blocks = set()

    # Open file for output at the start
    output_file = "proposals.log"
    if os.path.exists(output_file):
        os.remove(output_file)  # Remove the file if it exists to start fresh
    
    # If the path is a directory, get all files
    if os.path.isdir(path):
        filepaths = [os.path.join(path, f) for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))]
    elif os.path.isfile(path):
        filepaths = [path]
    else:
        print(f"Error: {path} is not a valid file or directory.")
        sys.exit(1)

    # Check for .gz files if the --decompress option is provided
    if decompress_logs:
        gz_files = [f for f in filepaths if f.endswith('.gz')]
        if not gz_files:
            print("No compressed .gz files found in the specified directory.")
            user_input = input("Do you want to continue processing uncompressed files? (y/n): ")
            if user_input.lower() != 'y':
                print("Exiting script.")
                sys.exit(0)
            else:
                print("Continuing with uncompressed files...")

    for filepath in filepaths:
        parse_log_file(filepath, proposals, committed_blocks, decompress_logs)

    # Sort by height
    proposals = sorted(proposals.items(), key=lambda e: e[1][3])

    # Report all proposals with committed status
    for local_date_time, (block_hash, epoch, round, height) in proposals:
        is_committed = (block_hash, epoch, round, height) in committed_blocks
        output_data = {
            "block_timestamp_local_date_time": local_date_time,
            "block_hash": block_hash,
            "epoch": epoch,
            "round": round,
            "height": height,
            "committed": is_committed
        }
        write_output_to_file(str(output_data), output_file)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("""
usage: python check_proposals.py path [--decompress]

Process Supra block proposal logs.

positional arguments:
    path          Path to the log file or directory

Options:
    -h, --help    show this help message and exit
    --decompress    Decompress .gz files before parsing
        """)
        sys.exit(1)

    # Argument parsing for handling the --decompress flag
    parser = argparse.ArgumentParser(
        description='Process Supra block proposal logs.',
        usage="python check_proposals.py path [--decompress]"  # Custom usage format
    )

    parser.add_argument('path', help='Path to the log file or directory')
    parser.add_argument('--decompress', action='store_true', help='Decompress .gz files before parsing')


    args = parser.parse_args()

    main(args.path, args.decompress)
