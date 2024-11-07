#!/bin/bash

set -e

# Define the path for storing configuration in the current directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
BIN_DIR="${ROOT_DIR}/bin"
CONFIG_FILE="${ROOT_DIR}/bridge_config.json"
QEMU_CONFIG_FILE="/etc/qemu/bridge.conf"
QEMU_HELPER="/usr/lib/qemu/qemu-bridge-helper"
START_VM_SCRIPT="${BIN_DIR}/start_vm.sh"
ACCESS_VM_SCRIPT="${BIN_DIR}/access_vm.sh"
SHARED_DIR="${ROOT_DIR}/shared"
BAT_FILE="${SHARED_DIR}/configure_network.bat"

function create_folder() {
  directory_path="$1"

  # Check if the directory exists
  if [[ ! -d "$directory_path" ]]; then
      # If the directory does not exist, create it
      mkdir -p "$directory_path"
      echo "Directory created at $directory_path"
  else
      echo "Directory already exists at $directory_path"
  fi
}

# Function to check if a command is available
function check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "The command '$1' is not available. Please install the appropriate package."
        case "$1" in
            brctl)
                echo "Install it with: sudo apt install bridge-utils"
                ;;
            iptables)
                echo "Install it with: sudo apt install iptables"
                ;;
            ip)
                echo "Install it with: sudo apt install iproute2"
                ;;
            nano)
                echo "Install it with: sudo apt install nano"
                ;;
            jq)
                echo "Install it with: sudo apt install jq"
                ;;
            *)
                echo "For the command '$1', a different package might be required."
                ;;
        esac
        exit 1
    fi
}

# Function to create start_vm.sh script
function create_start_vm_script() {
  create_folder "$BIN_DIR"

  if [[ -f "$START_VM_SCRIPT" ]]; then
      echo "$START_VM_SCRIPT already exists. Skipping creation."
      return
  fi

  cat <<EOL > "$START_VM_SCRIPT"
#!/bin/bash

ROOT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)"
CONFIG_FILE="\${ROOT_DIR}/bridge_config.json"

# Check if qemu-system-x86_64 command exists
if ! command -v qemu-system-x86_64 &> /dev/null; then
    echo "qemu-system-x86_64 command not found. Please install it first."
    exit 1
fi

# Check if jq command exists
if ! command -v jq &> /dev/null; then
    echo "jq command not found. Please install it first."
    exit 1
fi

# Load bridges from configuration file
if [[ ! -f "\$CONFIG_FILE" ]]; then
    echo "Configuration file not found: \$CONFIG_FILE"
    exit 1
fi

# Display available bridges
echo "Available network bridges:"
jq -c '.[] | "\(.bridge_name) - \(.ip_address)"' "\$CONFIG_FILE" | nl
read -p "Select the number of the bridge to use: " selection
selected_bridge=\$(jq -r ".[\$selection-1]" "\$CONFIG_FILE")

if [[ "\$selected_bridge" == "null" ]]; then
    echo "Invalid selection."
    exit 1
fi

BRIDGE_NAME=\$(echo "\$selected_bridge" | jq -r '.bridge_name')

# Start the virtual machine
qemu-system-x86_64 \\
    -machine q35,accel=kvm \\
    -smp 4 \\
    -enable-kvm \\
    -device intel-iommu \\
    -cpu host \\
    -m 8G \\
    -drive file="\${ROOT_DIR}/disk.img",index=0,media=disk,format=qcow2,if=virtio,l2-cache-size=10M \\
    -rtc clock=vm,base=localtime \\
    -netdev bridge,id=net0,br=\$BRIDGE_NAME \\
    -device virtio-net-pci,netdev=net0 \\
    -nographic

echo "Virtual machine started and connected to bridge \$BRIDGE_NAME."
EOL

  chmod +x "$START_VM_SCRIPT"
  echo "Created VM start script: $START_VM_SCRIPT"
}

function create_access_vm_script() {
  create_folder "$BIN_DIR"

  if [[ -f "$ACCESS_VM_SCRIPT" ]]; then
      echo "$ACCESS_VM_SCRIPT already exists. Skipping creation."
      return
  fi

  cat <<EOL > "$ACCESS_VM_SCRIPT"
#!/bin/bash

ROOT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)"
CONFIG_FILE="\${ROOT_DIR}/bridge_config.json"
DESKTOP_SCALE=100

# Check if wlfreerdp command exists
if ! command -v wlfreerdp &> /dev/null; then
    echo "wlfreerdp command not found. Please install it first."
    exit 1
fi

