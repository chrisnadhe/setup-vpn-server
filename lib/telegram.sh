#!/bin/bash
# Telegram Bot Functions for WireGuard Manager
# Remote management via Telegram bot

# Telegram API base URL
TELEGRAM_API="https://api.telegram.org/bot"

# Initialize Telegram bot
init_telegram() {
    if [[ "${TELEGRAM_ENABLED}" != "true" ]]; then
        print_debug "Telegram bot is disabled"
        return 1
    fi
    
    if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
        print_error "Telegram bot token not configured"
        return 1
    fi
    
    # Test bot token
    local response=$(telegram_api "getMe")
    local ok=$(echo "${response}" | jq -r '.ok' 2>/dev/null)
    
    if [[ "${ok}" == "true" ]]; then
        local bot_name=$(echo "${response}" | jq -r '.result.username')
        print_success "Telegram bot initialized: @${bot_name}"
        log_message "INFO" "Telegram bot initialized: @${bot_name}"
        return 0
    else
        print_error "Invalid Telegram bot token"
        return 1
    fi
}

# Make Telegram API call
telegram_api() {
    local method="$1"
    local data="$2"
    
    if [[ -n "${data}" ]]; then
        curl -s -X POST "${TELEGRAM_API}${TELEGRAM_BOT_TOKEN}/${method}" \
            -H "Content-Type: application/json" \
            -d "${data}"
    else
        curl -s "${TELEGRAM_API}${TELEGRAM_BOT_TOKEN}/${method}"
    fi
}

# Send message to Telegram
send_telegram_message() {
    local chat_id="$1"
    local text="$2"
    local parse_mode="${3:-HTML}"
    
    # Use jq with raw input to preserve HTML tags
    local data=$(printf '%s' "${text}" | jq -R -s \
        --arg chat_id "${chat_id}" \
        --arg parse_mode "${parse_mode}" \
        '{chat_id: $chat_id, text: ., parse_mode: $parse_mode}')
    
    telegram_api "sendMessage" "${data}" > /dev/null
}

# Send message with keyboard
send_telegram_keyboard() {
    local chat_id="$1"
    local text="$2"
    local keyboard="$3"  # JSON array of buttons
    
    local data=$(printf '%s' "${text}" | jq -R -s \
        --arg chat_id "${chat_id}" \
        --argjson keyboard "${keyboard}" \
        '{chat_id: $chat_id, text: ., parse_mode: "HTML", reply_markup: {keyboard: $keyboard, resize_keyboard: true}}')
    
    telegram_api "sendMessage" "${data}" > /dev/null
}

# Send inline keyboard
send_telegram_inline_keyboard() {
    local chat_id="$1"
    local text="$2"
    local keyboard="$3"
    
    local data=$(printf '%s' "${text}" | jq -R -s \
        --arg chat_id "${chat_id}" \
        --argjson keyboard "${keyboard}" \
        '{chat_id: $chat_id, text: ., parse_mode: "HTML", reply_markup: {inline_keyboard: $keyboard}}')
    
    telegram_api "sendMessage" "${data}" > /dev/null
}

# Check if user is authorized
is_telegram_authorized() {
    local chat_id="$1"
    
    # Check if chat_id is in allowed users list
    if [[ -z "${TELEGRAM_ALLOWED_USERS}" ]]; then
        return 1
    fi
    
    echo "${TELEGRAM_ALLOWED_USERS}" | tr ',' '\n' | grep -q "^${chat_id}$"
}

# Add authorized user
add_telegram_authorized_user() {
    local chat_id="$1"
    
    if [[ -z "${TELEGRAM_ALLOWED_USERS}" ]]; then
        TELEGRAM_ALLOWED_USERS="${chat_id}"
    else
        TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS},${chat_id}"
    fi
    
    save_config
    print_success "Added authorized Telegram user: ${chat_id}"
}

# Remove authorized user
remove_telegram_authorized_user() {
    local chat_id="$1"
    
    TELEGRAM_ALLOWED_USERS=$(echo "${TELEGRAM_ALLOWED_USERS}" | tr ',' '\n' | grep -v "^${chat_id}$" | tr '\n' ',' | sed 's/,$//')
    
    save_config
    print_success "Removed authorized Telegram user: ${chat_id}"
}

