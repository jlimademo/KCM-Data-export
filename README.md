################################################################################
README FILE
################################################################################
================================== FILE DESCRIPTIONS ==================================
exportscript.py
This is the primary Python script used to extract data from the database and generate
a structured JSON export for all protocols and their corresponding fields.
Features:
Fetch Connections:
Extracts details of all connections, including parameters, attributes, and associated
users/groups.
Dropdown Options:
Identifies and exports dropdown menu options for fields defined as ENUM in the
database schema.
Dynamic Schema Handling:
Dynamically identifies fields and includes any missing ones with default values.
Output JSON Structure:
Creates a hierarchical JSON with groups, connections, and dropdown options.
How It Works:
Database Configuration:
Extracts database credentials from the docker-compose.yml file.
Schema Analysis:
Queries INFORMATION_SCHEMA.COLUMNS to fetch schema details like data types,
constraints, and ENUM options.
Connection Extraction:
Fetches all connection details, including protocol-specific parameters and attributes.
JSON Export:
Writes the structured data into export.json for further use or import.
========================================================================================
export_all_protocols.json
This JSON file is the output of the exportscript.py script. It contains the raw data of connections, including all protocols, fields, parameters, attributes, and associated users/groups.
Key Features:
Group Structure:
Groups connections by their associated group_name.
Parameters and Attributes:
Includes all available parameters and attributes for each connection.
Users and Groups:
Lists users and groups associated with each connection.
Dropdown Options:
Provides ENUM dropdown values (e.g., proxy_encryption_method).
========================================================================================
modified_import_test.json
This file is a modified version of the exported JSON, renamed for clarity. It is intended for import testing with modified group and connection names to verify successful import.
Modifications:
Group Name:
Changed the group name to "Test Group - Modified".
Connection Names:
Updated connection names to indicate their protocol and test purpose (e.g.,
"RDP Fields - Test").
Structure:
Retains the original structure but ensures changes in names are evident upon successful
import.
========================================================================================
================================= USAGE INSTRUCTIONS ===================================
Run the Script:
Execute exportscript.py to generate a new export.json file.
Command:
python3 exportscript.py
Verify the Output:
Inspect the export.json file to ensure all connections, parameters, attributes, and
dropdown options are included.
Test Import:
Use the modified_import_test.json file for import
testing. Confirm that the changes in names (group and connection) appear correctly
in the imported system.
Feedback and Adjustments:
If any fields are missing or additional functionality is required, modify the script
and rerun.
========================================================================================
======================================= CONTACT ========================================
For any issues or further assistance, reach out to the script maintainer.
################################################################################
