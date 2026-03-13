# ZotecReports

A Python project to connect to MySQL database, execute queries from SQL files with dynamic date placeholders, export results to CSV files with specific formatting, and encrypt the files using GPG.

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

2. The SQL files in `resources/` use `%START_DT%` and `%END_DT%` placeholders, which are automatically replaced with yesterday's date range (00:00:00 to 23:59:59).

3. Queries are defined in the `QUERIES` list in `main.py`, each with 'name' and 'file' keys pointing to SQL files.

## Usage

Run the script:
```
python main.py
```

The script will:
- Connect to the MySQL database
- Execute each query in sequence, replacing date placeholders
- Export the results to timestamped CSV files in the `output/` directory
- Encrypt each CSV file to a `.pgp` file using the GPG key

## Output

CSV files are created in the `output/` directory with specific naming:
- For `visits`: `TDOC_core_visit_yyyyMMddHHmm.csv`
- For `payments`: `TDOC_PatientPayments_yyyyMMdd_HHmmss.csv`
- For others: `{query_name}_yyyyMMdd_HHmmss.csv`

Each CSV is encrypted to a corresponding `.pgp` file.

CSV formatting:
- Visits: Pipe-separated (`|`), all fields quoted
- Payments: Comma-separated (`,`), all fields quoted
- Null values: Left as blank
- Line endings: `\r\n`

## Dependencies

- mysql-connector-python: For MySQL database connection
- pandas: For data manipulation and CSV export
- PyYAML: For configuration file parsing

## GPG Encryption

- GPG must be installed on the system.
- The `zotec-prod.asc` public key must be copied to `resources/` before running.
- The script imports the key, encrypts files, and saves `.pgp` files.

## Logging

The script includes logging to track execution and errors.

## Security

- Sensitive files like `config.yaml` and `resources/zotec-prod.asc` are ignored by Git (see `.gitignore`).
- Do not commit credentials or keys to the repository.