# List authorized users
list_telegram_authorized_users() {
    if [[ -z "${TELEGRAM_ALLOWED_USERS}" ]]; then
        echo "No authorized users"
    else
        echo "Authorized users:"
        echo "${TELEGRAM_ALLOWED_USERS}" | tr ',' '\n' | while read -r chat_id; do
            echo "  - ${chat_id}"
        done
    fi
}

# Process Telegram command
process_telegram_command() {
    local chat_id="$1"
    local command="$2"
    local args="$3"
    
    # Check authorization
    if ! is_telegram_authorized "${chat_id}"; then
        send_telegram_message "${chat_id}" "⛔ Unauthorized. Your chat ID: ${chat_id}"
        log_message "WARN" "Unauthorized Telegram access attempt from chat_id: ${chat_id}"
        return 1
    fi
    
    log_message "INFO" "Telegram command from ${chat_id}: ${command} ${args}"
    
    case "${command}" in
        /start)
            cmd_telegram_start "${chat_id}"
            ;;
        /help)
            cmd_telegram_help "${chat_id}"
            ;;
        /status)
            cmd_telegram_status "${chat_id}"
            ;;
        /users)
            cmd_telegram_users "${chat_id}"
            ;;
        /adduser)
            cmd_telegram_adduser "${chat_id}" "${args}"
            ;;
        /deluser)
            cmd_telegram_deluser "${chat_id}" "${args}"
            ;;
        /enableuser)
            cmd_telegram_enableuser "${chat_id}" "${args}"
            ;;
        /disableuser)
            cmd_telegram_disableuser "${chat_id}" "${args}"
            ;;
        /userinfo)
            cmd_telegram_userinfo "${chat_id}" "${args}"
            ;;
        /usage)
            cmd_telegram_usage "${chat_id}" "${args}"
            ;;
        /config)
            cmd_telegram_config "${chat_id}" "${args}"
            ;;
        /qr)
            cmd_telegram_qr "${chat_id}" "${args}"
            ;;
        /getconfig)
            cmd_telegram_getconfig "${chat_id}" "${args}"
            ;;
        /backup)
            cmd_telegram_backup "${chat_id}"
            ;;
        /restart)
            cmd_telegram_restart "${chat_id}"
            ;;
        /reboot)
            cmd_telegram_reboot "${chat_id}"
            ;;
        /menu)
            cmd_telegram_menu "${chat_id}"
            ;;
        *)
            local unknown_msg="❓ Unknown command: ${command}

Type /help for available commands."
            send_telegram_message "${chat_id}" "${unknown_msg}"
            ;;
    esac
}

# Command: /start
cmd_telegram_start() {
    local chat_id="$1"
    
    local message="🤖 <b>WireGuard VPN Manager Bot</b>

Welcome! This bot allows you to manage your WireGuard VPN server remotely.

Your Chat ID: <code>${chat_id}</code>

Type /help to see available commands or /menu for quick actions."
    
    send_telegram_message "${chat_id}" "${message}"
}

# Command: /help
cmd_telegram_help() {
    local chat_id="$1"
    
    local message="📖 <b>Available Commands</b>

<b>User Management:</b>
/users - List all VPN users
/adduser &lt;name&gt; - Add new user
/deluser &lt;name&gt; - Delete user
/enableuser &lt;name&gt; - Enable user
/disableuser &lt;name&gt; - Disable user
/userinfo &lt;name&gt; - User details
/usage &lt;name&gt; - User usage stats
/qr &lt;name&gt; - Get QR code for user
/getconfig &lt;name&gt; - Download config file

<b>Server Management:</b>
/status - Server status
/config - View/edit configuration
/backup - Create backup
/restart - Restart WireGuard
/reboot - Reboot server

<b>Other:</b>
/menu - Show quick action menu
/help - Show this help message"
    
    send_telegram_message "${chat_id}" "${message}"
}

