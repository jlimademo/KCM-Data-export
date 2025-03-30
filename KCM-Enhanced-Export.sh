# ================================================================================
# SECTION 1: HEADER AND DESCRIPTION
# --------------------------------------------------------------------------------
# Purpose: Provides script description, usage, and flags documentation
# --------------------------------------------------------------------------------
# Keeper PAM Export Tool
# ----------------------------------------
# Description:
#   This script exports Apache Guacamole connection data into Keeper PAM-ready
#   formats for import via Keeper Commander CLI. It safely patches the docker-compose
#   file to expose database ports if needed and provides JSON export files that can
#   be imported using the Keeper Commander tool.
#
# Usage Examples:
#   ./keeper-pam-export.sh                # Interactive mode
#   ./keeper-pam-export.sh --export       # CLI export with defaults
#
# Flags:
#   --export            Run export with default settings
#   --output-dir DIR    Custom export directory (default: current directory)
#   --filename-prefix   Prefix for output files (default: keeper)
#   --compose-file      Path to docker-compose.yml (default: /etc/kcm-setup/docker-compose.yml)
#   --db-host           Database host (default: localhost)
#   --db-port           Database port (default: 3306)
#   --sanitize          Credentials sanitization mode: none, placeholder, remove (default: placeholder)
#   --keeper-folder     Root folder for Keeper PAM import (default: Guacamole)
#   --debug             Enable debug logging
#   --help              Show this help message
#   --version           Show version information
# ================================================================================

set -e


# ================================================================================
# SECTION 2: VARIABLES AND CONFIG
# --------------------------------------------------------------------------------
# Purpose: Defines default configuration variables
# --------------------------------------------------------------------------------
# Script Version
VERSION="1.3.0"

# Default Configs
EXPORT_DIR="."  # Current directory where script is run
FILENAME_PREFIX="keeper"
COMPOSE_FILE="/etc/kcm-setup/docker-compose.yml"
DB_HOST="localhost"
DB_PORT=3306
DB_USER=""
DB_PASS=""
DB_NAME=""
SANITIZE_MODE="placeholder"  # Options: none, placeholder, remove
KEEPER_ROOT_FOLDER="Guacamole"
DEBUG=false
QUIET=false
DB_SERVICE=""
MAX_RETRIES=3
CONNECTION_VERIFIED=false


# ================================================================================
# SECTION 3: LOGGING FUNCTIONS
# --------------------------------------------------------------------------------
# Purpose: Provides logging utilities for different message types
# --------------------------------------------------------------------------------
log_info() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_success() { echo -e "\033[1;34m[SUCCESS]\033[0m $1"; }
log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "\033[1;35m[DEBUG]\033[0m $1"
    fi
}

