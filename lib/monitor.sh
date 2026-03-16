#!/bin/bash
# Monitoring Functions for WireGuard Manager
# Usage tracking, statistics, and real-time monitoring

# Initialize monitoring
init_monitoring() {
    mkdir -p "${USAGE_LOG_DIR}"
    chmod 700 "${USAGE_LOG_DIR}"
    
    # Create monitoring state file
    local state_file="${WG_MANAGER_DIR}/monitor_state"
    if [[ ! -f "${state_file}" ]]; then
        echo "last_check=$(date +%s)" > "${state_file}"
    fi
    
    print_debug "Monitoring initialized"
}

# Record usage snapshot
record_usage_snapshot() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local epoch=$(date +%s)
    
    if ! is_wireguard_running; then
        print_debug "WireGuard not running, skipping usage snapshot"
        return 1
    fi
    
    # Get all peers transfer data
    wg show "${WG_INTERFACE}" dump | tail -n +2 | while read -r line; do
        local public_key=$(echo "${line}" | awk '{print $1}')
        local rx=$(echo "${line}" | awk '{print $6}')
        local tx=$(echo "${line}" | awk '{print $7}')
        
        # Find username by public key
        local username=$(grep "|${public_key}|" "${USER_DB}" 2>/dev/null | cut -d'|' -f1)
        
        if [[ -n "${username}" ]]; then
            # Calculate delta from last snapshot
            local last_rx=0
            local last_tx=0
            local last_epoch=0
            
            if [[ -f "${USAGE_LOG_DIR}/${username}.log" ]]; then
                local last_line=$(tail -1 "${USAGE_LOG_DIR}/${username}.log")
                last_epoch=$(echo "${last_line}" | cut -d'|' -f1)
                last_rx=$(echo "${last_line}" | cut -d'|' -f3)
                last_tx=$(echo "${last_line}" | cut -d'|' -f4)
            fi
            
            # Calculate delta
            local delta_rx=$((rx - last_rx))
            local delta_tx=$((tx - last_tx))
            
            # Handle counter reset (negative delta)
            [[ ${delta_rx} -lt 0 ]] && delta_rx=${rx}
            [[ ${delta_tx} -lt 0 ]] && delta_tx=${tx}
            
            # Log the snapshot
            echo "${epoch}|${timestamp}|${rx}|${tx}|${delta_rx}|${delta_tx}" >> "${USAGE_LOG_DIR}/${username}.log"
            
            # Check bandwidth limit
            check_bandwidth_limit "${username}" "${rx}" "${tx}"
        fi
    done
    
    # Update state
    echo "last_check=${epoch}" > "${WG_MANAGER_DIR}/monitor_state"
}

# Check bandwidth limit
check_bandwidth_limit() {
    local username="$1"
    local rx="$2"
    local tx="$3"
    
    local limit=$(get_user_field "${username}" 6)
    
    if [[ "${limit}" -gt 0 ]]; then
        local total_mb=$(( (rx + tx) / 1048576 ))
        
        if [[ ${total_mb} -ge ${limit} ]]; then
            print_warning "User '${username}' has exceeded bandwidth limit (${total_mb}/${limit} MB)"
            log_message "WARN" "Bandwidth limit exceeded for ${username}: ${total_mb}/${limit} MB"
            
            # Optionally disable user
            # disable_user "${username}"
        elif [[ ${total_mb} -ge $((limit * 90 / 100)) ]]; then
            print_warning "User '${username}' approaching bandwidth limit (${total_mb}/${limit} MB)"
        fi
    fi
}

