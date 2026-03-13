# ZotecReports

A Python project to connect to MySQL database, execute a sequence of queries, and export results to CSV files.

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

## Configuration

1. Update the `DB_CONFIG` dictionary in `main.py` with your MySQL database credentials:
   ```python
   DB_CONFIG = {
       'host': 'your_host',
       'user': 'your_username',
       'password': 'your_password',
       'database': 'your_database'
   }
   ```

2. Modify the `QUERIES` list in `main.py` to include your specific SQL queries. Each query should be a dictionary with 'name' and 'sql' keys.

## Usage

Run the script:
```
python main.py
```

The script will:
- Connect to the MySQL database
- Execute each query in sequence
- Export the results of each query to a timestamped CSV file in the `output/` directory

## Output

CSV files will be created in the `output/` directory with the format: `{query_name}_{timestamp}.csv`

## Dependencies

- mysql-connector-python: For MySQL database connection
- pandas: For data manipulation and CSV export

## Logging

The script includes logging to track the execution process and any errors that may occur.
