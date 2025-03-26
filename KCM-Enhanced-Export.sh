#!/bin/bash

# ========================================
# Guacamole Export Tool
# ----------------------------------------
# Description:
#   This script exports Apache Guacamole connection data into standard JSON/CSV
#   and Keeper PAM-ready formats. It supports interactive and CLI modes, safely
#   patches the docker-compose file to expose database ports, and optionally
#   imports records directly into Keeper Vault using Keeper Commander.
#
# Usage Examples:
#   ./guac-export.sh                # Interactive mode
#   ./guac-export.sh --both         # CLI export (both formats)
#   ./guac-export.sh --keeper --push-to-keeper
#
# Flags:
#   --keeper           Export Keeper PAM-ready JSON
#   --standard         Export full Guacamole data
#   --both             Export both formats
#   --output-dir DIR   Custom export directory
#   --filename-prefix  Prefix for output files
#   --push-to-keeper   Push Keeper records using Keeper Commander
#   --compose-file     Path to docker-compose.yml (default: /etc/kcm-setup/docker-compose.yml)
#   --db-host          Database host (default: localhost)
#   --db-port          Database port (default: 3306)
# ========================================

set -e

# ---------- Logging Functions ---------- #
log_info() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_success() { echo -e "\033[1;34m[SUCCESS]\033[0m $1"; }

# ---------- Default Configs ---------- #
EXPORT_DIR="."  # Current directory where script is run
FILENAME_PREFIX="guac"
DO_KEEPER=false
DO_STANDARD=false
PUSH_KEEPER=false
COMPOSE_FILE="/etc/kcm-setup/docker-compose.yml"
DB_HOST="localhost"
DB_PORT=3306
DB_USER=""
DB_PASS=""
DB_NAME=""
SANITIZE_MODE="placeholder"  # Options: none, placeholder, remove

# ---------- Cleanup Function ---------- #
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script terminated with errors. Exit code: $exit_code"
    fi
    exit $exit_code
}

trap cleanup EXIT

# ---------- Parse CLI Arguments ---------- #
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        log_info "No CLI flags provided. Entering interactive mode."
        echo "Choose export mode:"
        echo "1) Keeper PAM Export"
        echo "2) Standard Guacamole Export"
        echo "3) Both"
        read -p "Enter choice [1-3]: " mode
        case $mode in
            1) DO_KEEPER=true;;
            2) DO_STANDARD=true;;
            3) DO_KEEPER=true; DO_STANDARD=true;;
            *) log_error "Invalid selection."; exit 1;;
        esac
        
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
    else
        while [[ $# -gt 0 ]]; do
            case $1 in
                --keeper) DO_KEEPER=true ; shift ;;
                --standard) DO_STANDARD=true ; shift ;;
                --both) DO_KEEPER=true ; DO_STANDARD=true ; shift ;;
                --output-dir) EXPORT_DIR="$2" ; shift 2 ;;
                --filename-prefix) FILENAME_PREFIX="$2" ; shift 2 ;;
                --push-to-keeper) PUSH_KEEPER=true ; shift ;;
                --compose-file) COMPOSE_FILE="$2" ; shift 2 ;;
                --db-host) DB_HOST="$2" ; shift 2 ;;
                --db-port) DB_PORT="$2" ; shift 2 ;;
                --sanitize)
                    case "$2" in
                        none|placeholder|remove) SANITIZE_MODE="$2" ; shift 2 ;;
                        *) log_error "Invalid sanitize mode: $2. Use none, placeholder, or remove." ; exit 1 ;;
                    esac
                    ;;
                --help) 
                    echo "Usage: $0 [options]"
                    echo "Options:"
                    echo "  --keeper             Export Keeper PAM-ready JSON"
                    echo "  --standard           Export full Guacamole data"
                    echo "  --both               Export both formats"
                    echo "  --output-dir DIR     Custom export directory"
                    echo "  --filename-prefix    Prefix for output files"
                    echo "  --push-to-keeper     Push Keeper records using Keeper Commander"
                    echo "  --compose-file       Path to docker-compose.yml"
                    echo "  --db-host            Database host (default: localhost)"
                    echo "  --db-port            Database port (default: 3306)"
                    echo "  --sanitize MODE      Sanitize credentials: none, placeholder, remove"
                    echo "  --help               Show this help message"
                    exit 0
                    ;;
                *) log_error "Unknown argument: $1. Use --help for usage information." ; exit 1 ;;
            esac
        done
    fi

    # Validate required parameters
    if [[ "$DO_KEEPER" == false && "$DO_STANDARD" == false ]]; then
        log_error "No export mode selected. Use --keeper, --standard, or --both."
        exit 1
    fi
    
    # Set default sanitization mode if not specified
    if [[ -z "$SANITIZE_MODE" ]]; then
        SANITIZE_MODE="placeholder"
        log_info "Using default credential sanitization mode: placeholder"
    else
        log_info "Credential sanitization mode: $SANITIZE_MODE"
    fi
}

