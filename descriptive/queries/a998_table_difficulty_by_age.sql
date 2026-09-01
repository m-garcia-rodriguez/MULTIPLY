-- =============================================================================
-- A998 (Spain 2025-26): which multiplication table is hardest, by classroom age
-- =============================================================================
-- Aggregated server-side (not a per-statement pull -- ~5.2M qualifying rows,
-- consistent with every other CSV in queries/ being pre-aggregated). Grain of
-- the OUTPUT is one row per (definition, table, classroom_course_age).
--
-- `operation` format (confirmed live on 2026-07-29, see fluency-test-
-- statements-columns memory + direct probe): "F1<sep>F2", single-digit
-- factors 0-9, string length always 3 for multiplications. Divisions use ':'.
--
-- >>> SEPARATOR GOTCHA (extends the one already on record): a full scan of
--     ES_2025 A998 multiplications found TWO distinct symbols in live use,
--     never mixed within one string: U+00D7 '×' (4,392,832 rows) and U+00B7
--     '·' MIDDLE DOT (1,047,045 rows -- 19% of all multiplications, not a
--     rounding error). Splitting on '×' alone silently CAST-fails on every
--     '·' row ([CAST_INVALID_INPUT], confirmed by running this query
--     unguarded). Both are normalized to '×' before splitting.
--
-- THREE DEFINITIONS OF "taula del X", built from the SAME base rows via
-- UNION ALL so the notebook never has to reconcile them by hand:
--   'either'  -- X is EITHER factor (commutative view). A fact with
--               factor_1 <> factor_2 (e.g. 8×7) is counted once under table 8
--               AND once under table 7. A fact with factor_1 = factor_2
--               (e.g. 6×6) is counted only once, not twice.
--   'first'   -- X is strictly factor_1 (e.g. 8×7 counts for table 8 only)
--   'second'  -- X is strictly factor_2 (e.g. 8×7 counts for table 7 only)
-- The commutative-ASYMMETRY question itself (does 8×7 behave differently from
-- 7×8?) is deliberately NOT answered here -- that comes later.
--
-- Decisions applied (Learning_Team_Plots/Decisions.txt):
--   #1 A998 only
--   #2 ages 8-15 (classroom_course_age)
--   #5 multiplication only for table classification (operation NOT LIKE '%:%')
--   #7 first statement of each pack-sitting (statement_idx = 0) dropped -- same
--      countdown/orientation bias documented for the per-minute rate; applied
--      here for consistency even though this pull is not a per-minute rate.
--
-- Age source: classroom_course_age lives on fluency_test_metrics, NOT on
-- fluency_test_statements (see fluency-test-statements-columns memory).
-- Joined on metric_id, confirmed unique per row in fluency_test_metrics
-- (399,546 rows / 399,546 distinct metric_id for A998 x ES_2025 on 2026-07-29).
--
-- ERROR RATE: 'Incorrect' and 'Help' both count as an error ('Help' means the
-- pupil could not answer unaided). error_rate = n_error / n.
--
-- RESPONSE TIME: mean_rt is computed over CORRECT answers only, following
-- rt_A998_answers.sql's convention (an incorrect answer given quickly is not
-- evidence of fluency, and 'Help' has no meaningful independent RT).
--
-- CAVEAT the notebook must print: packs differ by age x trimester (Decision
-- #4), so not every table is practiced at every age (e.g. age 8 T1 only sees
-- tables 2 and 5) -- a missing or thin line for a table at a young age is
-- curriculum, not necessarily a data problem. Check `n` before trusting a
-- point.
--
-- RAPID-GUESSING FILTER (Maria, 2026-08-13): drop Incorrect/Help answers under
-- 1.2s, to keep the "hardest table/fact" ranking from being contaminated by
-- disengaged rapid guesses.
-- >>> READ BEFORE TRUSTING THE RESULT: this filter is NOT symmetric. It only
--     ever removes rows from the WRONG side (is_error = 1) and never touches a
--     fast CORRECT answer. Algebraically, dropping F fast-wrong rows takes
--     error_rate from W/N to (W-F)/(N-F), which is provably <= W/N for any
--     F > 0 -- i.e. this filter can only ever LOWER a cell's computed error
--     rate, never raise it, and it lowers it MORE for cells with more fast
--     guessing. That is the opposite of neutral cleaning: it is exactly the
--     "hardest fact" signal this notebook exists to measure, so a table/fact
--     that attracts a lot of rapid guessing will look artificially easier
--     after this filter, not just "cleaner". Also note 1.2s is Maria's number,
--     not the 1.5s antimode threshold already established for A998 racing
--     detection (see a998-endofpack-keyboard-noise / Decision #12) -- that
--     threshold is a SITTING-level flag (median RT < 1.5s AND accuracy < 25%
--     for the whole session+pack), a different and more defensible construct
--     than a flat per-answer time cutoff.
-- If a symmetric version is wanted instead (drop fast answers regardless of
-- correctness -- still not sitting-level, but at least not one-directional),
-- replace the line below with:
--   AND NOT (s.statement_seconds_spent < 1.2)
--
-- Scope: academic_year_id = 'ES_2025' (Spain, current year) only.
-- =============================================================================

WITH base AS (
    SELECT
        CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[0] AS INT) AS factor_1,
        CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[1] AS INT) AS factor_2,
        m.classroom_course_age                                      AS age,
        CASE WHEN s.statement_result IN ('Incorrect', 'Help')
             THEN 1 ELSE 0 END                                      AS is_error,
        CASE WHEN s.statement_result = 'Correct'
             THEN 1 ELSE 0 END                                      AS is_correct,
        s.statement_seconds_spent                                   AS rt_seconds

    FROM bi_gold_prod.dm_research.fluency_test_statements s
    INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
            ON m.metric_id = s.metric_id

    WHERE s.activity_codename        = 'A998'
      AND s.academic_year_id         = 'ES_2025'
      AND s.operation NOT LIKE '%:%'          -- multiplications only (Decision #5)
      AND s.statement_idx           >= 1      -- drop first statement (Decision #7)
      AND s.statement_seconds_spent IS NOT NULL
      AND m.classroom_course_age BETWEEN 8 AND 15   -- Decision #2
      AND NOT (s.statement_result IN ('Incorrect', 'Help') AND s.statement_seconds_spent < 1.2)  -- rapid-guessing filter, see caveat above
),

long AS (
    SELECT 'first'  AS definition, factor_1 AS tbl, age, is_error, is_correct, rt_seconds FROM base
    UNION ALL
    SELECT 'second' AS definition, factor_2 AS tbl, age, is_error, is_correct, rt_seconds FROM base
    UNION ALL
    SELECT 'either'  AS definition, factor_1 AS tbl, age, is_error, is_correct, rt_seconds FROM base
    UNION ALL
    SELECT 'either'  AS definition, factor_2 AS tbl, age, is_error, is_correct, rt_seconds
    FROM base WHERE factor_1 <> factor_2          -- avoid double-counting e.g. 6x6
)

SELECT
    definition,
    tbl                                              AS mult_table,
    age                                              AS classroom_course_age,
    COUNT(*)                                         AS n,
    SUM(is_error)                                    AS n_error,
    ROUND(SUM(is_error) / COUNT(*), 4)               AS error_rate,
    SUM(is_correct)                                  AS n_correct,
    ROUND(AVG(CASE WHEN is_correct = 1 THEN rt_seconds END), 4) AS mean_rt

FROM long
GROUP BY definition, tbl, age
ORDER BY definition, tbl, age
