-- =============================================================================
-- Same as the Fluency base query, capped to N rows PER MULTIPLICATION FACT
-- (factor_1, factor_2) -- not per region, not per age, just per fact -- to
-- keep the download size bounded. 144 facts currently exist for Fluency
-- multiplications; every one already exceeds 100,000 rows, so this cap bites
-- everywhere (checked live 2026-08-13: min 210k, max 915k, avg 471k card-rows
-- per fact, before the attempt-unpivot below roughly doubles it).
--
-- SAMPLE, NOT TOP-N: ordering by HASH(...) instead of e.g. rt_seconds or
-- attempt_at means the 100k kept per fact are a reproducible pseudo-random
-- sample, not "the first 100k chronologically" or "the fastest/slowest" --
-- either of those would bias whatever you compute afterward. HASH is
-- deterministic, so re-running this query returns the exact same 100k rows
-- each time (good for cached_query() and for reproducing a threshold later),
-- unlike RAND() which would reshuffle on every run.
--
-- WHAT THIS DOES NOT DO: it doesn't make Databricks scan less data --
-- ROW_NUMBER still has to rank every row in a fact before it can tell which
-- ones are the first 100,000, so compute cost is roughly the same as the
-- uncapped query. What shrinks is the SIZE OF THE RESULT SET you pull down
-- afterward, which is what was slow.
--
-- BALANCE ACROSS REGIONS: a flat per-fact cap keeps each region's NATURAL
-- share -- ES is ~55-60% of Fluency multiplication volume, so ES will be
-- ~55-60% of each fact's 100k sample too, same as it would be uncapped, just
-- scaled down. If you instead want EQUAL sample sizes per region (or per
-- region x age) for a fair cross-region comparison, change the PARTITION BY
-- below to (region, classroom_course_age, factor_1, factor_2) and lower N
-- accordingly -- with ~11 regions x ~4 ages x 144 facts, even 1,000 rows per
-- cell is already ~6M rows total.
-- =============================================================================

WITH base AS (
    SELECT
        REGEXP_EXTRACT(a.academic_year_id, '^(.+)_[0-9]{4}$', 1)  AS region,
        a.academic_year_id,
        s.classroom_course_age,
        a.student_uuid,
        a.elementary_fluency_session_uuid,
        a.elementary_fluency_attempt_uuid,
        a.operation                                               AS operation_raw,
        TRY_CAST(TRIM(SPLIT(a.operation, 'X')[0]) AS INT)          AS factor_1,
        TRY_CAST(TRIM(SPLIT(a.operation, 'X')[1]) AS INT)          AS factor_2,
        a.attempt_result,
        a.first_attempt_duration,
        a.second_attempt_duration

    FROM bi_gold_prod.dwh_digital_practice.f_elementary_fluency_attempts a
    INNER JOIN bi_gold_prod.dwh_global_dimensions_historic.d_students s
            ON s.student_uuid     = a.student_uuid
           AND s.academic_year_id = a.academic_year_id

    WHERE a.operation_type = 'multiplication'
),

attempts AS (
    SELECT
        region, academic_year_id, classroom_course_age, student_uuid,
        elementary_fluency_session_uuid, elementary_fluency_attempt_uuid,
        operation_raw, factor_1, factor_2,
        1                                                              AS attempt_no,
        attempt_result,
        CASE WHEN attempt_result = 'Correct at first' THEN 1 ELSE 0 END AS is_correct,
        CAST(first_attempt_duration AS DOUBLE)                        AS rt_seconds
    FROM base
    WHERE first_attempt_duration IS NOT NULL

    UNION ALL

    SELECT
        region, academic_year_id, classroom_course_age, student_uuid,
        elementary_fluency_session_uuid, elementary_fluency_attempt_uuid,
        operation_raw, factor_1, factor_2,
        2                                                              AS attempt_no,
        attempt_result,
        CASE WHEN attempt_result = 'Correct at second' THEN 1 ELSE 0 END AS is_correct,
        CAST(second_attempt_duration AS DOUBLE)                       AS rt_seconds
    FROM base
    WHERE attempt_result <> 'Correct at first'
      AND second_attempt_duration IS NOT NULL
),

capped AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY factor_1, factor_2
            ORDER BY HASH(elementary_fluency_attempt_uuid, attempt_no)  -- deterministic pseudo-random
        ) AS rn
    FROM attempts
)

SELECT
    region, academic_year_id, classroom_course_age, student_uuid,
    elementary_fluency_session_uuid, elementary_fluency_attempt_uuid,
    operation_raw, factor_1, factor_2, attempt_no, attempt_result,
    is_correct, rt_seconds
FROM capped
WHERE rn <= 100000        -- <- the cap; change this one number to adjust it
ORDER BY factor_1, factor_2, region, academic_year_id, classroom_course_age, rn