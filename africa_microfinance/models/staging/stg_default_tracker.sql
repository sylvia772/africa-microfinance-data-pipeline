-- stg_default_tracker.sql
-- Location: models/staging/stg_default_tracker.sql
--
-- PURPOSE: Cleans and standardizes the default_tracker table.
-- This table tracks problematic borrowers — those who defaulted,
-- relocated, absconded, or otherwise failed to repay fully.
-- One row per borrower flag.
--
-- KEY DECISIONS:
--   - sn dropped: serial number with no analytical value
--   - unnamed dropped: unknown column, mostly nan
--   - gender standardized to lowercase male/female (same logic as stg_borrower_profile)
--   - remark standardized to lowercase snake_case categories
--   - RELOCATED and RELOCATED - NEW NUMBER collapsed into single 'relocated' value
--   - count cast from STRING to INTEGER (Bronze landed everything as STRING)
--   - Ghost rows filtered where full_name = 'nan' or null


with source as (

    -- Pull everything from the raw Bronze table.
    -- No filtering or logic here — that's what the next CTE is for.
    select * from {{ source('raw_loans', 'default_tracker') }}

),

cleaned as (

    select

        -- IDENTITY
        -- Renamed from 'name' to 'full_name' for consistency
        -- with stg_borrower_profile. Ghost rows filtered below.
        name                                                as full_name,

        -- GEOGRAPHY
        -- Branch kept as-is. Critical for geographic analysis
        -- across Nairobi, Accra, and Kigali.
        branch,

        -- GENDER
        -- Raw data contains: 'F', 'M', 'Female', 'Male' (mixed case).
        -- Same standardization logic as stg_borrower_profile.
        -- Anything unrecognized becomes null.
        case
            when trim(lower(gender)) in ('f', 'female') then 'female'
            when trim(lower(gender)) in ('m', 'male')   then 'male'
            else null
        end                                                 as gender,

        -- REMARK
        -- Standardized to lowercase snake_case.
        -- RELOCATED and RELOCATED - NEW NUMBER collapsed into
        -- a single 'relocated' value — same concept, different wording.
        -- DECEASED kept — important for risk analysis.
        -- Anything unrecognized becomes null — never assume.
        case
            when remark = 'RELOCATED'                    then 'relocated'
            when remark = 'RELOCATED - NEW NUMBER'       then 'relocated'
            when remark = 'ABSCONDED'                    then 'absconded'
            when remark = 'NO CONTACT'                   then 'no_contact'
            when remark = 'PARTIALLY PAID'               then 'partially_paid'
            when remark = 'PAID IN FULL BUT DEFAULTED'   then 'paid_in_full_but_defaulted'
            when remark = 'YET TO BAL'                   then 'yet_to_balance'
            when remark = 'DECEASED'                     then 'deceased'
            else null
        end                                                 as default_remark,

        -- COUNT
        -- Number of times this borrower has been flagged.
        -- Bronze cast everything to STRING so we cast back to INTEGER.
        -- safe_cast returns null instead of crashing on bad values.
        -- 'nan' (literal text from Bronze) explicitly converted to null first.
        case
            when count = 'nan' then null
            else safe_cast(count as integer)
        end                                                 as flag_count

        -- DROPPED COLUMNS:
        --   sn      → serial number, no analytical value
        --   unnamed → unknown column, predominantly nan

    from source

    -- GHOST ROW FILTER
    -- Same pattern as stg_borrower_profile.
    -- Bronze stored empty cells as literal text "nan".
    -- Filter both that and true nulls.
    where name != 'nan'
      and name is not null

)

select * from cleaned