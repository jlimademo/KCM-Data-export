# KCM - GUACAMOLE to Keeper PAM Export Tools

## Disclaimer

⚠️ **Caution**: These tools modify system configurations and handle connection data. Always test in a non-production environment first and create backups before use.

The Keeper PAM Export Tools simplify migrating Apache Guacamole connections to Keeper's Privileged Access Management system. They automatically inspect your Docker Compose configuration, extract database credentials, and transform connection data into the proper format for Keeper PAM import.

These tools are not supported by Keeper and are individual contributions from a curious individual :)

## Overview

Two utility scripts that export Apache Guacamole connection data into Keeper PAM-ready formats for seamless import via Keeper Commander CLI:

1. **KCM-Enhanced-mysql-Export.sh** - For MySQL/MariaDB databases
2. **KCM-Enhanced-postgress-Export.sh** - For PostgreSQL databases

## Features

- 🔄 **Export Connection Data**: Extracts Guacamole connections in Keeper PAM-compatible format
- 🔎 **Connection Analysis**: Analyzes your Guacamole connection types and hierarchy
- 🔒 **Credential Sanitization**: Multiple sanitization options for secure exports
- 🔧 **Auto-Configuration**: Detects and configures database connectivity
- 📊 **Summary Reports**: Generates comprehensive export statistics

## Choosing the Right Script

Use the appropriate script based on your Guacamole database type:

- **MySQL/MariaDB**: Use `KCM-Enhanced-mysql-Export.sh` if your Guacamole instance uses MySQL or MariaDB
- **PostgreSQL**: Use `KCM-Enhanced-postgress-Export.sh` if your Guacamole instance uses PostgreSQL

If you're unsure which database your Guacamole instance uses, check your docker-compose.yml file for database service images containing "mysql", "mariadb", or "postgres".

## Prerequisites

### Common Requirements

- Bash shell environment
- Python 3
- Docker and Docker Compose
- Python modules:
  - `pyyaml`
  - `json`

### MySQL Version Requirements

- MySQL client (optional, for enhanced connectivity checks)
- Python module: `mysql-connector-python` (auto-installed if missing)

### PostgreSQL Version Requirements

- PostgreSQL client (optional, for enhanced connectivity checks)
- Python module: `psycopg2-binary` (auto-installed if missing)

## Usage

### Interactive Mode

Simply run the appropriate script without arguments to enter interactive mode:

```bash
# For MySQL/MariaDB
./KCM-Enhanced-mysql-Export.sh

# For PostgreSQL
./KCM-Enhanced-postgress-Export.sh
```

The script will guide you through configuration options including credential sanitization preferences and folder organization.

### CLI Mode

For automated or unattended operation, use CLI flags:

```bash
# For MySQL/MariaDB
./KCM-Enhanced-mysql-Export.sh --export --sanitize placeholder

# For PostgreSQL
./KCM-Enhanced-postgress-Export.sh --export --sanitize placeholder
```

### Available Options

```
Flags:
  --export            Run export with default settings
  --output-dir DIR    Custom export directory (default: current directory)
  --filename-prefix   Prefix for output files (default: keeper)
  --compose-file      Path to docker-compose.yml (default: /etc/kcm-setup/docker-compose.yml)
  --db-host           Database host (default: localhost)
  --db-port           Database port (default: 3306 for MySQL, 5432 for PostgreSQL)
  --sanitize          Credentials sanitization mode: none, placeholder, remove (default: placeholder)
  --keeper-folder     Root folder for Keeper PAM import (default: Guacamole)
  --debug             Enable debug logging
  --help              Show this help message
  --version           Show version information
```

## Credential Sanitization Options

Both tools provide three sanitization modes for handling sensitive connection credentials:

1. **none**: Export actual credentials as-is (least secure)
2. **placeholder**: Replace credentials with secure placeholders like `[PASSWORD]` (recommended)
3. **remove**: Completely remove credential information from exports (most secure)

## Docker Compose Integration

Both scripts can automatically:
- Inspect your docker-compose.yml configuration
- Detect if database ports are exposed
- Offer to safely patch and backup your compose file
- Restart containers with the new configuration

## Database-Specific Features

### MySQL Version

- Identifies MySQL/MariaDB services in docker-compose.yml
- Handles default MySQL port (3306)
- Optimized for MariaDB and MySQL connection parameters
- Extracts credentials from MySQL environment variables

### PostgreSQL Version

- Identifies PostgreSQL services in docker-compose.yml
- Handles default PostgreSQL port (5432)
- Optimized for PostgreSQL connection parameters
- Extracts credentials from PostgreSQL environment variables
- Specifically detects Guacamole-PostgreSQL configurations
- Handles custom PostgreSQL port configurations used by Guacamole

