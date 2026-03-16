# WireGuard VPN Manager

A comprehensive shell script system to deploy and manage WireGuard VPN on Debian/Ubuntu VPS with user management CLI, usage monitoring, Telegram bot integration, and server administration features.

## Features

### 🚀 Installation
- Automated WireGuard installation for Debian/Ubuntu
- Interactive configuration wizard
- Quick install with recommended settings
- Firewall configuration (UFW/iptables)
- IP forwarding setup

### 👥 User Management
- Add/Delete/Edit users
- Enable/Disable users without deletion
- IP address allocation and management
- QR code generation for mobile clients
- Configuration file export
- User import from backup

### 📊 Monitoring
- Real-time statistics
- Live monitoring dashboard
- Per-user usage tracking (daily/weekly/monthly)
- Bandwidth limit alerts
- Server load monitoring
- Usage reports and export

### 🤖 Telegram Bot
- Remote management via Telegram
- Authorized user whitelist
- Commands for all operations
- Inline keyboards for quick actions
- QR code delivery via Telegram

### 🛠️ Server Management
- Automated backups
- Backup restore functionality
- Scheduled tasks (cron)
- System health checks
- Log viewing and rotation
- Auto-reboot scheduling
- Update management

## Directory Structure

```
setup-vpn-server/
├── wireguard-setup.sh      # Installation script
├── wg-manager.sh           # Management CLI
├── lib/
│   ├── utils.sh            # Utility functions
│   ├── core.sh             # Core functions
│   ├── users.sh            # User management
│   ├── monitor.sh          # Monitoring functions
│   ├── telegram.sh         # Telegram bot
│   └── server.sh           # Server management
├── config/
│   └── default.conf        # Default configuration
└── README.md               # This file
```

## Installation

### One-Line Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/chrisnadhe/setup-vpn-server/main/install.sh | sudo bash
```

### Manual Install

```bash
# Clone the repository
git clone https://github.com/chrisnadhe/setup-vpn-server.git
cd setup-vpn-server

# Make scripts executable
chmod +x wireguard-setup.sh wg-manager.sh

# Run installation
sudo ./wireguard-setup.sh --install
```

### Interactive Installation

```bash
sudo ./wireguard-setup.sh
```

This will show a menu with options:
1. Install WireGuard VPN Server only
2. Install WireGuard + Management Tools
3. Install Management Tools Only
4. Quick Install (Recommended settings)

## Usage

### Starting the Management CLI

```bash
# If installed with symlink
sudo wg-manager

# Or run directly
sudo ./wg-manager.sh
```

### Main Menu Options

```
1) User Management
2) Monitoring & Statistics
3) Server Management
4) Telegram Bot
5) Configuration
```

### User Management

- **Add User**: Create new VPN user with IP allocation
- **Delete User**: Remove user and free IP
- **Edit User**: Modify IP, bandwidth, notes, or rename
- **List Users**: Show all users with status
- **User Details**: View detailed user information
- **Enable/Disable**: Toggle user without deletion
- **Generate QR Code**: Create QR for mobile setup
- **Export Config**: Save .conf file to location
- **Import User**: Restore from backup

### Monitoring

- **Real-time Statistics**: Current peer status and traffic
- **Live Monitor**: Auto-refreshing dashboard
- **Usage Report**: Per-user usage for periods
- **All Users Summary**: Combined usage report
- **Server Load**: System resource usage
- **Generate Report**: Export full report to file

### Server Management

- **Server Status**: WireGuard and system status
- **Health Check**: Comprehensive system check
- **Test Connectivity**: Verify VPN functionality
- **System Information**: Hardware and OS details
- **View Logs**: Manager, WireGuard, or system logs
- **Backup & Restore**: Configuration backup management
- **Scheduled Tasks**: View cron jobs
- **Check Updates**: System update status
- **Restart WireGuard**: Restart VPN service
- **Reboot Server**: System reboot

## Telegram Bot Setup

### 1. Create a Telegram Bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow instructions
3. Copy the bot token

### 2. Configure the Bot

In the management CLI:
```
4) Telegram Bot → 1) Configure Bot Token
```

Or edit `/etc/wireguard-manager/config.conf`:
```bash
TELEGRAM_ENABLED="true"
TELEGRAM_BOT_TOKEN="your-bot-token-here"
```

### 3. Get Your Chat ID

1. Start a chat with your bot
2. Send `/start`
3. The bot will show your Chat ID

### 4. Authorize Your Chat ID

In the management CLI:
```
4) Telegram Bot → 2) Add Authorized User
```

### 5. Start the Bot Service

```
4) Telegram Bot → 5) Start Bot Service
```

### Telegram Commands

| Command | Description |
|---------|-------------|
| `/start` | Initialize bot |
| `/help` | Show available commands |
| `/status` | Server status |
| `/users` | List all users |
| `/adduser <name>` | Add new user |
| `/deluser <name>` | Delete user |
| `/enableuser <name>` | Enable user |
| `/disableuser <name>` | Disable user |
| `/userinfo <name>` | User details |
| `/usage [name]` | Usage statistics |
| `/config show` | Show configuration |
| `/qr <name>` | Get QR code |
| `/backup` | Create backup |
| `/restart` | Restart WireGuard |
| `/reboot` | Reboot server |
| `/menu` | Quick action menu |

## Configuration

Configuration file location: `/etc/wireguard-manager/config.conf`

### Key Settings

```bash
# Server
WG_INTERFACE="wg0"
WG_PORT="51820"
WG_SUBNET="10.66.66.0/24"
WG_DNS="1.1.1.1, 8.8.8.8"

