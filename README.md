# Bridge Setup Script for Virtual Machines

This script configures a bridge network on a Linux host to allow virtual machines to connect through the host's network interface, with options for adding or removing bridges. It creates a JSON-based configuration to store bridge details and provides auxiliary scripts for starting and accessing virtual machines through the configured bridge.

## Prerequisites

### Required VM Disk Image

To run a virtual machine, download a compatible VM disk image file (e.g., a `.qcow2` format image). You can obtain one from a source like [Example Disk Image Repository](https://example.com/your-disk-image). Once downloaded, save the image as `disk.img` in the root directory of this project (same location as `setup.sh`).

Example:

```bash
/path/to/this/directory/
├── setup.sh
├── disk.img     # Place the VM image file here
└── bridge_config.json
```

### Required Tools

The script requires the following tools and commands:

- `brctl`: for bridge management. Install with `sudo apt install bridge-utils`.
- `iptables`: for managing firewall rules. Install with `sudo apt install iptables`.
- `ip`: for IP configuration. Install with `sudo apt install iproute2`.
- `jq`: for JSON processing. Install with `sudo apt install jq`.
- `qemu-system-x86_64`: for running VMs with QEMU. Install with `sudo apt install qemu`.
- `wlfreerdp`: for accessing VMs using FreeRDP (optional but recommended for RDP-based access).

Ensure all dependencies are installed before running the script.

## Script Structure

### Key Files and Directories

- **`bridge_config.json`**: Stores bridge configuration details.
- **`start_vm.sh`**: Script to start a VM and connect it to a selected bridge.
- **`access_vm.sh`**: Script to access a running VM using FreeRDP.
- **`configure_network.bat`**: Windows batch script to configure network settings if connecting from a Windows VM.

### Usage

1. **Running the Script**: Execute `./setup.sh` in a terminal.

   - The script checks if dependencies are installed. Missing dependencies will prompt a message to install them.

2. **Setting Up a Bridge**:

   - The script will prompt for bridge configuration if no bridges exist.
   - You will need to provide the following details:
     - **Bridge Name**: Name of the network bridge.
     - **Host Interface**: Select from available network interfaces on the host.
     - **Bridge IP**: IP address for the bridge.
     - **VM IP, Subnet, Gateway, DNS Server**: Settings for VMs to use the bridge.

3. **Removing a Bridge**:

   - If bridges are already configured, you can choose to remove an existing bridge.
   - The script will display configured bridges to select from.

4. **Starting a VM**:

   - Run `./bin/start_vm.sh` to start a VM connected to a configured bridge.
   - You will be prompted to select a bridge for the VM network.
   - Ensure `disk.img` exists in the root directory of the script for the VM disk image.

5. **Accessing a VM**:
   - Run `./bin/access_vm.sh` to access a running VM using FreeRDP.
   - The script lists available bridges and prompts for a selection.
   - FreeRDP will connect to the VM's IP over the selected bridge.

## Configurations and Files

### JSON Configuration (`bridge_config.json`)

Each bridge configuration includes:

- `bridge_name`: The name of the bridge.
- `interface`: The host interface to bridge.
- `ip_address`: IP address assigned to the bridge.
- `vm_ip_address`: The VM’s IP address on this bridge.
- `vm_subnet`: Subnet mask.
- `vm_gateway`: Gateway IP for routing.
- `vm_dns_server`: DNS server IP for name resolution.

### Batch Script (`configure_network.bat`)

For VMs using Windows, this batch script automates network configuration:

- Sets a static IP, subnet, gateway, and DNS based on the bridge configuration.
- Adjusts the network interface `Ethernet`. Update as needed if your network interface name differs.

---

## Detailed Setup and Usage Guide

### Step 1: Script Execution

1. **Starting the Setup**:

   - Run the script with `./setup.sh`.
   - This will check for all required commands and tools. If any are missing, the script will notify you and suggest how to install them.
   - The script sets up essential directories and configuration files if they don’t already exist, creating a clean environment for bridge management and VM networking.

2. **Configuration Management**:
   - The configuration data for each bridge is stored in `bridge_config.json`. This JSON file allows the script to keep track of the bridges, IPs, and network settings that you specify.
   - If a bridge is added or removed, the script updates this file automatically, ensuring you always have an up-to-date configuration.

### Step 2: Adding a New Bridge

1. **Entering Network Bridge Details**:

   - When adding a bridge, you will be prompted to provide several pieces of information:
     - **Bridge Name**: A custom name for your network bridge. This name should be unique and descriptive for easier management.
     - **Network Interface**: You’ll choose from the available network interfaces on your host (e.g., `eth0`, `wlan0`), which will serve as the foundation for the bridge. The script lists interfaces with IPv4 addresses, making it easier to pick the correct one.

2. **IP Configuration for the Bridge**:

   - **Bridge IP Address**: You will specify an IP address for the bridge. This IP is typically on the same subnet as the host machine’s network.
   - **VM Network Settings**: You’ll specify the following for the VMs connected to this bridge:
     - **VM IP Address**: The IP address that VMs will use on this bridge. It should be in the same subnet as the bridge but unique from other devices to avoid conflicts.
     - **Subnet Mask, Gateway, and DNS Server**: These are essential for the VM’s networking, defining the subnet range, the gateway for external network access, and the DNS server for domain resolution.

3. **Bridge Creation**:
   - The script then:
     - Uses `brctl` to create the bridge.
     - Adds the selected network interface to this bridge.
     - Configures the IP address and enables the bridge.
   - **IPTables Rule**: Adds a rule in `iptables` to allow traffic forwarding across the bridge.
   - Updates the **QEMU Configuration** (`/etc/qemu/bridge.conf`) to allow QEMU to use the new bridge for VM networking.

### Step 3: Removing an Existing Bridge

1. **Selection of Bridge for Removal**:

   - The script lists all currently configured bridges, displaying their names, associated interfaces, and IP addresses.
   - You select the bridge you wish to remove based on this list.

2. **Bridge Cleanup**:
   - Upon selection, the script:
     - Removes the IP address from the bridge.
     - Brings down and deletes the bridge using `brctl`.
     - Deletes the associated IP forwarding rule from `iptables`.
   - It also updates `bridge_config.json` to remove the bridge entry.
   - If no other bridges exist after removal, the script removes the special permissions on `qemu-bridge-helper`, reverting the setup to its default state.

### Step 4: Starting a Virtual Machine

1. **VM Start Script (`start_vm.sh`)**:
   - The `start_vm.sh` script is generated by `setup.sh` and located in the `bin` directory. It provides a straightforward way to start a VM with QEMU.
   - The script:
     - Lists available bridges stored in `bridge_config.json`, so you can select one.
     - Launches a VM with QEMU, specifying various options like memory, CPU, and disk. The `-netdev` option is configured to attach the VM to the selected bridge, allowing it to communicate over the network via this bridge.

### Step 5: Accessing a Virtual Machine

1. **VM Access Script (`access_vm.sh`)**:

   - This script enables remote access to the VM through RDP (Remote Desktop Protocol) if the VM is running an RDP-compatible OS (e.g., Windows).
   - It:
     - Lists bridges along with the configured VM IP addresses.
     - Prompts you to select a bridge.
     - Uses `wlfreerdp` to initiate an RDP connection to the selected VM IP.

2. **Customizing FreeRDP Parameters**:
   - You can adjust `DESKTOP_SCALE` and other FreeRDP parameters directly in `access_vm.sh` if needed (e.g., to change display resolution, color depth, or performance settings).

### Step 6: Windows Network Configuration (Optional)

1. **Windows Configuration Script (`configure_network.bat`)**:
   - This batch script, created for Windows VMs, configures static IP, subnet, gateway, and DNS settings based on the bridge configuration.
   - Run this script within the Windows VM to apply the network settings, allowing the VM to seamlessly connect through the bridge.
   - **Adjustable Interface Name**: By default, the script uses `Ethernet` as the interface name. Update it if your network adapter has a different name in Windows.
