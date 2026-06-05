# Africa Microfinance Data Pipeline

An end-to-end ELT data pipeline for a multi-country African microfinance 
operation spanning Nairobi (Kenya), Accra (Ghana), and Kigali (Rwanda) 
across 2020-2023.

Built as a portfolio project to demonstrate analytics engineering and 
data engineering skills using modern data stack tools.

---

## Why This Project Exists

In microfinance operations across Africa, loan data is often collected 
manually by field officers using Excel spreadsheets. This creates 
significant data quality challenges — inconsistent formats, missing 
values, schema drift across years, and mixed currencies — that make 
it nearly impossible to answer critical business questions reliably.

**The cost of bad data in lending is not just technical — it's financial 
and human.** When data is unreliable:

- Credit managers make loan approval decisions based on wrong signals
- ML models trained on dirty data learn the wrong patterns and 
  misclassify borrowers as low risk when they are high risk
- Branch managers cannot identify which loan officers are approving 
  risky loans
- Executives cannot compare performance across cities because 
  metrics are calculated inconsistently
- Borrowers who are creditworthy get rejected while risky borrowers 
  get approved

**The goal of this pipeline is to turn messy operational data into 
a single source of truth that analysts, ML engineers, and business 
leaders can trust.**

Clean, well-structured data is not just a technical achievement — 
it is the foundation that every downstream decision, model, and 
insight depends on. A dashboard is only as trustworthy as the 
pipeline behind it. An ML model is only as accurate as the data 
it was trained on.

This pipeline applies the medallion architecture (Bronze → Silver → Gold)
to systematically address data quality at every layer before data 
reaches any consumer.

---

## What This Project Does

Raw Excel operational data from microfinance loan officers is transformed 
into clean, business-ready tables in BigQuery using the medallion 
architecture (Bronze → Silver → Gold).

The Gold layer serves three consumers:
- **Analysts** — SQL queries and dashboards in BigQuery
- **ML team** — parquet files for default prediction model training
- **Executives** — branch performance and loan officer metrics

---

## Architecture
Excel File (Source)
↓
Python (load_to_bigquery.py)
↓
BigQuery: raw_loans (Bronze)

loan_register
borrower_profile
default_tracker
loans_2020 / loans_2021 / loans_2022 / loans_2023
loan_calendar
↓
dbt (Transform in BigQuery)
↓
BigQuery: staging_loans (Silver)
stg_borrower_profile
stg_default_tracker
stg_loans_2020 / 2021 / 2022 / 2023
↓
BigQuery: mart_loans (Gold)
mart_loans
mart_borrower_profile
mart_branch_perf
mart_loan_officer
↓
Python (export_to_parquet.py)
↓
Parquet + JSON files (ML team)




---

## Gold Layer Tables

### mart_loans
One row per loan transaction. Combines all four years into a single 
unified table. Key columns: branch, currency, repayment_status, 
loan_status, due_diligence_verified, digital_channel, loan_officer.

### mart_borrower_profile
One row per borrower. Summarises complete loan history including 
default_rate, total_loans, avg_approved_amount. Primary feature 
table for ML default prediction model.

### mart_branch_perf
One row per branch per year. Answers: "Is this branch lending to 
the right people?" Key metrics: default_rate, due_diligence_rate, 
digital_adoption_rate.

### mart_loan_officer
One row per loan officer (2023 only). Answers: "Which loan officers 
approve the riskiest loans?" Key metrics: default_rate, 
due_diligence_rate.

---

## Key Design Decisions

**ELT not ETL** — Data is loaded raw into BigQuery first, then 
transformed inside BigQuery using dbt. This preserves the original 
data and leverages BigQuery's processing power.

**Local currencies preserved** — KES, GHS, RWF kept in local 
currency. USD conversion is a business decision made downstream 
by analysts, not in the pipeline.

**Bronze = untouched** — Raw data lands exactly as it came from 
Excel. No transformations in the loading script except column name 
standardisation for BigQuery compatibility.

**Idempotency** — Loading script uses WRITE_TRUNCATE. Running it 
multiple times produces the same result, never duplicates.

**has_date_anomaly flag** — Rather than dropping rows with 
impossible dates (completed before started), rows are flagged so 
analysts can filter appropriately.

---

## Data Quality

14 dbt tests covering:
- Not null checks on key columns
- Accepted values for branch, currency, loan_status, repayment_status
- loan_year range validation
---
## Tech Stack

| Tool | Purpose |
|------|---------|
| Python | Extract from Excel, load to BigQuery, export to parquet/json |
| pandas | Read Excel sheets into dataframes |
| google-cloud-bigquery | Load data into BigQuery |
| dbt (dbt-bigquery) | Transform data inside BigQuery |
| BigQuery | Cloud data warehouse |
| Git + GitHub | Version control |

---