# Command: /status
cmd_telegram_status() {
    local chat_id="$1"
    
    local wg_status="Stopped"
    if is_wireguard_running; then
        wg_status="Running"
    fi
    
    local peer_count=0
    local online_count=0
    local total_rx=0
    local total_tx=0
    
    if is_wireguard_running; then
        peer_count=$(wg show "${WG_INTERFACE}" peers 2>/dev/null | wc -l)
        
        while IFS='|' read -r username ip public_key enabled created bandwidth notes; do
            [[ "${enabled}" != "1" ]] && continue
            
            if is_peer_connected "${public_key}"; then
                online_count=$((online_count + 1))
            fi
        done < "${USER_DB}"
        
        total_rx=$(wg show "${WG_INTERFACE}" transfer 2>/dev/null | awk '{sum+=$2} END {print sum}')
        total_tx=$(wg show "${WG_INTERFACE}" transfer 2>/dev/null | awk '{sum+=$3} END {print sum}')
    fi
    
    local load=$(cat /proc/loadavg | awk '{print $1}')
    local mem_info=$(free -m | grep Mem)
    local mem_used=$(echo "${mem_info}" | awk '{print $3}')
    local mem_total=$(echo "${mem_info}" | awk '{print $2}')
    local mem_percent=$((mem_used * 100 / mem_total))
    
    local message="🖥️ <b>Server Status</b>

<b>WireGuard:</b> ${wg_status}
<b>Interface:</b> ${WG_INTERFACE}
<b>Port:</b> ${WG_PORT}

<b>Users:</b> ${online_count}/${peer_count} online
<b>Total RX:</b> $(bytes_to_human ${total_rx:-0})
<b>Total TX:</b> $(bytes_to_human ${total_tx:-0})

<b>System:</b>
Load: ${load}
Memory: ${mem_used}/${mem_total} MB (${mem_percent}%)
Uptime: $(uptime -p 2>/dev/null || echo "N/A")"
    
    send_telegram_message "${chat_id}" "${message}"
}

# Command: /users
cmd_telegram_users() {
    local chat_id="$1"
    
    if [[ ! -s "${USER_DB}" ]]; then
        send_telegram_message "${chat_id}" "📭 No users found"
        return
    fi
    
    local message="👥 <b>VPN Users</b>

"
    
    while IFS='|' read -r username ip public_key enabled created bandwidth notes; do
        local status="❌"
        if [[ "${enabled}" == "1" ]]; then
            if is_peer_connected "${public_key}"; then
                status="🟢"
            else
                status="🟡"
            fi
        fi
        
        message+="${status} <b>${username}</b> - ${ip}
"
    done < "${USER_DB}"
    
    send_telegram_message "${chat_id}" "${message}"
}

# Command: /adduser
cmd_telegram_adduser() {
    local chat_id="$1"
    local username="$2"
    
    if [[ -z "${username}" ]]; then
        send_telegram_message "${chat_id}" "❓ Usage: /adduser <username>"
        return
    fi
    
    # Run add user command
    local result=$(add_user "${username}" 2>&1)
    local exit_code=$?
    
    if [[ ${exit_code} -eq 0 ]]; then
        local ip=$(get_user_field "${username}" 2)
        local message="✅ User <b>${username}</b> created successfully!

IP: <code>${ip}</code>

Use /qr ${username} to get QR code or /getconfig ${username} to download config."
        send_telegram_message "${chat_id}" "${message}"
    else
        local message="❌ Failed to create user:

${result}"
        send_telegram_message "${chat_id}" "${message}"
    fi
}

# Command: /deluser
cmd_telegram_deluser() {
    local chat_id="$1"
    local username="$2"
    
    if [[ -z "${username}" ]]; then
        send_telegram_message "${chat_id}" "❓ Usage: /deluser &lt;username&gt;"
        return
    fi
    
    # Confirm deletion with inline keyboard
    local keyboard='[[{"text":"✅ Yes, delete","callback_data":"deluser_confirm_'${username}'"},{"text":"❌ Cancel","callback_data":"deluser_cancel"}]]'
    
    send_telegram_inline_keyboard "${chat_id}" "⚠️ Are you sure you want to delete user <b>${username}</b>?" "${keyboard}"
}

# Command: /enableuser
cmd_telegram_enableuser() {
    local chat_id="$1"
    local username="$2"
    
    if [[ -z "${username}" ]]; then
        send_telegram_message "${chat_id}" "❓ Usage: /enableuser &lt;username&gt;"
        return
    fi
    
    enable_user "${username}" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        send_telegram_message "${chat_id}" "✅ User <b>${username}</b> enabled"
    else
        send_telegram_message "${chat_id}" "❌ Failed to enable user <b>${username}</b>"
    fi
}

