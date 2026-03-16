#!/bin/bash
# WireGuard VPN Installation Script
# For Debian/Ubuntu VPS
# Version: 1.0.0

set -e

# Script directory (resolve symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
export MAIN_SCRIPT_DIR="${SCRIPT_DIR}"

# Source libraries
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/core.sh"

# Load configuration
load_config

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
░██╗░░░░░░░██╗░██████╗░   ████████╗░█████╗░░█████╗░██╗░░░░░
░██║░░██╗░░██║██╔════╝░   ╚══██╔══╝██╔══██╗██╔══██╗██║░░░░░
░╚██╗████╗██╔╝██║░░██╗░   ░░░██║░░░██║░░██║██║░░██║██║░░░░░
░░████╔═████║░██║░░╚██╗   ░░░██║░░░██║░░██║██║░░██║██║░░░░░
░░╚██╔╝░╚██╔╝░╚██████╔╝   ░░░██║░░░╚█████╔╝╚█████╔╝███████╗
░░░╚═╝░░░╚═╝░░░╚═════╝░   ░░░╚═╝░░░░╚════╝░░╚════╝░╚══════╝
                                              
EOF
    echo -e "${NC}"
    echo -e "${DIM}VPN Server Installation Script for Debian/Ubuntu${NC}"
    echo -e "${DIM}Version 1.0.0${NC}"
    echo ""
}

# Check root
check_root

# Detect OS
detect_os

# Installation menu
installation_menu() {
    show_banner
    
    echo -e "${BOLD}Installation Options:${NC}"
    echo ""
    echo "  1) Install WireGuard VPN Server"
    echo "  2) Install WireGuard + Management Tools"
    echo "  3) Install Management Tools Only"
    echo "  4) Quick Install (Recommended settings)"
    echo ""
    echo "  0) Exit"
    echo ""
    
    read -rp "$(echo -e "${CYAN}Select option [0-4]: ${NC}")" choice
    
    case "${choice}" in
        1) install_wireguard_only ;;
        2) install_full ;;
        3) install_management_only ;;
        4) quick_install ;;
        0) exit 0 ;;
        *) print_error "Invalid option"; installation_menu ;;
    esac
}

# Install WireGuard only
install_wireguard_only() {
    print_header "Installing WireGuard"
    
    install_dependencies
    generate_server_keys
    configure_wireguard
    configure_network
    enable_services
    
    print_success "WireGuard installation completed!"
    show_installation_summary
}

# Install WireGuard + Management Tools
install_full() {
    print_header "Full Installation"
    
    # Configure settings first
    configure_installation
    
    # Install WireGuard
    install_dependencies
    generate_server_keys
    configure_wireguard
    configure_network
    enable_services
    
    # Setup management tools
    setup_management_tools
    
    print_success "Full installation completed!"
    show_installation_summary
}

# Install management tools only
install_management_only() {
    print_header "Installing Management Tools"
    
    # Check if WireGuard is installed
    if ! is_wireguard_installed; then
        print_error "WireGuard is not installed. Please install WireGuard first."
        return 1
    fi
    
    setup_management_tools
    
    print_success "Management tools installed!"
}

# Quick install with recommended settings
quick_install() {
    print_header "Quick Install (Recommended Settings)"
    
    echo -e "${DIM}Using recommended settings:${NC}"
    echo "  - Port: 51820"
    echo "  - Subnet: 10.66.66.0/24"
    echo "  - DNS: Cloudflare (1.1.1.1)"
    echo ""
    
    if ! confirm_action "Continue with these settings?"; then
        installation_menu
        return
    fi
    
    # Use default settings
    WG_PORT="51820"
    WG_SUBNET="10.66.66.0/24"
    WG_SERVER_IP="10.66.66.1"
    WG_DNS="1.1.1.1, 8.8.8.8"
    
    # Get public interface
    SERVER_PUB_NIC=$(get_default_interface)
    SERVER_PUB_IP=$(get_public_ip)
    
    # Install
    install_dependencies
    generate_server_keys
    configure_wireguard
    configure_network
    enable_services
    setup_management_tools
    
    print_success "Quick installation completed!"
    show_installation_summary
}