## Guacamole-Specific Configuration

Both scripts are optimized for finding Guacamole-specific database configurations, but with database-specific approaches:

### MySQL Version

- Looks for environment variables like `MYSQL_DATABASE`, `GUACAMOLE_DATABASE`
- Detects common MySQL images used with Guacamole

### PostgreSQL Version

- Looks for environment variables like `GUACAMOLE_DATABASE`, `GUACAMOLE_USERNAME`
- Identifies PostgreSQL services by both image name and environment variables
- Handles Guacamole admin credentials as fallback

## Connection Handling

### MySQL Version

Connection strategies:
- Extracted credentials from docker-compose.yml
- Container name-based connection
- Root user fallback
- Alternative database name attempts

### PostgreSQL Version

Connection strategies:
- Extracted credentials from docker-compose.yml
- Container name-based connection
- Guacamole admin credentials fallback
- PostgreSQL superuser connection attempts
- Alternative database name attempts

## Export Process

For both scripts, the process is:

1. The script first inspects your Docker Compose configuration
2. It extracts database credentials and tests connectivity
3. Connection data is exported to both raw and Keeper PAM formats
4. A comprehensive summary is generated with import instructions

## Output Files

Both scripts generate these files (with timestamp):
- `keeper_connections_TIMESTAMP.json` - Raw Guacamole connection data
- `keeper_pam_format_TIMESTAMP.json` - Complete Keeper PAM format
- `keeper_folders_TIMESTAMP.json` - Shared folders for import
- `keeper_records_TIMESTAMP.json` - Records for import
- `keeper_summary_TIMESTAMP.txt` - Export summary with statistics

## Import to Keeper PAM

After export, you can import the data to Keeper PAM using Keeper Commander:

```bash
# Import folders first
keeper import --format=json keeper_folders_TIMESTAMP.json

# Then import records
keeper import --format=json keeper_records_TIMESTAMP.json
```

## Security Considerations

- Always review exported data before importing
- Use credential sanitization when sharing export files
- Ensure proper permissions on export directory
- Consider removing export files after successful import

## Troubleshooting

### Common Troubleshooting

1. Enable debug mode with `--debug` flag
2. Verify database connectivity manually
3. Check Docker Compose configuration
4. Ensure your Guacamole database is properly configured

### MySQL Troubleshooting

If you have MySQL connection issues:
- Check if MySQL port 3306 is exposed correctly
- Verify MySQL credentials
- Try connecting directly: `mysql -h localhost -P 3306 -u USERNAME -p DATABASE_NAME`

### PostgreSQL Troubleshooting

If you have PostgreSQL connection issues:
- Verify PostgreSQL port mapping in your docker-compose file
- Check if PostgreSQL is running on the expected port inside the container
- Try connecting directly: `docker exec -it CONTAINER_ID psql -U USERNAME -d DATABASE_NAME`
- If your PostgreSQL container uses a non-standard port configuration:
  1. Check for discrepancies between Docker port mapping and actual PostgreSQL port
  2. Identify which port PostgreSQL is listening on inside the container
  3. Adjust connection parameters accordingly

## Notes on Custom Configurations

### MySQL Custom Configurations

- Default MySQL port is 3306
- Check for non-standard port configurations in docker-compose.yml
- MySQL configuration typically uses `MYSQL_ROOT_PASSWORD`, `MYSQL_USER`, etc.

### PostgreSQL Custom Configurations

- Default PostgreSQL port is 5432
- Some Guacamole PostgreSQL containers use custom ports (e.g., 5352)
- PostgreSQL configuration typically uses `POSTGRES_USER`, `POSTGRES_PASSWORD`, etc.
- Guacamole may use specific variables like `GUACAMOLE_USERNAME`, `GUACAMOLE_PASSWORD`

## Troubleshooting Port Issues

### MySQL Port Issues

- Check Docker port mapping: `0.0.0.0:HOST_PORT->3306/tcp`
- Ensure MySQL is listening on port 3306 inside the container
- Verify connectivity: `mysql -h localhost -P HOST_PORT -u root -p`

### PostgreSQL Port Issues

- Check Docker port mapping: `0.0.0.0:HOST_PORT->CONTAINER_PORT/tcp`
- Identify actual PostgreSQL port inside container: `docker exec -it CONTAINER_ID psql -U postgres`
- For custom setups where internal and external ports differ:
  - Connect directly to the container to verify database access
  - Consider updating port mappings to match actual PostgreSQL port