# Command: /disableuser
cmd_telegram_disableuser() {
    local chat_id="$1"
    local username="$2"
    
    if [[ -z "${username}" ]]; then
        send_telegram_message "${chat_id}" "❓ Usage: /disableuser &lt;username&gt;"
        return
    fi
    
    disable_user "${username}" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        send_telegram_message "${chat_id}" "✅ User <b>${username}</b> disabled"
    else
        send_telegram_message "${chat_id}" "❌ Failed to disable user <b>${username}</b>"
    fi
}

# Command: /userinfo
cmd_telegram_userinfo() {
    local chat_id="$1"
    local username="$2"
    
    if [[ -z "${username}" ]]; then
        send_telegram_message "${chat_id}" "❓ Usage: /userinfo &lt;username&gt;"
        return
    fi
    
    if ! user_exists "${username}"; then
        send_telegram_message "${chat_id}" "❌ User <b>${username}</b> not found"
        return
    fi
    
    local ip=$(get_user_field "${username}" 2)
    local enabled=$(get_user_field "${username}" 4)
    local created=$(get_user_field "${username}" 5)
    local bandwidth=$(get_user_field "${username}" 6)
    local notes=$(get_user_field "${username}" 7)
    
    local status="Disabled"
    [[ "${enabled}" == "1" ]] && status="Enabled"
    
    local limit_text="Unlimited"
    [[ "${bandwidth}" -gt 0 ]] && limit_text="${bandwidth} MB"
    
    # Get current session
    local session_info=""
    if [[ "${enabled}" == "1" ]]; then
        local public_key=$(get_user_field "${username}" 3)
        local peer_info=$(wg show "${WG_INTERFACE}" dump 2>/dev/null | grep "^${public_key}")
        
        if [[ -n "${peer_info}" ]]; then
            local last_handshake=$(echo "${peer_info}" | awk '{print $5}')
            local rx=$(echo "${peer_info}" | awk '{print $6}')
            local tx=$(echo "${peer_info}" | awk '{print $7}')
            
            if [[ ${last_handshake} -lt 180 && ${last_handshake} -gt 0 ]]; then
                session_info="
<b>Current Session:</b>
Last seen: ${last_handshake}s ago
RX: $(bytes_to_human ${rx})
TX: $(bytes_to_human ${tx})"
            else
                session_info="
<b>Status:</b> Offline"
            fi
        fi
    fi
    
    local message="👤 <b>User: ${username}</b>

<b>IP:</b> ${ip}
<b>Status:</b> ${status}
<b>Created:</b> ${created}
<b>Bandwidth Limit:</b> ${limit_text}
<b>Notes:</b> ${notes:-None}${session_info}"
    
    send_telegram_message "${chat_id}" "${message}"
}

# Command: /usage
cmd_telegram_usage() {
    local chat_id="$1"
    local username="$2"
    
    if [[ -z "${username}" ]]; then
        # Show all users usage
        local message="📊 <b>All Users Usage (Today)</b>

"
        
        while IFS='|' read -r user ip public_key enabled created bandwidth notes; do
            local log_file="${USAGE_LOG_DIR}/${user}.log"
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
            
            message+="<b>${user}</b>: ↓$(bytes_to_human ${total_rx}) ↑$(bytes_to_human ${total_tx})
"
        done < "${USER_DB}"
        
        send_telegram_message "${chat_id}" "${message}"
        return
    fi
    
    if ! user_exists "${username}"; then
        send_telegram_message "${chat_id}" "❌ User <b>${username}</b> not found"
        return
    fi
    
    local log_file="${USAGE_LOG_DIR}/${username}.log"
    
    if [[ ! -f "${log_file}" ]]; then
        send_telegram_message "${chat_id}" "📭 No usage data for <b>${username}</b>"
        return
    fi
    
    # Calculate usage for different periods
    local now=$(date +%s)
    local daily_rx=0 daily_tx=0
    local weekly_rx=0 weekly_tx=0
    local monthly_rx=0 monthly_tx=0
    
    while IFS='|' read -r epoch timestamp rx tx delta_rx delta_tx; do
        # Daily
        if [[ ${epoch} -ge $((now - 86400)) ]]; then
            daily_rx=$((daily_rx + delta_rx))
            daily_tx=$((daily_tx + delta_tx))
        fi
        # Weekly
        if [[ ${epoch} -ge $((now - 604800)) ]]; then
            weekly_rx=$((weekly_rx + delta_rx))
            weekly_tx=$((weekly_tx + delta_tx))
        fi
        # Monthly
        if [[ ${epoch} -ge $((now - 2592000)) ]]; then
            monthly_rx=$((monthly_rx + delta_rx))
            monthly_tx=$((monthly_tx + delta_tx))
        fi
    done < "${log_file}"
    
    local message="📊 <b>Usage: ${username}</b>

<b>Today:</b>
↓ $(bytes_to_human ${daily_rx}) | ↑ $(bytes_to_human ${daily_tx})

<b>This Week:</b>
↓ $(bytes_to_human ${weekly_rx}) | ↑ $(bytes_to_human ${weekly_tx})

<b>This Month:</b>
↓ $(bytes_to_human ${monthly_rx}) | ↑ $(bytes_to_human ${monthly_tx})"
    
    send_telegram_message "${chat_id}" "${message}"
}