# Get real-time statistics
get_realtime_stats() {
    if ! is_wireguard_running; then
        print_error "WireGuard is not running"
        return 1
    fi
    
    print_header "Real-time WireGuard Statistics"
    
    # Server info
    echo -e "${BOLD}Interface:${NC}     ${WG_INTERFACE}"
    echo -e "${BOLD}Server IP:${NC}     ${WG_SERVER_IP}"
    echo -e "${BOLD}Public IP:${NC}     ${SERVER_PUB_IP}:${WG_PORT}"
    echo ""
    
    # Peer statistics
    print_subheader "Connected Peers"
    
    local peer_count=0
    local online_count=0
    
    printf "${BOLD}%-20s %-15s %-20s %-15s %-15s${NC}\n" "USERNAME" "IP" "ENDPOINT" "RX" "TX"
    echo "──────────────────────────────────────────────────────────────────────────────────────────────"
    
    while IFS='|' read -r username ip public_key enabled created bandwidth notes; do
        [[ "${enabled}" != "1" ]] && continue
        
        peer_count=$((peer_count + 1))
        
        local peer_info=$(wg show "${WG_INTERFACE}" dump | grep "^${public_key}")
        
        if [[ -n "${peer_info}" ]]; then
            local endpoint=$(echo "${peer_info}" | awk '{print $3}')
            local last_handshake=$(echo "${peer_info}" | awk '{print $5}')
            local rx=$(echo "${peer_info}" | awk '{print $6}')
            local tx=$(echo "${peer_info}" | awk '{print $7}')
            
            # Check if online (handshake within 3 minutes)
            local status_color="${DIM}"
            if [[ ${last_handshake} -lt 180 && ${last_handshake} -gt 0 ]]; then
                status_color="${GREEN}"
                online_count=$((online_count + 1))
            fi
            
            printf "${status_color}%-20s %-15s %-20s %-15s %-15s${NC}\n" \
                "${username}" "${ip}" "${endpoint}" "$(bytes_to_human ${rx})" "$(bytes_to_human ${tx})"
        else
            printf "${RED}%-20s %-15s %-20s %-15s %-15s${NC}\n" \
                "${username}" "${ip}" "Not Connected" "0 B" "0 B"
        fi
    done < "${USER_DB}"
    
    echo ""
    echo -e "${BOLD}Summary:${NC} ${online_count}/${peer_count} peers online"
}

# Get user usage report
get_user_usage_report() {
    local username="$1"
    local period="${2:-daily}"  # daily, weekly, monthly
    
    if ! user_exists "${username}"; then
        print_error "User '${username}' does not exist"
        return 1
    fi
    
    local log_file="${USAGE_LOG_DIR}/${username}.log"
    
    if [[ ! -f "${log_file}" ]]; then
        print_warning "No usage data for user '${username}'"
        return 1
    fi
    
    print_header "Usage Report: ${username} (${period})"
    
    local now=$(date +%s)
    local start_time=0
    
    case "${period}" in
        daily)
            start_time=$((now - 86400))
            ;;
        weekly)
            start_time=$((now - 604800))
            ;;
        monthly)
            start_time=$((now - 2592000))
            ;;
    esac
    
    local total_rx=0
    local total_tx=0
    local peak_rx=0
    local peak_tx=0
    local session_count=0
    
    while IFS='|' read -r epoch timestamp rx tx delta_rx delta_tx; do
        [[ ${epoch} -lt ${start_time} ]] && continue
        
        total_rx=$((total_rx + delta_rx))
        total_tx=$((total_tx + delta_tx))
        
        [[ ${delta_rx} -gt ${peak_rx} ]] && peak_rx=${delta_rx}
        [[ ${delta_tx} -gt ${peak_tx} ]] && peak_tx=${delta_tx}
        
        [[ ${delta_rx} -gt 0 || ${delta_tx} -gt 0 ]] && session_count=$((session_count + 1))
    done < "${log_file}"
    
    echo -e "${BOLD}Period:${NC}           ${period}"
    echo -e "${BOLD}Total Download:${NC}  $(bytes_to_human ${total_rx})"
    echo -e "${BOLD}Total Upload:${NC}    $(bytes_to_human ${total_tx})"
    echo -e "${BOLD}Total Transfer:${NC}  $(bytes_to_human $((total_rx + total_tx)))"
    echo -e "${BOLD}Peak Download:${NC}   $(bytes_to_human ${peak_rx})/interval"
    echo -e "${BOLD}Peak Upload:${NC}     $(bytes_to_human ${peak_tx})/interval"
    echo -e "${BOLD}Active Sessions:${NC} ${session_count}"
    
    # Bandwidth limit info
    local limit=$(get_user_field "${username}" 6)
    if [[ "${limit}" -gt 0 ]]; then
        local used_mb=$(( (total_rx + total_tx) / 1048576 ))
        local percentage=$((used_mb * 100 / limit))
        echo -e "${BOLD}Bandwidth Limit:${NC} ${used_mb}/${limit} MB (${percentage}%)"
    fi
}

