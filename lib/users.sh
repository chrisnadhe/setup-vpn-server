#!/bin/bash
# User Management Functions for WireGuard Manager
# Add, delete, edit, list, enable/disable users

# User database format: username|ip|public_key|enabled|created_date|bandwidth_limit|notes
# Example: john|10.66.66.2|abc123...|1|2024-01-15|0|Premium user

# Initialize user database
init_user_db() {
    if [[ ! -f "${USER_DB}" ]]; then
        touch "${USER_DB}"
        chmod 600 "${USER_DB}"
        print_debug "Created user database"
    fi
}

# Check if user exists
user_exists() {
    local username="$1"
    grep -q "^${username}|" "${USER_DB}" 2>/dev/null
}

# Get user info
get_user_info() {
    local username="$1"
    grep "^${username}|" "${USER_DB}" 2>/dev/null
}

# Get user field
get_user_field() {
    local username="$1"
    local field="$2"  # 1=username, 2=ip, 3=public_key, 4=enabled, 5=created, 6=bandwidth, 7=notes
    
    get_user_info "${username}" | cut -d'|' -f"${field}"
}

# Get next available IP
get_next_ip() {
    local used_ips=()
    
    # Read used IPs from database
    if [[ -f "${USER_DB}" ]]; then
        while IFS='|' read -r username ip rest; do
            [[ -n "${ip}" ]] && used_ips+=("${ip}")
        done < "${USER_DB}"
    fi
    
    # Parse subnet
    local subnet_base="${WG_SUBNET%.*}"
    local start_octet="${IP_POOL_START##*.}"
    local end_octet="${IP_POOL_END##*.}"
    
    # Find next available IP
    for ((i=start_octet; i<=end_octet; i++)); do
        local test_ip="${subnet_base}.${i}"
        local found=0
        
        for used_ip in "${used_ips[@]}"; do
            if [[ "${used_ip}" == "${test_ip}" ]]; then
                found=1
                break
            fi
        done
        
        if [[ ${found} -eq 0 ]]; then
            echo "${test_ip}"
            return 0
        fi
    done
    
    print_error "No available IP addresses in pool"
    return 1
}

# Add new user
add_user() {
    local username="$1"
    local bandwidth_limit="${2:-0}"  # 0 = unlimited
    local notes="${3:-}"
    
    # Validate username
    if ! validate_username "${username}"; then
        print_error "Invalid username. Use alphanumeric characters, dash, or underscore (2-32 chars)"
        return 1
    fi
    
    # Check if user already exists
    if user_exists "${username}"; then
        print_error "User '${username}' already exists"
        return 1
    fi
    
    # Get next available IP
    local user_ip=$(get_next_ip)
    if [[ -z "${user_ip}" ]]; then
        return 1
    fi
    
    print_info "Creating user '${username}' with IP ${user_ip}..."
    
    # Generate keys
    generate_keys "${username}"
    local private_key=$(get_key "${username}" "private")
    local public_key=$(get_key "${username}" "public")
    local preshared_key=$(get_key "${username}" "preshared")
    
    # Get server public key
    local server_public_key=$(get_server_public_key)
    
    # Create user directory
    local user_dir="${WG_USERS_DIR}/${username}"
    mkdir -p "${user_dir}"
    
    # Generate client configuration
    cat > "${user_dir}/client.conf" << EOF
[Interface]
PrivateKey = ${private_key}
Address = ${user_ip}/32
DNS = ${WG_DNS}
MTU = ${WG_MTU}

[Peer]
PublicKey = ${server_public_key}
PresharedKey = ${preshared_key}
Endpoint = ${SERVER_PUB_IP}:${WG_PORT}
AllowedIPs = ${ALLOWED_IPS}
PersistentKeepalive = ${PERSISTENT_KEEPALIVE}
EOF
    
    chmod 600 "${user_dir}/client.conf"
    
    # Add peer to server configuration
    add_peer_to_config "${username}" "${public_key}" "${preshared_key}" "${user_ip}"
    
    # Add to user database
    local created_date=$(date '+%Y-%m-%d')
    echo "${username}|${user_ip}|${public_key}|1|${created_date}|${bandwidth_limit}|${notes}" >> "${USER_DB}"
    
    # Initialize usage log
    touch "${USAGE_LOG_DIR}/${username}.log"
    
    # Reload WireGuard
    reload_wireguard
    
    print_success "User '${username}' created successfully"
    print_info "IP Address: ${user_ip}"
    print_info "Config file: ${user_dir}/client.conf"
    
    log_message "INFO" "Added user: ${username} (${user_ip})"
    
    return 0
}