# Command: /config
cmd_telegram_config() {
    local chat_id="$1"
    local action="$2"
    
    if [[ "${action}" == "show" ]]; then
        local message="⚙️ <b>Server Configuration</b>

<b>Interface:</b> ${WG_INTERFACE}
<b>Port:</b> ${WG_PORT}
<b>Subnet:</b> ${WG_SUBNET}
<b>Server IP:</b> ${WG_SERVER_IP}
<b>DNS:</b> ${WG_DNS}
<b>MTU:</b> ${WG_MTU}
<b>Public IP:</b> ${SERVER_PUB_IP}"
        
        send_telegram_message "${chat_id}" "${message}"
    else
        local config_help="⚙️ <b>Config Commands:</b>

/config show - Show current config"
        send_telegram_message "${chat_id}" "${config_help}"
    fi
}

# Command: /qr
cmd_telegram_qr() {
    local chat_id="$1"
    local username="$2"
    
    if [[ -z "${username}" ]]; then
        send_telegram_message "${chat_id}" "❓ Usage: /qr &lt;username&gt;"
        return
    fi
    
    if ! user_exists "${username}"; then
        send_telegram_message "${chat_id}" "❌ User <b>${username}</b> not found"
        return
    fi
    
    local config_file="${WG_USERS_DIR}/${username}/client.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        send_telegram_message "${chat_id}" "❌ Config file not found for <b>${username}</b>"
        return
    fi
    
    # Generate QR code as image and send
    local qr_file="/tmp/wg_qr_${username}.png"
    qrencode -o "${qr_file}" -t PNG < "${config_file}" 2>/dev/null
    
    if [[ -f "${qr_file}" ]]; then
        # Send photo
        curl -s -X POST "${TELEGRAM_API}${TELEGRAM_BOT_TOKEN}/sendPhoto" \
            -F "chat_id=${chat_id}" \
            -F "photo=@${qr_file}" \
            -F "caption=QR Code for ${username}" > /dev/null
        
        rm -f "${qr_file}"
    else
        # Fallback: send config as text
        local config_content=$(cat "${config_file}")
        local qr_fallback="📱 <b>Config for ${username}</b>

<code>${config_content}</code>"
        send_telegram_message "${chat_id}" "${qr_fallback}"
    fi
}

# Command: /getconfig - Send config file as document
cmd_telegram_getconfig() {
    local chat_id="$1"
    local username="$2"
    
    if [[ -z "${username}" ]]; then
        send_telegram_message "${chat_id}" "❓ Usage: /getconfig &lt;username&gt;"
        return
    fi
    
    if ! user_exists "${username}"; then
        send_telegram_message "${chat_id}" "❌ User <b>${username}</b> not found"
        return
    fi
    
    local config_file="${WG_USERS_DIR}/${username}/client.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        send_telegram_message "${chat_id}" "❌ Config file not found for <b>${username}</b>"
        return
    fi
    
    send_telegram_message "${chat_id}" "📄 Sending configuration file for <b>${username}</b>..."
    
    # Send config file as document
    local response=$(curl -s -X POST "${TELEGRAM_API}${TELEGRAM_BOT_TOKEN}/sendDocument" \
        -F "chat_id=${chat_id}" \
        -F "document=@${config_file}" \
        -F "caption=WireGuard config for ${username}")
    
    # Check if send was successful
    local ok=$(echo "${response}" | jq -r '.ok' 2>/dev/null)
    if [[ "${ok}" == "true" ]]; then
        send_telegram_message "${chat_id}" "✅ Configuration file sent! Import it in your WireGuard client."
    else
        # Fallback: send as text message
        local config_content=$(cat "${config_file}")
        local config_fallback="📄 <b>Config for ${username}</b> (copy and save as .conf):

<code>${config_content}</code>"
        send_telegram_message "${chat_id}" "${config_fallback}"
    fi
}