# Check if jq command exists
if ! command -v jq &> /dev/null; then
    echo "jq command not found. Please install it first."
    exit 1
fi

# Load bridges from configuration file
if [[ ! -f "\$CONFIG_FILE" ]]; then
    echo "Configuration file not found: \$CONFIG_FILE"
    exit 1
fi

# Display available bridges
echo "Available network bridges:"
jq -c '.[] | "\(.bridge_name) - \(.vm_ip_address)"' "\$CONFIG_FILE" | nl
read -p "Select the number of the bridge to use: " selection
selected_bridge=\$(jq -r ".[\$selection-1]" "\$CONFIG_FILE")

if [[ "\$selected_bridge" == "null" ]]; then
    echo "Invalid selection."
    exit 1
fi

BRIDGE_IP=\$(echo "\$selected_bridge" | jq -r '.vm_ip_address')

# Access the VM via FreeRDP
wlfreerdp \\
  /u:User \\
  /p:lkwpeter \\
  /v:\${BRIDGE_IP} \\
  /cert-ignore \\
  /network:lan \\
  /dynamic-resolution \\
  /size:1920x1200 \\
  /scale-desktop:\${DESKTOP_SCALE} \\
  /scale:100 \\
  /gdi:hw \\
  /rfx \\
  /bpp:24 \\
  +aero \\
  +fonts \\
  -compression \\
  &>/dev/null &
EOL

  chmod +x "$ACCESS_VM_SCRIPT"
  echo "Created VM access script: $ACCESS_VM_SCRIPT"
}

# Function to create the .bat file for Windows IP configuration
function create_bat_script() {
  create_folder "$SHARED_DIR"

  host_ip="$1"
  subnet_mask="$2"
  gateway="$3"
  dns_server="$4"

  if [[ -f "$BAT_FILE" ]]; then
    echo "$BAT_FILE already exists. Deleting it."
    rm "$BAT_FILE"
  fi

  cat <<EOL > "$BAT_FILE"
@echo off
setlocal

REM Install optional feature 'OpenSSH Server'
echo Installing OpenSSH Server...
dism /online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0

REM Start SSH service and set it to start automatically
echo Starting SSH service and setting it to automatic...
sc start sshd
sc config sshd start=auto

REM Add firewall rules for SSH (Port 21 and 22)
echo Configuring firewall rules for SSH ports 21 and 22...
netsh advfirewall firewall add rule name="SSH Port 21" dir=in action=allow protocol=TCP localport=21
netsh advfirewall firewall add rule name="SSH Port 22" dir=in action=allow protocol=TCP localport=22

REM Configure SSH keys and authorized_keys file
set "ssh_dir=%USERPROFILE%\\.ssh"
set "authorized_keys=%ssh_dir%\\authorized_keys"

if not exist "%ssh_dir%" (
    echo Creating SSH directory in user profile...
    mkdir "%ssh_dir%"
)

if not exist "%authorized_keys%" (
    echo Creating authorized_keys file...
    type nul > "%authorized_keys%"
)

echo Setting permissions for authorized_keys file...
icacls "%authorized_keys%" /inheritance:r /grant "%USERNAME%":F

REM Configure network settings based on bridge configuration
set "host_ip=${host_ip}"
set "subnet_mask=${subnet_mask}"
set "gateway=${gateway}"
set "dns_server=${dns_server}"
set "interface_name=Ethernet"  REM Change this if necessary

echo Configuring IP address on interface "%interface_name%"...
netsh interface ip set address name="%interface_name%" static %host_ip% %subnet_mask% %gateway%

echo Configuring DNS server on interface "%interface_name%"...
netsh interface ip set dns name="%interface_name%" static %dns_server%

echo Configuration complete. Press any key to exit.
pause
EOL

    echo "Windows network configuration script created at: $BAT_FILE"
}

# Function to prompt for input until a valid (non-empty) response is given
function prompt_until_valid() {
    local prompt_message=$1 
    local user_input=""
    while [[ -z "$user_input" ]]; do
        read -p "$prompt_message" user_input
        if [[ -z "$user_input" ]]; then
            echo "Error: Input cannot be empty. Please try again."
        fi
    done
    echo "$user_input"
}

# Check if all necessary commands are available
check_command brctl
check_command ip
check_command iptables
check_command nano
check_command jq # JSON processing utility for reading/writing

# Load existing configuration or initialize new one
if [[ -f $CONFIG_FILE ]]; then
    config=$(jq '.' "$CONFIG_FILE")
else
    config="[]"
    echo "$config" > "$CONFIG_FILE"
