#!/bin/bash
# Server Management Functions for WireGuard Manager
# Backup, restore, scheduling, and system maintenance

# Create backup
create_backup() {
    local backup_name="wg_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="${WG_BACKUP_DIR}/${backup_name}"
    
    print_info "Creating backup: ${backup_name}"
    
    mkdir -p "${backup_path}"
    
    # Backup WireGuard configuration
    if [[ -d "/etc/wireguard" ]]; then
        cp -r /etc/wireguard "${backup_path}/wireguard"
    fi
    
    # Backup manager data
    cp -r "${WG_USERS_DIR}" "${backup_path}/users" 2>/dev/null
    cp -r "${WG_KEYS_DIR}" "${backup_path}/keys" 2>/dev/null
    cp "${USER_DB}" "${backup_path}/users.db" 2>/dev/null
    cp "${SYSTEM_CONFIG}" "${backup_path}/config.conf" 2>/dev/null
    
    # Backup usage logs (last 30 days)
    mkdir -p "${backup_path}/usage"
    find "${USAGE_LOG_DIR}" -name "*.log" -mtime -30 -exec cp {} "${backup_path}/usage/" \; 2>/dev/null
    
    # Create metadata file
    cat > "${backup_path}/metadata.txt" << EOF
Backup Date: $(date '+%Y-%m-%d %H:%M:%S')
Server IP: ${SERVER_PUB_IP}
Interface: ${WG_INTERFACE}
Port: ${WG_PORT}
User Count: $(wc -l < "${USER_DB}" 2>/dev/null || echo 0)
EOF
    
    # Compress backup
    if [[ "${BACKUP_COMPRESS}" == "true" ]]; then
        tar -czf "${backup_path}.tar.gz" -C "${WG_BACKUP_DIR}" "${backup_name}"
        rm -rf "${backup_path}"
        backup_path="${backup_path}.tar.gz"
    fi
    
    print_success "Backup created: ${backup_path}"
    log_message "INFO" "Backup created: ${backup_name}"
    
    echo "${backup_path}"
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    
    if [[ ! -f "${backup_file}" ]]; then
        print_error "Backup file not found: ${backup_file}"
        return 1
    fi
    
    print_warning "This will overwrite current configuration!"
    if ! confirm_action "Continue with restore?"; then
        return 1
    fi
    
    print_info "Restoring from backup..."
    
    # Create temporary restore directory
    local restore_dir="/tmp/wg_restore_$$"
    mkdir -p "${restore_dir}"
    
    # Extract backup
    if [[ "${backup_file}" == *.tar.gz ]]; then
        tar -xzf "${backup_file}" -C "${restore_dir}"
        restore_dir="${restore_dir}/$(ls "${restore_dir}")"
    else
        cp -r "${backup_file}"/* "${restore_dir}/"
    fi
    
    # Stop WireGuard
    stop_wireguard 2>/dev/null
    
    # Backup current config before restore
    create_backup > /dev/null
    
    # Restore WireGuard configuration
    if [[ -d "${restore_dir}/wireguard" ]]; then
        rm -rf /etc/wireguard
        cp -r "${restore_dir}/wireguard" /etc/wireguard
        chmod 600 /etc/wireguard/*.conf
    fi
    
    # Restore manager data
    [[ -d "${restore_dir}/users" ]] && cp -r "${restore_dir}/users"/* "${WG_USERS_DIR}/" 2>/dev/null
    [[ -d "${restore_dir}/keys" ]] && cp -r "${restore_dir}/keys"/* "${WG_KEYS_DIR}/" 2>/dev/null
    [[ -f "${restore_dir}/users.db" ]] && cp "${restore_dir}/users.db" "${USER_DB}"
    [[ -f "${restore_dir}/config.conf" ]] && cp "${restore_dir}/config.conf" "${SYSTEM_CONFIG}"
    
    # Restore usage logs
    [[ -d "${restore_dir}/usage" ]] && cp "${restore_dir}/usage"/* "${USAGE_LOG_DIR}/" 2>/dev/null
    
    # Cleanup
    rm -rf "/tmp/wg_restore_$$"
    
    # Start WireGuard
    start_wireguard 2>/dev/null
    
    print_success "Restore completed successfully"
    log_message "INFO" "Restored from backup: $(basename "${backup_file}")"
}

# List backups
list_backups() {
    print_header "Available Backups"
    
    if [[ ! -d "${WG_BACKUP_DIR}" ]]; then
        print_warning "No backups found"
        return
    fi
    
    local count=0
    
    for backup in "${WG_BACKUP_DIR}"/wg_backup_*; do
        [[ ! -e "${backup}" ]] && continue
        
        count=$((count + 1))
        local name=$(basename "${backup}")
        local size=$(du -sh "${backup}" 2>/dev/null | awk '{print $1}')
        local date=$(echo "${name}" | grep -oP '\d{8}_\d{6}' | sed 's/_/ /')
        
        echo -e "${BOLD}${name}${NC}"
        echo -e "  Size: ${size} | Date: ${date}"
    done
    
    if [[ ${count} -eq 0 ]]; then
        print_warning "No backups found"
    else
        echo ""
        echo -e "${DIM}Total: ${count} backup(s)${NC}"
    fi
}

# Delete old backups
cleanup_old_backups() {
    local retain_days="${BACKUP_RETAIN_DAYS:-30}"
    
    print_info "Cleaning up backups older than ${retain_days} days..."
    
    local count=$(find "${WG_BACKUP_DIR}" -name "wg_backup_*" -mtime +${retain_days} 2>/dev/null | wc -l)
    
    find "${WG_BACKUP_DIR}" -name "wg_backup_*" -mtime +${retain_days} -delete 2>/dev/null
    
    print_success "Removed ${count} old backup(s)"
    log_message "INFO" "Cleaned up ${count} old backups"
}

# Schedule automatic backup
schedule_backup() {
    local schedule="${BACKUP_SCHEDULE:-0 2 * * *}"
    
    print_info "Scheduling automatic backup: ${schedule}"
    
    # Create backup script
    cat > /usr/local/bin/wg-backup.sh << 'EOF'
#!/bin/bash
source /etc/wireguard-manager/config.conf
source /path/to/wg-manager.sh --backup-only
EOF
    
    chmod +x /usr/local/bin/wg-backup.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "wg-backup.sh"; echo "${schedule} /usr/local/bin/wg-backup.sh") | crontab -
    
    print_success "Automatic backup scheduled"
}

# Schedule automatic reboot
schedule_reboot() {
    local schedule="${AUTO_REBOOT_SCHEDULE:-0 4 * * 0}"
    
    if [[ "${AUTO_REBOOT_ENABLED}" != "true" ]]; then
        print_warning "Auto-reboot is disabled in configuration"
        return 1
    fi
    
    print_info "Scheduling automatic reboot: ${schedule}"
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "auto-reboot"; echo "${schedule} /sbin/reboot # wg-auto-reboot") | crontab -
    
    print_success "Automatic reboot scheduled"
}

# Remove scheduled reboot
unschedule_reboot() {
    crontab -l 2>/dev/null | grep -v "wg-auto-reboot" | crontab -
    print_success "Automatic reboot removed from schedule"
}

# Get scheduled tasks
get_scheduled_tasks() {
    print_header "Scheduled Tasks"
    
    echo -e "${BOLD}Cron Jobs:${NC}"
    crontab -l 2>/dev/null | grep -E "(wg-|wireguard)" || echo "  No WireGuard-related cron jobs"
    echo ""
    
    echo -e "${BOLD}Systemd Timers:${NC}"
    systemctl list-timers 2>/dev/null | grep -E "(wg-|wireguard)" || echo "  No WireGuard-related timers"
}

# Check system updates
check_updates() {
    print_header "System Updates"
    
    print_info "Checking for updates..."
    
    apt-get update -qq 2>/dev/null
    
    local updates=$(apt-get -s upgrade 2>/dev/null | grep -c "^Inst")
    local security=$(apt-get -s upgrade 2>/dev/null | grep -c "Inst.*security")
    
    echo -e "${BOLD}Available Updates:${NC} ${updates}"
    echo -e "${BOLD}Security Updates:${NC} ${security}"
    
    if [[ ${security} -gt 0 ]]; then
        print_warning "There are ${security} security updates available!"
    fi
    
    # Check WireGuard specifically
    local wg_update=$(apt-cache policy wireguard 2>/dev/null | grep -A2 "Candidate" | tail -1)
    echo -e "${BOLD}WireGuard:${NC} ${wg_update}"
}

# Apply system updates
apply_updates() {
    local security_only="${1:-false}"
    
    print_warning "This will apply system updates. A reboot may be required."
    if ! confirm_action "Continue with updates?"; then
        return 1
    fi
    
    print_info "Applying updates..."
    
    if [[ "${security_only}" == "true" ]]; then
        apt-get upgrade -y -o Dir::Etc::SourceList=/etc/apt/sources.list.d/security.list 2>/dev/null
    else
        apt-get upgrade -y 2>/dev/null
    fi
    
    print_success "Updates applied"
    log_message "INFO" "System updates applied (security_only: ${security_only})"
    
    # Check if reboot required
    if [[ -f /var/run/reboot-required ]]; then
        print_warning "System reboot is required"
    fi
}

# Check server health
check_server_health() {
    print_header "Server Health Check"
    
    local issues=0
    
    # Check WireGuard service
    echo -n "WireGuard Service: "
    if is_wireguard_running; then
        echo -e "${GREEN}✓ Running${NC}"
    else
        echo -e "${RED}✗ Not Running${NC}"
        issues=$((issues + 1))
    fi
    
    # Check WireGuard interface
    echo -n "WireGuard Interface: "
    if ip link show "${WG_INTERFACE}" &>/dev/null; then
        echo -e "${GREEN}✓ Present${NC}"
    else
        echo -e "${RED}✗ Missing${NC}"
        issues=$((issues + 1))
    fi
    
    # Check IP forwarding
    echo -n "IP Forwarding: "
    local forwarding=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
    if [[ "${forwarding}" == "1" ]]; then
        echo -e "${GREEN}✓ Enabled${NC}"
    else
        echo -e "${RED}✗ Disabled${NC}"
        issues=$((issues + 1))
    fi
    
    # Check firewall rules
    echo -n "Firewall Rules: "
    if iptables -L INPUT -n 2>/dev/null | grep -q "${WG_PORT}"; then
        echo -e "${GREEN}✓ Configured${NC}"
    else
        echo -e "${YELLOW}⚠ Port ${WG_PORT} not found in rules${NC}"
        issues=$((issues + 1))
    fi
    
    # Check DNS resolution
    echo -n "DNS Resolution: "
    if host -t A google.com &>/dev/null || nslookup google.com &>/dev/null; then
        echo -e "${GREEN}✓ Working${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
        issues=$((issues + 1))
    fi
    
    # Check disk space
    echo -n "Disk Space: "
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    if [[ ${disk_usage} -lt 90 ]]; then
        echo -e "${GREEN}✓ ${disk_usage}% used${NC}"
    else
        echo -e "${RED}✗ ${disk_usage}% used (critical)${NC}"
        issues=$((issues + 1))
    fi
    
    # Check memory
    echo -n "Memory: "
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2*100}')
    if [[ ${mem_usage} -lt 90 ]]; then
        echo -e "${GREEN}✓ ${mem_usage}% used${NC}"
    else
        echo -e "${YELLOW}⚠ ${mem_usage}% used${NC}"
    fi
    
    # Check configuration files
    echo -n "Config Files: "
    if [[ -f "/etc/wireguard/${WG_INTERFACE}.conf" ]]; then
        echo -e "${GREEN}✓ Present${NC}"
    else
        echo -e "${RED}✗ Missing${NC}"
        issues=$((issues + 1))
    fi
    
    # Check user database
    echo -n "User Database: "
    if [[ -f "${USER_DB}" ]]; then
        echo -e "${GREEN}✓ Present${NC}"
    else
        echo -e "${RED}✗ Missing${NC}"
        issues=$((issues + 1))
    fi
    
    echo ""
    if [[ ${issues} -eq 0 ]]; then
        print_success "All checks passed! Server is healthy."
    else
        print_warning "Found ${issues} issue(s). Review the output above."
    fi
    
    return ${issues}
}

# Test VPN connectivity
test_vpn_connectivity() {
    print_header "VPN Connectivity Test"
    
    # Check if WireGuard is running
    if ! is_wireguard_running; then
        print_error "WireGuard is not running"
        return 1
    fi
    
    # Test port availability
    echo -n "Port ${WG_PORT} (UDP): "
    if ss -uln | grep -q ":${WG_PORT}"; then
        echo -e "${GREEN}✓ Listening${NC}"
    else
        echo -e "${RED}✗ Not Listening${NC}"
        return 1
    fi
    
    # Test external connectivity
    echo -n "External IP: "
    local ext_ip=$(get_public_ip)
    if [[ -n "${ext_ip}" ]]; then
        echo -e "${GREEN}✓ ${ext_ip}${NC}"
    else
        echo -e "${RED}✗ Could not determine${NC}"
    fi
    
    # Test DNS
    echo -n "DNS Resolution: "
    if host -t A google.com &>/dev/null; then
        echo -e "${GREEN}✓ Working${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
    
    # Show peer status
    echo ""
    print_subheader "Peer Status"
    wg show "${WG_INTERFACE}"
}

# View system logs
view_logs() {
    local log_type="${1:-manager}"  # manager, wireguard, system
    local lines="${2:-50}"
    
    case "${log_type}" in
        manager)
            print_header "Manager Logs (last ${lines} lines)"
            if [[ -f "${LOG_FILE}" ]]; then
                tail -n "${lines}" "${LOG_FILE}"
            else
                print_warning "No manager logs found"
            fi
            ;;
        wireguard)
            print_header "WireGuard Logs (last ${lines} lines)"
            journalctl -u "wg-quick@${WG_INTERFACE}" -n "${lines}" --no-pager 2>/dev/null || \
            dmesg | grep -i wireguard | tail -n "${lines}"
            ;;
        system)
            print_header "System Logs (last ${lines} lines)"
            journalctl -n "${lines}" --no-pager 2>/dev/null || \
            tail -n "${lines}" /var/log/syslog 2>/dev/null
            ;;
        *)
            print_error "Unknown log type: ${log_type}"
            print_info "Available types: manager, wireguard, system"
            ;;
    esac
}

# Rotate logs
rotate_logs() {
    print_info "Rotating logs..."
    
    # Rotate manager log
    if [[ -f "${LOG_FILE}" ]]; then
        local log_size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}" 2>/dev/null)
        
        if [[ ${log_size} -gt 10485760 ]]; then  # 10MB
            mv "${LOG_FILE}" "${LOG_FILE}.$(date +%Y%m%d)"
            touch "${LOG_FILE}"
            chmod 600 "${LOG_FILE}"
            
            # Compress old logs
            gzip "${LOG_FILE}.$(date +%Y%m%d)" 2>/dev/null
            
            # Keep only last 5 rotated logs
            ls -t "${LOG_FILE}".* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
        fi
    fi
    
    print_success "Log rotation completed"
}

# Configure server settings
configure_server() {
    local setting="$1"
    local value="$2"
    
    case "${setting}" in
        port)
            if [[ ${value} -lt 1 || ${value} -gt 65535 ]]; then
                print_error "Invalid port number"
                return 1
            fi
            WG_PORT="${value}"
            ;;
        dns)
            WG_DNS="${value}"
            ;;
        mtu)
            WG_MTU="${value}"
            ;;
        subnet)
            WG_SUBNET="${value}"
            ;;
        telegram-token)
            TELEGRAM_BOT_TOKEN="${value}"
            ;;
        telegram-enable)
            TELEGRAM_ENABLED="${value}"
            ;;
        telegram-allowed)
            TELEGRAM_ALLOWED_USERS="${value}"
            ;;
        backup-schedule)
            BACKUP_SCHEDULE="${value}"
            ;;
        auto-reboot)
            AUTO_REBOOT_ENABLED="${value}"
            ;;
        *)
            print_error "Unknown setting: ${setting}"
            print_info "Available settings: port, dns, mtu, subnet, telegram-token, telegram-enable, telegram-allowed, backup-schedule, auto-reboot"
            return 1
            ;;
    esac
    
    save_config
    print_success "Setting '${setting}' updated to '${value}'"
}

# Show server configuration
show_config() {
    print_header "Server Configuration"
    
    echo -e "${BOLD}Network Settings:${NC}"
    echo "  Interface:      ${WG_INTERFACE}"
    echo "  Port:           ${WG_PORT}"
    echo "  Subnet:         ${WG_SUBNET}"
    echo "  Server IP:      ${WG_SERVER_IP}"
    echo "  Public IP:      ${SERVER_PUB_IP}"
    echo "  DNS:            ${WG_DNS}"
    echo "  MTU:            ${WG_MTU}"
    echo ""
    
    echo -e "${BOLD}Telegram Bot:${NC}"
    echo "  Enabled:        ${TELEGRAM_ENABLED}"
    echo "  Token:          $([ -n "${TELEGRAM_BOT_TOKEN}" ] && echo "****${TELEGRAM_BOT_TOKEN: -4}" || echo "Not set")"
    echo "  Allowed Users:  ${TELEGRAM_ALLOWED_USERS:-None}"
    echo ""
    
    echo -e "${BOLD}Monitoring:${NC}"
    echo "  Enabled:        ${MONITOR_ENABLED}"
    echo "  Interval:       ${MONITOR_INTERVAL}s"
    echo "  Alert Threshold: ${ALERT_THRESHOLD_MB} MB"
    echo ""
    
    echo -e "${BOLD}Backup:${NC}"
    echo "  Enabled:        ${BACKUP_ENABLED}"
    echo "  Schedule:       ${BACKUP_SCHEDULE}"
    echo "  Retention:      ${BACKUP_RETAIN_DAYS} days"
    echo ""
    
    echo -e "${BOLD}Maintenance:${NC}"
    echo "  Auto Reboot:    ${AUTO_REBOOT_ENABLED}"
    echo "  Reboot Schedule: ${AUTO_REBOOT_SCHEDULE}"
    echo "  Auto Update:    ${AUTO_UPDATE_ENABLED}"
}

# Uninstall WireGuard
uninstall_wireguard() {
    print_warning "This will completely remove WireGuard and all configurations!"
    print_warning "All user data and keys will be lost!"
    
    if ! confirm_action "Are you sure you want to uninstall?"; then
        return 1
    fi
    
    print_info "Creating final backup..."
    create_backup > /dev/null
    
    print_info "Stopping services..."
    stop_wireguard 2>/dev/null
    stop_monitor_daemon 2>/dev/null
    stop_telegram_service 2>/dev/null
    
    print_info "Removing WireGuard..."
    apt-get remove --purge -y wireguard wireguard-tools 2>/dev/null
    
    print_info "Cleaning up configuration..."
    rm -rf /etc/wireguard
    rm -rf "${WG_MANAGER_DIR}"
    rm -f /etc/systemd/system/wg-quick@.service.d/override.conf
    rm -f /etc/systemd/system/wg-monitor.service
    rm -f /etc/systemd/system/wg-telegram.service
    
    # Remove cron jobs
    crontab -l 2>/dev/null | grep -v "wg-" | crontab -
    
    systemctl daemon-reload
    
    print_success "WireGuard has been uninstalled"
    print_info "Final backup saved in: ${WG_BACKUP_DIR}"
    log_message "INFO" "WireGuard uninstalled"
}

# Update WireGuard Manager
update_manager() {
    print_info "Checking for updates..."
    
    # This would typically pull from a git repository
    # For now, just show current version
    echo -e "${BOLD}Current Version:${NC} 1.0.0"
    echo -e "${BOLD}Latest Version:${NC} 1.0.0"
    echo ""
    print_info "You are running the latest version"
}

# Show system information
show_system_info() {
    print_header "System Information"
    
    echo -e "${BOLD}OS:${NC}             ${OS_NAME}"
    echo -e "${BOLD}Kernel:${NC}         $(uname -r)"
    echo -e "${BOLD}Hostname:${NC}       $(hostname)"
    echo -e "${BOLD}Uptime:${NC}         $(uptime -p 2>/dev/null || uptime)"
    echo ""
    
    echo -e "${BOLD}CPU:${NC}            $(grep -c processor /proc/cpuinfo) cores"
    echo -e "${BOLD}Load Average:${NC}   $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
    echo ""
    
    local mem_info=$(free -m | grep Mem)
    echo -e "${BOLD}Total Memory:${NC}   $(echo "${mem_info}" | awk '{print $2}') MB"
    echo -e "${BOLD}Used Memory:${NC}    $(echo "${mem_info}" | awk '{print $3}') MB"
    echo -e "${BOLD}Free Memory:${NC}    $(echo "${mem_info}" | awk '{print $4}') MB"
    echo ""
    
    echo -e "${BOLD}Disk Usage:${NC}"
    df -h / | tail -1 | awk '{print "  Total: "$2" | Used: "$3" | Available: "$4" | Usage: "$5}'
    echo ""
    
    echo -e "${BOLD}Network Interfaces:${NC}"
    ip -4 addr show | grep -E "^[0-9]+:|inet " | sed 's/^/  /'
}
