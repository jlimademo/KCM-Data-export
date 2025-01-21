# KCM Data Export Scripts

This repository contains three scripts designed for exporting data from the KCM system. Each script offers different functionalities and approaches for extracting and exporting database records efficiently.

---

## Script Descriptions

### 1. `KCM-Enhanced-Export.sh`
The **Enhanced Export script** is a combination of Bash and Python, integrating the strengths of both scripts to provide a seamless and robust data export solution.

**Key Features:**
- Extracts database credentials using Python for reliable YAML parsing.
- Prompts the user to select data categories (history, users, groups, connections).
- Ensures proper error handling through structured logging.
- Exports data into JSON format for easy analysis and visualization.
- Dynamically handles paths and user inputs.

---

### 2. `KCM-data-exportscript.py`
This standalone **Python script** focuses on exporting data directly from the database by reading credentials from the `docker-compose.yml` file.

**Key Features:**
- Uses Python's `yaml` module to accurately parse the `docker-compose.yml` file for credentials.
- Connects to the database and retrieves all connection-related data.
- Outputs data in JSON format.
- Structured exception handling for errors.
- Fully automated process without user interaction.

---

### 3. `KCM-data-exportscript.sh`
This **Bash script** provides an interactive way for users to export specific data categories by manually parsing credentials and invoking the export process.

**Key Features:**
- Prompts the user for database port and export options.
- Parses credentials from `docker-compose.yml` using Bash utilities (`grep`, `cut`).
- Exports selected data categories (history, users, groups, connections).
- Basic error handling and logging via Bash functions.

---

## Feature Comparison

| Feature                    | KCM-Enhanced-Export.sh | KCM-data-exportscript.py | KCM-data-exportscript.sh |
|----------------------------|-----------------------|--------------------------|--------------------------|
| **User Interaction**        | Yes (Menu-driven)      | No                        | Yes (Menu-driven)         |
| **Credential Extraction**   | Python (YAML parsing)  | Python (YAML parsing)     | Bash (`grep`, `cut`)      |
| **Data Export Method**      | Python (MySQL queries) | Python (MySQL queries)    | Python (MySQL queries)    |
| **Export Format**           | JSON                   | JSON                       | JSON                       |
| **Error Handling**          | Bash & Python (Logs)   | Python (Exception Handling) | Bash (Basic Logging)     |
| **Automation Level**        | Semi-automated         | Fully automated            | Semi-automated            |
| **Dependencies**            | Bash, Python, jq       | Python (`mysql.connector`) | Bash, Python              |
| **Best Use Case**           | Interactive & Reliable | Automated & Scheduled      | Quick manual exports      |

---

## How to Use

### Running the Enhanced Export Script:
```bash
chmod +x KCM-Enhanced-Export.sh
./KCM-Enhanced-Export.sh
```
Follow the on-screen prompts to select export options and provide necessary inputs.

---

### Running the Python Script:
```bash
python3 KCM-data-exportscript.py
```
This script will automatically fetch credentials and export all data.

---

### Running the Bash Script:
```bash
chmod +x KCM-data-exportscript.sh
./KCM-data-exportscript.sh
```
User-friendly prompts will guide the export process.

---

## Dependencies

Ensure the following dependencies are installed before running any scripts:

- **For Bash scripts:** `bash`, `jq`, `python3`
- **For Python scripts:** `pip install mysql-connector-python pyyaml`

---

## Conclusion

- Use **KCM-Enhanced-Export.sh** for the best balance of automation and user control.
- Use **KCM-data-exportscript.py** for fully automated, non-interactive exports.
- Use **KCM-data-exportscript.sh** for quick manual exports with minimal dependencies.

---

Joao Lima
*Version: 1.0*  
*Date: 2025-01-21*
