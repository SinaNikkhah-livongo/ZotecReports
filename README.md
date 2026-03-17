# ZotecReports

A Python project to connect to MySQL database, execute queries from SQL files with dynamic date placeholders, export results to CSV or XML files with specific formatting, encrypt the files using GPG, and optionally upload to SFTP.

## Setup

1. Install Python 3.8 or higher if not already installed.

2. Clone or download this project.

3. Create a virtual environment:
   ```
   python -m venv .venv
   ```

4. Activate the virtual environment:
   - On macOS/Linux: `source .venv/bin/activate`
   - On Windows: `.venv\Scripts\activate`

5. Install dependencies:
   ```
   pip install -r requirements.txt
   ```

6. Install GPG if not already installed (e.g., `brew install gnupg` on macOS).

7. Copy the `zotec-prod.asc` GPG key file to the `resources/` folder.

## Configuration

1. Update the `config.yaml` file with your MySQL database credentials:
   ```yaml
   database:
     host: your_host
     port: 3306
     user: your_username
     password: your_password
     database: your_database
   ```

2. Update the SFTP configuration in `config.yaml`:
   ```yaml
   sftp:
     host: your_sftp_host
     port: 22
     username: your_sftp_username
     password: your_sftp_password
   ```

3. The SQL files in `resources/` use placeholders like `%START_TS%`, `%END_TS%`, `%START_DT%`, `%END_DT%`, which are automatically replaced with appropriate date values (yesterday's dates).

4. Queries are defined in the `QUERIES` list in `main.py`, each with keys like 'name', 'file', 'remote_dir', 'sep', 'filename_prefix', 'strftime', 'file_type'.

## Usage

Run the script with no arguments to execute all queries in local mode (no upload):
```
python main.py
```

Run the script with a query name to execute only that query in local mode:
```
python main.py visits
python main.py payments
python main.py claims
```

Run the script with a query name and upload mode ('local' or 'mft'):
```
python main.py visits local
python main.py payments mft
python main.py claims mft
```

The script will:
- Connect to the MySQL database
- Execute the specified query(s), replacing date placeholders
- Export the results to timestamped CSV or XML files in the `output/` directory based on 'file_type'
- Encrypt each file to a `.pgp` file using the GPG key
- If upload mode is 'mft', upload the encrypted `.pgp` file to the appropriate SFTP directory

## Output

Files are created in the `output/` directory with specific naming:
- For `visits`: `TDOC_core_visit_yyyyMMddHHmm.csv`
- For `payments`: `TDOC_PatientPayments_yyyyMMdd_HHmmss.csv`
- For `claims`: `TDOC_core_charge_yyyyMMddHHmm.xml`

Each file is encrypted to a corresponding `.pgp` file.

Formatting:
- CSV (visits, payments): Pipe-separated (`|`) or comma-separated (`,`), all fields quoted, nulls as blank, `\r\n` line endings
- XML (claims): Standard XML format using etree parser

## Dependencies

- mysql-connector-python: For MySQL database connection
- pandas: For data manipulation and export
- PyYAML: For configuration file parsing
- paramiko: For SFTP upload

## GPG Encryption

- GPG must be installed on the system.
- The `zotec-prod.asc` public key must be copied to `resources/` before running.
- The script imports the key, encrypts files, and saves `.pgp` files.

## Logging

The script includes logging to track execution and errors.

## Security

- Sensitive files like `config.yaml` and `resources/zotec-prod.asc` are ignored by Git (see `.gitignore`).
- Do not commit credentials or keys to the repository.
