import mysql.connector
import pandas as pd
import logging
import os
from datetime import datetime, timedelta
import yaml
import csv
import subprocess
import sys
import paramiko

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Load database configuration from config.yaml
with open('config.yaml', 'r') as file:
    config = yaml.safe_load(file)
DB_CONFIG = config['database']
SFTP_CONFIG = config['sftp']

# List of queries to execute
QUERIES = [
    {
        'name': 'visits',
        'file': 'resources/visits.sql',
        'remote_dir': 'zotec_prod/outbound/Core/',
        'sep': '|',
        'filename_prefix': 'TDOC_core_visit_',
        'strftime': '%Y%m%d%H%M',
        'file_type': 'csv'
    },
    {
        'name': 'payments',
        'file': 'resources/payments.sql',
        'remote_dir': 'zotec_prod/outbound/Payments/',
        'sep': ',',
        'filename_prefix': 'TDOC_PatientPayments_',
        'strftime': '%Y%m%d_%H%M%S',
        'file_type': 'csv'
    },
    {
        'name': 'claims',
        'file': 'resources/claims.sql',
        'remote_dir': 'zotec_prod/outbound/Core/',
        'sep': '|',
        'filename_prefix': 'TDOC_core_charge_',
        'strftime': '%Y%m%d%H%M',
        'file_type': 'xml'
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

def export_to_xml(df, filename):
    """Export DataFrame to XML file."""
    try:
        df.to_xml(filename, index=False, parser='etree')
        logging.info(f"Data exported to {filename}")
    except Exception as err:
        logging.error(f"Error exporting to XML: {err}")
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

def upload_file(pgp_filename, query_name):
    """Upload the encrypted file to the SFTP server based on query name."""
    try:
        # Determine remote directory from query name
        remote_dir = next((q['remote_dir'] for q in QUERIES if q['name'] == query_name), None)
        if not remote_dir:
            raise ValueError(f"No upload directory defined for query: {query_name}")

        # Establish SFTP connection
        transport = paramiko.Transport((SFTP_CONFIG['host'], SFTP_CONFIG['port']))
        transport.connect(username=SFTP_CONFIG['username'], password=SFTP_CONFIG['password'])
        sftp = paramiko.SFTPClient.from_transport(transport)

        # Ensure remote directory exists
        try:
            sftp.listdir(remote_dir)
        except IOError:
            sftp.mkdir(remote_dir)

        # Upload the file
        remote_path = os.path.join(remote_dir, os.path.basename(pgp_filename)).replace('\\', '/')
        sftp.put(pgp_filename, remote_path)

        sftp.close()
        transport.close()
        logging.info(f"File uploaded to SFTP: {remote_path}")
    except Exception as err:
        logging.error(f"Error uploading file: {err}")
        raise

def main():
    """Main function to run the sequence of queries and export results."""
    # Check for command-line arguments
    query_to_run = None
    upload_mode = 'local'  # default
    if len(sys.argv) > 1:
        query_to_run = sys.argv[1]
    if len(sys.argv) > 2:
        upload_mode = sys.argv[2]
        if upload_mode not in ['local', 'mft']:
            logging.error(f"Invalid upload mode: {upload_mode}. Use 'local' or 'mft'.")
            return

    queries_to_run = QUERIES
    if query_to_run:
        queries_to_run = [q for q in QUERIES if q['name'] == query_to_run]
        if not queries_to_run:
            logging.error(f"No query found with name: {query_to_run}")
            return

    # Create output directory if it doesn't exist
    output_dir = 'output'
    os.makedirs(output_dir, exist_ok=True)
    # Get current timestamp for file naming
    timestamp = datetime.now()
    conn = None
    try:
        conn = connect_to_db()

        for query_info in queries_to_run:
            query_name = query_info['name']
            query_file = query_info['file']
            sep = query_info['sep']
            filename_prefix = query_info['filename_prefix']
            strftime_format = query_info['strftime']
            file_type = query_info['file_type']

            logging.info(f"Executing query: {query_name}")

            # Read SQL file
            with open(query_file, 'r') as file:
                query_sql = file.read()

            # Format query with dates if placeholders exist
            yesterday = datetime.now() - timedelta(days=1)
            start_ts = yesterday.replace(hour=0, minute=0, second=0, microsecond=0).strftime('%Y-%m-%d %H:%M:%S')
            end_ts = yesterday.replace(hour=23, minute=59, second=59, microsecond=0).strftime('%Y-%m-%d %H:%M:%S')
            start_dt = yesterday.strftime('%Y%m%d')
            end_dt = yesterday.strftime('%Y%m%d')
            if query_name == 'claims':
                end_ts = start_ts  # For claims, END_TS is also start_ts
            query_sql = query_sql.replace('%START_TS%', start_ts).replace('%END_TS%', end_ts).replace('%START_DT%', start_dt).replace('%END_DT%', end_dt)

            # Execute query
            df = execute_query(conn, query_sql)

            # Generate filename
            extension = '.csv' if file_type == 'csv' else '.xml'
            filename = f"{output_dir}/{filename_prefix}{timestamp.strftime(strftime_format)}{extension}"

            # Export to CSV or XML
            if file_type == 'csv':
                export_to_csv(df, filename, sep)
            elif file_type == 'xml':
                export_to_xml(df, filename)

            # Encrypt and upload
            encrypt_file(filename)
            if upload_mode == 'mft':
                upload_file(filename + '.pgp', query_name)

    except Exception as err:
        logging.error(f"An error occurred: {err}")
    finally:
        if conn:
            conn.close()
            logging.info("Database connection closed.")

if __name__ == "__main__":
    main()
