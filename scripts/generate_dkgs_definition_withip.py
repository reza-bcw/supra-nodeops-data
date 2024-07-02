import os
import json

def extract_ip_address(folder_name):
    # Split the folder name using underscores
    parts = folder_name.split("_")
    # Take the last part as the IP address
    ip_address = parts[-1]
    return ip_address

def generate_dkgs_definition(release_folder_path):
    committee_members = []

    # Iterate over the folders inside the release folder
    for folder_name in os.listdir(release_folder_path):
        # Skip the supra-public-configs folder
        if folder_name == "supra-public-configs":
            continue
        if folder_name == "supra-35.102.53.124(sample)":
            continue

        # Extract the IP address from the folder name
        address = extract_ip_address(folder_name)
        print(f"address: {address}")
        # Path to the smr_public_key.json file inside the node folder
        node_folder_path = os.path.join(release_folder_path, folder_name, "smr_public_key.json")

        # Read the JSON file inside the node folder
        with open(node_folder_path, "r") as file:
            data = json.load(file)
            public_key = data["list"][data["active"]]["ed25519"]
            cg_public_key = data["list"][data["active"]]["cg_public_key"]
            print(f"public_key:{public_key}")
            # Create a dictionary for the committee member
            committee_members.append({
                "address": address + ":25000",
                "publickey": public_key,
                "cg_public_key": cg_public_key
            })

    # Create dkgs_definition.json file
    dkgs_definition = [{"dkg_type": "Smr", "committee": committee_members}]
    with open(os.path.join(release_folder_path, "supra-public-configs", "dkgs_definition.json"), "w") as outfile:
        json.dump(dkgs_definition, outfile, indent=4)

def verify_dkgs_definition(release_folder_path):
    # Load the generated dkgs_definition.json
    with open(os.path.join(release_folder_path, "supra-public-configs", "dkgs_definition.json"), "r") as file:
        dkgs_definition = json.load(file)

    # Iterate over the folders inside the release folder
    for folder_name in os.listdir(release_folder_path):
        # Extract the IP address from the folder name
        address = extract_ip_address(folder_name)
        if folder_name == "supra-public-configs":
            continue
        if folder_name == "supra-35.102.53.124(sample)":
            continue
        # Path to the smr_public_key.json file inside the node folder
        node_folder_path = os.path.join(release_folder_path, folder_name, "smr_public_key.json")

        # Read the JSON file inside the node folder
        with open(node_folder_path, "r") as file:
            data = json.load(file)
            public_key = data["list"][data["active"]]["ed25519"]
            cg_public_key = data["list"][data["active"]]["cg_public_key"]

            # Check if the information matches the dkgs_definition
            for committee_member in dkgs_definition[0]["committee"]:
                if (committee_member["address"] == address + ":25000" and
                        committee_member["publickey"] == public_key and
                        committee_member["cg_public_key"] == cg_public_key):
                    print(f"Verification passed for node at IP address {address}.")
                    break
            else:
                print(f"Verification failed for node at IP address {address}.")

if __name__ == "__main__":
    release_folder_path = "release_round3_data"
    generate_dkgs_definition(release_folder_path)
    verify_dkgs_definition(release_folder_path)
