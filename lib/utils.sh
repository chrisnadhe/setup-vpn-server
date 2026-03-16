#!/bin/bash
# Utility Functions for WireGuard Manager
# Common helper functions used across all modules

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'
readonly DIM='\033[2m'

# Print functions with colors
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
        echo -e "${DIM}[DEBUG]${NC} $1"
    fi
}

print_header() {
    echo -e "\n${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}\n"
}

print_subheader() {
    echo -e "\n${BOLD}${PURPLE}── $1 ──${NC}\n"
}

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -f "${LOG_FILE}" ]]; then
        echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="${ID}"
        OS_VERSION="${VERSION_ID}"
        OS_NAME="${PRETTY_NAME}"
    else
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    case "${OS}" in
        debian|ubuntu)
            print_debug "Detected OS: ${OS_NAME}"
            ;;
        *)
            print_error "Unsupported OS: ${OS}. This script supports Debian and Ubuntu only."
            exit 1
            ;;
    esac
}

# Get public IP address
get_public_ip() {
    local ip=""
    
    # Try multiple services for reliability
    ip=$(curl -s4 --max-time 5 https://ifconfig.io 2>/dev/null) ||
    ip=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null) ||
    ip=$(curl -s4 --max-time 5 https://icanhazip.com 2>/dev/null) ||
    ip=$(curl -s4 --max-time 5 https://ipecho.net/plain 2>/dev/null)
    
    if [[ -z "${ip}" ]]; then
        # Fallback to local IP
        ip=$(ip -4 addr show "${SERVER_PUB_NIC}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    fi
    
    echo "${ip}"
}

# Get default network interface
get_default_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

# Validate IP address
validate_ip() {
    local ip="$1"
    local stat=1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    
    return $stat
}

# Validate username (alphanumeric, dash, underscore)
validate_username() {
    local username="$1"
    
    if [[ ! "${username}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        return 1
    fi
    
    if [[ ${#username} -lt 2 || ${#username} -gt 32 ]]; then
        return 1
    fi
    
    return 0
}

# Generate random string
generate_random_string() {
    local length="${1:-32}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "${length}"
}

# Convert bytes to human readable
bytes_to_human() {
    local bytes=$1
    
    if [[ ${bytes} -lt 1024 ]]; then
        echo "${bytes} B"
    elif [[ ${bytes} -lt 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1024}") KB"
    elif [[ ${bytes} -lt 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1073741824}") GB"
    fi
}

# Convert seconds to human readable
seconds_to_human() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))
    
    if [[ ${days} -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [[ ${hours} -gt 0 ]]; then
        echo "${hours}h ${minutes}m ${secs}s"
    elif [[ ${minutes} -gt 0 ]]; then
        echo "${minutes}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

# Confirm prompt
confirm_action() {
    local message="${1:-Are you sure?}"
    local default="${2:-n}"
    
    if [[ "${default}" == "y" ]]; then
        read -rp "$(echo -e "${YELLOW}${message} [Y/n]: ${NC}")" response
        response=${response:-y}
    else
        read -rp "$(echo -e "${YELLOW}${message} [y/N]: ${NC}")" response
        response=${response:-n}
    fi
    
    case "${response}" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Press any key to continue
press_any_key() {
    local message="${1:-Press any key to continue...}"
    echo -e "\n${DIM}${message}${NC}"
    read -rsn1
}

# Spinner for long operations
spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local i=0
    
    echo -ne "${CYAN}${message} ${NC}"
    
    while kill -0 "${pid}" 2>/dev/null; do
        i=$(( (i+1) % 8 ))
        printf "\r${CYAN}${message} ${spin:$i:1}${NC}"
        sleep 0.1
    done
    
    printf "\r${GREEN}${message} ✓${NC}\n"
}

# Run command with spinner
run_with_spinner() {
    local message="$1"
    shift
    "$@" &
    spinner $! "${message}"
}

# Create backup of file before modification
backup_file() {
    local file="$1"
    local backup_dir="${WG_BACKUP_DIR}/file_backups"
    
    if [[ -f "${file}" ]]; then
        mkdir -p "${backup_dir}"
        local backup_name="$(basename "${file}").$(date +%Y%m%d_%H%M%S).bak"
        cp "${file}" "${backup_dir}/${backup_name}"
        print_debug "Backed up ${file} to ${backup_dir}/${backup_name}"
    fi
}

# Check if service is running
is_service_running() {
    local service="$1"
    systemctl is-active --quiet "${service}"
}

# Check if service is enabled
is_service_enabled() {
    local service="$1"
    systemctl is-enabled --quiet "${service}" 2>/dev/null
}

# Get service status
get_service_status() {
    local service="$1"
    
    if is_service_running "${service}"; then
        echo -e "${GREEN}● Running${NC}"
    elif is_service_enabled "${service}"; then
        echo -e "${YELLOW}● Enabled (Not Running)${NC}"
    else
        echo -e "${RED}● Stopped${NC}"
    fi
}

# Progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r${CYAN}["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %d%% (%d/%d)${NC}" "${percentage}" "${current}" "${total}"
    
    if [[ ${current} -eq ${total} ]]; then
        echo ""
    fi
}

# Table printing
print_table_header() {
    local headers=("$@")
    local separator=""
    
    echo -e "${BOLD}"
    for header in "${headers[@]}"; do
        printf "%-20s" "${header}"
        separator+="────────────────────"
    done
    echo -e "${NC}"
    echo "${separator}"
}

print_table_row() {
    local values=("$@")
    
    for value in "${values[@]}"; do
        printf "%-20s" "${value}"
    done
    echo ""
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    
    # Remove temporary files
    rm -f /tmp/wg_manager_* 2>/dev/null
    
    # Log exit
    log_message "INFO" "Script exited with code ${exit_code}"
    
    exit ${exit_code}
}

# Set trap for cleanup
trap cleanup EXIT INT TERM
