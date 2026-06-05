-- stg_loans_2021.sql
-- Location: models/staging/stg_loans_2021.sql
--
-- PURPOSE: Cleans and standardizes the loans_2021 raw table.
-- One row per loan transaction for the year 2021.
--
-- SCHEMA CHANGES VS loans_2020:
--   + due_diligence added: indicates borrower verification status
--   - month removed: was already being dropped in 2020 anyway
--
-- All other transformations identical to stg_loans_2020.


with source as (

    select * from {{ source('raw_loans', 'loans_2021') }}

),

cleaned as (

    select

        -- IDENTITY
        name                                                as full_name,

        -- LOAN YEAR
        -- Hardcoded constant. Critical for Gold layer unioning.
        2021                                                as loan_year,

        -- GEOGRAPHY
        branch,

        -- GENDER
        -- Same standardization as stg_borrower_profile and stg_loans_2020.
        case
            when trim(lower(gender)) in ('f', 'female') then 'female'
            when trim(lower(gender)) in ('m', 'male')   then 'male'
            else null
        end                                                 as gender,

        -- BUSINESS INFO
        type_of_business,

        -- CURRENCY
        currency,

        -- LOAN COUNT & DURATION
        -- Bronze cast everything to STRING. Float intermediate needed
        -- because values like '3.0' can't cast directly to INT64.
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
        -- Strip all non-numeric characters before casting.
        -- Handles: 'GHS 1,700', 'KES 41,400', '3,200', '3200'.
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

        case
            when daily_fix = 'nan' then null
            else safe_cast(daily_fix as numeric)
        end                                                 as daily_fix,

        -- DATES
        -- Two mixed formats: DD/MM/YYYY and YYYY-MM-DD.
        -- coalesce tries format 1 first, falls back to format 2.
        -- Typos like 19//12//2020 return null automatically via safe.parse_date.
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
        -- 'nan' means loan not yet completed — null.
        case
            when completed_date = 'nan' then null
            else coalesce(
                safe.parse_date('%d/%m/%Y', completed_date),
                safe.parse_date('%Y-%m-%d', completed_date)
            )
        end                                                 as completed_date,

        -- STATUS
        case
            when status = 'nan'                   then null
            when lower(status) = 'cleared'        then 'cleared'
            when lower(status) like '%didnt pay%' then 'defaulted'
            else lower(status)
        end                                                 as loan_status,

        -- REPAYMENT STATUS
        -- 5 boolean flags collapsed into one category.
        -- Values are '1.0' or '0.0' because Bronze cast everything to STRING.
        case
            when didnt_pay_entire_loan = '1.0' then 'defaulted'
            when late_payment_gt5days  = '1.0' then 'late_gt5days'
            when late_payment_lt5days  = '1.0' then 'late_lt5days'
            when paid_on_due_date      = '1.0' then 'on_time'
            when paid_before_due_date  = '1.0' then 'early'
            else null
        end                                                 as repayment_status,

        -- DUE DILIGENCE
        -- NEW in 2021. Indicates whether borrower verification was completed.
        -- Raw values: 'Verified' or 'nan'.
        -- Standardized to BOOLEAN: true / null.
        -- We use null (not false) for missing — we cannot confirm it
        -- was NOT done, only that it wasn't recorded.
        case
            when due_diligence = 'Verified' then true
            else null
        end                                                 as due_diligence_verified,

        -- RATING
        case
            when remark_rating = 'nan' then null
            else remark_rating
        end                                                 as remark_rating

        -- DROPPED COLUMNS (same as stg_loans_2020):
        --   s_n, age, phone_number, business_address, names1
        --   5 repayment flag columns (collapsed into repayment_status)

    from source

    -- GHOST ROW FILTER
    -- Excel header rows: s_n = '2021', 'November', 'TOTAL' etc.
    where name != 'nan'
      and name is not null

)

select * from cleaned