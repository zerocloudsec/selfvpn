#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please run again with sudo or as root."
    exit 1
fi

# Check if the OS is Debian-based
if ! [ -f /etc/debian_version ]; then
    echo "This script is designed for Debian-based systems only."
    exit 1
fi

# Update and install necessary packages
echo "Updating system and installing necessary packages..."
apt-get update
#apt-get upgrade -y
apt-get install -y curl nano git
echo "System updated and required packages installed."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    echo "Docker installed successfully."
else
    echo "Docker is already installed."
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose is not installed. Installing Docker Compose..."
    apt-get install -y docker-compose
    echo "Docker Compose installed successfully."
else
    echo "Docker Compose is already installed."
fi

# Get the internal IP from the system
INTERNAL_IP=$(hostname -I | awk '{print $1}')

# Get the public IP from an external service
PUBLIC_IP=$(curl -s icanhazip.com)

# Verify that the public IP matches an address in `ip addr`
if ip addr | grep -q "$PUBLIC_IP"; then
    echo "Verified: Public IP ($PUBLIC_IP) exists on this machine."
else
    echo "Error: Public IP ($PUBLIC_IP) does not match any IP on this machine."
    echo "Please check your network configuration."
    exit 1
fi

# Get the password from the user
read -s -p "Enter the password for WireGuard: " USER_PASSWORD
echo
echo "Generating bcrypt hash for the entered password..."
PASSWORD_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$USER_PASSWORD" | tr -d '\r')
PASSWORD_HASH=$(echo "$PASSWORD_HASH" | sed -e "s/^PASSWORD_HASH=//" -e "s/'//g")
ESCAPED_HASH=$(echo "$PASSWORD_HASH" | sed 's/\$/\$\$/g')

# Confirm the details with the user
echo "Configuration Details:"
echo "-----------------------"
echo "Public IP: $PUBLIC_IP"
echo "WireGuard Password: $USER_PASSWORD"
echo "Password Hash: $ESCAPED_HASH"
echo "-----------------------"
read -p "Do you want to proceed with this configuration? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Installation aborted by user."
    exit 1
fi

# Create the docker-compose.yml file
cat <<EOF > docker-compose.yml
volumes:
  etc_wireguard:

services:
  wg-easy:
    environment:
      - LANG=en
      - WG_HOST=$PUBLIC_IP
      - PASSWORD_HASH=$ESCAPED_HASH
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    volumes:
      - etc_wireguard:/etc/wireguard
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF

# Run the Docker Compose service
echo "Starting the WireGuard service..."
docker compose up -d

echo "Installation complete. WireGuard is running!"