fi

# Function to prompt the user for setup or removal based on existing configurations
function prompt_action() {
    # Check if there are any existing bridges in the configuration
    if jq -e '. | length > 0' "$CONFIG_FILE" >/dev/null; then
        local PS3="Select an option (1 or 2): "
        local options=("Setup a new virtual bridge" "Remove an existing virtual bridge")
        select opt in "${options[@]}"; do
            case $REPLY in
                1) return 0 ;; # Setup
                2) return 1 ;; # Remove
                *) echo "Invalid option. Please choose 1 or 2." ;;
            esac
        done
    else
        echo "No bridges are currently configured. Only setup is available."
        return 0 # Proceed with setup since no bridges exist
    fi
}

function propmpt_delete_scripts() {
  local PS3="Do you want to remove the scripts (1 or 2): "
  local options=("Delete the scripts" "Keep the scripts")
  select o in "${options[@]}"; do
      case $REPLY in
          1) return 0 ;; # Keep
          2) return 1 ;; # Remove
          *) echo "Invalid option. Please choose 1 or 2." ;;
      esac
  done
}

# Function to persist bridge configuration to JSON file
function save_config() {
    bridge_name="$1"
    interface="$2"
    ip_address="$3"
    vm_ip_address="$4"
    vm_subnet="$5"
    vm_gateway="$6"
    vm_dns_server="$7"

    # Add the new bridge configuration as JSON
    config=$(jq ". + [{\"bridge_name\": \"$bridge_name\", \"interface\": \"$interface\", \"ip_address\": \"$ip_address\", \"vm_ip_address\": \"$vm_ip_address\", \"vm_subnet\": \"$vm_subnet\", \"vm_gateway\": \"$vm_gateway\", \"vm_dns_server\": \"$vm_dns_server\"}]" "$CONFIG_FILE")
    echo "$config" > "$CONFIG_FILE"
}

# Function to remove a bridge based on saved configuration
function remove_bridge() {
    echo "Available bridges to remove:"
    jq -c '.[] | "\(.bridge_name) - \(.interface) - \(.ip_address)"' "$CONFIG_FILE" | nl

    read -p "Select the number of the bridge to remove: " selection
    selected_bridge=$(jq -r ".[$selection-1]" "$CONFIG_FILE")

    if [[ "$selected_bridge" == "null" ]]; then
        echo "Invalid selection."
        exit 1
    fi

    bridge_name=$(echo "$selected_bridge" | jq -r '.bridge_name')
    interface=$(echo "$selected_bridge" | jq -r '.interface')
    ip_address=$(echo "$selected_bridge" | jq -r '.ip_address')

    echo "Removing bridge $bridge_name with interface $interface and IP $ip_address."

    # Remove the IP address and bring down the bridge
    sudo ip addr del "$ip_address"/24 dev "$bridge_name"
    sudo ip link set "$bridge_name" down
    sudo brctl delbr "$bridge_name"

    # Remove the iptables rule
    sudo iptables -D FORWARD -m physdev --physdev-is-bridged -j ACCEPT

    # Remove the bridge configuration from the file
    config=$(jq "del(.[$selection-1])" "$CONFIG_FILE")
    echo "$config" > "$CONFIG_FILE"

    # Remove bridge entry from QEMU config if it exists
    if [[ -f $QEMU_CONFIG_FILE ]]; then
        sudo sed -i "/allow $bridge_name/d" "$QEMU_CONFIG_FILE"
        echo "Removed bridge $bridge_name from QEMU configuration."
    fi

    # If no other bridges exist, remove the +s permission from qemu-bridge-helper
    if ! jq -e '. | length > 0' "$CONFIG_FILE" >/dev/null; then
        if [[ -f $QEMU_HELPER ]]; then
            sudo chmod -s "$QEMU_HELPER"
            echo "Removed +s permission from $QEMU_HELPER."
        fi
    fi

    echo "Bridge $bridge_name has been removed."

    # Prompt to remove scripts
    if propmpt_delete_scripts; then
      if [[ -f "$START_VM_SCRIPT" ]]; then
        rm "$START_VM_SCRIPT"
      fi

      if [[ -f "$ACCESS_VM_SCRIPT" ]]; then
        rm "$ACCESS_VM_SCRIPT"
      fi

      if [[ -f "$BAT_FILE" ]]; then
        rm "$BAT_FILE"
      fi

      echo "Scripts have been removed."
    else
      echo "Scripts have not been removed."
    fi
}