# Get all users usage summary
get_all_usage_summary() {
    local period="${1:-daily}"
    
    print_header "All Users Usage Summary (${period})"
    
    printf "${BOLD}%-20s %-15s %-15s %-15s %-10s${NC}\n" "USERNAME" "DOWNLOAD" "UPLOAD" "TOTAL" "STATUS"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    while IFS='|' read -r username ip public_key enabled created bandwidth notes; do
        local log_file="${USAGE_LOG_DIR}/${username}.log"
        local total_rx=0
        local total_tx=0
        
        if [[ -f "${log_file}" ]]; then
            local now=$(date +%s)
            local start_time=0
            
            case "${period}" in
                daily) start_time=$((now - 86400)) ;;
                weekly) start_time=$((now - 604800)) ;;
                monthly) start_time=$((now - 2592000)) ;;
            esac
            
            while IFS='|' read -r epoch timestamp rx tx delta_rx delta_tx; do
                [[ ${epoch} -lt ${start_time} ]] && continue
                total_rx=$((total_rx + delta_rx))
                total_tx=$((total_tx + delta_tx))
            done < "${log_file}"
        fi
        
        local status=$([ "${enabled}" == "1" ] && echo -e "${GREEN}Active${NC}" || echo -e "${RED}Disabled${NC}")
        
        printf "%-20s %-15s %-15s %-15s %-18b\n" \
            "${username}" \
            "$(bytes_to_human ${total_rx})" \
            "$(bytes_to_human ${total_tx})" \
            "$(bytes_to_human $((total_rx + total_tx)))" \
            "${status}"
    done < "${USER_DB}"
}

# Live monitoring view
live_monitor() {
    local refresh_interval="${1:-5}"
    
    print_info "Starting live monitor (refresh every ${refresh_interval}s). Press Ctrl+C to exit."
    sleep 2
    
    while true; do
        clear
        get_realtime_stats
        echo ""
        echo -e "${DIM}Last updated: $(date '+%Y-%m-%d %H:%M:%S') | Refresh: ${refresh_interval}s | Press Ctrl+C to exit${NC}"
        sleep "${refresh_interval}"
    done
}

