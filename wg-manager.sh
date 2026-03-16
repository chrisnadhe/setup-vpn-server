#!/bin/bash
# WireGuard VPN Manager CLI
# Interactive menu-driven interface for daily operations
# Version: 1.0.0

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/core.sh"
source "${SCRIPT_DIR}/lib/users.sh"
source "${SCRIPT_DIR}/lib/monitor.sh"
source "${SCRIPT_DIR}/lib/telegram.sh"
source "${SCRIPT_DIR}/lib/server.sh"

# Version
VERSION="1.0.0"

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
    echo -e "${DIM}VPN Server Management CLI v${VERSION}${NC}"
    echo ""
}

# Main menu
main_menu() {
    while true; do
        show_banner
        
        # Show quick status
        echo -e "${BOLD}Quick Status:${NC}"
        echo -e "  WireGuard: $(get_wireguard_status)"
        echo -e "  Users: $(get_user_count)"
        echo -e "  Server: ${SERVER_PUB_IP}:${WG_PORT}"
        echo ""
        
        echo -e "${BOLD}Main Menu:${NC}"
        echo ""
        echo "  1) User Management"
        echo "  2) Monitoring & Statistics"
        echo "  3) Server Management"
        echo "  4) Telegram Bot"
        echo "  5) Configuration"
        echo ""
        echo "  0) Exit"
        echo ""
        
        read -rp "$(echo -e "${CYAN}Select option [0-5]: ${NC}")" choice
        
        case "${choice}" in
            1) user_management_menu ;;
            2) monitoring_menu ;;
            3) server_management_menu ;;
            4) telegram_menu ;;
            5) configuration_menu ;;
            0) exit_script ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# User Management Menu
user_management_menu() {
    while true; do
        show_banner
        print_header "User Management"
        
        echo "  1) Add User"
        echo "  2) Delete User"
        echo "  3) Edit User"
        echo "  4) List Users"
        echo "  5) User Details"
        echo "  6) Enable/Disable User"
        echo "  7) Generate QR Code"
        echo "  8) Export Configuration"
        echo "  9) Import User"
        echo "  10) Search Users"
        echo ""
        echo "  0) Back to Main Menu"
        echo ""
        
        read -rp "$(echo -e "${CYAN}Select option [0-10]: ${NC}")" choice
        
        case "${choice}" in
            1) menu_add_user ;;
            2) menu_delete_user ;;
            3) menu_edit_user ;;
            4) menu_list_users ;;
            5) menu_user_details ;;
            6) menu_toggle_user ;;
            7) menu_generate_qr ;;
            8) menu_export_config ;;
            9) menu_import_user ;;
            10) menu_search_users ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# Add User
menu_add_user() {
    print_header "Add New User"
    
    read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
    
    if [[ -z "${username}" ]]; then
        print_error "Username cannot be empty"
        press_any_key
        return
    fi
    
    read -rp "$(echo -e "${CYAN}Bandwidth limit (MB, 0=unlimited) [0]: ${NC}")" bandwidth
    bandwidth="${bandwidth:-0}"
    
    read -rp "$(echo -e "${CYAN}Notes (optional): ${NC}")" notes
    
    echo ""
    add_user "${username}" "${bandwidth}" "${notes}"
    
    echo ""
    if confirm_action "Show QR code for mobile?"; then
        generate_qr_code "${username}"
    fi
    
    press_any_key
}

# Delete User
menu_delete_user() {
    print_header "Delete User"
    
    # Show users first
    list_users false
    
    read -rp "$(echo -e "${CYAN}Username to delete: ${NC}")" username
    
    if [[ -z "${username}" ]]; then
        print_error "Username cannot be empty"
        press_any_key
        return
    fi
    
    if ! user_exists "${username}"; then
        print_error "User '${username}' not found"
        press_any_key
        return
    fi
    
    echo ""
    show_user_details "${username}" | head -10
    
    echo ""
    if confirm_action "Are you sure you want to delete '${username}'?"; then
        delete_user "${username}"
    else
        print_info "Deletion cancelled"
    fi
    
    press_any_key
}

