# KCM - GUACAMOLE to Keeper PAM Export Tool

A utility script that exports Apache Guacamole connection data into Keeper PAM-ready formats for seamless import via Keeper Commander CLI.

## Features

- 🔄 **Export Connection Data**: Extracts Guacamole connections in Keeper PAM-compatible format
- 🔎 **Connection Analysis**: Analyzes your Guacamole connection types and hierarchy
- 🔒 **Credential Sanitization**: Multiple sanitization options for secure exports
- 🔧 **Auto-Configuration**: Detects and configures database connectivity
- 📊 **Summary Reports**: Generates comprehensive export statistics

## Overview

## Disclaimer

⚠️ **Caution**: This tool modifies system configurations and handles connection data. Always test in a non-production environment first and create backups before use.


The Keeper PAM Export Tool simplifies migrating Apache Guacamole connections to Keeper's Privileged Access Management system. It automatically inspects your Docker Compose configuration, extracts database credentials, and transforms connection data into the proper format for Keeper PAM import.

## Prerequisites

- Bash shell environment
- Python 3
- Docker and Docker Compose
- MySQL client (optional, for enhanced connectivity checks)
- Python modules:
  - `pyyaml`
  - `mysql-connector-python` (auto-installed if missing)
  - `json`

## Usage

### Interactive Mode

Simply run the script without arguments to enter interactive mode:

```bash
./keeper-pam-export.sh
```

The script will guide you through configuration options including credential sanitization preferences and folder organization.

### CLI Mode

For automated or unattended operation, use CLI flags:

```bash
./keeper-pam-export.sh --export --sanitize placeholder
```

### Available Options

```
Flags:
  --export            Run export with default settings
  --output-dir DIR    Custom export directory (default: current directory)
  --filename-prefix   Prefix for output files (default: keeper)
  --compose-file      Path to docker-compose.yml (default: /etc/kcm-setup/docker-compose.yml)
  --db-host           Database host (default: localhost)
  --db-port           Database port (default: 3306)
  --sanitize          Credentials sanitization mode: none, placeholder, remove (default: placeholder)
  --keeper-folder     Root folder for Keeper PAM import (default: Guacamole)
  --debug             Enable debug logging
  --help              Show this help message
  --version           Show version information
```

## Credential Sanitization Options

The tool provides three sanitization modes for handling sensitive connection credentials:

1. **none**: Export actual credentials as-is (least secure)
2. **placeholder**: Replace credentials with secure placeholders like `[PASSWORD]` (recommended)
3. **remove**: Completely remove credential information from exports (most secure)

## Docker Compose Integration

The script can automatically:
- Inspect your docker-compose.yml configuration
- Detect if database ports are exposed
- Offer to safely patch and backup your compose file
- Restart containers with the new configuration

## Export Process

1. The script first inspects your Docker Compose configuration
2. It extracts database credentials and tests connectivity
3. Connection data is exported to both raw and Keeper PAM formats
4. A comprehensive summary is generated with import instructions

## Import to Keeper PAM

After export, you can import the data to Keeper PAM using Keeper Commander:

```bash
keeper import --format=json keeper_pam_format_TIMESTAMP.json
```

## Security Considerations

- Always review exported data before importing
- Use credential sanitization when sharing export files
- Ensure proper permissions on export directory
- Consider removing export files after successful import

## Troubleshooting

If you encounter issues:

1. Enable debug mode with `--debug` flag
2. Verify database connectivity manually
3. Check Docker Compose configuration
4. Ensure your Guacamole database is properly configured