# Get server load statistics
get_server_load() {
    print_header "Server Statistics"
    
    # System info
    echo -e "${BOLD}Hostname:${NC}      $(hostname)"
    echo -e "${BOLD}Uptime:${NC}        $(uptime -p 2>/dev/null || uptime)"
    echo -e "${BOLD}Load Average:${NC}  $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
    echo ""
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo -e "${BOLD}CPU Usage:${NC}     ${cpu_usage}%"
    
    # Memory usage
    local mem_info=$(free -m | grep Mem)
    local mem_total=$(echo "${mem_info}" | awk '{print $2}')
    local mem_used=$(echo "${mem_info}" | awk '{print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))
    echo -e "${BOLD}Memory:${NC}        ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"
    
    # Disk usage
    local disk_info=$(df -h / | tail -1)
    local disk_used=$(echo "${disk_info}" | awk '{print $3}')
    local disk_total=$(echo "${disk_info}" | awk '{print $2}')
    local disk_percent=$(echo "${disk_info}" | awk '{print $5}')
    echo -e "${BOLD}Disk:${NC}          ${disk_used} / ${disk_total} (${disk_percent})"
    echo ""
    
    # Network statistics
    print_subheader "Network Interface: ${SERVER_PUB_NIC}"
    local net_stats=$(cat "/sys/class/net/${SERVER_PUB_NIC}/statistics/rx_bytes" 2>/dev/null || echo 0)
    local net_tx=$(cat "/sys/class/net/${SERVER_PUB_NIC}/statistics/tx_bytes" 2>/dev/null || echo 0)
    echo -e "${BOLD}Total RX:${NC}      $(bytes_to_human ${net_stats})"
    echo -e "${BOLD}Total TX:${NC}      $(bytes_to_human ${net_tx})"
    echo ""
    
    # WireGuard statistics
    if is_wireguard_running; then
        print_subheader "WireGuard Interface: ${WG_INTERFACE}"
        local wg_rx=$(wg show "${WG_INTERFACE}" transfer | awk '{sum+=$2} END {print sum}')
        local wg_tx=$(wg show "${WG_INTERFACE}" transfer | awk '{sum+=$3} END {print sum}')
        local peer_count=$(wg show "${WG_INTERFACE}" peers | wc -l)
        
        echo -e "${BOLD}Peers:${NC}         ${peer_count}"
        echo -e "${BOLD}Total RX:${NC}      $(bytes_to_human ${wg_rx:-0})"
        echo -e "${BOLD}Total TX:${NC}      $(bytes_to_human ${wg_tx:-0})"
    fi
}

# Generate usage report file
generate_usage_report() {
    local output_dir="${WG_BACKUP_DIR}/reports"
    local report_file="${output_dir}/usage_report_$(date +%Y%m%d_%H%M%S).txt"
    
    mkdir -p "${output_dir}"
    
    {
        echo "=========================================="
        echo "WireGuard VPN Usage Report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
        echo ""
        
        echo "--- Server Information ---"
        echo "Hostname: $(hostname)"
        echo "Public IP: ${SERVER_PUB_IP}"
        echo "Interface: ${WG_INTERFACE}"
        echo "Port: ${WG_PORT}"
        echo ""
        
        echo "--- User Summary ---"
        get_user_count
        echo ""
        
        echo "--- Daily Usage ---"
        while IFS='|' read -r username ip public_key enabled created bandwidth notes; do
            local log_file="${USAGE_LOG_DIR}/${username}.log"
            local total_rx=0
            local total_tx=0
            
            if [[ -f "${log_file}" ]]; then
                local now=$(date +%s)
                local start_time=$((now - 86400))
                
                while IFS='|' read -r epoch timestamp rx tx delta_rx delta_tx; do
                    [[ ${epoch} -lt ${start_time} ]] && continue
                    total_rx=$((total_rx + delta_rx))
                    total_tx=$((total_tx + delta_tx))
                done < "${log_file}"
            fi
            
            local status=$([ "${enabled}" == "1" ] && echo "Active" || echo "Disabled")
            echo "${username} | ${ip} | ${status} | RX: $(bytes_to_human ${total_rx}) | TX: $(bytes_to_human ${total_tx})"
        done < "${USER_DB}"
        echo ""
        
        echo "--- System Resources ---"
        echo "Load: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
        echo "Memory: $(free -m | grep Mem | awk '{printf "%.1f%%", $3/$2*100}')"
        echo "Disk: $(df -h / | tail -1 | awk '{print $5}')"
        
    } > "${report_file}"
    
    print_success "Report generated: ${report_file}"
    echo "${report_file}"
}

# Start monitoring daemon
start_monitor_daemon() {
    local interval="${MONITOR_INTERVAL:-60}"
    
    print_info "Starting monitoring daemon (interval: ${interval}s)..."
    
    # Create systemd service
    cat > /etc/systemd/system/wg-monitor.service << EOF
[Unit]
Description=WireGuard Usage Monitor
After=wg-quick@${WG_INTERFACE}.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do ${SCRIPT_DIR}/wg-manager.sh --record-usage; sleep ${interval}; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable wg-monitor.service
    systemctl start wg-monitor.service
    
    print_success "Monitoring daemon started"
}

# Stop monitoring daemon
stop_monitor_daemon() {
    systemctl stop wg-monitor.service 2>/dev/null
    systemctl disable wg-monitor.service 2>/dev/null
    rm -f /etc/systemd/system/wg-monitor.service
    systemctl daemon-reload
    
    print_success "Monitoring daemon stopped"
}

# Get monitoring daemon status
get_monitor_status() {
    if systemctl is-active --quiet wg-monitor.service 2>/dev/null; then
        echo -e "${GREEN}● Running${NC}"
    else
        echo -e "${RED}● Stopped${NC}"
    fi
}

# Clean old usage logs
clean_old_logs() {
    local days="${1:-90}"
    
    print_info "Cleaning usage logs older than ${days} days..."
    
    find "${USAGE_LOG_DIR}" -name "*.log" -mtime +${days} -delete 2>/dev/null
    
    print_success "Old logs cleaned"
}

# Export usage data
export_usage_data() {
    local output_file="${WG_BACKUP_DIR}/usage_export_$(date +%Y%m%d).csv"
    
    echo "username,timestamp,rx_bytes,tx_bytes,delta_rx,delta_tx" > "${output_file}"
    
    for log_file in "${USAGE_LOG_DIR}"/*.log; do
        [[ ! -f "${log_file}" ]] && continue
        
        local username=$(basename "${log_file}" .log)
        
        while IFS='|' read -r epoch timestamp rx tx delta_rx delta_tx; do
            echo "${username},${timestamp},${rx},${tx},${delta_rx},${delta_tx}"
        done < "${log_file}"
    done >> "${output_file}"
    
    print_success "Usage data exported to: ${output_file}"
}
