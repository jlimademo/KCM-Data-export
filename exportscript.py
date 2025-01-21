import mysql.connector
import yaml
import json

# Path to the docker-compose.yml file
docker_compose_file = '/etc/kcm-setup/docker-compose.yml'

def get_db_config_from_compose():
    with open(docker_compose_file, 'r') as file:
        compose_data = yaml.safe_load(file)
        db_service = compose_data['services']['db']
        environment = db_service['environment']

        db_name = environment.get('GUACAMOLE_DATABASE', 'guacamole_db')
        db_user = environment.get('GUACAMOLE_USERNAME', 'guacamole_user')
        db_password = environment.get('GUACAMOLE_PASSWORD', 'password')

        return {
            'host': 'localhost',
            'user': db_user,
            'password': db_password,
            'database': db_name,
        }

# SQL query to fetch all relevant data from the database
query = """
SELECT
    c.connection_id,
    c.connection_name AS name,
    c.protocol,
    cp.parameter_name,
    cp.parameter_value,
    ca.attribute_name,
    ca.attribute_value,
    g.connection_group_id,
    g.connection_group_name AS group_name,
    e.name AS entity_name,
    e.type AS entity_type
FROM
    guacamole_connection c
LEFT JOIN
    guacamole_connection_parameter cp ON c.connection_id = cp.connection_id
LEFT JOIN
    guacamole_connection_attribute ca ON c.connection_id = ca.connection_id
LEFT JOIN
    guacamole_connection_group g ON c.parent_id = g.connection_group_id
LEFT JOIN
    guacamole_connection_permission p ON c.connection_id = p.connection_id
LEFT JOIN
    guacamole_entity e ON p.entity_id = e.entity_id
ORDER BY
    c.connection_id;
"""

def fetch_dropdown_options(cursor):
    """
    Fetch dropdown options for ENUM fields and linked tables.
    """
    dropdown_options = {}

    # Fetch ENUM fields
    cursor.execute("""
    SELECT COLUMN_NAME, COLUMN_TYPE
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME IN ('guacamole_connection', 'guacamole_connection_parameter', 'guacamole_connection_attribute')
      AND DATA_TYPE = 'enum';
    """)
    enum_fields = cursor.fetchall()

    for field in enum_fields:
        column_name = field['COLUMN_NAME']
        column_type = field['COLUMN_TYPE']
        # Parse ENUM values
        options = column_type.strip("enum()").replace("'", "").split(",")
        dropdown_options[column_name] = options

    # Add logic for linked tables if applicable
    # Example:
    # cursor.execute("SELECT value FROM lookup_table WHERE field_name = 'some_field'")
    # results = cursor.fetchall()
    # dropdown_options['some_field'] = [row['value'] for row in results]

    return dropdown_options

def export_to_json(db_config):
    try:
        conn = mysql.connector.connect(**db_config)
        print("Database connection successful.")
        cursor = conn.cursor(dictionary=True)

        # Fetch dropdown options
        print("Fetching dropdown options...")
        dropdown_options = fetch_dropdown_options(cursor)
        print(f"Dropdown options: {dropdown_options}")

        # Fetch connection data
        cursor.execute(query)
        rows = cursor.fetchall()
        print(f"Number of rows fetched: {len(rows)}")

        if not rows:
            print("No data found in the database.")
            return

        groups = {}
        for row in rows:
            group_id = row['connection_group_id']
            conn_id = row['connection_id']

            if group_id not in groups:
                groups[group_id] = {
                    'group_name': row['group_name'] or "ROOT",
                    'connections': []
                }

            connection = next(
                (c for c in groups[group_id]['connections'] if c['connection_id'] == conn_id),
                None
            )
            if not connection:
                connection = {
                    'connection_id': conn_id,
                    'name': row['name'] or f"Unnamed Connection {conn_id}",
                    'protocol': row['protocol'] or "ssh",
                    'parameters': {},
                    'attributes': {},
                    'users': [],
                    'groups': []
                }
                groups[group_id]['connections'].append(connection)

            # Add parameters
            if row['parameter_name']:
                connection['parameters'][row['parameter_name']] = row['parameter_value']

            # Add attributes
            if row['attribute_name']:
                connection['attributes'][row['attribute_name']] = row['attribute_value']

            # Add users
            if row['entity_type'] == 'USER' and row['entity_name'] not in connection['users']:
                connection['users'].append(row['entity_name'])

            # Add groups
            if row['entity_type'] == 'USER_GROUP' and row['entity_name'] not in connection['groups']:
                connection['groups'].append(row['entity_name'])

        export_data = {
            "connections": list(groups.values()),
            "dropdown_options": dropdown_options  # Include dropdown options
        }

        with open('export.json', 'w') as json_file:
            json.dump(export_data, json_file, indent=4)

        print("Export successful! Data written to export.json")

    except mysql.connector.Error as err:
        print(f"Database error: {err}")
    except Exception as e:
        print(f"Unexpected error: {e}")
    finally:
        if 'cursor' in locals() and cursor:
            cursor.close()
        if 'conn' in locals() and conn:
            conn.close()

if __name__ == '__main__':
    db_config = get_db_config_from_compose()
    port_input = input("Enter the database port (default 3306): ")
    db_config['port'] = int(port_input) if port_input.strip() else 3306

    print("Running export...")
    export_to_json(db_config)
