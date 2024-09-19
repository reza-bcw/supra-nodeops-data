import subprocess
import sys

def check_command_installed(command):
    try:
        subprocess.run([command, '--version'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print(f"{command.capitalize()} is installed.")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(f"{command.capitalize()} is not installed.")
        return False

def check_cargo_installed():
    try:
        # Run 'cargo --version' to check if Cargo is installed
        result = subprocess.run(['cargo', '--version'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode == 0:
            print("Cargo is installed.")
            return True
        else:
            print("Cargo is not installed.")
            return False
    except FileNotFoundError:
        # 'cargo' command is not found
        print("Cargo is not installed.")
        return False

def Create_Docker_Container():
    print("\nCreating Docker Container\n")
    
    # Docker run command
    docker_command = [
        "docker", "run", "--name", f"supra_cli",
        "-v", "./supra_configs:/supra/configs",
        "-e", "SUPRA_HOME=/supra/configs",
        "--net=host",
        "-itd", "asia-docker.pkg.dev/supra-devnet-misc/smr-moonshot-devnet/validator-node:v6.0.0.rc7"
    ]
    
    try:
        # Run the Docker command
        result = subprocess.run(docker_command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        if result.returncode == 0:
            print(f"Docker container 'supra_cli' created successfully.")
        else:
            print(f"Failed to create Docker container 'supra_cli'.")
            return 1

    except subprocess.CalledProcessError as e:
        print(f"Failed to create Docker container 'supra_cli'. Error: {e.stderr.decode()}")
        return 1

def main():

    prerequisites = ["docker", "cargo", "gcloud"]
    
    for i in prerequisites: 
        # Check if prerequisites are installed
        if not check_command_installed(i):
            print(f"Please install {i} to proceed.")
            sys.exit(1)
        

    Create_Docker_Container ()
    sys.exit(1)
    
    main()  # Recursively call main() to prompt again

if __name__ == "__main__":
    main()