# Configure installation settings
configure_installation() {
    print_header "Configuration"
    
    # Get public IP
    SERVER_PUB_IP=$(get_public_ip)
    read -rp "$(echo -e "${CYAN}Public IP [${SERVER_PUB_IP}]: ${NC}")" input
    SERVER_PUB_IP="${input:-${SERVER_PUB_IP}}"
    
    # Get network interface
    SERVER_PUB_NIC=$(get_default_interface)
    read -rp "$(echo -e "${CYAN}Network interface [${SERVER_PUB_NIC}]: ${NC}")" input
    SERVER_PUB_NIC="${input:-${SERVER_PUB_NIC}}"
    
    # Get port
    read -rp "$(echo -e "${CYAN}WireGuard port [${WG_PORT}]: ${NC}")" input
    WG_PORT="${input:-${WG_PORT}}"
    
    # Get subnet
    read -rp "$(echo -e "${CYAN}VPN subnet [${WG_SUBNET}]: ${NC}")" input
    WG_SUBNET="${input:-${WG_SUBNET}}"
    
    # Calculate server IP from subnet
    WG_SERVER_IP="${WG_SUBNET%.*}.1"
    
    # Get DNS servers
    read -rp "$(echo -e "${CYAN}DNS servers [${WG_DNS}]: ${NC}")" input
    WG_DNS="${input:-${WG_DNS}}"
    
    echo ""
    print_info "Configuration summary:"
    echo "  Public IP: ${SERVER_PUB_IP}"
    echo "  Interface: ${SERVER_PUB_NIC}"
    echo "  Port: ${WG_PORT}"
    echo "  Subnet: ${WG_SUBNET}"
    echo "  Server IP: ${WG_SERVER_IP}"
    echo "  DNS: ${WG_DNS}"
    echo ""
    
    if ! confirm_action "Is this correct?"; then
        configure_installation
    fi
}

# Install dependencies
install_dependencies() {
    print_info "Installing dependencies..."
    
    # Update package list
    apt-get update -qq
    
    # Install required packages
    apt-get install -y \
        wireguard \
        wireguard-tools \
        qrencode \
        iptables \
        curl \
        jq \
        bc \
        dnsutils \
        net-tools
    
    # Install haveged for entropy (optional)
    apt-get install -y haveged 2>/dev/null || true
    
    # Check if WireGuard kernel module is available
    if ! modprobe wireguard 2>/dev/null; then
        print_warning "WireGuard kernel module not available. Trying to install..."
        
        # Try to install kernel headers and wireguard-dkms
        apt-get install -y linux-headers-$(uname -r) wireguard-dkms 2>/dev/null || true
        
        # Try loading module again
        modprobe wireguard 2>/dev/null || print_warning "Could not load WireGuard kernel module. It may be built into the kernel."
    fi
    
    print_success "Dependencies installed"
}

# Generate server keys
generate_server_keys() {
    print_info "Generating server keys..."
    
    # Create keys directory
    mkdir -p "${WG_KEYS_DIR}/server"
    chmod 700 "${WG_KEYS_DIR}"
    chmod 700 "${WG_KEYS_DIR}/server"
    
    # Set secure umask for key generation
    local old_umask=$(umask)
    umask 077
    
    # Generate server keys
    wg genkey > "${WG_KEYS_DIR}/server/private.key"
    wg pubkey < "${WG_KEYS_DIR}/server/private.key" > "${WG_KEYS_DIR}/server/public.key"
    
    # Restore umask
    umask ${old_umask}
    
    print_success "Server keys generated"
}

# Configure WireGuard
configure_wireguard() {
    print_info "Configuring WireGuard..."
    
    # Create WireGuard directory
    mkdir -p /etc/wireguard
    chmod 700 /etc/wireguard
    
    # Get server private key
    local server_private_key=$(cat "${WG_KEYS_DIR}/server/private.key")
    
    # Calculate subnet prefix (e.g., 24 from 10.66.66.0/24)
    local subnet_prefix="${WG_SUBNET##*/}"
    
    # Create server configuration
    cat > "/etc/wireguard/${WG_INTERFACE}.conf" << EOF
[Interface]
Address = ${WG_SERVER_IP}/${subnet_prefix}
ListenPort = ${WG_PORT}
PrivateKey = ${server_private_key}
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
SaveConfig = true

EOF
    
    chmod 600 "/etc/wireguard/${WG_INTERFACE}.conf"
    
    # Validate configuration by checking if wg can parse it
    if wg showconf "${WG_INTERFACE}" > /dev/null 2>&1 || [[ -f "/etc/wireguard/${WG_INTERFACE}.conf" ]]; then
        print_success "WireGuard configured"
    else
        print_warning "Configuration created but may have issues. Check /etc/wireguard/${WG_INTERFACE}.conf"
    fi
}

