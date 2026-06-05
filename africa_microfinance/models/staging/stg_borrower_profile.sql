-- =============================================================================
-- stg_borrower_profile.sql
-- Purpose: Clean and standardise borrower profile data from Bronze layer
-- Source: raw_loans.borrower_profile
-- Grain: One row per unique borrower
-- Decisions:
--   - PII dropped: phone, account_number, guarantor_phone, house_address
--   - age dropped: too unreliable, mixed formats across all three countries
--   - guarantor_name dropped: not needed for analysis
--   - bank_name dropped: not needed for analysis
--   - Gender standardised: F/M → female/male
--   - national_id_type standardised to consistent values
--   - years_in_business cast to numeric, nan → null
-- =============================================================================

{{ config(materialized='view') }}

with source as (
    -- Pull raw data from Bronze layer
    select * from {{ source('raw_loans', 'borrower_profile') }}
),

renamed as (
    select
        -- Borrower identity
        name                                        as full_name,

        -- Standardise gender — handles F, f, female, M, m, male, spaces
        case
            when trim(lower(gender)) in ('f', 'female') then 'female'
            when trim(lower(gender)) in ('m', 'male') then 'male'
            else null
        end                                         as gender,

        -- Business information
        type_of_business                            as business_type,

        case
            when years_in_business = 'nan' then null
            else cast(years_in_business as numeric)
        end                                         as years_in_business,

        -- Geographic information — critical for branch analysis
        branch,

        -- ID type standardisation
        case
            when national_id_type = 'nan' then null
            when national_id_type = 'Ghana Card' then 'Ghana Card'
            when national_id_type = 'Kenyan National ID' then 'Kenyan National ID'
            when national_id_type = 'Rwanda Nida' then 'Rwanda Nida'
            else null
        end                                         as national_id_type

        -- Dropped: phone (PII)
        -- Dropped: account_number (PII)
        -- Dropped: guarantor_phone (PII)
        -- Dropped: guarantor_name (not needed for analysis)
        -- Dropped: house_address (PII, not needed)
        -- Dropped: bank_name (not needed for analysis)
        -- Dropped: age (too unreliable — mixed formats, impossible values)

    from source
),

cleaned as (
    select * from renamed
    -- Remove ghost rows from Excel formatting
    where full_name != 'nan'
    and full_name is not null
    and full_name != 'nan '
)

select * from cleaned