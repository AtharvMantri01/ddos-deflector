#!/bin/bash

# Zentra Host Advanced DDoS Deflector Installer
# Version 1.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/usr/local/zentra"
CONFIG_DIR="/etc/zentra"
BIN_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/zentra-ddos.service"
SCRIPT_NAME="zentra_ddos_deflector.sh"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}[ERROR] This script must be run as root!${NC}"
  exit 1
fi

header() {
  clear
  echo -e "${CYAN}╔════════════════════════════════════════════╗"
  echo -e "║    Zentra Host DDoS Deflector Installer    ║"
  echo -e "╚════════════════════════════════════════════╝${NC}"
  echo
}

# Check system compatibility
check_system() {
  header
  echo -e "${YELLOW}[*] Checking system compatibility...${NC}"
  
  # Check for supported OS
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
  else
    echo -e "${RED}[ERROR] Could not detect OS type.${NC}"
    exit 1
  fi

  echo -e "${GREEN}[+] Detected OS: ${OS} ${OS_VERSION}${NC}"

  # Check for systemd
  if ! command -v systemctl >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Systemd is required but not found.${NC}"
    exit 1
  fi

  echo -e "${GREEN}[+] System is compatible${NC}"
  sleep 2
}

# Install dependencies
install_dependencies() {
  header
  echo -e "${YELLOW}[*] Installing dependencies...${NC}"
  
  # Common dependencies
  DEPS="iptables ipset curl net-tools geoip-bin"

  case $OS in
    "ubuntu"|"debian")
      apt-get update
      apt-get install -y $DEPS
      ;;
    "centos"|"rhel"|"fedora")
      yum install -y $DEPS
      ;;
    *)
      echo -e "${RED}[ERROR] Unsupported OS for automatic dependency installation.${NC}"
      echo -e "${YELLOW}Please manually install: iptables ipset curl net-tools geoip-bin${NC}"
      ;;
  esac

  # Check if dependencies were installed
  for dep in iptables ipset curl netstat; do
    if ! command -v $dep >/dev/null 2>&1; then
      echo -e "${RED}[ERROR] Failed to install $dep${NC}"
      exit 1
    fi
  done

  echo -e "${GREEN}[+] Dependencies installed successfully${NC}"
  sleep 2
}

# Install the script
install_script() {
  header
  echo -e "${YELLOW}[*] Installing Zentra DDoS Deflector...${NC}"

  # Create directories
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
  echo -e "${GREEN}[+] Created directories${NC}"

  # Copy the script
  if [ -f "$SCRIPT_NAME" ]; then
    cp "$SCRIPT_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "$BIN_DIR/zentra-ddos"
    echo -e "${GREEN}[+] Script installed to $INSTALL_DIR/${NC}"
  else
    echo -e "${RED}[ERROR] Could not find $SCRIPT_NAME in current directory${NC}"
    exit 1
  fi

  # Create default config files
  cat > "$CONFIG_DIR/zentra_whitelist.txt" <<EOF
# Add whitelisted IPs here (one per line)
# Example:
# 192.168.1.1
# 10.0.0.1
EOF

  cat > "$CONFIG_DIR/advanced_rules.conf" <<EOF
# Advanced DDoS Protection Rules
# Format: rule_type,pattern,action,rate_limit
http,User-Agent: (wget|curl|python),block,10/60
http,GET /wp-admin,block,5/60
http,POST /xmlrpc.php,block,2/60
tcp,flags=SYN,check_syn,50/10
udp,,check_udp,200/10
EOF

  echo -e "${GREEN}[+] Configuration files created${NC}"
  sleep 2
}

# Create systemd service
create_service() {
  header
  echo -e "${YELLOW}[*] Creating systemd service...${NC}"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Zentra Host Advanced DDoS Deflector
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/zentra-ddos
Restart=always
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable zentra-ddos >/dev/null 2>&1

  echo -e "${GREEN}[+] Systemd service created and enabled${NC}"
  sleep 2
}

# Post-install instructions
post_install() {
  header
  echo -e "${CYAN}╔════════════════════════════════════════════╗"
  echo -e "║    Installation Complete!               ║"
  echo -e "╚════════════════════════════════════════════╝${NC}"
  echo
  echo -e "${GREEN}Zentra Host Advanced DDoS Deflector has been installed successfully!${NC}"
  echo
  echo -e "${YELLOW}Next steps:${NC}"
  echo -e "1. Configure your Discord webhook in $INSTALL_DIR/$SCRIPT_NAME"
  echo -e "2. Add whitelisted IPs to $CONFIG_DIR/zentra_whitelist.txt"
  echo -e "3. Review advanced rules in $CONFIG_DIR/advanced_rules.conf"
  echo
  echo -e "${YELLOW}Management commands:${NC}"
  echo -e "Start service:    ${CYAN}systemctl start zentra-ddos${NC}"
  echo -e "Stop service:     ${CYAN}systemctl stop zentra-ddos${NC}"
  echo -e "View status:      ${CYAN}systemctl status zentra-ddos${NC}"
  echo -e "Interactive mode: ${CYAN}zentra-ddos${NC}"
  echo
  echo -e "${YELLOW}Would you like to start the service now? [y/N]${NC}"
  read -n1 start_now
  echo

  if [[ "$start_now" =~ [yY] ]]; then
    systemctl start zentra-ddos
    echo -e "${GREEN}[+] Service started successfully!${NC}"
    echo -e "You can check the status with: ${CYAN}systemctl status zentra-ddos${NC}"
  else
    echo -e "${YELLOW}You can start the service later with: ${CYAN}systemctl start zentra-ddos${NC}"
  fi

  echo
  echo -e "${GREEN}Installation complete!${NC}"
}

# Main installation process
main() {
  check_system
  install_dependencies
  install_script
  create_service
  post_install
}

# Start installation
main