# Command: /backup
cmd_telegram_backup() {
    local chat_id="$1"
    
    send_telegram_message "${chat_id}" "⏳ Creating backup..."
    
    local backup_file=$(create_backup 2>/dev/null)
    
    if [[ -f "${backup_file}" ]]; then
        local backup_msg="✅ Backup created successfully!

File: <code>$(basename "${backup_file}")</code>"
        send_telegram_message "${chat_id}" "${backup_msg}"
    else
        send_telegram_message "${chat_id}" "❌ Backup failed"
    fi
}

# Command: /restart
cmd_telegram_restart() {
    local chat_id="$1"
    
    send_telegram_message "${chat_id}" "⏳ Restarting WireGuard..."
    
    restart_wireguard 2>/dev/null
    
    if is_wireguard_running; then
        send_telegram_message "${chat_id}" "✅ WireGuard restarted successfully"
    else
        send_telegram_message "${chat_id}" "❌ Failed to restart WireGuard"
    fi
}

# Command: /reboot
cmd_telegram_reboot() {
    local chat_id="$1"
    
    # Confirm with inline keyboard
    local keyboard='[[{"text":"✅ Yes, reboot","callback_data":"reboot_confirm"},{"text":"❌ Cancel","callback_data":"reboot_cancel"}]]'
    
    send_telegram_inline_keyboard "${chat_id}" "⚠️ Are you sure you want to reboot the server?" "${keyboard}"
}

# Command: /menu
cmd_telegram_menu() {
    local chat_id="$1"
    
    local keyboard='[
        [{"text":"📊 Status","callback_data":"menu_status"},{"text":"👥 Users","callback_data":"menu_users"}],
        [{"text":"➕ Add User","callback_data":"menu_adduser"},{"text":"📈 Usage","callback_data":"menu_usage"}],
        [{"text":"📄 Get Config","callback_data":"menu_getconfig"},{"text":"📱 QR Code","callback_data":"menu_qr"}],
        [{"text":"⚙️ Config","callback_data":"menu_config"},{"text":"💾 Backup","callback_data":"menu_backup"}],
        [{"text":"🔄 Restart","callback_data":"menu_restart"},{"text":"❓ Help","callback_data":"menu_help"}]
    ]'
    
    local menu_msg="🤖 <b>WireGuard Manager</b>

Select an action:"
    send_telegram_inline_keyboard "${chat_id}" "${menu_msg}" "${keyboard}"
}

# Process callback query
process_callback_query() {
    local callback_query_id="$1"
    local chat_id="$2"
    local data="$3"
    
    # Answer callback query
    telegram_api "answerCallbackQuery" "{\"callback_query_id\":\"${callback_query_id}\"}" > /dev/null
    
    case "${data}" in
        menu_status)
            cmd_telegram_status "${chat_id}"
            ;;
        menu_users)
            cmd_telegram_users "${chat_id}"
            ;;
        menu_adduser)
            send_telegram_message "${chat_id}" "Send: /adduser &lt;username&gt;"
            ;;
        menu_usage)
            cmd_telegram_usage "${chat_id}"
            ;;
        menu_config)
            cmd_telegram_config "${chat_id}" "show"
            ;;
        menu_backup)
            cmd_telegram_backup "${chat_id}"
            ;;
        menu_restart)
            cmd_telegram_restart "${chat_id}"
            ;;
        menu_help)
            cmd_telegram_help "${chat_id}"
            ;;
        menu_getconfig)
            send_telegram_message "${chat_id}" "Send: /getconfig &lt;username&gt;"
            ;;
        menu_qr)
            send_telegram_message "${chat_id}" "Send: /qr &lt;username&gt;"
            ;;
        deluser_confirm_*)
            local username="${data#deluser_confirm_}"
            delete_user "${username}" 2>/dev/null
            send_telegram_message "${chat_id}" "✅ User <b>${username}</b> deleted"
            ;;
        deluser_cancel)
            send_telegram_message "${chat_id}" "❌ Deletion cancelled"
            ;;
        reboot_confirm)
            send_telegram_message "${chat_id}" "🔄 Rebooting server..."
            sleep 2
            reboot
            ;;
        reboot_cancel)
            send_telegram_message "${chat_id}" "❌ Reboot cancelled"
            ;;
    esac
}