# Delete user
delete_user() {
    local username="$1"
    local keep_config="${2:-false}"
    
    # Check if user exists
    if ! user_exists "${username}"; then
        print_error "User '${username}' does not exist"
        return 1
    fi
    
    print_info "Deleting user '${username}'..."
    
    # Get user's public key
    local public_key=$(get_user_field "${username}" 3)
    
    # Remove peer from WireGuard
    wg set "${WG_INTERFACE}" peer "${public_key}" remove 2>/dev/null
    
    # Remove from server config
    remove_peer_from_config "${username}"
    
    # Backup and remove user directory
    if [[ "${keep_config}" != "true" ]]; then
        local user_dir="${WG_USERS_DIR}/${username}"
        if [[ -d "${user_dir}" ]]; then
            # Create backup before deletion
            tar -czf "${WG_BACKUP_DIR}/${username}_$(date +%Y%m%d_%H%M%S).tar.gz" -C "${WG_USERS_DIR}" "${username}" 2>/dev/null
            rm -rf "${user_dir}"
        fi
        
        # Delete keys
        delete_keys "${username}"
        
        # Archive usage log
        if [[ -f "${USAGE_LOG_DIR}/${username}.log" ]]; then
            mv "${USAGE_LOG_DIR}/${username}.log" "${WG_BACKUP_DIR}/${username}_usage_$(date +%Y%m%d).log" 2>/dev/null
        fi
    fi
    
    # Remove from user database
    sed -i "/^${username}|/d" "${USER_DB}"
    
    print_success "User '${username}' deleted successfully"
    log_message "INFO" "Deleted user: ${username}"
    
    return 0
}

# Edit user
edit_user() {
    local username="$1"
    local field="$2"  # ip, bandwidth, notes, name
    local new_value="$3"
    
    # Check if user exists
    if ! user_exists "${username}"; then
        print_error "User '${username}' does not exist"
        return 1
    fi
    
    case "${field}" in
        ip)
            if ! validate_ip "${new_value}"; then
                print_error "Invalid IP address"
                return 1
            fi
            update_user_ip "${username}" "${new_value}"
            ;;
        bandwidth)
            update_user_bandwidth "${username}" "${new_value}"
            ;;
        notes)
            update_user_notes "${username}" "${new_value}"
            ;;
        name)
            rename_user "${username}" "${new_value}"
            ;;
        *)
            print_error "Unknown field: ${field}"
            print_info "Available fields: ip, bandwidth, notes, name"
            return 1
            ;;
    esac
    
    return 0
}

# Update user IP
update_user_ip() {
    local username="$1"
    local new_ip="$2"
    
    # Check if IP is already in use
    if grep -q "|${new_ip}|" "${USER_DB}" 2>/dev/null; then
        print_error "IP ${new_ip} is already in use"
        return 1
    fi
    
    local old_ip=$(get_user_field "${username}" 2)
    local public_key=$(get_user_field "${username}" 3)
    
    # Update WireGuard peer
    wg set "${WG_INTERFACE}" peer "${public_key}" allowed-ips "${new_ip}/32" 2>/dev/null
    
    # Update server config
    sed -i "s|AllowedIPs = ${old_ip}/32|AllowedIPs = ${new_ip}/32|g" "/etc/wireguard/${WG_INTERFACE}.conf"
    
    # Update client config
    local client_conf="${WG_USERS_DIR}/${username}/client.conf"
    if [[ -f "${client_conf}" ]]; then
        sed -i "s|Address = ${old_ip}/|Address = ${new_ip}/|g" "${client_conf}"
    fi
    
    # Update database
    sed -i "s|^${username}|${old_ip}|${username}|${new_ip}|" "${USER_DB}"
    
    print_success "IP updated from ${old_ip} to ${new_ip}"
    log_message "INFO" "Updated IP for ${username}: ${old_ip} -> ${new_ip}"
}