function add_bridge() {
  # Setup a new virtual bridge
  bridge_name=$(prompt_until_valid "Enter the name of the network bridge: ")

  if brctl show | grep -q "^$bridge_name"; then
      echo "The bridge $bridge_name already exists."
      exit 1
  fi

  # List available network interfaces with IPv4 addresses
  echo "Available network interfaces with IPv4 addresses:"
  interfaces=()
  while IFS= read -r line; do
      interface=$(echo "$line" | awk '{print $1}')
      ip_address=$(echo "$line" | awk '{print $2}')
      interfaces+=("$interface - $ip_address")
  done < <(ip -o -f inet addr show | awk '{print $2, $4}')

  if [ ${#interfaces[@]} -eq 0 ]; then
      echo "No available interfaces with IPv4 addresses found. Exiting."
      exit 1
  fi

  select interface_info in "${interfaces[@]}"; do
      if [[ -n "$interface_info" ]]; then
          interface=$(echo "$interface_info" | awk '{print $1}')
          interface_ip=$(echo "$interface_info" | awk '{print $3}' | cut -d/ -f1)
          echo "Selected interface: $interface with IP $interface_ip"
          break
      else
          echo "Invalid selection. Please try again."
      fi
  done

  # Get the base IP range
  ip_base=$(echo "$interface_ip" | cut -d. -f1-3)

  # Prompt for last octet and construct bridge IP
  last_octet=$(prompt_until_valid "Enter the last octet for the bridge IP (e.g., if IP should be $ip_base.X): ")
  bridge_ip="$ip_base.$last_octet"

  # Propmt for VM IP address
  last_octet=$(prompt_until_valid "Enter the last octet for the VM Host IP (e.g., if IP should be $ip_base.X, but not $bridge_ip): ")
  vm_ip="$ip_base.$last_octet"

  # Propmt for VM Subnet address
  subnet=$(prompt_until_valid "Enter the Subnet (e.g. 255.255.255.0): ")
  vm_subnet="$subnet"

  # Propmt for VM Gateway
  gateway=$(prompt_until_valid "Enter the Gateway (Usually your routers IP-Address): ")
  vm_gateway="$gateway"

  # Propmt for VM Gateway
  dns_server=$(prompt_until_valid "Enter the DNS Server (Usually your routers IP-Address): ")
  vm_dns_server="$dns_server"

  echo "Collected all information create bridge $bridge_name" on interface "$interface" with IP "$bridge_ip"
  echo ""

  sudo brctl addbr "$bridge_name"
  echo "Bridge $bridge_name created."

  # Add selected interface to the bridge
  
  # Attempt to add the interface to the bridge
  if ! sudo brctl addif "$bridge_name" "$interface" 2>/dev/null; then
      echo "Failed to add $interface to bridge $bridge_name. Operation not supported."

      if brctl show | grep -q "^$bridge_name"; then
        sudo brctl delbr "$bridge_name"
        echo "Undo adding $bridge_name"
      fi

      exit 1
  else
      echo "$interface added to bridge $bridge_name successfully."
  fi


  # Add IP to bridge and set it up
  sudo ip addr add "$bridge_ip"/24 dev "$bridge_name"
  sudo ip link set "$bridge_name" up
  echo "IP address $bridge_ip and bridge $bridge_name activated."

  # Add iptables rule for forwarding
  sudo iptables -I FORWARD -m physdev --physdev-is-bridged -j ACCEPT
  echo "IPTables forwarding rule for the bridge added."

  # Save configuration to JSON
  save_config "$bridge_name" "$interface" "$bridge_ip" "$vm_ip" "$vm_subnet" "$vm_gateway" "$vm_dns_server"

  # Update QEMU bridge configuration
  if [[ -f $QEMU_CONFIG_FILE ]]; then
      if ! grep -q "allow $bridge_name" "$QEMU_CONFIG_FILE"; then
          echo "allow $bridge_name" | sudo tee -a "$QEMU_CONFIG_FILE" > /dev/null
          echo "Bridge $bridge_name added to QEMU configuration."
      fi
  fi

  # Set permissions for qemu-bridge-helper if it exists
  if [[ -f $QEMU_HELPER ]]; then
      sudo chmod +s "$QEMU_HELPER"
      echo "Set +s permission for $QEMU_HELPER."
  fi

  create_start_vm_script
  create_access_vm_script

  create_bat_script "$vm_ip" "$vm_subnet" "$vm_gateway" "$vm_dns_server"
}

# Main logic based on user choice
if prompt_action; then
    # Add a new virtual bridge
    add_bridge
else
    # Remove an existing virtual bridge
    remove_bridge
fi