# ---------- Check Dependencies ---------- #
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
        log_warn "mysqladmin command not found. MySQL connectivity checks will be skipped."
        log_warn "Install with: apt-get install mysql-client or yum install mysql"
    fi
    
    if [[ "$PUSH_KEEPER" == true ]] && ! command -v keeper &>/dev/null; then
        log_error "Keeper Commander not found but --push-to-keeper was specified."
        log_error "Install with: pip install keeper-commander"
        exit 1
    elif ! command -v keeper &>/dev/null; then
        log_warn "Keeper Commander not found. Install with: pip install keeper-commander"
    fi
    
    log_success "All required dependencies are available."
}

# ---------- Setup Export Directory ---------- #
setup_export_directory() {
    # If default current directory, no need to create anything
    if [[ "$EXPORT_DIR" != "." && ! -d "$EXPORT_DIR" ]]; then
        log_info "Creating export directory: $EXPORT_DIR"
        mkdir -p "$EXPORT_DIR" || {
            log_error "Failed to create export directory"
            exit 1
        }
    fi
}

# ---------- Compose File Port Inspection ---------- #
inspect_compose_file() {
    log_info "Inspecting docker-compose.yml for database service and port exposure..."

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Compose file not found at $COMPOSE_FILE"
        exit 1
    fi

    db_port_info=$(python3 - <<EOF
import yaml
try:
    with open("$COMPOSE_FILE", "r") as f:
        data = yaml.safe_load(f)
        if 'services' not in data or 'db' not in data['services']:
            print("no_db_service")
            exit(0)
        ports = data['services']['db'].get('ports', [])
        for port in ports:
            port_str = str(port)
            if ':3306' in port_str:
                host_port = port_str.split(':')[0]
                print(f"found:{host_port}")
                exit(0)
        print("no")
except Exception as e:
    print(f"error: {str(e)}")
EOF
    )

    if [[ "$db_port_info" == "no_db_service" ]]; then
        log_error "No database service found in docker-compose.yml"
        exit 1
    elif [[ "$db_port_info" == "no" ]]; then
        log_warn "Database port for MySQL is NOT exposed in docker-compose.yml."
        read -p "Would you like to expose it now (this will patch the compose file)? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            patch_compose_file
        else
            log_warn "Continuing without exposing database port. Export may fail if DB is unreachable."
        fi
    elif [[ "$db_port_info" =~ ^error ]]; then
        log_error "Error occurred while parsing docker-compose.yml: ${db_port_info#error: }"
        exit 1
    elif [[ "$db_port_info" =~ ^found: ]]; then
        detected_port="${db_port_info#found:}"
        log_info "Database port $detected_port is exposed and will be used for connection."
        DB_PORT="$detected_port"
    else
        log_info "Database port is already exposed."
    fi
}

