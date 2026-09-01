-- =============================================================================
-- A998 (F2): how many DIFFERENT pupils take the test each week, by academic
-- year and by HEMISPHERE
-- =============================================================================
-- Question (Maria, 2026-08-14): is F2 / A998 really administered three times a
-- year? A weekly count of distinct pupils should show three clean "tongades"
-- (waves) per academic year if it is, and something messier if it is not.
--
-- SCOPE -- deliberately unfiltered.
--   * ALL regions. They are split into two hemisphere groups (below) but no
--     region is dropped.
--   * ALL ages. No join to `fluency_test_metrics`, no `classroom_course_age`
--     filter. This query is about ADMINISTRATION COVERAGE, so Decision #2
--     (ages 8-15) would undercount: a pupil outside 8-15 still took the test.
--   * ALL packs, multiplications AND divisions, first statement INCLUDED
--     (no `statement_idx >= 1`, i.e. Decision #7 is NOT applied). Dropping the
--     first statement of a pack-sitting is a measurement-quality decision for
--     accuracy/RT figures; here it would risk dropping a pupil entirely if that
--     pupil only ever produced one statement.
--
-- HEMISPHERE SPLIT (Maria's choice 2026-08-14: "strictly by hemisphere").
-- The school year runs Sep -> Jun north of the equator and Feb -> Dec south of
-- it, so pooling both into one weekly series superimposes two calendars and
-- makes the waves unreadable. Classification is by LATITUDE ONLY, as asked:
--     southern -> BR, CL
--     northern -> ES, IT, US, MX, CO-A, CO-B, EC-CO, EC-SI
-- Two judgement calls worth knowing before reading the figures:
--   * CO-A / CO-B are Colombia's calendar A (Feb-Nov) and calendar B (Aug-Jun).
--     Colombia is northern, so both sit on the northern axis -- but calendar A
--     runs on a southern-style year, so its waves will look displaced there.
--   * EC-CO / EC-SI are Ecuador's Costa (May-Feb) and Sierra (Sep-Jun) regimes.
--     Ecuador straddles the equator; both are put on the northern axis, and the
--     Costa regime will likewise look displaced.
-- To reclassify, edit the two IN-lists below -- nothing downstream hardcodes
-- which region belongs where. Any region NOT in either list becomes 'unknown'
-- rather than being silently folded into 'northern'; the notebook fails loudly
-- on 'unknown' so a newly onboarded country cannot slip in unclassified.
--
-- GRAIN -- three grains in one result set, distinguished by `grain` +
-- `hemisphere`:
--   grain='week', hemisphere in (northern, southern) -> the bars, one row per
--                 (academic_year, hemisphere, week_start).
--   grain='year', hemisphere in (northern, southern) -> the per-axis
--                 annotation: distinct pupils over the whole year.
--   grain='year', hemisphere='all'                   -> the pooled year total.
-- The 'year' rows exist because COUNT(DISTINCT student_uuid) is NOT additive:
-- a pupil who sits the test in three different waves is counted in three
-- different weekly rows, so summing `n_students` over the weeks OVERCOUNTS the
-- yearly total (roughly 3x if the three-waves hypothesis holds). The yearly
-- total therefore has to be computed by the warehouse over the whole year, and
-- cannot be derived in pandas from the weekly rows. Same reason the
-- hemisphere='all' row is not just northern + southern: it would only coincide
-- if no pupil ever appeared in both groups, which is an assumption, not a fact.
--
-- WEEK DEFINITION: `DATE_TRUNC('WEEK', response_at)` -- Spark weeks start on
-- MONDAY, so `week_start` is the Monday of the week the sitting happened in.
-- Beware `response_at` is session-level, not statement-level (all statements of
-- one sitting share the same timestamp) -- irrelevant for weekly binning, but
-- it does mean `n_statements` is not an independent time series.
--
-- ACADEMIC YEAR: `academic_year_id` is "<REGION>_<YEAR>" (ES_2025, MX_2025,
-- CO-A_2024, ...), so the year is the 4-digit suffix and the region is the
-- prefix. Academic year 2025 = the 2025-26 course in the north, the 2025
-- calendar course in the south. That mismatch is exactly why each figure draws
-- the full Jan <Y> -> Dec <Y+1> window on both axes: whichever hemisphere you
-- look at, its whole course fits inside it.
--
-- All years are returned; the notebook decides which to plot. Expect ES_2022
-- and ES_2023 to be thin (see the wave-coverage note in the repo memory:
-- only 2025 has a genuine 3/3-wave pattern in ES).
-- =============================================================================

WITH stmts AS (
    SELECT
        CAST(REGEXP_EXTRACT(s.academic_year_id, '_([0-9]{4})$', 1) AS INT) AS academic_year,
        REGEXP_EXTRACT(s.academic_year_id, '^(.+)_[0-9]{4}$', 1)           AS region,
        s.student_uuid,
        CAST(DATE_TRUNC('WEEK', s.response_at) AS DATE)                    AS week_start

    FROM bi_gold_prod.dm_research.fluency_test_statements s

    WHERE s.activity_codename = 'A998'
      AND s.response_at      IS NOT NULL
      AND s.student_uuid     IS NOT NULL
),

tagged AS (
    SELECT
        *,
        CASE
            WHEN region IN ('BR', 'CL')                                            THEN 'southern'
            WHEN region IN ('ES', 'IT', 'US', 'MX', 'CO-A', 'CO-B', 'EC-CO', 'EC-SI') THEN 'northern'
            ELSE 'unknown'
        END AS hemisphere
    FROM stmts
)

-- weekly bars, per hemisphere
SELECT
    'week'                                              AS grain,
    academic_year,
    hemisphere,
    week_start,
    COUNT(DISTINCT student_uuid)                        AS n_students,
    COUNT(DISTINCT region)                              AS n_regions,
    CONCAT_WS(',', SORT_ARRAY(COLLECT_SET(region)))     AS regions,
    COUNT(*)                                            AS n_statements
FROM tagged
GROUP BY academic_year, hemisphere, week_start

UNION ALL

-- yearly totals, per hemisphere (the per-axis annotation)
SELECT
    'year'                                              AS grain,
    academic_year,
    hemisphere,
    CAST(NULL AS DATE)                                  AS week_start,
    COUNT(DISTINCT student_uuid)                        AS n_students,
    COUNT(DISTINCT region)                              AS n_regions,
    CONCAT_WS(',', SORT_ARRAY(COLLECT_SET(region)))     AS regions,
    COUNT(*)                                            AS n_statements
FROM tagged
GROUP BY academic_year, hemisphere

UNION ALL

-- yearly totals, both hemispheres pooled
SELECT
    'year'                                              AS grain,
    academic_year,
    'all'                                               AS hemisphere,
    CAST(NULL AS DATE)                                  AS week_start,
    COUNT(DISTINCT student_uuid)                        AS n_students,
    COUNT(DISTINCT region)                              AS n_regions,
    CONCAT_WS(',', SORT_ARRAY(COLLECT_SET(region)))     AS regions,
    COUNT(*)                                            AS n_statements
FROM tagged
GROUP BY academic_year

ORDER BY academic_year, hemisphere, grain, week_start
