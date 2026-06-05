# =============================================================================
# export_to_parquet.py
# Purpose: Export Gold layer tables to parquet and JSON formats
#          Parquet → ML team for model training
#          JSON → alternative format for other consumers
# Note: BigQuery tables already exist for SQL analysts
#       These files are additional delivery formats
# =============================================================================

import pandas as pd
from google.cloud import bigquery
from google.oauth2 import service_account

SERVICE_ACCOUNT_FILE = "africa-microfinance-analytics-6a472342db65.json"
PROJECT_ID = "africa-microfinance-analytics"

credentials = service_account.Credentials.from_service_account_file(
    SERVICE_ACCOUNT_FILE
)

client = bigquery.Client(
    project=PROJECT_ID,
    credentials=credentials
)

def convert_dates_to_string(df):
    # Convert date columns to string for JSON compatibility
    # JSON doesn't handle BigQuery date types natively
    for col in df.columns:
        if str(df[col].dtype) in ['dbdate', 'object']:
            try:
                df[col] = df[col].astype(str)
            except:
                pass
    return df

# Tables to export
tables = [
    'mart_loans',
    'mart_borrower_profile',
    'mart_branch_perf',
    'mart_loan_officer'
]

for table in tables:
    print(f"Exporting {table}...")

    df = client.query(f"""
        SELECT * FROM `{PROJECT_ID}.mart_loans.{table}`
    """).to_dataframe()

    # Export to parquet — for ML team
    df.to_parquet(f"{table}.parquet", index=False)
    print(f"  ✓ {table}.parquet exported")

    # Export to JSON — alternative format
    df_json = convert_dates_to_string(df.copy())
    df_json.to_json(f"{table}.json", orient="records", indent=2)
    print(f"  ✓ {table}.json exported: {len(df)} rows")

print("\nAll exports complete!")