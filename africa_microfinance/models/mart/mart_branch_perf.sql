-- =============================================================================
-- mart_branch_perf.sql
-- Purpose: Branch level performance metrics per year
-- Grain: One row per branch per year
-- Consumers: Branch managers, executives, credit risk team
-- Key business question: "Is this branch lending to the right people?"
-- Key decisions:
--   - Metrics calculated per branch per year for trend analysis
--   - due_diligence_rate shows if branch is following verification process
--   - default_rate is the primary risk signal per branch
--   - repeat_borrower_rate shows borrower loyalty and portfolio health
-- =============================================================================

{{ config(materialized='table') }}

with all_loans as (
    select * from {{ ref('mart_loans') }}
),

branch_metrics as (
    select
        branch,
        loan_year,
        currency,

        -- Volume metrics
        count(*)                                    as total_loans,
        count(distinct full_name)                   as unique_borrowers,

        -- Amount metrics — in local currency
        sum(approved_amount)                        as total_disbursed,
        avg(approved_amount)                        as avg_loan_amount,
        max(approved_amount)                        as max_loan_amount,
        min(approved_amount)                        as min_loan_amount,

        -- Risk metrics — primary signal for "wrong borrowers"
        safe_divide(
            countif(repayment_status = 'defaulted'),
            count(*)
        )                                           as default_rate,

        countif(repayment_status = 'defaulted')     as total_defaults,
        countif(repayment_status = 'on_time')       as total_on_time,
        countif(repayment_status = 'early')         as total_early,
        countif(repayment_status = 'late_gt5days')  as total_late_gt5days,
        countif(repayment_status = 'late_lt5days')  as total_late_lt5days,

        -- Process metrics — is branch following verification process?
        safe_divide(
            countif(due_diligence_verified = true),
            count(*)
        )                                           as due_diligence_rate,

        -- Loan characteristics
        avg(duration_months)                        as avg_loan_duration,

        -- Digital adoption per branch
        safe_divide(
            countif(
                digital_channel is not null
                and digital_channel != 'In-person'
            ),
            count(*)
        )                                           as digital_adoption_rate

    from all_loans
    group by branch, loan_year, currency
)

select * from branch_metrics