# Edit User
menu_edit_user() {
    print_header "Edit User"
    
    list_users false
    
    read -rp "$(echo -e "${CYAN}Username to edit: ${NC}")" username
    
    if [[ -z "${username}" ]] || ! user_exists "${username}"; then
        print_error "Invalid username"
        press_any_key
        return
    fi
    
    echo ""
    echo "What would you like to edit?"
    echo "  1) IP Address"
    echo "  2) Bandwidth Limit"
    echo "  3) Notes"
    echo "  4) Rename User"
    echo ""
    
    read -rp "$(echo -e "${CYAN}Select option [1-4]: ${NC}")" edit_choice
    
    case "${edit_choice}" in
        1)
            read -rp "$(echo -e "${CYAN}New IP address: ${NC}")" new_value
            edit_user "${username}" "ip" "${new_value}"
            ;;
        2)
            read -rp "$(echo -e "${CYAN}New bandwidth limit (MB): ${NC}")" new_value
            edit_user "${username}" "bandwidth" "${new_value}"
            ;;
        3)
            read -rp "$(echo -e "${CYAN}New notes: ${NC}")" new_value
            edit_user "${username}" "notes" "${new_value}"
            ;;
        4)
            read -rp "$(echo -e "${CYAN}New username: ${NC}")" new_value
            edit_user "${username}" "name" "${new_value}"
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    press_any_key
}

# List Users
menu_list_users() {
    print_header "User List"
    
    echo "  1) All Users"
    echo "  2) Enabled Users Only"
    echo "  3) Online Users Only"
    echo ""
    
    read -rp "$(echo -e "${CYAN}Select option [1-3]: ${NC}")" choice
    
    case "${choice}" in
        1) list_users true ;;
        2) list_users false ;;
        3) 
            print_header "Online Users"
            while IFS='|' read -r username ip public_key enabled created bandwidth notes; do
                [[ "${enabled}" != "1" ]] && continue
                if is_peer_connected "${public_key}"; then
                    echo -e "${GREEN}●${NC} ${username} - ${ip}"
                fi
            done < "${USER_DB}"
            ;;
    esac
    
    press_any_key
}

# User Details
menu_user_details() {
    print_header "User Details"
    
    read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
    
    if [[ -z "${username}" ]] || ! user_exists "${username}"; then
        print_error "Invalid username"
        press_any_key
        return
    fi
    
    echo ""
    show_user_details "${username}"
    
    press_any_key
}

# Toggle User (Enable/Disable)
menu_toggle_user() {
    print_header "Enable/Disable User"
    
    list_users true
    
    read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
    
    if [[ -z "${username}" ]] || ! user_exists "${username}"; then
        print_error "Invalid username"
        press_any_key
        return
    fi
    
    local enabled=$(get_user_field "${username}" 4)
    
    if [[ "${enabled}" == "1" ]]; then
        if confirm_action "Disable user '${username}'?"; then
            disable_user "${username}"
        fi
    else
        if confirm_action "Enable user '${username}'?"; then
            enable_user "${username}"
        fi
    fi
    
    press_any_key
}

# Generate QR Code
menu_generate_qr() {
    print_header "Generate QR Code"
    
    read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
    
    if [[ -z "${username}" ]] || ! user_exists "${username}"; then
        print_error "Invalid username"
        press_any_key
        return
    fi
    
    echo ""
    generate_qr_code "${username}"
    
    press_any_key
}

# Export Config
menu_export_config() {
    print_header "Export User Configuration"
    
    read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
    
    if [[ -z "${username}" ]] || ! user_exists "${username}"; then
        print_error "Invalid username"
        press_any_key
        return
    fi
    
    read -rp "$(echo -e "${CYAN}Export path [.]: ${NC}")" export_path
    export_path="${export_path:-.}"
    
    export_user_config "${username}" "${export_path}"
    
    press_any_key
}