# Simple ASCII table display function
print_fancy_table() {
    local title="$1"
    local data="$2"
    local width=60  # Default width (will be adjusted based on content)
    local border_char="-"
    local side_char="|"
    local corner_tl="+"
    local corner_tr="+"
    local corner_bl="+"
    local corner_br="+"
    
    # Clean data - remove any null values or unwanted characters
    local cleaned_data=""
    while IFS= read -r line; do
        # Skip empty lines and lines with just "null"
        if [[ -n "$line" && "$line" != "null" ]]; then
            # Remove any trailing "null" strings
            line=$(echo "$line" | sed 's/null//g')
            cleaned_data="${cleaned_data}${line}"$'\n'
        fi
    done <<< "$data"
    
    # Get the column-formatted data
    local formatted_data=""
    if command -v column &>/dev/null; then
        formatted_data=$(echo -e "$cleaned_data" | column -t -s ',' -o ' | ')
    else
        # Fallback if column is not available
        formatted_data=$(echo -e "$cleaned_data" | sed 's/,/ | /g')
    fi
    
    # Skip empty tables
    if [[ -z "$formatted_data" ]]; then
        return 0
    fi
    
    # Calculate the max line length in the formatted data
    local max_length=0
    while IFS= read -r line; do
        local line_length=${#line}
        if (( line_length > max_length )); then
            max_length=$line_length
        fi
    done <<< "$formatted_data"
    
    # Adjust width if content is wider
    width=$(( max_length + 4 ))  # Add padding
    
    # Calculate title centering
    local title_length=${#title}
    local padding=$(( (width - title_length - 2) / 2 ))
    local left_padding=$padding
    local right_padding=$(( padding + (width - title_length - 2) % 2 ))
    
    # Print table top border with title
    echo -e "\n+$(printf '%*s' $width | tr ' ' "${border_char}")+"
    echo -e "|$(printf '%*s' $left_padding)${title}$(printf '%*s' $right_padding)|"
    echo -e "|$(printf '%*s' $width | tr ' ' " ")|"
    
    # Print the data rows
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            echo -e "| ${line}$(printf '%*s' $(( width - ${#line} - 2 )) | tr ' ' " ") |"
        fi
    done <<< "$formatted_data"
    
    # Print table bottom border
    echo -e "|$(printf '%*s' $width | tr ' ' " ")|"
    echo -e "+$(printf '%*s' $width | tr ' ' "${border_char}")+"
}

# ================================================================================
# SECTION 4: CLEANUP FUNCTION
# --------------------------------------------------------------------------------
# Purpose: Handles exit cleanup and error reporting
# --------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script terminated with errors. Exit code: $exit_code"
    fi
    exit $exit_code
}

trap cleanup EXIT

# ================================================================================
# SECTION 5: VERSION DISPLAY
# --------------------------------------------------------------------------------
# Purpose: Shows version information
# --------------------------------------------------------------------------------
show_version() {
    echo "Keeper PAM Export Tool v$VERSION"
    echo "Optimized for Keeper PAM import compatibility"
    exit 0
}

# ================================================================================
# SECTION 6: ARGUMENT PARSING
# --------------------------------------------------------------------------------
# Purpose: Parses and validates CLI arguments
# --------------------------------------------------------------------------------
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        log_info "No CLI flags provided. Entering interactive mode."

        # Ask about sanitization
        echo "Would you like to sanitize credentials in the export?"
        echo "1) No sanitization (include actual credentials)"
        echo "2) Replace with placeholders (recommended for security)"
        echo "3) Remove credentials completely"
        read -p "Enter choice [1-3]: " sanitize_mode
        case $sanitize_mode in
            1) SANITIZE_MODE="none";;
            2) SANITIZE_MODE="placeholder";;
            3) SANITIZE_MODE="remove";;
            *) log_warn "Invalid selection. Using placeholders as default."; SANITIZE_MODE="placeholder";;
        esac

        # Ask about Keeper root folder name
        read -p "Enter root folder name for Keeper PAM import [Guacamole]: " keeper_folder
        if [[ -n "$keeper_folder" ]]; then
            KEEPER_ROOT_FOLDER="$keeper_folder"
        fi
    else
        while [[ $# -gt 0 ]]; do
            case $1 in
                --export) EXPORT=true ; shift ;;
                --output-dir) EXPORT_DIR="$2" ; shift 2 ;;
                --filename-prefix) FILENAME_PREFIX="$2" ; shift 2 ;;
                --compose-file) COMPOSE_FILE="$2" ; shift 2 ;;
                --db-host) DB_HOST="$2" ; shift 2 ;;
                --db-port) DB_PORT="$2" ; shift 2 ;;
                --keeper-folder) KEEPER_ROOT_FOLDER="$2" ; shift 2 ;;
                --debug) DEBUG=true ; shift ;;
                --quiet) QUIET=true ; shift ;;
                --version) show_version ;;
                --sanitize)
                    case "$2" in
                        none|placeholder|remove) SANITIZE_MODE="$2" ; shift 2 ;;
                        *) log_error "Invalid sanitize mode: $2. Use none, placeholder, or remove." ; exit 1 ;;
                    esac
                    ;;
                --help)
                    echo "Usage: $0 [options]"
                    echo "Options:"
                    echo "  --export             Export with default settings"
                    echo "  --output-dir DIR     Custom export directory"
                    echo "  --filename-prefix    Prefix for output files"
                    echo "  --compose-file       Path to docker-compose.yml"
                    echo "  --db-host            Database host (default: localhost)"
                    echo "  --db-port            Database port (default: 3306)"
                    echo "  --sanitize MODE      Sanitize credentials: none, placeholder, remove"
                    echo "  --keeper-folder      Root folder for Keeper PAM import (default: Guacamole)"
                    echo "  --debug              Enable debug logging"
                    echo "  --quiet              Suppress detailed output"
                    echo "  --version            Show version information"
                    echo "  --help               Show this help message"
                    exit 0
                    ;;
                *) log_error "Unknown argument: $1. Use --help for usage information." ; exit 1 ;;
            esac
        done
    fi

    # Set default sanitization mode if not specified
    if [[ -z "$SANITIZE_MODE" ]]; then
        SANITIZE_MODE="placeholder"
        log_info "Using default credential sanitization mode: placeholder"
    else
        log_info "Credential sanitization mode: $SANITIZE_MODE"
    fi

    log_debug "Using Keeper root folder: $KEEPER_ROOT_FOLDER"
}

# ================================================================================
# SECTION 7: DEPENDENCY CHECKING
# --------------------------------------------------------------------------------
# Purpose: Verifies required tools are available
# --------------------------------------------------------------------------------
check_dependencies() {
    log_info "Checking required dependencies..."

    # Check Python modules
    python3 -c "import yaml, json" 2>/dev/null || {
        log_error "Missing required Python modules. Please install: pip install pyyaml"
        exit 1
    }

    # Try to import mysql connector but don't fail if it's missing yet
    if ! python3 -c "import mysql.connector" 2>/dev/null; then
        log_warn "MySQL Connector for Python not found. Will attempt to install it."
        pip install mysql-connector-python --quiet || {
            log_error "Failed to install mysql-connector-python. Please install it manually."
            exit 1
        }
        log_info "MySQL Connector installed successfully."
    fi

    # Check required command-line tools
    for cmd in docker-compose jq python3; do
        command -v $cmd &>/dev/null || {
            log_error "Required command '$cmd' not found"
            exit 1
        }
    done

    # Optional command checks with helpful instructions
    if ! command -v mysqladmin &>/dev/null; then
        log_warn "mysqladmin command not found. MySQL connectivity checks will be basic."
        log_warn "Install with: apt-get install mysql-client or yum install mysql"
    fi

    log_success "All required dependencies are available."
}
# ================================================================================

# ================================================================================
# SECTION 8: DIRECTORY SETUP
# --------------------------------------------------------------------------------
# Purpose: Creates and validates export directory
# --------------------------------------------------------------------------------
setup_export_directory() {
    # If default current directory, no need to create anything
    if [[ "$EXPORT_DIR" != "." && ! -d "$EXPORT_DIR" ]]; then
        log_info "Creating export directory: $EXPORT_DIR"
        mkdir -p "$EXPORT_DIR" || {
            log_error "Failed to create export directory"
            exit 1
        }
    fi

    # Make sure the directory is writable
    if [[ ! -w "$EXPORT_DIR" ]]; then
        log_error "Export directory is not writable: $EXPORT_DIR"
        exit 1
    fi

    log_debug "Export directory set to: $EXPORT_DIR"
}

