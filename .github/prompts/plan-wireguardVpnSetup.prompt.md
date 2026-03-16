# Plan: WireGuard VPN Management System

## Overview
Create a comprehensive shell script system to deploy and manage WireGuard VPN on Debian/Ubuntu VPS with user management CLI, monitoring, Telegram bot integration, and server administration features.

## Architecture

### Core Components
1. **Main Installation Script** (`wireguard-setup.sh`) - Initial WireGuard installation and configuration
2. **Management CLI** (`wg-manager.sh`) - Interactive menu-driven interface for daily operations
3. **Monitoring Module** (`wg-monitor.sh`) - Usage tracking and statistics
4. **Telegram Bot Module** (`wg-telegram.sh`) - Bot integration for remote management
5. **Server Management Module** (`wg-server.sh`) - System maintenance functions
6. **Configuration Files** - Centralized config storage in `/etc/wireguard-manager/`

### Directory Structure
```
/etc/wireguard-manager/
├── config.conf              # Main configuration
├── users/                   # User configurations
│   └── {username}/
│       ├── client.conf      # Client config
│       └── usage.log        # Usage logs
├── backups/                 # Configuration backups
├── logs/                    # System logs
└── telegram/                # Telegram bot config
```

## Implementation Steps

### Phase 1: Core Infrastructure (Steps 1-3)
1. **Create main installation script** (`wireguard-setup.sh`)
   - Detect OS (Debian/Ubuntu)
   - Install WireGuard and dependencies
   - Generate server keys
   - Configure network and firewall (iptables/nftables)
   - Enable IP forwarding
   - Create systemd service

2. **Create configuration management system**
   - Central config file structure
   - User database (simple file-based)
   - Key generation utilities
   - IP address allocation system

3. **Create base management framework** (`wg-manager.sh`)
   - Menu system with color output
   - Function library sourcing
   - Error handling and logging
   - Root permission checks

### Phase 2: User Management (Steps 4-6)
4. **Implement user operations**
   - Add user: Generate keys, allocate IP, create config, add peer
   - Delete user: Remove peer, revoke keys, free IP
   - Edit user: Modify bandwidth limits, rename, change IP
   - List users: Show all users with status and usage
   - Enable/Disable user: Toggle peer without deletion

5. **Create client configuration generator**
   - Generate .conf files for clients
   - Create QR codes for mobile clients
   - Export options (file, QR, clipboard)

6. **Implement IP management**
   - IP pool tracking
   - Automatic allocation
   - Conflict detection
   - Subnet management

### Phase 3: Monitoring System (Steps 7-8)
7. **Build usage monitoring**
   - Track bandwidth per user (rx/tx)
   - Connection time tracking
   - Real-time statistics via `wg show`
   - Historical data storage
   - Usage reports (daily/weekly/monthly)

8. **Create monitoring dashboard**
   - Terminal-based live view
   - Per-user statistics
   - Server load monitoring
   - Alert thresholds

### Phase 4: Telegram Integration (Steps 9-10)
9. **Implement Telegram bot**
   - Bot token configuration
   - Allowed users whitelist
   - Command handlers:
     - `/start` - Initialize bot
     - `/status` - Server status
     - `/users` - List users
     - `/adduser <name>` - Add user
     - `/deluser <name>` - Delete user
     - `/usage <name>` - User usage stats
     - `/help` - Command list

10. **Create bot service**
    - Systemd service for bot
    - Polling/webhook mode
    - Authentication and authorization
    - Error handling and logging

### Phase 5: Server Management (Steps 11-13)
11. **Implement backup system**
    - Export all configurations
    - Compressed backup files
    - Restore functionality
    - Scheduled backups via cron

12. **Add server maintenance functions**
    - Auto-reboot scheduling
    - System updates check
    - Service health monitoring
    - Log rotation

13. **Create status and diagnostics**
    - WireGuard service status
    - Network connectivity check
    - Port availability test
    - Configuration validation

### Phase 6: Polish and Documentation (Steps 14-15)
14. **Add advanced features**
    - Bandwidth limiting per user
    - DNS configuration options
    - Multiple interface support
    - IPv6 support (optional)

15. **Create documentation and helpers**
    - README with usage instructions
    - Uninstall script
    - Update mechanism
    - Troubleshooting guide

## Critical Files to Create

1. `/wireguard-setup.sh` - Main installation script
2. `/wg-manager.sh` - Management CLI entry point
3. `/lib/core.sh` - Core functions library
4. `/lib/users.sh` - User management functions
5. `/lib/monitor.sh` - Monitoring functions
6. `/lib/telegram.sh` - Telegram bot functions
7. `/lib/server.sh` - Server management functions
8. `/lib/config.sh` - Configuration management
9. `/lib/utils.sh` - Utility functions
10. `/config/default.conf` - Default configuration template

## Technical Decisions

### Storage Format
- User database: Simple text file with CSV format
- Configuration: Shell sourceable config files
- Logs: Standard syslog + custom logs

### Dependencies
- WireGuard tools (`wireguard-tools`)
- QR code generation (`qrencode`)
- JSON processing (`jq`) for Telegram API
- Standard tools: `curl`, `awk`, `sed`, `grep`

### Compatibility
- Debian 10+ (Buster and later)
- Ubuntu 20.04+ (Focal and later)
- Both iptables and nftables support

## Verification Steps

1. **Installation Test**
   - Run on fresh Debian/Ubuntu VPS
   - Verify WireGuard service starts
   - Test client connection

2. **User Management Test**
   - Add multiple users
   - Verify unique IP allocation
   - Test enable/disable functionality
   - Confirm deletion cleanup

3. **Monitoring Test**
   - Generate traffic through VPN
   - Verify usage tracking accuracy
   - Test report generation

4. **Telegram Bot Test**
   - Configure bot token
   - Test all commands
   - Verify authorization

5. **Backup/Restore Test**
   - Create backup
   - Modify configuration
   - Restore and verify

## Scope Boundaries

### Included
- Single WireGuard interface
- IPv4 support (primary)
- Basic bandwidth monitoring
- File-based user storage
- Telegram bot integration
- Systemd service management

### Excluded (Future Enhancements)
- Web UI dashboard
- Multi-server support
- Advanced firewall rules
- Database backend
- IPv6 as primary
- Commercial features

## Further Considerations

1. **Security Hardening**
   - Secure key storage permissions
   - Input validation for all user inputs
   - Rate limiting for Telegram bot
   - Audit logging

2. **Performance**
   - Efficient IP allocation algorithm
   - Minimal overhead monitoring
   - Optimized for small VPS (1GB RAM)

3. **User Experience**
   - Clear error messages
   - Progress indicators
   - Confirmation prompts for destructive actions
   - Help text for all commands
