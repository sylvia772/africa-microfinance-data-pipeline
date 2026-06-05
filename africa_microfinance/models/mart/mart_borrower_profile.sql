-- =============================================================================
-- mart_borrower_profile.sql
-- Purpose: One row per borrower summarising their complete loan history
-- Grain: One row per unique borrower (full_name + branch combination)
-- Consumers: ML team (default prediction features), analysts (segmentation)
-- Key decisions:
--   - Grouped by full_name + branch to handle same name across cities
--   - default_rate is key ML feature — times_defaulted / total_loans
--   - due_diligence_rate shows what % of loans were verified
--   - digital_adoption shows if borrower moved to digital channels
-- =============================================================================

{{ config(materialized='table') }}

with all_loans as (
    -- Pull from mart_loans — our clean unified Gold source
    select * from {{ ref('mart_loans') }}
),

profile as (
    select
        full_name,
        -- Use branch to differentiate borrowers with same name across cities
        branch,
        currency,
        max(gender)                                 as gender,
        max(type_of_business)                       as business_type,

        -- Loan history
        count(*)                                    as total_loans,
        min(loan_year)                              as first_loan_year,
        max(loan_year)                              as last_loan_year,

        -- Loan amounts
        avg(approved_amount)                        as avg_approved_amount,
        max(approved_amount)                        as max_approved_amount,
        sum(approved_amount)                        as total_borrowed,

        -- Repayment behaviour — key ML features
        countif(repayment_status = 'defaulted')     as times_defaulted,
        countif(repayment_status = 'on_time')       as times_paid_on_time,
        countif(repayment_status = 'early')         as times_paid_early,
        countif(repayment_status = 'late_gt5days')  as times_late_gt5days,
        countif(repayment_status = 'late_lt5days')  as times_late_lt5days,

        -- Default rate — most important ML feature
        -- safe_divide prevents division by zero
        safe_divide(
            countif(repayment_status = 'defaulted'),
            count(*)
        )                                           as default_rate,

        -- Loan status
        countif(loan_status = 'cleared')            as times_cleared,
        countif(loan_status = 'defaulted')          as times_loan_defaulted,

        -- Due diligence rate — were loans properly verified?
        safe_divide(
            countif(due_diligence_verified = true),
            count(*)
        )                                           as due_diligence_rate,

        -- Digital adoption — did borrower use digital channels?
        -- null means they never had access to digital (pre-2023)
        max(case
            when digital_channel is not null
                and digital_channel != 'In-person'
                then true
            else false
        end)                                        as uses_digital_channel,

        -- Average loan duration
        avg(duration_months)                        as avg_duration_months

    from all_loans
    group by full_name, branch, currency
)

select * from profile