# ================================================================================
# SECTION 9: DOCKER COMPOSE INSPECTION
# --------------------------------------------------------------------------------
# Purpose: Examines compose file for database service and port configuration
# --------------------------------------------------------------------------------
inspect_compose_file() {
    log_info "Inspecting docker-compose.yml for database service and port configuration..."

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Compose file not found at $COMPOSE_FILE"
        exit 1
    fi

    # Improved compose file parsing: Focus on service and port detection only
    db_info=$(python3 - <<EOF
import yaml, json
try:
    with open("$COMPOSE_FILE", "r") as f:
        data = yaml.safe_load(f)
        result = {"status": "error", "message": "No services found"}

        if 'services' not in data:
            print(json.dumps(result))
            exit(0)

        # Look for database service
        db_service = None
        ports_exposed = False
        port_mapping = None

        for service_name, service_config in data['services'].items():
            image = service_config.get('image', '').lower()

            # Identify database service by image name
            if any(db_img in image for db_img in ['mysql', 'mariadb', 'postgres']):
                db_service = service_name

                # Look for port configuration
                if 'ports' in service_config:
                    ports = service_config['ports']

                    # Handle various port formats
                    for port in ports:
                        if isinstance(port, dict) and 'published' in port and 'target' in port:
                            if port['target'] in [3306, 5432]:
                                port_mapping = f"{port['published']}:{port['target']}"
                                ports_exposed = True
                                break
                        elif isinstance(port, str):
                            # Handle formats like "3308:3306"
                            if ':' in port:
                                host_port, container_port = port.split(':')
                                if container_port in ['3306', '5432']:
                                    port_mapping = port
                                    ports_exposed = True
                                    break
                            # Handle direct port exposure like "3306"
                            elif port in ['3306', '5432']:
                                port_mapping = port
                                ports_exposed = True
                                break

                # Check environment variables for port config
                if 'environment' in service_config:
                    env = service_config['environment']
                    env_dict = {}

                    # Handle both list and dict formats
                    if isinstance(env, list):
                        for item in env:
                            if '=' in item:
                                key, value = item.split('=', 1)
                                env_dict[key] = value
                    else:
                        env_dict = env

                    # Look for port in environment
                    for key, value in env_dict.items():
                        if 'PORT' in key.upper() and value:
                            port_mapping = f"{value}:{value}" if not ports_exposed else port_mapping
                            break

                break  # Stop after finding the first database service

        # Fallback to 'db' if no database service found by image
        if not db_service and 'db' in data['services']:
            db_service = 'db'
            # Repeat port detection for this service
            service_config = data['services']['db']
            # (port detection code would be duplicated here)

        # Prepare result
        if db_service:
            result = {
                "status": "success",
                "db_service": db_service,
                "ports_exposed": ports_exposed,
                "port_mapping": port_mapping
            }
        else:
            result = {
                "status": "error",
                "message": "No database service found in docker-compose.yml"
            }

        print(json.dumps(result))

except Exception as e:
    print(json.dumps({"status": "error", "message": str(e)}))
EOF
)

    log_debug "Docker-compose inspection result: $db_info"

    # Parse the JSON response
    if ! jq -e . >/dev/null 2>&1 <<< "$db_info"; then
        log_error "Failed to parse inspection result"
        exit 1
    fi

    status=$(echo "$db_info" | jq -r '.status')

    if [[ "$status" == "error" ]]; then
        message=$(echo "$db_info" | jq -r '.message')
        log_error "Docker-compose inspection failed: $message"
        exit 1
    fi

    DB_SERVICE=$(echo "$db_info" | jq -r '.db_service')
    ports_exposed=$(echo "$db_info" | jq -r '.ports_exposed')
    port_mapping=$(echo "$db_info" | jq -r '.port_mapping')

    log_info "Found database service: $DB_SERVICE"

    if [[ "$ports_exposed" == "true" && -n "$port_mapping" ]]; then
        log_success "Database port is exposed: $port_mapping"

        # Extract host port from mapping (e.g., "3308:3306" → "3308")
        if [[ "$port_mapping" == *":"* ]]; then
            DB_PORT=$(echo "$port_mapping" | cut -d':' -f1)
        else
            DB_PORT=$port_mapping
        fi

        log_info "Using port $DB_PORT for database connection"
    else
        log_warn "Database port for MySQL is NOT exposed in docker-compose.yml"
        read -p "Would you like to expose it now (this will patch the compose file)? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            patch_compose_file
        else
            log_warn "Continuing without exposing database port."
            log_info "You may need to provide connection details manually later if automatic detection fails."
        fi
    fi
}

# ================================================================================
# SECTION 10: COMPOSE FILE PATCHING
# --------------------------------------------------------------------------------
# Purpose: Modifies compose file to expose database port
# --------------------------------------------------------------------------------
patch_compose_file() {
    backup_file="${COMPOSE_FILE}.bak.$(date +%s)"
    cp "$COMPOSE_FILE" "$backup_file"
    log_info "Backup of original compose file saved as $backup_file"

    read -p "Enter the host port to expose for MySQL (default: $DB_PORT): " custom_port
    [[ -z "$custom_port" ]] && custom_port=$DB_PORT

    # Patch the file using Python
    patch_result=$(python3 - <<EOF
import yaml, json
try:
    compose_file = "$COMPOSE_FILE"
    db_service = "$DB_SERVICE"
    port = "$custom_port"
    container_port = "3306"  # Default MySQL port

    with open(compose_file) as file:
        config = yaml.safe_load(file)

        # Ensure ports list exists
        if 'ports' not in config['services'][db_service]:
            config['services'][db_service]['ports'] = []

        # Add the port mapping
        port_mapping = f"{port}:{container_port}"

        # Check if this exact mapping already exists
        if port_mapping not in config['services'][db_service]['ports']:
            config['services'][db_service]['ports'].append(port_mapping)

            # Write the updated config back to the file
            with open(compose_file, "w") as out:
                yaml.dump(config, out, default_flow_style=False)

            print(json.dumps({"status": "success", "message": "Compose file patched successfully"}))
        else:
            print(json.dumps({"status": "warning", "message": "Port mapping already exists"}))

except Exception as e:
    print(json.dumps({"status": "error", "message": str(e)}))
EOF
)

    status=$(echo "$patch_result" | jq -r '.status')
    message=$(echo "$patch_result" | jq -r '.message')

    if [[ "$status" == "error" ]]; then
        log_error "Failed to patch compose file: $message"
        log_info "You can try manual port exposure by editing $COMPOSE_FILE"
        return 1
    elif [[ "$status" == "warning" ]]; then
        log_warn "$message"
    else
        log_success "Compose file patched to expose port ${custom_port} → 3306"
    fi

    # Update the DB_PORT to the custom port for subsequent operations
    DB_PORT=$custom_port

    read -p "Apply changes and restart containers with 'docker-compose up -d'? [y/N]: " restart_confirm
    if [[ "$restart_confirm" =~ ^[Yy]$ ]]; then
        restart_containers
    else
        log_warn "User chose not to restart containers. Please do so manually."
    fi
}