# Configure network
configure_network() {
    print_info "Configuring network..."
    
    # Enable IP forwarding
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
    
    sysctl -p > /dev/null 2>&1
    
    # Configure firewall
    if command_exists ufw; then
        ufw allow "${WG_PORT}/udp" > /dev/null 2>&1
        ufw allow OpenSSH > /dev/null 2>&1
        echo "y" | ufw enable > /dev/null 2>&1
    elif command_exists iptables; then
        iptables -A INPUT -p udp --dport "${WG_PORT}" -j ACCEPT
        iptables -A FORWARD -i "${WG_INTERFACE}" -j ACCEPT
        iptables -A FORWARD -o "${WG_INTERFACE}" -j ACCEPT
        iptables -t nat -A POSTROUTING -o "${SERVER_PUB_NIC}" -j MASQUERADE
        
        # Save rules
        if command_exists iptables-save; then
            iptables-save > /etc/iptables.rules
            
            # Create restore script
            cat > /etc/network/if-pre-up.d/iptables << 'EOF'
#!/bin/bash
iptables-restore < /etc/iptables.rules
EOF
            chmod +x /etc/network/if-pre-up.d/iptables
        fi
    fi
    
    print_success "Network configured"
}

# Enable services
enable_services() {
    print_info "Enabling services..."
    
    # Enable WireGuard
    systemctl enable "wg-quick@${WG_INTERFACE}" > /dev/null 2>&1
    
    # Start WireGuard and capture any errors
    local start_output=$(systemctl start "wg-quick@${WG_INTERFACE}" 2>&1)
    local start_exit=$?
    
    # Wait for interface to come up
    sleep 2
    
    # Check if service is active
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        print_success "WireGuard service started"
    else
        print_warning "WireGuard service may have issues. Checking status..."
        systemctl status "wg-quick@${WG_INTERFACE}" --no-pager -l 2>/dev/null | head -20
        echo ""
        print_info "You can check logs with: journalctl -u wg-quick@${WG_INTERFACE} -n 50"
    fi
    
    # Enable haveged for entropy (optional, don't fail if not available)
    if command_exists haveged; then
        systemctl enable haveged > /dev/null 2>&1
        systemctl start haveged > /dev/null 2>&1
    fi
    
    print_success "Services configuration completed"
}

# Setup management tools
setup_management_tools() {
    print_info "Setting up management tools..."
    
    # Create manager directory structure
    mkdir -p "${WG_MANAGER_DIR}"
    mkdir -p "${WG_USERS_DIR}"
    mkdir -p "${WG_BACKUP_DIR}"
    mkdir -p "${WG_LOG_DIR}"
    mkdir -p "${USAGE_LOG_DIR}"
    chmod 700 "${WG_MANAGER_DIR}"
    
    # Initialize files
    touch "${USER_DB}"
    touch "${USED_IPS_FILE}"
    touch "${LOG_FILE}"
    chmod 600 "${USER_DB}"
    
    # Copy configuration
    cp "${SCRIPT_DIR}/config/default.conf" "${SYSTEM_CONFIG}"
    
    # Update configuration with actual values
    sed -i "s|SERVER_PUB_IP=\"\"|SERVER_PUB_IP=\"${SERVER_PUB_IP}\"|g" "${SYSTEM_CONFIG}"
    sed -i "s|SERVER_PUB_NIC=\"eth0\"|SERVER_PUB_NIC=\"${SERVER_PUB_NIC}\"|g" "${SYSTEM_CONFIG}"
    
    # Create symlink for easy access
    ln -sf "${SCRIPT_DIR}/wg-manager.sh" /usr/local/bin/wg-manager
    
    # Create systemd service for monitoring
    cat > /etc/systemd/system/wg-monitor.service << EOF
[Unit]
Description=WireGuard Usage Monitor
After=wg-quick@${WG_INTERFACE}.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do ${SCRIPT_DIR}/wg-manager.sh --record-usage; sleep 60; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    print_success "Management tools installed"
}