# Telegram
TELEGRAM_ENABLED="false"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_ALLOWED_USERS=""

# Monitoring
MONITOR_ENABLED="true"
MONITOR_INTERVAL="60"
ALERT_THRESHOLD_MB="10240"

# Backup
BACKUP_ENABLED="true"
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_RETAIN_DAYS="30"

# Maintenance
AUTO_REBOOT_ENABLED="false"
AUTO_REBOOT_SCHEDULE="0 4 * * 0"
```

## Command Line Usage

```bash
# One-line install from GitHub
curl -sSL https://raw.githubusercontent.com/chrisnadhe/setup-vpn-server/main/install.sh | sudo bash

# Installation (after cloning)
sudo ./wireguard-setup.sh --install      # Quick install
sudo ./wireguard-setup.sh --uninstall    # Uninstall

# Management
sudo wg-manager                          # Interactive menu (if symlinked)
sudo ./wg-manager.sh                     # Interactive menu
sudo ./wg-manager.sh --record-usage      # Record usage (for daemon)
sudo ./wg-manager.sh --telegram-bot      # Start Telegram bot
sudo ./wg-manager.sh --backup-only       # Create backup (for cron)
```

## Systemd Services

The installation creates the following services:

- `wg-quick@wg0` - WireGuard VPN service
- `wg-monitor` - Usage monitoring daemon
- `wg-telegram` - Telegram bot service

```bash
# Check status
systemctl status wg-quick@wg0
systemctl status wg-monitor
systemctl status wg-telegram

# Start/Stop/Restart
systemctl start wg-quick@wg0
systemctl stop wg-quick@wg0
systemctl restart wg-quick@wg0
```

## File Locations

| Path | Description |
|------|-------------|
| `/etc/wireguard/` | WireGuard configuration |
| `/etc/wireguard-manager/` | Manager data directory |
| `/etc/wireguard-manager/config.conf` | Manager configuration |
| `/etc/wireguard-manager/users.db` | User database |
| `/etc/wireguard-manager/users/` | User configurations |
| `/etc/wireguard-manager/keys/` | User keys |
| `/etc/wireguard-manager/backups/` | Backup files |
| `/etc/wireguard-manager/logs/` | Log files |
| `/etc/wireguard-manager/usage/` | Usage logs |

## Client Setup

### Desktop (Windows/Mac/Linux)

1. Install WireGuard client from [wireguard.com](https://www.wireguard.com/install/)
2. Import the `.conf` file from the manager
3. Activate the tunnel

### Mobile (iOS/Android)

1. Install WireGuard app from App Store/Play Store
2. Scan the QR code from the manager
3. Activate the tunnel

### Getting Client Configuration

From the management CLI:
```
1) User Management → 8) Export Configuration
```

Or via Telegram:
```
/qr username
```

## Troubleshooting

### WireGuard won't start

```bash
# Check logs
journalctl -u wg-quick@wg0 -n 50

# Check configuration
wg showconf wg0

# Verify interface
ip link show wg0
```

### Users can't connect

1. Check if user is enabled
2. Verify firewall allows UDP port
3. Check server public IP is correct
4. Verify client configuration

### Telegram bot not responding

```bash
# Check service status
systemctl status wg-telegram

# Check logs
journalctl -u wg-telegram -n 50

# Verify bot token
curl "https://api.telegram.org/bot<TOKEN>/getMe"
```

### Port already in use

```bash
# Check what's using the port
ss -ulnp | grep 51820

# Change port in configuration
wg-manager → 5) Configuration → 2) Change Port
```

## Security Recommendations

1. **Change default port**: Use a non-standard port
2. **Enable firewall**: Only allow necessary ports
3. **Regular updates**: Keep system and WireGuard updated
4. **Backup regularly**: Schedule automatic backups
5. **Monitor usage**: Watch for unusual activity
6. **Strong keys**: Keys are auto-generated securely
7. **Limit access**: Use Telegram whitelist

## Uninstallation

```bash
sudo ./wireguard-setup.sh --uninstall
```

This will:
- Create a final backup
- Stop all services
- Remove WireGuard packages
- Remove configurations (backup preserved)

## Requirements

- Debian 10+ or Ubuntu 20.04+
- Root access
- Public IP address
- UDP port available (default: 51820)
- Minimum 512MB RAM (1GB recommended)
- 1GB free disk space

## Dependencies

Installed automatically:
- `wireguard` - VPN software
- `wireguard-tools` - Management utilities
- `qrencode` - QR code generation
- `iptables` - Firewall management
- `curl` - HTTP client
- `jq` - JSON processing
- `bc` - Calculator
- `dnsutils` - DNS tools
- `net-tools` - Network utilities
- `haveged` - Entropy generator

## License

This project is provided as-is for educational and personal use.

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review logs in `/etc/wireguard-manager/logs/`
3. Check WireGuard documentation at [wireguard.com](https://www.wireguard.com/)

## Credits

Built with ❤️ for the WireGuard community.