# ================================================================================
# SECTION 11: CONTAINER RESTART
# --------------------------------------------------------------------------------
# Purpose: Restarts containers after compose file changes
# --------------------------------------------------------------------------------
restart_containers() {
    log_info "Restarting containers with docker-compose..."

    # Check if compose file path is in a directory different from current directory
    local compose_dir=$(dirname "$COMPOSE_FILE")
    if [[ "$compose_dir" != "." ]]; then
        log_info "Changing to directory: $compose_dir"
        (cd "$compose_dir" && docker-compose up -d)
    else
        docker-compose -f "$COMPOSE_FILE" up -d
    fi

    log_info "Waiting 15 seconds for containers to restart..."
    sleep 15
}

# ================================================================================
# SECTION 12: CREDENTIAL EXTRACTION
# --------------------------------------------------------------------------------
# Purpose: Gets database credentials from compose file
# --------------------------------------------------------------------------------
extract_db_credentials() {
    log_info "Extracting database credentials from docker-compose.yml..."

    if [[ -z "$DB_SERVICE" ]]; then
        log_error "Database service name not available. Run inspect_compose_file first."
        exit 1
    fi

    # Enhanced credential extraction with better error handling
    credentials=$(python3 - <<EOF
import yaml, json
try:
    compose_file = "$COMPOSE_FILE"
    db_service = "$DB_SERVICE"

    with open(compose_file) as file:
        config = yaml.safe_load(file)

        if 'services' not in config or db_service not in config['services']:
            print(json.dumps({
                "status": "error",
                "message": f"Service '{db_service}' not found in compose file"
            }))
            exit(0)

        service_config = config['services'][db_service]
        env_vars = {}

        # Extract environment variables
        if 'environment' in service_config:
            env = service_config['environment']

            # Handle dict format
            if isinstance(env, dict):
                env_vars = env
            # Handle list format like ["KEY=VALUE"]
            elif isinstance(env, list):
                for item in env:
                    if isinstance(item, str) and '=' in item:
                        key, value = item.split('=', 1)
                        env_vars[key] = value

        # Look for database credentials in environment variables
        # Try multiple possible variable names
        username = None
        password = None
        database = None

        # Username variables
        for var in ['MYSQL_USER', 'MARIADB_USER', 'GUACAMOLE_USERNAME']:
            if var in env_vars and env_vars[var]:
                username = env_vars[var]
                break

        # Password variables
        for var in ['MYSQL_PASSWORD', 'MARIADB_PASSWORD', 'GUACAMOLE_PASSWORD']:
            if var in env_vars and env_vars[var]:
                password = env_vars[var]
                break

        # Database name variables
        for var in ['MYSQL_DATABASE', 'MARIADB_DATABASE', 'GUACAMOLE_DATABASE']:
            if var in env_vars and env_vars[var]:
                database = env_vars[var]
                break

        # Check for root password as fallback
        root_password = None
        for var in ['MYSQL_ROOT_PASSWORD', 'MARIADB_ROOT_PASSWORD']:
            if var in env_vars and env_vars[var]:
                root_password = env_vars[var]
                break

        # If no database name found, use some common defaults
        if not database:
            for default_db in ['guacamole_db', 'guacamole']:
                database = default_db
                break

        # Prepare result
        result = {
            "status": "success",
            "user": username,
            "password": password,
            "database": database,
            "root_password": root_password
        }

        # Flag if credentials seem incomplete
        if not username or not password:
            result["status"] = "incomplete"
            result["message"] = "Some credentials could not be extracted automatically"

        print(json.dumps(result))
except Exception as e:
    print(json.dumps({
        "status": "error",
        "message": str(e)
    }))
EOF
)

    # For security, redact passwords in debug output
    if [[ "$DEBUG" == "true" ]]; then
        redacted_credentials=$(echo "$credentials" | jq '.password = "REDACTED" | .root_password = "REDACTED"')
        log_debug "Credential extraction result: $redacted_credentials"
    fi

    status=$(echo "$credentials" | jq -r '.status')

    if [[ "$status" == "error" ]]; then
        message=$(echo "$credentials" | jq -r '.message')
        log_error "Failed to extract credentials: $message"
        prompt_manual_credentials
    elif [[ "$status" == "incomplete" ]]; then
        message=$(echo "$credentials" | jq -r '.message')
        log_warn "$message"

        # Try to use partial credentials if available
        DB_USER=$(echo "$credentials" | jq -r '.user // empty')
        DB_PASS=$(echo "$credentials" | jq -r '.password // empty')
        DB_NAME=$(echo "$credentials" | jq -r '.database // empty')

        # Store root password for fallback connection attempts
        ROOT_PASS=$(echo "$credentials" | jq -r '.root_password // empty')

        log_info "Some credentials were extracted. You may need to provide missing details."
        if [[ -z "$DB_USER" || -z "$DB_PASS" || -z "$DB_NAME" ]]; then
            prompt_manual_credentials
        fi
    else
        DB_USER=$(echo "$credentials" | jq -r '.user')
        DB_PASS=$(echo "$credentials" | jq -r '.password')
        DB_NAME=$(echo "$credentials" | jq -r '.database')
        ROOT_PASS=$(echo "$credentials" | jq -r '.root_password // empty')

        log_success "Database credentials extracted successfully."
        log_info "Username: $DB_USER, Database: $DB_NAME"
    fi
}

