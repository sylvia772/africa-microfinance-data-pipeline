-- stg_loans_2023.sql
-- Location: models/staging/stg_loans_2023.sql
--
-- PURPOSE: Cleans and standardizes the loans_2023 raw table.
-- One row per loan transaction for the year 2023.
--
-- SCHEMA CHANGES VS loans_2022:
--   + digital_channel added: how the loan application was submitted
--     (Mobile App, USSD, In-Person)
--   + loan_officer added: name of the officer who processed the loan.
--     This column is critical for mart_loan_officer_perf in Gold.
--
-- All other transformations identical to stg_loans_2022.


with source as (

    select * from {{ source('raw_loans', 'loans_2023') }}

),

cleaned as (

    select

        -- IDENTITY
        name                                                as full_name,

        -- LOAN YEAR
        -- Hardcoded constant. Critical for Gold layer unioning.
        2023                                                as loan_year,

        -- GEOGRAPHY
        branch,

        -- GENDER
        -- Same standardization as all prior staging models.
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
        -- Handles: 'GHS 2,500', 'RWF 932,000', 'KES 74,300', plain numbers.
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

        -- AGENT FEE
        case
            when agent_fee = 'nan' then null
            else safe_cast(
                regexp_replace(agent_fee, r'[^0-9.]', '') as numeric
            )
        end                                                 as agent_fee,

        -- DATES
        -- Two mixed formats: DD/MM/YYYY and YYYY-MM-DD.
        -- safe.parse_date returns null for typos like 27//04//2023.
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

        case
            when completed_date = 'nan' then null
            else coalesce(
                safe.parse_date('%d/%m/%Y', completed_date),
                safe.parse_date('%Y-%m-%d', completed_date)
            )
        end                                                 as completed_date,

        -- STATUS
        case
            when status = 'nan'                    then null
            when lower(status) = 'cleared'         then 'cleared'
            when lower(status) like '%didnt pay%'  then 'defaulted'
            else lower(status)
        end                                                 as loan_status,

        -- REPAYMENT STATUS
        -- 5 boolean flags collapsed into one category.
        case
            when didnt_pay_entire_loan = '1.0' then 'defaulted'
            when late_payment_gt5days  = '1.0' then 'late_gt5days'
            when late_payment_lt5days  = '1.0' then 'late_lt5days'
            when paid_on_due_date      = '1.0' then 'on_time'
            when paid_before_due_date  = '1.0' then 'early'
            else null
        end                                                 as repayment_status,

        -- DUE DILIGENCE
        -- null means not recorded, not that it was skipped.
        case
            when due_diligence = 'Verified' then true
            else null
        end                                                 as due_diligence_verified,

        -- RATING
        case
            when remark_rating = 'nan' then null
            else remark_rating
        end                                                 as remark_rating,

        -- BANK NAME
        case
            when bank_name = 'nan' then null
            else bank_name
        end                                                 as bank_name,

        -- YEARS IN BUSINESS
        case
            when no_of_years_in_business = 'nan' then null
            else safe_cast(
                safe_cast(no_of_years_in_business as float64) as int64
            )
        end                                                 as years_in_business,

        -- PREFERRED ID
        case
            when preferred_id = 'nan' then null
            else preferred_id
        end                                                 as preferred_id,

        -- DIGITAL CHANNEL
        -- NEW in 2023. How the loan application was submitted.
        -- Values: 'Mobile App', 'USSD', 'In-Person'
        -- Kept as-is — useful for digital adoption analysis in Gold.
        -- 'nan' → null.
        case
            when digital_channel = 'nan' then null
            else digital_channel
        end                                                 as digital_channel,

        -- LOAN OFFICER
        -- NEW in 2023. Name of the officer who processed the loan.
        -- Critical column — feeds directly into mart_loan_officer_perf in Gold.
        -- 'nan' → null.
        case
            when loan_officer = 'nan' then null
            else loan_officer
        end                                                 as loan_officer

        -- DROPPED COLUMNS (same as prior years):
        --   s_n, age, phone_number, business_address, names1
        --   5 repayment flag columns (collapsed into repayment_status)

    from source

    -- GHOST ROW FILTER
    -- Excel header rows: s_n = '2023', 'Oct', 'TOTAL' etc.
    where name != 'nan'
      and name is not null

)

select * from cleaned