# =============================================================================
# load_to_bigquery.py
# Purpose: Extract data from Excel file and load each sheet into BigQuery
#          as-is (Bronze layer). No transformations applied here.
#          This is the ELT pattern — Extract, Load, then Transform in BigQuery.
# =============================================================================

import pandas as pd
from google.cloud import bigquery
from google.oauth2 import service_account

# =============================================================================
# CONFIGURATION
# All project-level settings in one place — change here, not inside the code
# =============================================================================
SERVICE_ACCOUNT_FILE = "africa-microfinance-analytics-6a472342db65.json"
PROJECT_ID = "africa-microfinance-analytics"
DATASET_ID = "raw_loans"
EXCEL_FILE = "Microfinance_Operations_Africa_2020_2023.xlsx"

# =============================================================================
# AUTHENTICATION
# Use service account JSON to authenticate with Google Cloud
# credentials = your ID card
# client = the door that opens once your ID is verified
# =============================================================================
credentials = service_account.Credentials.from_service_account_file(
    SERVICE_ACCOUNT_FILE
)

client = bigquery.Client(
    project=PROJECT_ID,
    credentials=credentials
)

# =============================================================================
# COLUMN NAME CLEANING
# BigQuery does not allow special characters in column names
# This function standardises all column names before loading
# Rules: lowercase, spaces→underscores, remove special chars
# =============================================================================
def clean_column_names(df):
    df.columns = (
        df.columns
        .str.strip()
        .str.lower()
        .str.replace(" ", "_", regex=False)
        .str.replace("/", "_", regex=False)
        .str.replace("(", "", regex=False)
        .str.replace(")", "", regex=False)
        .str.replace(">", "gt", regex=False)
        .str.replace("<", "lt", regex=False)
        .str.replace(".", "", regex=False)
        .str.replace("'", "", regex=False)
    )
    # Only drop columns with completely empty headers
    # These are Excel formatting artifacts with no data
    # We NEVER drop columns that have actual data — that happens in Silver
    df = df.loc[:, df.columns.str.strip() != ""]
    return df

# =============================================================================
# LOAD EACH SHEET INTO BIGQUERY
# Each sheet becomes one table in the raw_loans dataset
# We convert everything to string (astype str) to preserve raw data exactly
# Type casting happens in Silver layer (dbt), not here
# write_disposition=WRITE_TRUNCATE ensures idempotency —
# running this script twice produces the same result, not duplicates
# =============================================================================
excel_file = pd.ExcelFile(EXCEL_FILE)

for sheet_name in excel_file.sheet_names:
    print(f"Loading sheet: {sheet_name}...")

    # Read sheet into dataframe
    df = pd.read_excel(excel_file, sheet_name=sheet_name)

    # Convert all values to string — Bronze layer keeps everything raw
    df = df.astype(str)

    # Clean column names for BigQuery compatibility
    df = clean_column_names(df)

    # Convert sheet name to valid BigQuery table name
    table_name = sheet_name.lower().replace(" ", "_")

    # Full table address in BigQuery: project.dataset.table
    table_id = f"{PROJECT_ID}.{DATASET_ID}.{table_name}"

    # Configure load job
    job_config = bigquery.LoadJobConfig(
        # WRITE_TRUNCATE = delete existing data and replace
        # This makes the script idempotent — safe to run multiple times
        write_disposition="WRITE_TRUNCATE"
    )

    # Load dataframe into BigQuery
    job = client.load_table_from_dataframe(
        df, table_id, job_config=job_config
    )
    job.result()

    print(f"✓ Loaded {len(df)} rows into {table_id}")

print("\nAll sheets loaded successfully into raw_loans dataset!")