# ---------- Patch Compose File ---------- #
patch_compose_file() {
    backup_file="${COMPOSE_FILE}.bak.$(date +%s)"
    cp "$COMPOSE_FILE" "$backup_file"
    log_info "Backup of original compose file saved as $backup_file"

    read -p "Enter the host port to expose for MySQL (default: $DB_PORT): " custom_port
    [[ -z "$custom_port" ]] && custom_port=$DB_PORT

    # Patch the file using Python
    python3 - <<EOF
import yaml
f = "$COMPOSE_FILE"
bak = "$backup_file"
port = "$custom_port"
try:
    with open(f) as file:
        d = yaml.safe_load(file)
        if 'ports' not in d['services']['db']:
            d['services']['db']['ports'] = []
        d['services']['db']['ports'].append(f"{port}:$DB_PORT")
        with open(f, "w") as out:
            yaml.dump(d, out, default_flow_style=False)
    print("success")
except Exception as e:
    print(f"error: {str(e)}")
EOF

    log_info "Compose file patched to expose ${custom_port} -> ${DB_PORT}"
    
    # Update the DB_PORT to the custom port for subsequent operations
    DB_PORT=$custom_port
    
    read -p "Apply changes and restart containers with 'docker-compose up -d'? [y/N]: " restart_confirm
    if [[ "$restart_confirm" =~ ^[Yy]$ ]]; then
        restart_containers
    else
        log_warn "User chose not to restart containers. Please do so manually."
    fi
}

# ---------- Restart Containers ---------- #
restart_containers() {
    log_info "Restarting containers with docker-compose..."
    docker-compose -f "$COMPOSE_FILE" up -d
    log_info "Waiting 10 seconds for containers to restart..."
    sleep 10
    check_mysql_connectivity
}

# ---------- Check MySQL Connectivity ---------- #
check_mysql_connectivity() {
    log_info "Checking MySQL connectivity..."
    
    # Only check if we have the credentials
    if [[ -z "$DB_USER" || -z "$DB_PASS" ]]; then
        log_warn "Database credentials not available yet. Skipping connectivity check."
        return
    fi
    
    if command -v mysqladmin &> /dev/null; then
        if mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" --silent; then
            log_success "MySQL is reachable and responding."
        else
            log_error "MySQL is not responding on port $DB_PORT. Please check the container logs."
            exit 1
        fi
    else
        log_warn "mysqladmin command not found. Skipping connectivity check."
    fi
}

# ---------- Extract DB Credentials ---------- #
extract_db_credentials() {
    log_info "Extracting DB credentials from docker-compose.yml..."
    credentials=$(python3 - <<EOF
import yaml, json
try:
    with open("$COMPOSE_FILE") as file:
        c = yaml.safe_load(file)
        env = c['services']['db']['environment']
        out = {
            "user": env.get('GUACAMOLE_USERNAME', 'guac_user'),
            "password": env.get('GUACAMOLE_PASSWORD', 'guac_pass'),
            "database": env.get('GUACAMOLE_DATABASE', 'guacamole_db')
        }
        print(json.dumps(out))
except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF
    )
    
    error=$(echo "$credentials" | jq -r '.error // empty')
    if [[ -n "$error" ]]; then
        log_error "Failed to extract credentials: $error"
        exit 1
    fi
    
    DB_USER=$(echo "$credentials" | jq -r '.user')
    DB_PASS=$(echo "$credentials" | jq -r '.password')
    DB_NAME=$(echo "$credentials" | jq -r '.database')
    
    if [[ -z "$DB_USER" || -z "$DB_PASS" || -z "$DB_NAME" ]]; then
        log_error "Unable to extract complete database credentials"
        exit 1
    fi
    
    log_info "Credentials loaded successfully."
}