# Update user bandwidth limit
update_user_bandwidth() {
    local username="$1"
    local limit="$2"  # in MB, 0 = unlimited
    
    local user_line=$(get_user_info "${username}")
    local fields=(${user_line//|/ })
    
    # Rebuild line with new bandwidth
    sed -i "s|^${username}|.*|${fields[0]}|${fields[1]}|${fields[2]}|${fields[3]}|${fields[4]}|${limit}|${fields[6]}|" "${USER_DB}"
    
    print_success "Bandwidth limit updated to ${limit} MB (0 = unlimited)"
    log_message "INFO" "Updated bandwidth limit for ${username}: ${limit} MB"
}

# Update user notes
update_user_notes() {
    local username="$1"
    local notes="$2"
    
    local user_line=$(get_user_info "${username}")
    local fields=(${user_line//|/ })
    
    # Rebuild line with new notes
    sed -i "s|^${username}|.*|${fields[0]}|${fields[1]}|${fields[2]}|${fields[3]}|${fields[4]}|${fields[5]}|${notes}|" "${USER_DB}"
    
    print_success "Notes updated"
}

# Rename user
rename_user() {
    local old_name="$1"
    local new_name="$2"
    
    # Validate new username
    if ! validate_username "${new_name}"; then
        print_error "Invalid username"
        return 1
    fi
    
    # Check if new name already exists
    if user_exists "${new_name}"; then
        print_error "User '${new_name}' already exists"
        return 1
    fi
    
    # Rename directories
    mv "${WG_USERS_DIR}/${old_name}" "${WG_USERS_DIR}/${new_name}" 2>/dev/null
    mv "${WG_KEYS_DIR}/${old_name}" "${WG_KEYS_DIR}/${new_name}" 2>/dev/null
    mv "${USAGE_LOG_DIR}/${old_name}.log" "${USAGE_LOG_DIR}/${new_name}.log" 2>/dev/null
    
    # Update server config comment
    sed -i "s|# User: ${old_name}|# User: ${new_name}|g" "/etc/wireguard/${WG_INTERFACE}.conf"
    
    # Update database
    sed -i "s|^${old_name}|${new_name}|" "${USER_DB}"
    
    print_success "User renamed from '${old_name}' to '${new_name}'"
    log_message "INFO" "Renamed user: ${old_name} -> ${new_name}"
}

# Enable user
enable_user() {
    local username="$1"
    
    if ! user_exists "${username}"; then
        print_error "User '${username}' does not exist"
        return 1
    fi
    
    local public_key=$(get_user_field "${username}" 3)
    local ip=$(get_user_field "${username}" 2)
    local preshared_key=$(get_key "${username}" "preshared")
    
    # Add peer back to WireGuard
    wg set "${WG_INTERFACE}" peer "${public_key}" preshared-key "${WG_KEYS_DIR}/${username}/preshared.key" allowed-ips "${ip}/32" 2>/dev/null
    
    # Update database
    sed -i "s|^${username}|\([^|]*\)|\([^|]*\)|\([^|]*\)|0|/|${username}|\1|\2|\3|1|/" "${USER_DB}"
    
    print_success "User '${username}' enabled"
    log_message "INFO" "Enabled user: ${username}"
}

# Disable user
disable_user() {
    local username="$1"
    
    if ! user_exists "${username}"; then
        print_error "User '${username}' does not exist"
        return 1
    fi
    
    local public_key=$(get_user_field "${username}" 3)
    
    # Remove peer from WireGuard (but keep config)
    wg set "${WG_INTERFACE}" peer "${public_key}" remove 2>/dev/null
    
    # Update database
    sed -i "s|^${username}|\([^|]*\)|\([^|]*\)|\([^|]*\)|1|/|${username}|\1|\2|\3|0|/" "${USER_DB}"
    
    print_success "User '${username}' disabled"
    log_message "INFO" "Disabled user: ${username}"
}

# List all users
list_users() {
    local show_disabled="${1:-true}"
    
    if [[ ! -s "${USER_DB}" ]]; then
        print_warning "No users found"
        return 0
    fi
    
    print_header "VPN Users"
    
    printf "${BOLD}%-20s %-15s %-10s %-12s %-15s${NC}\n" "USERNAME" "IP ADDRESS" "STATUS" "CREATED" "USAGE"
    echo "──────────────────────────────────────────────────────────────────────────────────────"
    
    while IFS='|' read -r username ip public_key enabled created bandwidth notes; do
        # Skip disabled users if not showing them
        if [[ "${show_disabled}" != "true" && "${enabled}" == "0" ]]; then
            continue
        fi
        
        # Get status
        local status="${RED}Disabled${NC}"
        if [[ "${enabled}" == "1" ]]; then
            if is_peer_connected "${public_key}"; then
                status="${GREEN}Online${NC}"
            else
                status="${YELLOW}Offline${NC}"
            fi
        fi
        
        # Get usage
        local usage=$(get_user_usage "${username}")
        
        printf "%-20s %-15s %-22s %-12s %-15s\n" "${username}" "${ip}" "${status}" "${created}" "${usage}"
    done < "${USER_DB}"
    
    echo ""
}

# Get user usage
get_user_usage() {
    local username="$1"
    
    if [[ -f "${USAGE_LOG_DIR}/${username}.log" ]]; then
        local total_rx=0
        local total_tx=0
        
        while IFS='|' read -r timestamp rx tx; do
            total_rx=$((total_rx + rx))
            total_tx=$((total_tx + tx))
        done < "${USAGE_LOG_DIR}/${username}.log"
        
        echo "↓$(bytes_to_human ${total_rx}) ↑$(bytes_to_human ${total_tx})"
    else
        echo "N/A"
    fi
}

# Get user current session info
get_user_session() {
    local username="$1"
    local public_key=$(get_user_field "${username}" 3)
    
    if [[ -z "${public_key}" ]]; then
        return 1
    fi
    
    local peer_info=$(wg show "${WG_INTERFACE}" dump | grep "^${public_key}")
    
    if [[ -n "${peer_info}" ]]; then
        local endpoint=$(echo "${peer_info}" | awk '{print $3}')
        local allowed_ips=$(echo "${peer_info}" | awk '{print $4}')
        local last_handshake=$(echo "${peer_info}" | awk '{print $5}')
        local rx=$(echo "${peer_info}" | awk '{print $6}')
        local tx=$(echo "${peer_info}" | awk '{print $7}')
        
        echo "Endpoint: ${endpoint}"
        echo "Last Handshake: $(seconds_to_human ${last_handshake}) ago"
        echo "Received: $(bytes_to_human ${rx})"
        echo "Transmitted: $(bytes_to_human ${tx})"
    else
        echo "User is not connected"
    fi
}

# Show user details
show_user_details() {
    local username="$1"
    
    if ! user_exists "${username}"; then
        print_error "User '${username}' does not exist"
        return 1
    fi
    
    local ip=$(get_user_field "${username}" 2)
    local public_key=$(get_user_field "${username}" 3)
    local enabled=$(get_user_field "${username}" 4)
    local created=$(get_user_field "${username}" 5)
    local bandwidth=$(get_user_field "${username}" 6)
    local notes=$(get_user_field "${username}" 7)
    
    print_header "User Details: ${username}"
    
    echo -e "${BOLD}Username:${NC}      ${username}"
    echo -e "${BOLD}IP Address:${NC}    ${ip}"
    echo -e "${BOLD}Status:${NC}        $([ "${enabled}" == "1" ] && echo -e "${GREEN}Enabled${NC}" || echo -e "${RED}Disabled${NC}")"
    echo -e "${BOLD}Created:${NC}       ${created}"
    echo -e "${BOLD}Bandwidth Limit:${NC} $([ "${bandwidth}" == "0" ] && echo "Unlimited" || echo "${bandwidth} MB")"
    echo -e "${BOLD}Notes:${NC}         ${notes:-None}"
    echo ""
    
    print_subheader "Current Session"
    get_user_session "${username}"
    echo ""
    
    print_subheader "Configuration File"
    local config_file="${WG_USERS_DIR}/${username}/client.conf"
    if [[ -f "${config_file}" ]]; then
        echo -e "${DIM}Location: ${config_file}${NC}"
        echo ""
        cat "${config_file}"
    else
        print_warning "Configuration file not found"
    fi
}

# Generate QR code for user
generate_qr_code() {
    local username="$1"
    local config_file="${WG_USERS_DIR}/${username}/client.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        print_error "Configuration file not found for user '${username}'"
        return 1
    fi
    
    if ! command_exists qrencode; then
        print_error "qrencode is not installed. Install it with: apt install qrencode"
        return 1
    fi
    
    print_info "QR Code for ${username}:"
    echo ""
    qrencode -t ansiutf8 < "${config_file}"
    echo ""
}

# Export user configuration
export_user_config() {
    local username="$1"
    local output_path="${2:-.}"
    local config_file="${WG_USERS_DIR}/${username}/client.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        print_error "Configuration file not found for user '${username}'"
        return 1
    fi
    
    local output_file="${output_path}/${username}.conf"
    cp "${config_file}" "${output_file}"
    
    print_success "Configuration exported to: ${output_file}"
}

# Import user from backup
import_user() {
    local backup_file="$1"
    
    if [[ ! -f "${backup_file}" ]]; then
        print_error "Backup file not found: ${backup_file}"
        return 1
    fi
    
    # Extract username from backup filename
    local username=$(basename "${backup_file}" | cut -d'_' -f1)
    
    # Check if user already exists
    if user_exists "${username}"; then
        print_error "User '${username}' already exists. Delete first or use a different name."
        return 1
    fi
    
    print_info "Importing user '${username}'..."
    
    # Extract backup
    tar -xzf "${backup_file}" -C "${WG_USERS_DIR}" 2>/dev/null
    
    # Re-add user to system (regenerate keys for security)
    local old_ip=$(grep "Address" "${WG_USERS_DIR}/${username}/client.conf" | cut -d'=' -f2 | tr -d ' ' | cut -d'/' -f1)
    
    # Generate new keys
    generate_keys "${username}"
    local public_key=$(get_key "${username}" "public")
    local preshared_key=$(get_key "${username}" "preshared")
    
    # Add to server
    add_peer_to_config "${username}" "${public_key}" "${preshared_key}" "${old_ip}"
    
    # Add to database
    local created_date=$(date '+%Y-%m-%d')
    echo "${username}|${old_ip}|${public_key}|1|${created_date}|0|Imported from backup" >> "${USER_DB}"
    
    reload_wireguard
    
    print_success "User '${username}' imported successfully"
    print_warning "New keys generated. Update client configuration."
}

# Get user count
get_user_count() {
    local total=0
    local enabled=0
    
    if [[ -f "${USER_DB}" && -s "${USER_DB}" ]]; then
        total=$(wc -l < "${USER_DB}" 2>/dev/null | tr -d '[:space:]')
        enabled=$(grep -c "|1|" "${USER_DB}" 2>/dev/null | tr -d '[:space:]')
    fi
    
    total=${total:-0}
    enabled=${enabled:-0}
    local disabled=$((total - enabled))
    
    echo "Total: ${total} | Enabled: ${enabled} | Disabled: ${disabled}"
}

# Search users
search_users() {
    local query="$1"
    
    if [[ -z "${query}" ]]; then
        list_users
        return
    fi
    
    print_header "Search Results for '${query}'"
    
    grep -i "${query}" "${USER_DB}" | while IFS='|' read -r username ip public_key enabled created bandwidth notes; do
        local status=$([ "${enabled}" == "1" ] && echo "Enabled" || echo "Disabled")
        echo -e "${BOLD}${username}${NC} - ${ip} (${status})"
        [[ -n "${notes}" ]] && echo -e "  ${DIM}Notes: ${notes}${NC}"
    done
}
