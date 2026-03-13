import mysql.connector
import pandas as pd
import logging
import os
from datetime import datetime, timedelta
import yaml
import csv
import subprocess

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Load database configuration from config.yaml
with open('config.yaml', 'r') as file:
    config = yaml.safe_load(file)
DB_CONFIG = config['database']

# List of queries to execute
QUERIES = [
    {
        'name': 'visits',
        'file': 'resources/visits.sql'
    },
    {
        'name': 'payments',
        'file': 'resources/payments.sql'
    },
    # Add more queries as needed
]

def connect_to_db():
    """Establish connection to MySQL database."""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        logging.info("Connected to MySQL database successfully.")
        return conn
    except mysql.connector.Error as err:
        logging.error(f"Error connecting to MySQL: {err}")
        raise

def execute_query(conn, query):
    """Execute a single query and return results as DataFrame."""
    try:
        statements = [s.strip() for s in query.split(';') if s.strip()]
        cursor = conn.cursor()
        # Execute all statements except the last one
        for stmt in statements[:-1]:
            cursor.execute(stmt)
        # Execute the last statement and fetch results
        cursor.execute(statements[-1])
        if cursor.with_rows:
            rows = cursor.fetchall()
            columns = cursor.column_names
            df = pd.DataFrame(rows, columns=columns)
        else:
            df = pd.DataFrame()
        cursor.close()
        logging.info(f"Query executed successfully. Rows returned: {len(df)}")
        return df
    except Exception as err:
        logging.error(f"Error executing query: {err}")
        raise

def export_to_csv(df, filename, sep):
    """Export DataFrame to CSV file."""
    try:
        df.to_csv(filename, index=False, sep=sep, quotechar='"', quoting=csv.QUOTE_ALL, na_rep='', lineterminator='\r\n')
        logging.info(f"Data exported to {filename}")
    except Exception as err:
        logging.error(f"Error exporting to CSV: {err}")
        raise

def encrypt_file(filename):
    """Encrypt the file using GPG with the key from resources/zotec-prod.asc."""
    pgp_filename = filename + '.pgp'
    try:
        # Import the key
        result = subprocess.run(['gpg', '--import', 'resources/zotec-prod.asc'], capture_output=True, text=True)
        if result.returncode != 0:
            raise ValueError(f"Key import failed: {result.stderr}")
        # List keys to get the key id
        result = subprocess.run(['gpg', '--list-keys', '--with-colons'], capture_output=True, text=True)
        logging.debug(f"List keys output: {result.stdout}")
        if result.returncode != 0:
            raise ValueError(f"List keys failed: {result.stderr}")
        # Parse the output to get the key id
        lines = result.stdout.split('\n')
        key_id = None
        for line in lines:
            if line.startswith('pub:'):
                parts = line.split(':')
                key_id = parts[4]
                break
        if not key_id:
            raise ValueError("No key found")
        # Encrypt
        result = subprocess.run(['gpg', '--yes', '--trust-model', 'always', '--encrypt', '--recipient', key_id, '--output', pgp_filename, filename], capture_output=True, text=True)
        if result.returncode != 0:
            raise ValueError(f"Encryption failed: {result.stderr}")
        logging.info(f"File encrypted to {pgp_filename}")
    except Exception as err:
        logging.error(f"Error encrypting file: {err}")
        raise

def main():
    """Main function to run the sequence of queries and export results."""
    # Create output directory if it doesn't exist
    output_dir = 'output'
    os.makedirs(output_dir, exist_ok=True)
    # Get current timestamp for file naming
    timestamp = datetime.now()
    conn = None
    try:
        conn = connect_to_db()

        for query_info in QUERIES:
            query_name = query_info['name']
            query_file = query_info['file']

            logging.info(f"Executing query: {query_name}")

            # Read SQL file
            with open(query_file, 'r') as file:
                query_sql = file.read()

            # Format query with dates if placeholders exist
            if '%START_DT%' in query_sql and '%END_DT%' in query_sql:
                # Calculate start_dt as yesterday at 00:00:00
                yesterday = datetime.now() - timedelta(days=1)
                start_dt = yesterday.replace(hour=0, minute=0, second=0, microsecond=0).strftime('%Y-%m-%d %H:%M:%S')
                # Calculate end_dt as yesterday at 23:59:59
                end_dt = yesterday.replace(hour=23, minute=59, second=59, microsecond=0).strftime('%Y-%m-%d %H:%M:%S')
                query_sql = query_sql.replace('%START_DT%', start_dt).replace('%END_DT%', end_dt)

            # Execute query
            df = execute_query(conn, query_sql)

            # Generate filename
            if query_name == 'visits':
                filename = f"{output_dir}/TDOC_core_visit_{timestamp.strftime('%Y%m%d%H%M')}.csv"
            elif query_name == 'payments':
                filename = f"{output_dir}/TDOC_PatientPayments_{timestamp.strftime('%Y%m%d_%H%M%S')}.csv"
            else:
                filename = f"{output_dir}/{query_name}_{timestamp.strftime('%Y%m%d_%H%M%S')}.csv"

            # Export to CSV
            export_to_csv(df, filename, sep = '|' if query_name == 'visits' else ',')
            encrypt_file(filename)

    except Exception as err:
        logging.error(f"An error occurred: {err}")
    finally:
        if conn:
            conn.close()
            logging.info("Database connection closed.")

if __name__ == "__main__":
    main()
