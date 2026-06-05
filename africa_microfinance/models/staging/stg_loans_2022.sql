-- stg_loans_2022.sql
-- Location: models/staging/stg_loans_2022.sql
--
-- PURPOSE: Cleans and standardizes the loans_2022 raw table.
-- One row per loan transaction for the year 2022.
--
-- SCHEMA CHANGES VS loans_2021:
--   + bank_name added: borrower's bank institution
--   + no_of_years_in_business added: borrower business tenure
--   + agent_fee added: fee charged by loan agent
--   + preferred_id added: borrower's preferred ID document type
--
-- All other transformations identical to stg_loans_2021.


with source as (

    select * from {{ source('raw_loans', 'loans_2022') }}

),

cleaned as (

    select

        -- IDENTITY
        name                                                as full_name,

        -- LOAN YEAR
        -- Hardcoded constant. Critical for Gold layer unioning.
        2022                                                as loan_year,

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
        -- Handles: 'GHS 1,800', 'RWF 767,000', 'KES 34,700', plain numbers.
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
        -- NEW in 2022. Fee charged by the loan agent.
        -- Same casting pattern as other numeric columns.
        case
            when agent_fee = 'nan' then null
            else safe_cast(
                regexp_replace(agent_fee, r'[^0-9.]', '') as numeric
            )
        end                                                 as agent_fee,

        -- DATES
        -- Two mixed formats: DD/MM/YYYY and YYYY-MM-DD.
        -- safe.parse_date returns null for typos like 23//03//2022.
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
        case
            when didnt_pay_entire_loan = '1.0' then 'defaulted'
            when late_payment_gt5days  = '1.0' then 'late_gt5days'
            when late_payment_lt5days  = '1.0' then 'late_lt5days'
            when paid_on_due_date      = '1.0' then 'on_time'
            when paid_before_due_date  = '1.0' then 'early'
            else null
        end                                                 as repayment_status,

        -- DUE DILIGENCE
        -- Same logic as stg_loans_2021.
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
        -- NEW in 2022. Borrower's bank institution.
        -- Kept as-is — institutional data, not PII.
        -- 'nan' → null.
        case
            when bank_name = 'nan' then null
            else bank_name
        end                                                 as bank_name,

        -- YEARS IN BUSINESS
        -- NEW in 2022. Same pattern as stg_borrower_profile.
        -- Float intermediate needed: '4.0' can't cast directly to INT64.
        case
            when no_of_years_in_business = 'nan' then null
            else safe_cast(
                safe_cast(no_of_years_in_business as float64) as int64
            )
        end                                                 as years_in_business,

        -- PREFERRED ID
        -- NEW in 2022. ID document type used by borrower.
        -- Values: 'Ghana Card', 'Kenyan National ID', 'Rwanda Nida',
        --         'MTN Mobile Money', 'M-Pesa', 'MoMo'
        -- Kept as-is — useful for country-level segmentation in Gold.
        -- 'nan' → null.
        case
            when preferred_id = 'nan' then null
            else preferred_id
        end                                                 as preferred_id

        -- DROPPED COLUMNS (same as prior years):
        --   s_n, age, phone_number, business_address, names1
        --   5 repayment flag columns (collapsed into repayment_status)

    from source

    -- GHOST ROW FILTER
    where name != 'nan'
      and name is not null

)

select * from cleaned