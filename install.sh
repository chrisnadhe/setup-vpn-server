#!/bin/bash
# WireGuard VPN Manager - One-Line Installer
# Usage: curl -sSL https://raw.githubusercontent.com/chrisnadhe/setup-vpn-server/main/install.sh | sudo bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# Repository info
REPO_URL="https://github.com/chrisnadhe/setup-vpn-server"
BRANCH="main"
INSTALL_DIR="/opt/wireguard-manager"

# Banner
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
echo -e "${DIM}One-Line Installer${NC}"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root"
    echo "Usage: curl -sSL ... | sudo bash"
    exit 1
fi

# Detect OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS="${ID}"
    OS_NAME="${PRETTY_NAME}"
else
    echo -e "${RED}[ERROR]${NC} Cannot detect OS"
    exit 1
fi

case "${OS}" in
    debian|ubuntu)
        echo -e "${GREEN}[INFO]${NC} Detected: ${OS_NAME}"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Unsupported OS: ${OS}"
        echo "This script supports Debian and Ubuntu only."
        exit 1
        ;;
esac

# Check for required commands
echo -e "${GREEN}[INFO]${NC} Checking dependencies..."

if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Installing git..."
    apt-get update -qq
    apt-get install -y git
fi

if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Installing curl..."
    apt-get install -y curl
fi

# Clone repository
echo -e "${GREEN}[INFO]${NC} Downloading WireGuard Manager..."

if [[ -d "${INSTALL_DIR}" ]]; then
    echo -e "${YELLOW}[INFO]${NC} Updating existing installation..."
    cd "${INSTALL_DIR}"
    git pull origin "${BRANCH}"
else
    git clone -b "${BRANCH}" "${REPO_URL}.git" "${INSTALL_DIR}"
fi

cd "${INSTALL_DIR}"

# Make scripts executable
chmod +x wireguard-setup.sh
chmod +x wg-manager.sh
chmod +x install.sh

# Create symlink
ln -sf "${INSTALL_DIR}/wg-manager.sh" /usr/local/bin/wg-manager

echo ""
echo -e "${GREEN}[SUCCESS]${NC} Installation files downloaded to ${INSTALL_DIR}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Run the installer:"
echo -e "     ${YELLOW}sudo ${INSTALL_DIR}/wireguard-setup.sh${NC}"
echo ""
echo "  2. Or use quick install:"
echo -e "     ${YELLOW}sudo ${INSTALL_DIR}/wireguard-setup.sh --install${NC}"
echo ""
echo "  3. After installation, manage with:"
echo -e "     ${YELLOW}sudo wg-manager${NC}"
echo ""

# Ask to run installer
read -rp "$(echo -e "${CYAN}Run installer now? [Y/n]: ${NC}")" run_now
run_now="${run_now:-y}"

if [[ "${run_now}" =~ ^[Yy]$ ]]; then
    echo ""
    exec "${INSTALL_DIR}/wireguard-setup.sh"
fi