# Import User
menu_import_user() {
    print_header "Import User from Backup"
    
    echo "Available backups:"
    ls -1 "${WG_BACKUP_DIR}"/*_*.tar.gz 2>/dev/null | head -10
    
    echo ""
    read -rp "$(echo -e "${CYAN}Backup file path: ${NC}")" backup_file
    
    if [[ -z "${backup_file}" ]]; then
        print_error "No file specified"
        press_any_key
        return
    fi
    
    import_user "${backup_file}"
    
    press_any_key
}

# Search Users
menu_search_users() {
    print_header "Search Users"
    
    read -rp "$(echo -e "${CYAN}Search query: ${NC}")" query
    
    echo ""
    search_users "${query}"
    
    press_any_key
}

# Monitoring Menu
monitoring_menu() {
    while true; do
        show_banner
        print_header "Monitoring & Statistics"
        
        echo "  1) Real-time Statistics"
        echo "  2) Live Monitor"
        echo "  3) User Usage Report"
        echo "  4) All Users Usage Summary"
        echo "  5) Server Load"
        echo "  6) Generate Report"
        echo "  7) Export Usage Data"
        echo "  8) Record Usage Snapshot"
        echo ""
        echo "  0) Back"
        echo ""
        
        read -rp "$(echo -e "${CYAN}Select option [0-8]: ${NC}")" choice
        
        case "${choice}" in
            1) 
                get_realtime_stats
                press_any_key
                ;;
            2)
                read -rp "$(echo -e "${CYAN}Refresh interval (seconds) [5]: ${NC}")" interval
                interval="${interval:-5}"
                live_monitor "${interval}"
                ;;
            3)
                read -rp "$(echo -e "${CYAN}Username: ${NC}")" username
                read -rp "$(echo -e "${CYAN}Period (daily/weekly/monthly) [daily]: ${NC}")" period
                period="${period:-daily}"
                get_user_usage_report "${username}" "${period}"
                press_any_key
                ;;
            4)
                read -rp "$(echo -e "${CYAN}Period (daily/weekly/monthly) [daily]: ${NC}")" period
                period="${period:-daily}"
                get_all_usage_summary "${period}"
                press_any_key
                ;;
            5)
                get_server_load
                press_any_key
                ;;
            6)
                generate_usage_report
                press_any_key
                ;;
            7)
                export_usage_data
                press_any_key
                ;;
            8)
                record_usage_snapshot
                print_success "Usage snapshot recorded"
                press_any_key
                ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# Server Management Menu
server_management_menu() {
    while true; do
        show_banner
        print_header "Server Management"
        
        echo "  1) Server Status"
        echo "  2) Health Check"
        echo "  3) Test Connectivity"
        echo "  4) System Information"
        echo "  5) View Logs"
        echo "  6) Backup & Restore"
        echo "  7) Scheduled Tasks"
        echo "  8) Check Updates"
        echo "  9) Restart WireGuard"
        echo " 10) Reboot Server"
        echo ""
        echo "  0) Back"
        echo ""
        
        read -rp "$(echo -e "${CYAN}Select option [0-10]: ${NC}")" choice
        
        case "${choice}" in
            1)
                get_server_stats
                echo ""
                get_wireguard_status
                press_any_key
                ;;
            2)
                check_server_health
                press_any_key
                ;;
            3)
                test_vpn_connectivity
                press_any_key
                ;;
            4)
                show_system_info
                press_any_key
                ;;
            5)
                menu_view_logs
                ;;
            6)
                menu_backup_restore
                ;;
            7)
                get_scheduled_tasks
                press_any_key
                ;;
            8)
                check_updates
                press_any_key
                ;;
            9)
                if confirm_action "Restart WireGuard?"; then
                    restart_wireguard
                fi
                press_any_key
                ;;
            10)
                if confirm_action "Reboot server?"; then
                    print_info "Rebooting..."
                    sleep 2
                    reboot
                fi
                ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# View Logs submenu
menu_view_logs() {
    print_header "View Logs"
    
    echo "  1) Manager Logs"
    echo "  2) WireGuard Logs"
    echo "  3) System Logs"
    echo ""
    
    read -rp "$(echo -e "${CYAN}Select option [1-3]: ${NC}")" choice
    read -rp "$(echo -e "${CYAN}Number of lines [50]: ${NC}")" lines
    lines="${lines:-50}"
    
    case "${choice}" in
        1) view_logs "manager" "${lines}" ;;
        2) view_logs "wireguard" "${lines}" ;;
        3) view_logs "system" "${lines}" ;;
    esac
    
    press_any_key
}

# Backup & Restore submenu
menu_backup_restore() {
    print_header "Backup & Restore"
    
    echo "  1) Create Backup"
    echo "  2) List Backups"
    echo "  3) Restore from Backup"
    echo "  4) Delete Old Backups"
    echo "  5) Schedule Automatic Backup"
    echo ""
    
    read -rp "$(echo -e "${CYAN}Select option [1-5]: ${NC}")" choice
    
    case "${choice}" in
        1)
            create_backup
            press_any_key
            ;;
        2)
            list_backups
            press_any_key
            ;;
        3)
            list_backups
            echo ""
            read -rp "$(echo -e "${CYAN}Backup file path: ${NC}")" backup_file
            if [[ -n "${backup_file}" ]]; then
                restore_backup "${backup_file}"
            fi
            press_any_key
            ;;
        4)
            read -rp "$(echo -e "${CYAN}Delete backups older than (days) [30]: ${NC}")" days
            days="${days:-30}"
            cleanup_old_backups "${days}"
            press_any_key
            ;;
        5)
            read -rp "$(echo -e "${CYAN}Cron schedule [0 2 * * *]: ${NC}")" schedule
            schedule="${schedule:-0 2 * * *}"
            BACKUP_SCHEDULE="${schedule}"
            schedule_backup
            press_any_key
            ;;
    esac
}

# Telegram Menu
telegram_menu() {
    while true; do
        show_banner
        print_header "Telegram Bot"
        
        echo -e "  Status: $(get_telegram_status 2>/dev/null || echo -e "${RED}Not configured${NC}")"
        echo ""
        
        echo "  1) Configure Bot Token"
        echo "  2) Add Authorized User"
        echo "  3) Remove Authorized User"
        echo "  4) List Authorized Users"
        echo "  5) Start Bot Service"
        echo "  6) Stop Bot Service"
        echo "  7) Test Bot Connection"
        echo ""
        echo "  0) Back"
        echo ""
        
        read -rp "$(echo -e "${CYAN}Select option [0-7]: ${NC}")" choice
        
        case "${choice}" in
            1)
                read -rp "$(echo -e "${CYAN}Bot Token: ${NC}")" token
                if [[ -n "${token}" ]]; then
                    TELEGRAM_BOT_TOKEN="${token}"
                    TELEGRAM_ENABLED="true"
                    save_config
                    print_success "Bot token configured"
                fi
                press_any_key
                ;;
            2)
                read -rp "$(echo -e "${CYAN}Chat ID to authorize: ${NC}")" chat_id
                if [[ -n "${chat_id}" ]]; then
                    add_telegram_authorized_user "${chat_id}"
                fi
                press_any_key
                ;;
            3)
                read -rp "$(echo -e "${CYAN}Chat ID to remove: ${NC}")" chat_id
                if [[ -n "${chat_id}" ]]; then
                    remove_telegram_authorized_user "${chat_id}"
                fi
                press_any_key
                ;;
            4)
                list_telegram_authorized_users
                press_any_key
                ;;
            5)
                create_telegram_service
                press_any_key
                ;;
            6)
                stop_telegram_service
                press_any_key
                ;;
            7)
                init_telegram
                press_any_key
                ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# Configuration Menu
configuration_menu() {
    while true; do
        show_banner
        print_header "Configuration"
        
        echo "  1) Show Current Configuration"
        echo "  2) Change Port"
        echo "  3) Change DNS Servers"
        echo "  4) Change MTU"
        echo "  5) Change Subnet"
        echo "  6) Toggle Auto-Reboot"
        echo "  7) Toggle Auto-Update"
        echo "  8) Save Configuration"
        echo ""
        echo "  0) Back"
        echo ""
        
        read -rp "$(echo -e "${CYAN}Select option [0-8]: ${NC}")" choice
        
        case "${choice}" in
            1)
                show_config
                press_any_key
                ;;
            2)
                read -rp "$(echo -e "${CYAN}New port [${WG_PORT}]: ${NC}")" new_port
                if [[ -n "${new_port}" ]]; then
                    configure_server "port" "${new_port}"
                fi
                press_any_key
                ;;
            3)
                read -rp "$(echo -e "${CYAN}New DNS servers [${WG_DNS}]: ${NC}")" new_dns
                if [[ -n "${new_dns}" ]]; then
                    configure_server "dns" "${new_dns}"
                fi
                press_any_key
                ;;
            4)
                read -rp "$(echo -e "${CYAN}New MTU [${WG_MTU}]: ${NC}")" new_mtu
                if [[ -n "${new_mtu}" ]]; then
                    configure_server "mtu" "${new_mtu}"
                fi
                press_any_key
                ;;
            5)
                read -rp "$(echo -e "${CYAN}New subnet [${WG_SUBNET}]: ${NC}")" new_subnet
                if [[ -n "${new_subnet}" ]]; then
                    configure_server "subnet" "${new_subnet}"
                fi
                press_any_key
                ;;
            6)
                if [[ "${AUTO_REBOOT_ENABLED}" == "true" ]]; then
                    configure_server "auto-reboot" "false"
                    unschedule_reboot
                else
                    configure_server "auto-reboot" "true"
                    schedule_reboot
                fi
                press_any_key
                ;;
            7)
                if [[ "${AUTO_UPDATE_ENABLED}" == "true" ]]; then
                    configure_server "auto-update" "false"
                else
                    configure_server "auto-update" "true"
                fi
                press_any_key
                ;;
            8)
                save_config
                print_success "Configuration saved"
                press_any_key
                ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# Exit script
exit_script() {
    echo ""
    print_info "Goodbye!"
    exit 0
}

# Handle command line arguments
handle_args() {
    case "${1}" in
        --record-usage)
            # Used by monitoring daemon
            init_manager
            record_usage_snapshot
            ;;
        --telegram-bot)
            # Used by telegram service
            init_manager
            start_telegram_bot
            ;;
        --backup-only)
            # Used by cron backup
            init_manager
            create_backup > /dev/null
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (none)           Start interactive menu"
            echo "  --record-usage   Record usage snapshot (for daemon)"
            echo "  --telegram-bot   Start Telegram bot (for service)"
            echo "  --backup-only    Create backup (for cron)"
            echo "  --help, -h       Show this help"
            ;;
        *)
            # No arguments - start interactive menu
            init_manager
            main_menu
            ;;
    esac
}

# Main
handle_args "$@"
