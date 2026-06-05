-- stg_loans_2020.sql
-- Location: models/staging/stg_loans_2020.sql
--
-- PURPOSE: Cleans and standardizes the loans_2020 raw table.
-- One row per loan transaction for the year 2020.
-- This is the Silver layer for 2020 loan data.
--
-- KEY DECISIONS:
--   - Ghost rows filtered: Excel header pollution landed as s_n = '2020',
--     'January', 'TOTAL' etc. Filter where name = 'nan' or null.
--   - month column dropped: inconsistent abbreviations (Sep/Sept/September)
--     and does not reliably match the date column. Extract month from
--     date in Gold instead.
--   - age dropped: mix of integers, dates of birth, 'Not available' — unreliable.
--   - names1 dropped: duplicate of name column.
--   - s_n dropped: serial number, no analytical value.
--   - phone_number dropped: PII.
--   - business_address dropped: PII / too granular.
--   - amount_requested and approved_amount: strip embedded currency symbols
--     and commas, cast to numeric.
--   - All date columns: handle two mixed formats DD/MM/YYYY and YYYY-MM-DD.
--   - completed_date: 'nan' means loan not yet completed — convert to null.
--   - status: standardize to lowercase, 'nan' → null.
--   - gender: same standardization as stg_borrower_profile.
--   - 5 repayment flag columns collapsed into single repayment_status column.
--   - loan_count and duration_no_of_months: cast from float STRING to integer.
--   - loan_year: hardcoded as 2020 — used for partitioning in Gold mart_loans.


with source as (

    -- Pull everything from the raw Bronze table.
    -- No filtering or logic here — that is what cleaned CTE is for.
    select * from {{ source('raw_loans', 'loans_2020') }}

),

cleaned as (

    select

        -- IDENTITY
        -- Renamed for consistency across all yearly staging models.
        name                                                as full_name,

        -- LOAN YEAR
        -- Hardcoded constant. Critical for Gold layer when we union
        -- all four yearly tables into mart_loans.
        2020                                                as loan_year,

        -- GEOGRAPHY
        branch,

        -- GENDER
        -- Same standardization logic as stg_borrower_profile.
        case
            when trim(lower(gender)) in ('f', 'female') then 'female'
            when trim(lower(gender)) in ('m', 'male')   then 'male'
            else null
        end                                                 as gender,

        -- BUSINESS INFO
        type_of_business,

        -- CURRENCY
        -- Keep local currency code (KES, GHS, RWF).
        -- Analyst converts to USD downstream if needed.
        currency,

        -- LOAN COUNTS & DURATION
        -- Bronze cast everything to STRING. Cast back to integer.
        -- safe_cast returns null instead of crashing on bad values.
        case
            when loan_count = 'nan' then null
            else safe_cast(
                safe_cast(loan_count as float64) as int64
            )
        end                                                 as loan_count,

        case
            when duration_no_of_months = 'nan' then null
            else safe_cast(
                safe_cast(duration_no_of_months as float64) as int64
            )
        end                                                 as duration_months,

        -- AMOUNTS
        -- Raw data has embedded currency symbols and commas:
        -- 'GHS 1,700', 'KES 41,400', '3,200', '3200'
        -- Strip everything except digits and decimal point, then cast.
        -- regexp_replace removes: letters, spaces, commas, currency symbols.
        case
            when amount_requested = 'nan' then null
            else safe_cast(
                regexp_replace(amount_requested, r'[^0-9.]', '') as numeric
            )
        end                                                 as amount_requested,

        case
            when approved_amount = 'nan' then null
            else safe_cast(
                regexp_replace(approved_amount, r'[^0-9.]', '') as numeric
            )
        end                                                 as approved_amount,

        -- DAILY REPAYMENT AMOUNT
        case
            when daily_fix = 'nan' then null
            else safe_cast(daily_fix as numeric)
        end                                                 as daily_fix,

        -- DATES
        -- Two formats exist in the raw data:
        --   DD/MM/YYYY         e.g. 22/01/2020
        --   YYYY-MM-DD         e.g. 2020-01-22
        -- Some also have typos like 19//12//2020 — safe_parse_date
        -- returns null automatically for those instead of crashing.
        -- coalesce tries format 1 first, falls back to format 2.
        coalesce(
            safe.parse_date('%d/%m/%Y', date),
            safe.parse_date('%Y-%m-%d', date)
        )                                                   as loan_date,

        coalesce(
            safe.parse_date('%d/%m/%Y', date_issued),
            safe.parse_date('%Y-%m-%d', date_issued)
        )                                                   as date_issued,

        coalesce(
            safe.parse_date('%d/%m/%Y', start_date),
            safe.parse_date('%Y-%m-%d', start_date)
        )                                                   as start_date,

        coalesce(
            safe.parse_date('%d/%m/%Y', end_date),
            safe.parse_date('%Y-%m-%d', end_date)
        )                                                   as end_date,

        -- COMPLETED DATE
        -- 'nan' means loan is not yet completed — explicitly null.
        -- Same two-format parsing as other date columns.
        case
            when completed_date = 'nan' then null
            else coalesce(
                safe.parse_date('%d/%m/%Y', completed_date),
                safe.parse_date('%Y-%m-%d', completed_date)
            )
        end                                                 as completed_date,

        -- STATUS
        -- Standardize to lowercase. 'nan' → null.
        case
            when status = 'nan'                  then null
            when lower(status) = 'cleared'       then 'cleared'
            when lower(status) like '%didnt pay%' then 'defaulted'
            else lower(status)
        end                                                 as loan_status,

        -- REPAYMENT STATUS
        -- 5 boolean flag columns collapsed into one clean category.
        -- Bronze cast booleans to STRING so values are '1.0' or '0.0'.
        -- All zeros or all nan = no outcome recorded yet → null.
        case
            when didnt_pay_entire_loan  = '1.0' then 'defaulted'
            when late_payment_gt5days   = '1.0' then 'late_gt5days'
            when late_payment_lt5days   = '1.0' then 'late_lt5days'
            when paid_on_due_date       = '1.0' then 'on_time'
            when paid_before_due_date   = '1.0' then 'early'
            else null
        end                                                 as repayment_status,

        -- RATING
        -- Keep remark_rating as-is for now.
        -- 'nan' → null.
        case
            when remark_rating = 'nan' then null
            else remark_rating
        end                                                 as remark_rating

        -- DROPPED COLUMNS:
        --   s_n              → serial number, no analytical value
        --   month            → inconsistent, redundant with loan_date
        --   age              → unreliable: mix of integers, DOB strings, 'Not available'
        --   phone_number     → PII
        --   business_address → PII / too granular for analysis
        --   names1           → exact duplicate of name column
        --   didnt_pay_entire_loan    → collapsed into repayment_status
        --   late_payment_gt5days     → collapsed into repayment_status
        --   late_payment_lt5days     → collapsed into repayment_status
        --   paid_on_due_date         → collapsed into repayment_status
        --   paid_before_due_date     → collapsed into repayment_status

    from source

    -- GHOST ROW FILTER
    -- Excel header rows landed as s_n = '2020', 'January', 'TOTAL' etc.
    -- All other columns on those rows are 'nan'. Filter on name.
    where name != 'nan'
      and name is not null

)

select * from cleaned