# Start Telegram bot polling
start_telegram_bot() {
    if [[ "${TELEGRAM_ENABLED}" != "true" ]]; then
        print_error "Telegram bot is not enabled"
        return 1
    fi
    
    print_info "Starting Telegram bot polling..."
    
    local offset=0
    local offset_file="/tmp/wg_telegram_offset"
    
    # Load saved offset if exists
    if [[ -f "${offset_file}" ]]; then
        offset=$(cat "${offset_file}" 2>/dev/null || echo 0)
    fi
    
    while true; do
        # Get updates
        local updates=$(telegram_api "getUpdates?offset=${offset}&timeout=30" 2>/dev/null)
        
        # Check if we got valid response
        local ok=$(echo "${updates}" | jq -r '.ok' 2>/dev/null)
        if [[ "${ok}" != "true" ]]; then
            sleep 5
            continue
        fi
        
        # Get number of results
        local result_count=$(echo "${updates}" | jq '.result | length' 2>/dev/null || echo 0)
        
        if [[ ${result_count} -gt 0 ]]; then
            # Process each update using index to avoid subshell
            for ((i=0; i<result_count; i++)); do
                local update=$(echo "${updates}" | jq -c ".result[${i}]" 2>/dev/null)
                
                # Get update_id and update offset
                local update_id=$(echo "${update}" | jq -r '.update_id' 2>/dev/null)
                offset=$((update_id + 1))
                echo "${offset}" > "${offset_file}"
                
                # Check for message
                local message=$(echo "${update}" | jq -r '.message // empty' 2>/dev/null)
                if [[ -n "${message}" && "${message}" != "null" ]]; then
                    local chat_id=$(echo "${update}" | jq -r '.message.chat.id' 2>/dev/null)
                    local text=$(echo "${update}" | jq -r '.message.text // empty' 2>/dev/null)
                    
                    if [[ "${text}" == /* ]]; then
                        local command=$(echo "${text}" | awk '{print $1}')
                        local args=$(echo "${text}" | cut -d' ' -f2-)
                        
                        process_telegram_command "${chat_id}" "${command}" "${args}"
                    fi
                fi
                
                # Check for callback query
                local callback_query=$(echo "${update}" | jq -r '.callback_query // empty' 2>/dev/null)
                if [[ -n "${callback_query}" && "${callback_query}" != "null" ]]; then
                    local callback_query_id=$(echo "${update}" | jq -r '.callback_query.id' 2>/dev/null)
                    local chat_id=$(echo "${update}" | jq -r '.callback_query.message.chat.id' 2>/dev/null)
                    local data=$(echo "${update}" | jq -r '.callback_query.data' 2>/dev/null)
                    
                    process_callback_query "${callback_query_id}" "${chat_id}" "${data}"
                fi
            done
        fi
        
        sleep 1
    done
}

# Create Telegram bot systemd service
create_telegram_service() {
    cat > /etc/systemd/system/wg-telegram.service << EOF
[Unit]
Description=WireGuard Telegram Bot
After=network.target wg-quick@${WG_INTERFACE}.service

[Service]
Type=simple
ExecStart=/bin/bash ${SCRIPT_DIR}/wg-manager.sh --telegram-bot
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable wg-telegram.service
    systemctl start wg-telegram.service
    
    print_success "Telegram bot service created and started"
}

# Stop Telegram bot service
stop_telegram_service() {
    systemctl stop wg-telegram.service 2>/dev/null
    systemctl disable wg-telegram.service 2>/dev/null
    rm -f /etc/systemd/system/wg-telegram.service
    systemctl daemon-reload
    
    print_success "Telegram bot service stopped"
}

# Get Telegram bot status
get_telegram_status() {
    if systemctl is-active --quiet wg-telegram.service 2>/dev/null; then
        echo -e "${GREEN}● Running${NC}"
    else
        echo -e "${RED}● Stopped${NC}"
    fi
}
