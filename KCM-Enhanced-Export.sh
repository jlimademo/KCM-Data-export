#!/bin/bash

# Function to log information messages
log_info() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

# Function to log error messages
log_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
}

# Function to prompt user for database port
set_database_port() {
    read -p "Enter the database port (default is 3306): " user_port
    while ! [[ "$user_port" =~ ^[0-9]+$ ]] && [[ -n "$user_port" ]]; do
        log_error "Invalid input. Please enter a numeric value."
        read -p "Enter the database port (default is 3306): " user_port
    done
    db_port=${user_port:-3306}
    log_info "Using database port: $db_port"
}

# Function to prompt user for data to export
menu_selection() {
    log_info "Choose what data to export:"
    echo "1) Connection History"
    echo "2) Users"
    echo "3) Groups"
    echo "4) Connections"
    echo "5) Export All"
    read -p "Enter your choice (1-5): " choice

    case $choice in
        1) export_category="history";;
        2) export_category="users";;
        3) export_category="groups";;
        4) export_category="connections";;
        5) export_category="all";;
        *) log_error "Invalid choice. Please enter a number between 1-5."; exit 1;;
    esac
    log_info "Selected export category: $export_category"
}

# Function to extract database credentials using Python
extract_db_credentials() {
    log_info "Extracting database credentials from docker-compose.yml..."
    credentials=$(python3 - <<EOF
import yaml, json

docker_compose_file = '/etc/kcm-setup/docker-compose.yml'

try:
    with open(docker_compose_file, 'r') as file:
        compose_data = yaml.safe_load(file)
        db_service = compose_data['services']['db']
        environment = db_service['environment']
        
        db_name = environment.get('GUACAMOLE_DATABASE', 'guacamole_db')
        db_user = environment.get('GUACAMOLE_USERNAME', 'guacamole_user')
        db_password = environment.get('GUACAMOLE_PASSWORD', 'password')
        
        print(json.dumps({"user": db_user, "password": db_password, "database": db_name}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
    exit(1)
EOF
)

    error=$(echo "$credentials" | jq -r '.error // empty')
    if [[ -n "$error" ]]; then
        log_error "Failed to extract credentials: $error"
        exit 1
    fi

    db_user=$(echo "$credentials" | jq -r '.user')
    db_password=$(echo "$credentials" | jq -r '.password')
    database=$(echo "$credentials" | jq -r '.database')

    log_info "Database credentials extracted successfully."
}

# Function to export data using Python
export_data() {
    export_file="${PWD}/export_data.json"

    if ! touch "$export_file" 2>/dev/null; then
        log_error "Cannot write to export file location: $export_file"
        exit 1
    fi

    log_info "Exporting data to $export_file..."

    python3 - <<EOF
import mysql.connector
import json
import sys
from datetime import datetime

db_config = {
    "host": "localhost",
    "port": ${db_port},
    "user": "${db_user}",
    "password": "${db_password}",
    "database": "${database}"
}

def serialize(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()
    return str(obj)

try:
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor(dictionary=True)

    data = {}

    if "${export_category}" in ["history", "all"]:
        cursor.execute("SELECT * FROM guacamole_connection_history")
        data["connection_history"] = cursor.fetchall()

    if "${export_category}" in ["users", "all"]:
        cursor.execute("SELECT * FROM guacamole_user")
        data["users"] = cursor.fetchall()

    if "${export_category}" in ["groups", "all"]:
        cursor.execute("SELECT * FROM guacamole_connection_group")
        data["groups"] = cursor.fetchall()

    if "${export_category}" in ["connections", "all"]:
        cursor.execute("SELECT * FROM guacamole_connection")
        data["connections"] = cursor.fetchall()

    with open("${export_file}", "w") as file:
        json.dump(data, file, indent=4, default=serialize)

    print("[INFO] Data export completed successfully!")

except mysql.connector.Error as err:
    print(f"[ERROR] Database error: {err}", file=sys.stderr)
    sys.exit(1)

except Exception as e:
    print(f"[ERROR] An unexpected error occurred: {e}", file=sys.stderr)
    sys.exit(1)

finally:
    if 'cursor' in locals() and cursor:
        cursor.close()
    if 'conn' in locals() and conn.is_connected():
        conn.close()
EOF
}

# Main script execution
log_info "Starting export script..."
set_database_port
extract_db_credentials
menu_selection
export_data
log_info "Script execution completed successfully."