# Helper function to prompt for manual credentials input
prompt_manual_credentials() {
    log_info "Please enter database connection details manually:"

    # Prefill with any values we already have
    [[ -n "$DB_USER" ]] && default_user="[$DB_USER]" || default_user=""
    [[ -n "$DB_NAME" ]] && default_db="[$DB_NAME]" || default_db=""

    read -p "Database username ${default_user}: " input_user
    read -sp "Database password: " input_pass
    echo ""
    read -p "Database name ${default_db}: " input_db

    # Only update if input is provided
    [[ -n "$input_user" ]] && DB_USER="$input_user"
    [[ -n "$input_pass" ]] && DB_PASS="$input_pass"
    [[ -n "$input_db" ]] && DB_NAME="$input_db"

    # Validate the entered credentials
    if [[ -z "$DB_USER" || -z "$DB_PASS" || -z "$DB_NAME" ]]; then
        log_error "All database connection fields are required"
        exit 1
    fi

    log_info "Manual connection details accepted"
}

# ================================================================================
# SECTION 13: DATABASE CONNECTION VERIFICATION
# --------------------------------------------------------------------------------
# Purpose: Tests database connection with retry and fallback mechanisms
# --------------------------------------------------------------------------------
verify_db_connection() {
    log_info "Verifying database connection..."

    # Try multiple connection approaches in sequence
    CONNECTION_VERIFIED=false

    # Approach 1: Try with extracted credentials
    log_info "Connection attempt #1: Using extracted credentials on $DB_HOST:$DB_PORT"
    if test_mysql_connection "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME"; then
        CONNECTION_VERIFIED=true
        log_success "Connection successful with extracted credentials"
        return 0
    fi

    # Approach 2: Try with container name as host
    if [[ "$DB_HOST" == "localhost" && -n "$DB_SERVICE" ]]; then
        log_info "Connection attempt #2: Using container name as host"
        if test_mysql_connection "$DB_SERVICE" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME"; then
            CONNECTION_VERIFIED=true
            DB_HOST="$DB_SERVICE"
            log_success "Connection successful using container name as host"
            return 0
        fi
    fi

    # Approach 3: Try with root user if root password available
    if [[ -n "$ROOT_PASS" ]]; then
        log_info "Connection attempt #3: Using root credentials"
        if test_mysql_connection "$DB_HOST" "$DB_PORT" "root" "$ROOT_PASS" "$DB_NAME"; then
            CONNECTION_VERIFIED=true
            DB_USER="root"
            DB_PASS="$ROOT_PASS"
            log_success "Connection successful with root credentials"
            return 0
        fi
    fi

    # Approach 4: Try common database names if the specified one failed
    log_info "Connection attempt #4: Trying alternative database names"
    for alt_db in "guacamole" "guacamole_db" "mysql"; do
        if [[ "$alt_db" != "$DB_NAME" ]]; then
            log_info "Trying database name: $alt_db"
            if test_mysql_connection "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$alt_db"; then
                CONNECTION_VERIFIED=true
                DB_NAME="$alt_db"
                log_success "Connection successful with database: $DB_NAME"
                return 0
            fi
        fi
    done

    # If all automatic attempts fail, prompt for manual credentials
    log_warn "All automatic connection attempts failed."
    log_info "Would you like to enter different database credentials?"
    read -p "Try different credentials? [Y/n]: " try_different

    if [[ -z "$try_different" || "$try_different" =~ ^[Yy]$ ]]; then
        prompt_manual_credentials

        # Try with the new manual credentials
        log_info "Trying connection with manual credentials..."
        if test_mysql_connection "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME"; then
            CONNECTION_VERIFIED=true
            log_success "Connection successful with manual credentials"
            return 0
        else
            log_error "Connection failed with manual credentials"
            log_error "Unable to establish a working database connection"
            exit 1
        fi
    else
        log_error "Unable to establish a working database connection"
        exit 1
    fi
}

# Helper function to test MySQL connection
test_mysql_connection() {
    local host=$1
    local port=$2
    local user=$3
    local pass=$4
    local db=$5

    log_debug "Testing connection to $host:$port with user $user, database $db"

    connection_result=$(python3 - <<EOF
import mysql.connector
import json
import sys

try:
    # Set a reasonably short timeout
    conn = mysql.connector.connect(
        host='$host',
        port=$port,
        user='$user',
        password='$pass',
        database='$db',
        connect_timeout=5
    )

    # Verify we can actually run a query
    cursor = conn.cursor()
    cursor.execute("SELECT 1")
    cursor.fetchone()
    cursor.close()

    conn.close()
    print(json.dumps({"status": "success"}))
except mysql.connector.Error as err:
    error_code = str(err.errno) if hasattr(err, 'errno') else 'unknown'
    error_msg = str(err)
    print(json.dumps({
        "status": "error",
        "error_code": error_code,
        "message": error_msg
    }))
except Exception as e:
    print(json.dumps({
        "status": "error",
        "error_code": "unknown",
        "message": str(e)
    }))
EOF
)

    status=$(echo "$connection_result" | jq -r '.status')

    if [[ "$status" == "success" ]]; then
        return 0
    else
        error_code=$(echo "$connection_result" | jq -r '.error_code')
        message=$(echo "$connection_result" | jq -r '.message')

        log_debug "Connection error ($error_code): $message"
        return 1
    fi
}


