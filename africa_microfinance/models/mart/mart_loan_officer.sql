-- =============================================================================
-- mart_loan_officer.sql
-- Purpose: Loan officer performance metrics (2023 data only)
-- Grain: One row per loan officer per branch
-- Consumers: Branch managers, HR, credit risk team
-- Key business question: "Which loan officers approve the riskiest loans?"
-- Key decisions:
--   - 2023 only — loan_officer column only exists from 2023
--   - default_rate per officer is the primary risk signal
--   - due_diligence_rate shows if officer follows verification process
--   - high default_rate + low due_diligence_rate = red flag
-- =============================================================================

{{ config(materialized='table') }}

with loans_2023 as (
    -- Only use 2023 data — loan_officer column only exists here
    select * from {{ ref('mart_loans') }}
    where loan_year = 2023
    and loan_officer is not null
    and loan_officer != 'nan'
),

officer_metrics as (
    select
        loan_officer,
        branch,
        currency,

        -- Volume metrics
        count(*)                                    as total_loans_approved,
        count(distinct full_name)                   as unique_borrowers,

        -- Amount metrics
        sum(approved_amount)                        as total_amount_approved,
        avg(approved_amount)                        as avg_loan_amount,

        -- Risk metrics — key signal for officer performance
        safe_divide(
            countif(repayment_status = 'defaulted'),
            count(*)
        )                                           as default_rate,

        countif(repayment_status = 'defaulted')     as total_defaults,
        countif(repayment_status = 'on_time')       as total_on_time,
        countif(repayment_status = 'early')         as total_early,

        -- Process compliance — is officer verifying borrowers?
        safe_divide(
            countif(due_diligence_verified = true),
            count(*)
        )                                           as due_diligence_rate,

        -- Digital channel usage per officer
        safe_divide(
            countif(
                digital_channel is not null
                and digital_channel != 'In-person'
            ),
            count(*)
        )                                           as digital_adoption_rate,

        -- Average loan duration approved
        avg(duration_months)                        as avg_loan_duration

    from loans_2023
    group by loan_officer, branch, currency
)

select * from officer_metrics