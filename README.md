# Guacamole Export Tool

## Disclaimer

⚠️ **Caution**: This tool modifies system configurations, interacts with Docker containers, and handles sensitive connection data. It may restart services, expose ports, and generate exports of connection information. 

Use carefully, always create backups, and test in a non-production environment first. The authors are not responsible for any unintended consequences.

## Overview

The Guacamole Export Tool is a Bash script designed to export Apache Guacamole connection data into standard JSON/CSV and Keeper PAM-ready formats. It provides flexible export options, secure credential handling, and optional direct import to Keeper Vault.

## Features

- 🔍 Interactive and CLI modes
- 🔒 Credential sanitization options
- 📦 Export in multiple formats:
  - Standard Guacamole full data export
  - Keeper PAM-ready format
- 🛠 Docker Compose file port inspection and patching
- 🌐 Supports various connection configurations
- 📥 Optional direct import to Keeper Vault

## Prerequisites

- Bash
- Python 3
- Required Python modules:
  - `pyyaml`
  - `mysql-connector-python`
- Optional: Keeper Commander (for Keeper Vault import)

## Installation

1. Clone the repository or download the script
2. Make the script executable:
   ```bash
   chmod +x guac-export.sh
   ```
3. Install required Python dependencies:
   ```bash
   pip install pyyaml mysql-connector-python
   ```
4. Optional: Install Keeper Commander
   ```bash
   pip install keeper-commander
   ```

## Usage

### Interactive Mode

Run the script without arguments to enter interactive mode:
```bash
./guac-export.sh
```

### CLI Mode

#### Export Options
- `--keeper`: Export Keeper PAM-ready JSON
- `--standard`: Export full Guacamole data
- `--both`: Export both formats

#### Additional Flags
- `--output-dir DIR`: Custom export directory
- `--filename-prefix PREFIX`: Prefix for output files
- `--push-to-keeper`: Push Keeper records using Keeper Commander
- `--compose-file FILE`: Path to docker-compose.yml
- `--db-host HOST`: Database host (default: localhost)
- `--db-port PORT`: Database port (default: 3306)
- `--sanitize MODE`: Credential sanitization mode (none, placeholder, remove)

### Examples

1. Interactive export:
   ```bash
   ./guac-export.sh
   ```

2. Export both standard and Keeper formats:
   ```bash
   ./guac-export.sh --both
   ```

3. Export to a specific directory with a custom prefix:
   ```bash
   ./guac-export.sh --keeper --output-dir /path/to/exports --filename-prefix myguac
   ```

4. Push to Keeper Vault after exporting:
   ```bash
   ./guac-export.sh --keeper --push-to-keeper
   ```

## Credential Sanitization Modes

- `none`: Include actual credentials (least secure)
- `placeholder`: Replace credentials with placeholders (recommended)
- `remove`: Remove credential fields completely

## Docker Compose Integration

The script can automatically:
- Inspect your docker-compose.yml file
- Detect if database ports are exposed
- Offer to patch and expose database ports

## Security Notes

- Always be cautious when handling connection credentials
- Use the sanitization modes to protect sensitive information
- Ensure the script and exported files have restricted permissions

## Troubleshooting

- Verify Python dependencies are installed
- Check Docker Compose file path
- Ensure database connectivity
- Review script logs for detailed error messages

## Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page.

## Licensing

### Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)

#### You are free to:
- **Share** — copy and redistribute the material in any medium or format
- **Adapt** — remix, transform, and build upon the material

#### Under the following terms:
- **Attribution** — You must give appropriate credit to the original creator
- **NonCommercial** — You may not use the material for commercial purposes

#### Additional Restrictions:
- Commercial use of this work requires explicit written permission from the original creator
- Any derivative works must be shared under the same license terms
- Attribution must include the original creator's name and a link to the original work

#### Full License Details
For complete license terms, visit: [Creative Commons Attribution-NonCommercial 4.0 International License](http://creativecommons.org/licenses/by-nc/4.0/)

[![CC BY-NC 4.0](https://i.creativecommons.org/l/by-nc/4.0/88x31.png)](http://creativecommons.org/licenses/by-nc/4.0/)

**Note:** For commercial use or additional permissions, please contact the original author.
