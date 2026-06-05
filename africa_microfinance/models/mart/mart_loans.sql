-- =============================================================================
-- mart_loans.sql
-- Purpose: Unified loan transactions across all years 2020-2023
-- Grain: One row per loan transaction
-- Consumers: Analysts, ML team, branch managers
-- Key decisions:
--   - Local currencies kept (KES/GHS/RWF) — analyst converts downstream
--   - loan_month extracted from date for all years
--   - due_diligence_verified is BOOL — null cast as bool for 2020
--   - digital_channel and loan_officer null for 2020-2022
--   - has_date_anomaly flag added for analysts
-- =============================================================================

{{ config(materialized='table') }}

with loans_2020 as (
    select
        full_name,
        loan_year,
        branch,
        currency,
        gender,
        type_of_business,
        loan_count,
        duration_months,
        amount_requested,
        approved_amount,
        daily_fix,
        loan_date,
        case
            when loan_date is not null then format_date('%B', loan_date)
            when start_date is not null then format_date('%B', start_date)
            else null
        end                             as loan_month,
        date_issued,
        start_date,
        end_date,
        completed_date,
        loan_status,
        repayment_status,
        remark_rating,
        cast(null as bool)              as due_diligence_verified,
        cast(null as numeric)           as agent_fee,
        cast(null as string)            as bank_name,
        cast(null as numeric)           as years_in_business,
        cast(null as string)            as preferred_id,
        cast(null as string)            as digital_channel,
        cast(null as string)            as loan_officer
    from {{ ref('stg_loans_2020') }}
),

loans_2021 as (
    select
        full_name,
        loan_year,
        branch,
        currency,
        gender,
        type_of_business,
        loan_count,
        duration_months,
        amount_requested,
        approved_amount,
        daily_fix,
        loan_date,
        case
            when loan_date is not null then format_date('%B', loan_date)
            when start_date is not null then format_date('%B', start_date)
            else null
        end                             as loan_month,
        date_issued,
        start_date,
        end_date,
        completed_date,
        loan_status,
        repayment_status,
        remark_rating,
        due_diligence_verified,
        cast(null as numeric)           as agent_fee,
        cast(null as string)            as bank_name,
        cast(null as numeric)           as years_in_business,
        cast(null as string)            as preferred_id,
        cast(null as string)            as digital_channel,
        cast(null as string)            as loan_officer
    from {{ ref('stg_loans_2021') }}
),

loans_2022 as (
    select
        full_name,
        loan_year,
        branch,
        currency,
        gender,
        type_of_business,
        loan_count,
        duration_months,
        amount_requested,
        approved_amount,
        daily_fix,
        loan_date,
        case
            when loan_date is not null then format_date('%B', loan_date)
            when start_date is not null then format_date('%B', start_date)
            else null
        end                             as loan_month,
        date_issued,
        start_date,
        end_date,
        completed_date,
        loan_status,
        repayment_status,
        remark_rating,
        due_diligence_verified,
        agent_fee,
        bank_name,
        years_in_business,
        preferred_id,
        cast(null as string)            as digital_channel,
        cast(null as string)            as loan_officer
    from {{ ref('stg_loans_2022') }}
),

loans_2023 as (
    select
        full_name,
        loan_year,
        branch,
        currency,
        gender,
        type_of_business,
        loan_count,
        duration_months,
        amount_requested,
        approved_amount,
        daily_fix,
        loan_date,
        case
            when loan_date is not null then format_date('%B', loan_date)
            when start_date is not null then format_date('%B', start_date)
            else null
        end                             as loan_month,
        date_issued,
        start_date,
        end_date,
        completed_date,
        loan_status,
        repayment_status,
        remark_rating,
        due_diligence_verified,
        agent_fee,
        bank_name,
        years_in_business,
        preferred_id,
        digital_channel,
        loan_officer
    from {{ ref('stg_loans_2023') }}
),

combined as (
    select * from loans_2020
    union all
    select * from loans_2021
    union all
    select * from loans_2022
    union all
    select * from loans_2023
),

cleaned as (
    select
        full_name,
        loan_year,
        branch,
        currency,
        gender,
        type_of_business,
        loan_count,
        duration_months,
        amount_requested,
        approved_amount,
        daily_fix,
        loan_date,
        loan_month,
        date_issued,
        start_date,
        end_date,
        completed_date,
        loan_status,
        repayment_status,
        remark_rating,
        due_diligence_verified,
        agent_fee,
        bank_name,
        years_in_business,
        preferred_id,
        digital_channel,
        loan_officer,

        -- flag impossible dates for analysts
        case
            when completed_date is not null
                and start_date is not null
                and completed_date < start_date then true
            else false
        end                             as has_date_anomaly

    from combined
    where full_name != 'nan'
    and full_name is not null
    and full_name != 'TOTAL'
)

select * from cleaned