# Show installation summary
show_installation_summary() {
    print_header "Installation Summary"
    
    local server_public_key=$(cat "${WG_KEYS_DIR}/server/public.key" 2>/dev/null || echo "N/A")
    
    # Check actual service status
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} WireGuard installed and running"
    else
        echo -e "${YELLOW}⚠${NC} WireGuard installed but not running"
    fi
    echo -e "${GREEN}✓${NC} Server configured on port ${WG_PORT}"
    echo -e "${GREEN}✓${NC} IP forwarding enabled"
    echo -e "${GREEN}✓${NC} Firewall configured"
    echo ""
    
    echo -e "${BOLD}Server Information:${NC}"
    echo "  Public IP:      ${SERVER_PUB_IP}"
    echo "  Port:           ${WG_PORT}"
    echo "  Interface:      ${WG_INTERFACE}"
    echo "  Server IP:      ${WG_SERVER_IP}"
    echo "  Subnet:         ${WG_SUBNET}"
    echo ""
    
    echo -e "${BOLD}Server Public Key:${NC}"
    echo "  ${server_public_key}"
    echo ""
    
    echo -e "${BOLD}Management:${NC}"
    echo "  Run: wg-manager"
    echo "  Or: ${SCRIPT_DIR}/wg-manager.sh"
    echo ""
    
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Run 'wg-manager' to open the management interface"
    echo "  2. Add your first user with option '1' in User Management"
    echo "  3. Configure Telegram bot (optional) in Server Management"
    echo ""
    
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}" 2>/dev/null; then
        print_success "WireGuard is running!"
    else
        print_warning "WireGuard service is not running."
        echo ""
        echo -e "${DIM}To start it manually:${NC}"
        echo "  sudo systemctl start wg-quick@${WG_INTERFACE}"
        echo ""
        echo -e "${DIM}To check logs:${NC}"
        echo "  sudo journalctl -u wg-quick@${WG_INTERFACE} -n 50"
        echo ""
        echo -e "${DIM}To check status:${NC}"
        echo "  sudo systemctl status wg-quick@${WG_INTERFACE}"
    fi
}

# Uninstall
uninstall() {
    print_header "Uninstall WireGuard"
    
    print_warning "This will remove WireGuard and all configurations!"
    
    if ! confirm_action "Are you sure you want to continue?"; then
        return 1
    fi
    
    # Create backup first
    print_info "Creating final backup..."
    
    # Ensure backup directory exists
    mkdir -p "${WG_BACKUP_DIR}" 2>/dev/null || WG_BACKUP_DIR="/root/wg-backups"
    mkdir -p "${WG_BACKUP_DIR}" 2>/dev/null
    
    local backup_file="${WG_BACKUP_DIR}/final_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    # Create backup of WireGuard config
    if [[ -d /etc/wireguard ]]; then
        tar -czf "${backup_file}" -C /etc wireguard 2>/dev/null
    fi
    
    # Add manager data to backup
    if [[ -d "${WG_MANAGER_DIR}" ]]; then
        if [[ -f "${backup_file}" ]]; then
            tar -czf "${backup_file}.tmp" -C "${WG_MANAGER_DIR}" . 2>/dev/null
            tar -czf "${backup_file}" --concatenate --file="${backup_file}" "${backup_file}.tmp" 2>/dev/null || true
            rm -f "${backup_file}.tmp" 2>/dev/null
        else
            tar -czf "${backup_file}" -C "${WG_MANAGER_DIR}" . 2>/dev/null
        fi
    fi
    
    if [[ -f "${backup_file}" ]]; then
        print_success "Backup created: ${backup_file}"
    else
        print_warning "Backup creation failed, continuing with uninstall..."
    fi
    
    print_info "Stopping services..."
    
    # Stop services
    systemctl stop "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
    systemctl disable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
    systemctl stop wg-monitor 2>/dev/null || true
    systemctl disable wg-monitor 2>/dev/null || true
    systemctl stop wg-telegram 2>/dev/null || true
    systemctl disable wg-telegram 2>/dev/null || true
    
    print_info "Removing packages..."
    
    # Remove packages
    apt-get remove --purge -y wireguard wireguard-tools 2>/dev/null || true
    
    print_info "Cleaning up configuration..."
    
    # Remove configurations
    rm -rf /etc/wireguard 2>/dev/null || true
    rm -rf "${WG_MANAGER_DIR}" 2>/dev/null || true
    rm -f /etc/systemd/system/wg-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/wg-telegram.service 2>/dev/null || true
    rm -f /usr/local/bin/wg-manager 2>/dev/null || true
    
    # Remove firewall rules
    if command_exists ufw; then
        ufw delete allow "${WG_PORT}/udp" 2>/dev/null || true
    fi
    
    systemctl daemon-reload 2>/dev/null || true
    
    print_success "WireGuard has been uninstalled"
    if [[ -f "${backup_file}" ]]; then
        print_info "Backup saved to: ${backup_file}"
    fi
}

# Main
main() {
    case "${1}" in
        --install)
            quick_install
            ;;
        --uninstall)
            uninstall
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --install      Quick install with recommended settings"
            echo "  --uninstall    Uninstall WireGuard"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "Run without options for interactive menu."
            ;;
        *)
            installation_menu
            ;;
    esac
}

# Run main
main "$@"
