#!/bin/bash
# Core Functions for WireGuard Manager
# Configuration loading, initialization, and core operations

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# Default configuration file
DEFAULT_CONFIG="${PROJECT_DIR}/config/default.conf"
SYSTEM_CONFIG="/etc/wireguard-manager/config.conf"

# Load configuration
load_config() {
    # Load default config first
    if [[ -f "${DEFAULT_CONFIG}" ]]; then
        source "${DEFAULT_CONFIG}"
        print_debug "Loaded default configuration"
    else
        print_error "Default configuration not found: ${DEFAULT_CONFIG}"
        exit 1
    fi
    
    # Override with system config if exists
    if [[ -f "${SYSTEM_CONFIG}" ]]; then
        source "${SYSTEM_CONFIG}"
        print_debug "Loaded system configuration"
    fi
    
    # Create required directories
    create_directories
}

# Create required directories
create_directories() {
    local dirs=(
        "${WG_MANAGER_DIR}"
        "${WG_USERS_DIR}"
        "${WG_BACKUP_DIR}"
        "${WG_LOG_DIR}"
        "${WG_KEYS_DIR}"
        "${USAGE_LOG_DIR}"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            mkdir -p "${dir}"
            chmod 700 "${dir}"
            print_debug "Created directory: ${dir}"
        fi
    done
    
    # Initialize files if they don't exist
    touch "${USER_DB}" 2>/dev/null
    touch "${USED_IPS_FILE}" 2>/dev/null
    touch "${LOG_FILE}" 2>/dev/null
    
    chmod 600 "${USER_DB}" 2>/dev/null
    chmod 600 "${USED_IPS_FILE}" 2>/dev/null
}

# Initialize WireGuard manager
init_manager() {
    print_info "Initializing WireGuard Manager..."
    
    # Load configuration
    load_config
    
    # Detect OS
    detect_os
    
    # Get network interface
    if [[ -z "${SERVER_PUB_NIC}" ]]; then
        SERVER_PUB_NIC=$(get_default_interface)
    fi
    
    # Get public IP
    if [[ -z "${SERVER_PUB_IP}" ]]; then
        SERVER_PUB_IP=$(get_public_ip)
    fi
    
    # Log initialization
    log_message "INFO" "WireGuard Manager initialized"
    
    print_debug "Server Public IP: ${SERVER_PUB_IP}"
    print_debug "Server Interface: ${SERVER_PUB_NIC}"
    print_debug "WireGuard Interface: ${WG_INTERFACE}"
}

# Check if WireGuard is installed
is_wireguard_installed() {
    command_exists wg && command_exists wg-quick
}

# Check if WireGuard is running
is_wireguard_running() {
    if [[ -f "/sys/class/net/${WG_INTERFACE}/operstate" ]]; then
        local state=$(cat "/sys/class/net/${WG_INTERFACE}/operstate" 2>/dev/null)
        [[ "${state}" == "up" ]]
    else
        return 1
    fi
}

# Get WireGuard status
get_wireguard_status() {
    if is_wireguard_running; then
        echo -e "${GREEN}● Active${NC}"
    elif is_wireguard_installed; then
        echo -e "${YELLOW}● Installed (Not Running)${NC}"
    else
        echo -e "${RED}● Not Installed${NC}"
    fi
}

# Start WireGuard
start_wireguard() {
    print_info "Starting WireGuard interface ${WG_INTERFACE}..."
    
    if wg-quick up "${WG_INTERFACE}" 2>/dev/null; then
        print_success "WireGuard started successfully"
        log_message "INFO" "WireGuard interface ${WG_INTERFACE} started"
        return 0
    else
        print_error "Failed to start WireGuard"
        log_message "ERROR" "Failed to start WireGuard interface ${WG_INTERFACE}"
        return 1
    fi
}

# Stop WireGuard
stop_wireguard() {
    print_info "Stopping WireGuard interface ${WG_INTERFACE}..."
    
    if wg-quick down "${WG_INTERFACE}" 2>/dev/null; then
        print_success "WireGuard stopped successfully"
        log_message "INFO" "WireGuard interface ${WG_INTERFACE} stopped"
        return 0
    else
        print_error "Failed to stop WireGuard"
        log_message "ERROR" "Failed to stop WireGuard interface ${WG_INTERFACE}"
        return 1
    fi
}

# Restart WireGuard
restart_wireguard() {
    print_info "Restarting WireGuard interface ${WG_INTERFACE}..."
    
    stop_wireguard
    sleep 2
    start_wireguard
}

# Reload WireGuard configuration (without downtime)
reload_wireguard() {
    print_info "Reloading WireGuard configuration..."
    
    if wg syncconf "${WG_INTERFACE}" <(wg-quick strip "${WG_INTERFACE}" 2>/dev/null) 2>/dev/null; then
        print_success "Configuration reloaded"
        log_message "INFO" "WireGuard configuration reloaded"
        return 0
    else
        print_warning "Hot reload failed, performing restart..."
        restart_wireguard
    fi
}

# Generate WireGuard keys
generate_keys() {
    local name="$1"
    local key_dir="${WG_KEYS_DIR}/${name}"
    
    mkdir -p "${key_dir}"
    
    # Generate private key
    wg genkey > "${key_dir}/private.key"
    chmod 600 "${key_dir}/private.key"
    
    # Generate public key from private key
    cat "${key_dir}/private.key" | wg pubkey > "${key_dir}/public.key"
    
    # Generate preshared key for additional security
    wg genpsk > "${key_dir}/preshared.key"
    chmod 600 "${key_dir}/preshared.key"
    
    print_debug "Generated keys for ${name}"
}

# Get key value
get_key() {
    local name="$1"
    local key_type="$2"  # private, public, preshared
    local key_file="${WG_KEYS_DIR}/${name}/${key_type}.key"
    
    if [[ -f "${key_file}" ]]; then
        cat "${key_file}"
    else
        print_error "Key not found: ${key_file}"
        return 1
    fi
}

# Delete keys
delete_keys() {
    local name="$1"
    local key_dir="${WG_KEYS_DIR}/${name}"
    
    if [[ -d "${key_dir}" ]]; then
        rm -rf "${key_dir}"
        print_debug "Deleted keys for ${name}"
    fi
}

# Get server public key
get_server_public_key() {
    local key_file="${WG_KEYS_DIR}/server/public.key"
    
    if [[ -f "${key_file}" ]]; then
        cat "${key_file}"
    else
        print_error "Server public key not found. Run installation first."
        return 1
    fi
}

# Get server private key
get_server_private_key() {
    local key_file="${WG_KEYS_DIR}/server/private.key"
    
    if [[ -f "${key_file}" ]]; then
        cat "${key_file}"
    else
        print_error "Server private key not found. Run installation first."
        return 1
    fi
}

# Generate server configuration
generate_server_config() {
    local server_private_key=$(get_server_private_key)
    
    if [[ -z "${server_private_key}" ]]; then
        print_error "Cannot generate server config: missing private key"
        return 1
    fi
    
    cat > "/etc/wireguard/${WG_INTERFACE}.conf" << EOF
[Interface]
Address = ${WG_SERVER_IP}/${WG_SUBNET##*/}
ListenPort = ${WG_PORT}
PrivateKey = ${server_private_key}
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
SaveConfig = ${SAVE_CONFIG}

EOF
    
    chmod 600 "/etc/wireguard/${WG_INTERFACE}.conf"
    print_debug "Generated server configuration"
}

# Add peer to server config
add_peer_to_config() {
    local username="$1"
    local public_key="$2"
    local preshared_key="$3"
    local allowed_ip="$4"
    
    cat >> "/etc/wireguard/${WG_INTERFACE}.conf" << EOF

# User: ${username}
[Peer]
PublicKey = ${public_key}
PresharedKey = ${preshared_key}
AllowedIPs = ${allowed_ip}/32

EOF
    
    print_debug "Added peer ${username} to server config"
}

# Remove peer from server config
remove_peer_from_config() {
    local username="$1"
    local config_file="/etc/wireguard/${WG_INTERFACE}.conf"
    
    if [[ -f "${config_file}" ]]; then
        backup_file "${config_file}"
        
        # Remove the peer section for this user
        sed -i "/# User: ${username}/,/^$/d" "${config_file}"
        
        print_debug "Removed peer ${username} from server config"
    fi
}

# Get peer info from wg show
get_peer_info() {
    local public_key="$1"
    wg show "${WG_INTERFACE}" dump | grep "^${public_key}"
}

# Get all peers
get_all_peers() {
    wg show "${WG_INTERFACE}" dump | tail -n +2
}

# Check if peer is connected
is_peer_connected() {
    local public_key="$1"
    local peer_info=$(get_peer_info "${public_key}")
    
    if [[ -n "${peer_info}" ]]; then
        local last_handshake=$(echo "${peer_info}" | awk '{print $5}')
        # Consider connected if handshake within last 3 minutes (180 seconds)
        [[ ${last_handshake} -lt 180 && ${last_handshake} -gt 0 ]]
    else
        return 1
    fi
}

# Enable IP forwarding
enable_ip_forwarding() {
    # IPv4
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    # IPv6 (optional)
    if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
    
    sysctl -p >/dev/null 2>&1
    print_debug "IP forwarding enabled"
}

# Configure firewall
configure_firewall() {
    local port="${WG_PORT}"
    
    print_info "Configuring firewall for port ${port}..."
    
    if command_exists ufw; then
        # UFW (Ubuntu/Debian)
        ufw allow "${port}/udp" >/dev/null 2>&1
        ufw allow OpenSSH >/dev/null 2>&1
        echo "y" | ufw enable >/dev/null 2>&1
        print_debug "UFW configured"
    elif command_exists iptables; then
        # iptables
        iptables -A INPUT -p udp --dport "${port}" -j ACCEPT
        iptables -A FORWARD -i "${WG_INTERFACE}" -j ACCEPT
        iptables -A FORWARD -o "${WG_INTERFACE}" -j ACCEPT
        iptables -t nat -A POSTROUTING -o "${SERVER_PUB_NIC}" -j MASQUERADE
        
        # Save rules
        if command_exists iptables-save; then
            iptables-save > /etc/iptables.rules 2>/dev/null
        fi
        print_debug "iptables configured"
    fi
    
    print_success "Firewall configured"
}

# Create systemd service
create_systemd_service() {
    cat > /etc/systemd/system/wg-quick@.service.d/override.conf << EOF
[Service]
ExecStartPre=/bin/bash -c 'wg-quick strip %I > /tmp/wg-strip-%I.conf'
EOF
    
    systemctl daemon-reload
    systemctl enable "wg-quick@${WG_INTERFACE}" >/dev/null 2>&1
    
    print_debug "Systemd service created and enabled"
}

# Get server statistics
get_server_stats() {
    local stats=""
    
    if is_wireguard_running; then
        local peer_count=$(wg show "${WG_INTERFACE}" peers | wc -l)
        local total_rx=$(wg show "${WG_INTERFACE}" transfer | awk '{sum+=$2} END {print sum}')
        local total_tx=$(wg show "${WG_INTERFACE}" transfer | awk '{sum+=$3} END {print sum}')
        
        stats="Peers: ${peer_count} | RX: $(bytes_to_human ${total_rx:-0}) | TX: $(bytes_to_human ${total_tx:-0})"
    else
        stats="WireGuard is not running"
    fi
    
    echo "${stats}"
}

# Save configuration
save_config() {
    local config_file="${SYSTEM_CONFIG}"
    
    cat > "${config_file}" << EOF
# WireGuard Manager System Configuration
# Generated: $(date)

# Server Configuration
WG_INTERFACE="${WG_INTERFACE}"
WG_PORT="${WG_PORT}"
WG_SUBNET="${WG_SUBNET}"
WG_SERVER_IP="${WG_SERVER_IP}"
WG_DNS="${WG_DNS}"
WG_MTU="${WG_MTU}"

# Network Configuration
SERVER_PUB_IP="${SERVER_PUB_IP}"
SERVER_PUB_NIC="${SERVER_PUB_NIC}"

# Telegram Configuration
TELEGRAM_ENABLED="${TELEGRAM_ENABLED}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS}"

# Monitoring Configuration
MONITOR_ENABLED="${MONITOR_ENABLED}"
ALERT_THRESHOLD_MB="${ALERT_THRESHOLD_MB}"

# Backup Configuration
BACKUP_ENABLED="${BACKUP_ENABLED}"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE}"
BACKUP_RETAIN_DAYS="${BACKUP_RETAIN_DAYS}"

# Server Maintenance
AUTO_REBOOT_ENABLED="${AUTO_REBOOT_ENABLED}"
AUTO_REBOOT_SCHEDULE="${AUTO_REBOOT_SCHEDULE}"
AUTO_UPDATE_ENABLED="${AUTO_UPDATE_ENABLED}"
EOF
    
    chmod 600 "${config_file}"
    print_success "Configuration saved"
}