# ================================================================================
# SECTION 14: DATA EXPORT
# --------------------------------------------------------------------------------
# Purpose: Extracts and formats connection data from Guacamole database to Keeper PAM format
# --------------------------------------------------------------------------------
export_connection_data() {
    log_info "Exporting connection data from Guacamole database to Keeper PAM format..."

    if [[ "$CONNECTION_VERIFIED" != "true" ]]; then
        log_error "Database connection not verified. Run verify_db_connection first."
        exit 1
    fi

    # Prepare output filenames with timestamps
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local connections_file="${EXPORT_DIR}/${FILENAME_PREFIX}_connections_${timestamp}.json"
    local pam_format_file="${EXPORT_DIR}/${FILENAME_PREFIX}_pam_format_${timestamp}.json"
    local folders_file="${EXPORT_DIR}/${FILENAME_PREFIX}_folders_${timestamp}.json"
    local records_file="${EXPORT_DIR}/${FILENAME_PREFIX}_records_${timestamp}.json"

    log_info "Exporting Guacamole connections to: $connections_file"
    log_info "Exporting PAM format to: $pam_format_file"
    log_info "Exporting folders to: $folders_file"
    log_info "Exporting records to: $records_file"

    # Execute the data export using Python for better error handling and formatting
    export_result=$(python3 - <<EOF
import mysql.connector
import json
import re
import sys
import hashlib

# Helper functions for data sanitization
def sanitize_value(value, mode):
    if value is None:
        return None

    if mode == "none":
        return value
    elif mode == "remove":
        return None
    else:  # placeholder mode
        # Use different placeholder formats based on field type
        if isinstance(value, str):
            if re.match(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$', value):
                # Looks like a password
                return "[PASSWORD]"
            elif re.match(r'^\w+@\w+\.\w+$', value):
                # Looks like an email
                return "[EMAIL]"
            elif re.match(r'^(\d{1,3}\.){3}\d{1,3}$', value):
                # Looks like an IP address
                return "[IP_ADDRESS]"
            else:
                # Generic credential
                return "[CREDENTIAL]"
        return "[CREDENTIAL]"

# Helper function to generate a simple UID from a name
def generate_uid(name):
    # Create a simple uid by replacing spaces with underscores and making lowercase
    return name.lower().replace(' ', '_').replace('-', '_')

try:
    # Connect to the database
    conn = mysql.connector.connect(
        host='$DB_HOST',
        port=$DB_PORT,
        user='$DB_USER',
        password='$DB_PASS',
        database='$DB_NAME'
    )

    cursor = conn.cursor(dictionary=True)

    # Check if we have guacamole_connection table
    cursor.execute("SHOW TABLES LIKE 'guacamole_connection'")
    if not cursor.fetchone():
        print(json.dumps({
            "status": "error",
            "message": "Required Guacamole tables not found in database"
        }))
        sys.exit(0)

    # Get connection data with parameters
    cursor.execute("""
        SELECT
            c.connection_id,
            c.connection_name,
            c.parent_id,
            c.protocol,
            p.parameter_name,
            p.parameter_value
        FROM
            guacamole_connection c
        LEFT JOIN
            guacamole_connection_parameter p ON c.connection_id = p.connection_id
        ORDER BY
            c.connection_id, p.parameter_name
    """)

    # Process results into a structured format
    connections = {}
    user_mappings = {}

    # First, structure the connection data
    for row in cursor:
        conn_id = row['connection_id']

        if conn_id not in connections:
            connections[conn_id] = {
                "id": conn_id,
                "name": row['connection_name'],
                "protocol": row['protocol'],
                "parent_id": row['parent_id'],
                "parameters": {}
            }

        # Add parameter if it exists
        if row['parameter_name']:
            param_name = row['parameter_name']
            param_value = row['parameter_value']

            # Apply sanitization based on mode and parameter type
            if param_name in ['password', 'passphrase', 'private-key', 'username', 'secret']:
                param_value = sanitize_value(param_value, '$SANITIZE_MODE')

            connections[conn_id]['parameters'][param_name] = param_value

    # Get connection hierarchy information (folders)
    cursor.execute("SELECT * FROM guacamole_connection_group")

    # Process connection groups (folders)
    groups = {}
    for row in cursor:
        group_id = row['connection_group_id']
        groups[group_id] = {
            "id": group_id,
            "name": row['connection_group_name'],
            "parent_id": row['parent_id'],
            "type": row['type']
        }

    # Prepare the original Guacamole format for Keeper
    keeper_data = {
        "root_folder": "$KEEPER_ROOT_FOLDER",
        "connections": list(connections.values()),
        "groups": list(groups.values()),
        "user_mappings": user_mappings
    }

    # Write the original connections file
    with open('$connections_file', 'w') as f:
        json.dump(keeper_data, f, indent=2)

    # ============================================================================
    # PREPARE KEEPER PAM EXPORT FOLLOWING DOCUMENTATION
    # ============================================================================
    
    # Prepare shared folders for PAM format
    shared_folders = []
    folder_map = {}
    
    # Create proper folder objects with uid and path
    for group_id, group in groups.items():
        if group['parent_id'] is None and group['type'] == 'ORGANIZATIONAL':
            folder_name = group['name']
            folder_uid = generate_uid(folder_name)
            
            # Create folder object with uid AND path
            folder_obj = {
                "name": folder_name,
                "uid": folder_uid,
                "path": folder_name  # Required by Keeper import
            }
            
            shared_folders.append(folder_obj)
            folder_map[group_id] = folder_obj

    # If no shared folders found, add a default one
    if not shared_folders:
        default_name = "$KEEPER_ROOT_FOLDER"
        default_uid = generate_uid(default_name)
        
        default_folder = {
            "name": default_name,
            "uid": default_uid,
            "path": default_name  # Required by Keeper import
        }
        
        shared_folders.append(default_folder)
    
    # Create separate folders file
    folders_data = {
        "shared_folders": shared_folders
    }
    
    # Create PAM format structure for complete export
    pam_format = {
        "shared_folders": shared_folders,
        "records": []
    }
    
    # Process all connections to create PAM records
    records = []
    for conn_id, conn in connections.items():
        # Get basic connection info
        protocol = conn['protocol']
        
        # Handle hostname and port
        hostname = conn['parameters'].get('hostname', '')
        if not hostname:
            hostname = conn['parameters'].get('host', '')
        
        port = conn['parameters'].get('port', '')
        
        # Fix hostname if it contains port
        if hostname and ':' in hostname:
            hostname_parts = hostname.split(':')
            hostname = hostname_parts[0]
            if not port:
                port = hostname_parts[1]
        
        # For http connections, try to extract hostname from URL
        if protocol == 'http' and not hostname:
            url = conn['parameters'].get('url', '')
            if url:
                try:
                    # Try to extract hostname from URL
                    if '://' in url:
                        hostname = url.split('://')[1].split('/')[0]
                    else:
                        hostname = url.split('/')[0]
                    
                    # Extract port if it's in the hostname
                    if ':' in hostname:
                        hostname_parts = hostname.split(':')
                        hostname = hostname_parts[0]
                        if not port:
                            port = hostname_parts[1]
                except:
                    pass
        
        # Get username/password if available
        username = conn['parameters'].get('username', 'username')
        password = conn['parameters'].get('password', 'password')
        
        # Determine SSL verification
        ssl_verification = True
        if protocol == 'rdp' and conn['parameters'].get('ignore-cert') == 'true':
            ssl_verification = False
        elif protocol == 'http' and conn['parameters'].get('url', '').startswith('http:'):
            ssl_verification = False
        
        # Create the record structure using the exact field names from Keeper's example
        record = {
            "title": conn['name'] if conn['name'] else "Unnamed Connection",
            "$type": "pamMachine",
            "custom_fields": {
                "$pamHostname": {
                    "hostName": hostname if hostname else "",
                    "port": port if port else ""
                },
                "$checkbox:sslVerification": ssl_verification
            },
            "login": username if username else "username",
            "password": password if password else "password",
            "folders": []
        }
        
        # Add folder mapping if available - use path string, not object
        if conn['parent_id'] in folder_map:
            folder_obj = folder_map[conn['parent_id']]
            record["folders"].append({
                "shared_folder": folder_obj["path"],
                "can_edit": True,
                "can_share": True
            })
        # If no parent folder found but we have a default folder, use it
        elif shared_folders:
            record["folders"].append({
                "shared_folder": shared_folders[0]["path"],
                "can_edit": True,
                "can_share": True
            })
        
        # Add the record to our lists
        records.append(record)
        pam_format["records"].append(record)
    
    # Validate and clean up records to prevent import errors
    for record in records:
        # Ensure title exists
        if not record.get("title"):
            record["title"] = "Unnamed Connection"
        
        # Ensure no empty keys exist at top level
        empty_keys = [k for k in list(record.keys()) if k == ""]
        for k in empty_keys:
            del record[k]
        
        # Ensure no empty keys in custom_fields
        if "custom_fields" in record and isinstance(record["custom_fields"], dict):
            empty_cf_keys = [k for k in list(record["custom_fields"].keys()) if k == ""]
            for k in empty_cf_keys:
                del record["custom_fields"][k]
        
        # Ensure folders is always a list
        if not record.get("folders") or not isinstance(record["folders"], list):
            record["folders"] = []
    
    # Create separate records file
    records_data = {
        "records": records
    }
    
    # Write all files
    with open('$pam_format_file', 'w') as f:
        json.dump(pam_format, f, indent=2)
        
    with open('$folders_file', 'w') as f:
        json.dump(folders_data, f, indent=2)
        
    with open('$records_file', 'w') as f:
        json.dump(records_data, f, indent=2)
    
    # Count protocol types for stats
    protocol_stats = {}
    machine_records_count = 0
    for conn in connections.values():
        protocol = conn['protocol'].upper()
        protocol_stats[protocol] = protocol_stats.get(protocol, 0) + 1
        machine_records_count += 1
    
    # Create protocol counts as a simple list for display
    protocol_counts = []
    for protocol, count in sorted(protocol_stats.items()):
        protocol_counts.append(f"{protocol},{count}")
        
    protocol_counts_str = "\n".join(protocol_counts)
    
    # Return a simple success message with integer counts
    results = {
        "status": "success",
        "connections_count": len(connections),
        "groups_count": len(groups),
        "pam_records_count": len(pam_format["records"]),
        "shared_folders_count": len(shared_folders),
        "machine_records_count": machine_records_count,
        "protocol_counts_str": protocol_counts_str
    }
    
    print(json.dumps(results))

    cursor.close()
    conn.close()

except Exception as e:
    print(json.dumps({
        "status": "error",
        "message": str(e)
    }))
EOF
)

    # Process the export result
    if ! echo "$export_result" | jq -e . > /dev/null 2>&1; then
        log_error "Invalid JSON output from export"
        log_debug "Raw output: $export_result"
        exit 1
    fi

    status=$(echo "$export_result" | jq -r '.status')

    if [[ "$status" == "error" ]]; then
        message=$(echo "$export_result" | jq -r '.message')
        log_error "Export failed: $message"
        exit 1
    elif [[ "$status" == "warning" ]]; then
        message=$(echo "$export_result" | jq -r '.message')
        log_warn "$message"
    else
        log_success "Export completed successfully!"
        
        # Format data for export statistics table - ensure clean values
        connections_count=$(echo "$export_result" | jq -r '.connections_count')
        groups_count=$(echo "$export_result" | jq -r '.groups_count')
        pam_records_count=$(echo "$export_result" | jq -r '.pam_records_count')
        shared_folders_count=$(echo "$export_result" | jq -r '.shared_folders_count')
        machine_records_count=$(echo "$export_result" | jq -r '.machine_records_count')
        
        # Create the export data with explicit values
        export_data="Metric,Value
Connections,${connections_count}
Groups,${groups_count}
PAM Records,${pam_records_count}"

        # Display export statistics in table
        print_fancy_table "EXPORT STATISTICS" "$export_data"
        
        # Display protocol distribution table
        if echo "$export_result" | jq -e '.protocol_counts_str' > /dev/null 2>&1; then
            protocol_counts_str=$(echo "$export_result" | jq -r '.protocol_counts_str')
            if [[ -n "$protocol_counts_str" ]]; then
                protocol_data="Protocol,Count
$protocol_counts_str"
                print_fancy_table "PROTOCOL DISTRIBUTION" "$protocol_data"
            fi
        fi
        
        # Display PAM details in table
        pam_data="Metric,Value
Shared Folders,${shared_folders_count}
Machine Records,${machine_records_count}"
        
        print_fancy_table "PAM FORMAT DETAILS" "$pam_data"

        # Generate summary with PAM information - using shell variables directly
        generate_export_summary "$connections_file" "$pam_format_file" "$folders_file" "$records_file"
        
        # Perform automatic import using Keeper Commander - using shell variables directly
        log_info "Starting automatic import using Keeper Commander..."
        
        # Import folders first
        log_info "Importing shared folders..."
        if [[ -f "$folders_file" ]]; then
            if keeper import --format=json "$folders_file"; then
                log_success "Folders imported successfully."
                
                # Then import records
                if [[ -f "$records_file" ]]; then
                    log_info "Importing records..."
                    if keeper import --format=json "$records_file"; then
                        log_success "Records imported successfully."
                        log_success "Import process completed. Please verify records in your Keeper vault."
                    else
                        log_error "Failed to import records. Please check Keeper Commander configuration."
                        log_info "You can try manual import with: keeper import --format=json \"$records_file\""
                    fi
                else
                    log_error "Records file not found: $records_file"
                fi
            else
                log_error "Failed to import folders. Please check Keeper Commander configuration."
                log_info "You can try manual import with: keeper import --format=json \"$folders_file\""
            fi
        else
            log_error "Folders file not found: $folders_file"
        fi
    fi
}

# Helper function to generate a readable summary
generate_export_summary() {
    local connections_file=$1
    local pam_format_file=$2
    local folders_file=$3
    local records_file=$4
    local summary_file="${EXPORT_DIR}/${FILENAME_PREFIX}_summary_$(date +%Y%m%d_%H%M%S).txt"

    log_info "Generating export summary to: $summary_file"

    # Get base filenames for display in summary
    local folders_basename=$(basename "$folders_file")
    local records_basename=$(basename "$records_file")

    cat > "$summary_file" << EOF
# Keeper PAM Export Summary
Generated: $(date +"%Y-%m-%d %H:%M:%S")
Root Folder: $KEEPER_ROOT_FOLDER

## Export Statistics
- Total Connections: $(jq '.connections | length' "$connections_file")
- Total Folders: $(jq '.groups | length' "$connections_file")
- Total PAM Records: $(jq '.records | length' "$pam_format_file")

## PAM Format Details
- Shared Folders: $(jq '.shared_folders | length' "$pam_format_file")
- Machine Records: $(jq '.records | length' "$pam_format_file")

## Credential Sanitization
- Mode: $SANITIZE_MODE

$(if [ "$SANITIZE_MODE" = "none" ]; then
    echo "- WARNING: Credentials are exported with actual values"
elif [ "$SANITIZE_MODE" = "placeholder" ]; then
    echo "- Credentials replaced with placeholders ([PASSWORD], [CREDENTIAL], etc.)"
else
    echo "- Credentials have been removed from export"
fi)

## Import Information
The script has attempted to automatically import your data to Keeper PAM.
If automatic import failed, you can manually import using these commands:

1. Import the shared folders first:
   - keeper import --format=json $folders_basename

2. Then import the records:
   - keeper import --format=json $records_basename

For detailed instructions, please refer to:
https://docs.keeper.io/en/keeperpam/privileged-access-manager/references/importing-pam-records
EOF

    if [[ -f "$summary_file" ]]; then
        log_success "Export summary generated successfully"

        if [[ "$QUIET" != "true" ]]; then
            echo ""
            cat "$summary_file"
            echo ""
        fi
    else
        log_warn "Failed to generate export summary"
    fi
}

# ================================================================================
# SECTION 15: MAIN EXECUTION
# --------------------------------------------------------------------------------
# Purpose: Orchestrates the complete export process
# --------------------------------------------------------------------------------
main() {
    log_info "Starting Keeper PAM Export Tool v$VERSION"

    # Parse command-line arguments
    parse_arguments "$@"

    # Check dependencies
    check_dependencies

    # Setup export directory
    setup_export_directory

    # Inspect Docker Compose file
    inspect_compose_file

    # Extract database credentials from compose file
    extract_db_credentials

    # Test database connection
    verify_db_connection

    # Export data from guacamole database
        export_connection_data

        log_success "Export process completed successfully!"
        log_info "Files are ready for import into Keeper PAM using Keeper Commander CLI"
        log_info "See the summary file for detailed import instructions"
    }

    # Run the main function with all arguments
    main "$@"
    # ================================================================================