# ---------- Export Standard Guacamole Data ---------- #
export_standard_data() {
    log_info "Exporting standard Guacamole data..."
    out_json="$EXPORT_DIR/${FILENAME_PREFIX}_full_export.json"
    out_csv="$EXPORT_DIR/${FILENAME_PREFIX}_full_export.csv"

    python3 - <<EOF
import mysql.connector, json, csv
from datetime import datetime
from pathlib import Path
import sys

def clean(data):
    return [
        {k: v for k, v in row.items() if v not in [None, ""]}
        for row in data
    ]

def execute_query(conn, query):
    """Execute a query and properly handle results"""
    cursor = conn.cursor(dictionary=True)
    cursor.execute(query)
    results = cursor.fetchall()
    cursor.close()
    return results

try:
    conn = mysql.connector.connect(
        host='$DB_HOST', 
        port=$DB_PORT,
        user='$DB_USER', 
        password='$DB_PASS', 
        database='$DB_NAME',
        consume_results=True  # Auto-consume any unread results
    )
    data = {}

    # Get essential connection data
    try:
        data['connections'] = clean(execute_query(conn, 
            "SELECT connection_id, connection_name, protocol, parent_id, max_connections, max_connections_per_user FROM guacamole_connection"))
    except Exception as e:
        print(f"warning: Error retrieving connections: {str(e)}")
        data['connections'] = []
    
    # Get connection parameters
    try:
        data['connection_parameters'] = clean(execute_query(conn,
            "SELECT connection_id, parameter_name, parameter_value FROM guacamole_connection_parameter"))
    except Exception as e:
        print(f"warning: Error retrieving connection parameters: {str(e)}")
        data['connection_parameters'] = []
    
    # Get connection groups
    try:
        data['groups'] = clean(execute_query(conn,
            "SELECT connection_group_id, parent_id, connection_group_name, type FROM guacamole_connection_group"))
    except Exception as e:
        print(f"warning: Error retrieving connection groups: {str(e)}")
        data['groups'] = []
    
    # Get user data - check for schema differences
    try:
        # First check the table structure
        columns = [column[0] for column in execute_query(conn, "DESCRIBE guacamole_user")]
        
        # Build a dynamic query based on available columns
        user_columns = []
        if 'user_id' in columns:
            user_columns.append('user_id')
        if 'entity_id' in columns:  # Newer Guacamole might use entity_id instead
            user_columns.append('entity_id')
        if 'username' in columns:
            user_columns.append('username')
        if 'disabled' in columns:
            user_columns.append('disabled')
        
        if user_columns:
            query = f"SELECT {', '.join(user_columns)} FROM guacamole_user"
            data['users'] = clean(execute_query(conn, query))
        else:
            data['users'] = []
            print("warning: Could not determine user columns")
    except Exception as e:
        print(f"warning: Error retrieving user data: {str(e)}")
        data['users'] = []
    
    # Permissions might be in different tables depending on version
    permissions_data = []
    
    # Try various permission tables - each in its own try block
    for table in ['guacamole_system_permission', 'guacamole_user_permission', 'guacamole_connection_permission']:
        try:
            # Check if table exists
            execute_query(conn, f"SHOW TABLES LIKE '{table}'")
            
            # Get appropriate columns based on the table
            if table == 'guacamole_connection_permission':
                permissions_data.extend(clean(execute_query(conn, 
                    f"SELECT entity_id, user_id, connection_id, permission FROM {table}")))
            else:
                permissions_data.extend(clean(execute_query(conn, 
                    f"SELECT entity_id, affected_user_id, connection_id, connection_group_id, permission FROM {table}")))
        except Exception as e:
            # Just skip tables that don't exist or have different schema
            continue
    
    data['permissions'] = permissions_data

    # Export to JSON with nice formatting
    Path("$out_json").write_text(json.dumps(data, indent=4, default=str))

    # Export to CSV (simplified format)
    with open("$out_csv", "w", newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Category", "Fields"])
        for k, v in data.items():
            writer.writerow([k, json.dumps(v)])

    conn.close()
    print("success")
except Exception as e:
    print(f"error: {str(e)}")
    sys.exit(1)  # Make sure to exit with error code
EOF

    log_success "Standard export written to $out_json and $out_csv"
}

# ---------- Export Keeper PAM Records ---------- #
export_keeper_data() {
    log_info "Exporting Keeper PAM records..."
    out_json="$EXPORT_DIR/${FILENAME_PREFIX}_keeper_import.json"
    out_csv="$EXPORT_DIR/${FILENAME_PREFIX}_keeper_import.csv"

    python3 - <<EOF
import mysql.connector, json, csv
from pathlib import Path

def ftype(t, v, sanitize_mode): 
    if t == "password" and sanitize_mode != "none":
        if sanitize_mode == "remove":
            return None
        else:  # placeholder
            return {"type": t, "value": "\${KEEPER_SERVER_PASSWORD}"}
    elif t == "login" and sanitize_mode != "none":
        if sanitize_mode == "remove":
            return None
        else:  # placeholder
            return {"type": t, "value": "\${KEEPER_SERVER_USERNAME}"}
    else:
        return {"type": t, "value": v} if v else None

try:
    conn = mysql.connector.connect(
        host='$DB_HOST', 
        port=$DB_PORT,
        user='$DB_USER', 
        password='$DB_PASS', 
        database='$DB_NAME',
        consume_results=True
    )
    
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT connection_id, connection_name, protocol FROM guacamole_connection")
    conns = cursor.fetchall()
    cursor.close()
    
    records = []

    for c in conns:
        cid = c['connection_id']
        
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT parameter_name, parameter_value FROM guacamole_connection_parameter WHERE connection_id = %s", (cid,))
        params = {r['parameter_name']: r['parameter_value'] for r in cursor.fetchall()}
        cursor.close()
        
        fields = list(filter(None, [
            ftype("host", params.get("hostname"), "$SANITIZE_MODE"),
            ftype("port", params.get("port"), "$SANITIZE_MODE"),
            ftype("login", params.get("username"), "$SANITIZE_MODE"),
            ftype("password", params.get("password"), "$SANITIZE_MODE"),
            ftype("protocol", c.get("protocol"), "$SANITIZE_MODE")
        ]))
        
        records.append({
            "type": "pam",
            "title": c["connection_name"],
            "notes": "Imported from Guacamole",
            "fields": fields
        })

    Path("$out_json").write_text(json.dumps(records, indent=4))

    with open("$out_csv", "w", newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["title", "type", "notes", "fields"])
        for r in records:
            writer.writerow([r['title'], r['type'], r['notes'], json.dumps(r['fields'])])

    conn.close()
    print("success")
except Exception as e:
    print(f"error: {str(e)}")
    sys.exit(1)
EOF

    log_success "Keeper export written to $out_json and $out_csv"

    if [[ "$PUSH_KEEPER" == true ]]; then
        push_to_keeper "$out_json"
    fi
}

# ---------- Push to Keeper ---------- #
push_to_keeper() {
    local json_file=$1
    log_info "Pushing records to Keeper Commander..."
    
    if ! command -v keeper &> /dev/null; then
        log_error "Keeper Commander not found. Please install it first."
        return 1
    fi
    
    if keeper record import "$json_file"; then
        log_success "Records successfully imported into Keeper"
    else
        log_error "Failed to import records into Keeper"
        return 1
    fi
}

# ---------- Main Function ---------- #
main() {
    log_info "Starting Guacamole Export Tool"
    
    parse_arguments "$@"
    check_dependencies
    setup_export_directory
    
    # First extract credentials to enable connectivity checks
    extract_db_credentials
    inspect_compose_file
    
    # Check connectivity after credentials are extracted
    check_mysql_connectivity
    
    # Perform exports based on user selections
    if [[ "$DO_STANDARD" == true ]]; then
        export_standard_data
    fi

    if [[ "$DO_KEEPER" == true ]]; then
        export_keeper_data
    fi

    log_success "All operations completed successfully."
}

# Call main function with all arguments
main "$@"
