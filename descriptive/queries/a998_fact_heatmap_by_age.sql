-- =============================================================================
-- A998 (Spain 2025-26): which INDIVIDUAL fact (a x b) is hardest, by classroom age
-- =============================================================================
-- Finer grain than a998_table_difficulty_by_age.sql: one row per
-- (factor_1, factor_2, classroom_course_age), not per table. Feeds a 10x10
-- heatmap (a on one axis, b on the other) per age. Because factor_1/factor_2
-- are kept in their ORIGINAL order (no "either" merge), 8x7 and 7x8 land in
-- different cells -- this is the natural setup for the commutative-asymmetry
-- question deferred earlier, even though this pull does not analyze it yet.
--
-- Same separator gotcha as a998_table_difficulty_by_age.sql: multiplications
-- use both U+00D7 '×' and U+00B7 '·' live in the data; both normalized to '×'
-- before splitting. See that file / a998-pack-reference memory for the full
-- writeup (19% of multiplication rows use '·').
--
-- Decisions applied (Learning_Team_Plots/Decisions.txt):
--   #1 A998 only  ·  #2 ages 8-15 (classroom_course_age)  ·  #5 multiplication
--   only  ·  #7 first statement of each pack-sitting dropped
--
-- error_rate = (Incorrect + Help) / n  (same convention as the table-level pull)
-- median_rt  = MEDIAN statement_seconds_spent, CORRECT answers only (per
--   2026-07-29 decision: consistent with rt_A998_answers.sql and with
--   a998_table_difficulty_by_age.sql's mean_rt, just median instead of mean
--   here since per-fact cells are noisier and RT is right-skewed).
--
-- Scope: academic_year_id = 'ES_2025' only.
--
-- RAPID-GUESSING FILTER (Maria, 2026-08-13): same filter and same caveat as
-- a998_table_difficulty_by_age.sql -- drops Incorrect/Help answers under
-- 1.2s, which is ONE-DIRECTIONAL (only ever removes wrong rows, never fast
-- correct ones) and so can only ever LOWER a cell's error_rate, more so for
-- cells with more fast guessing. See that file for the full writeup and for
-- the symmetric-filter alternative (drop fast answers regardless of
-- correctness) if that is wanted instead.
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
)

SELECT
    factor_1,
    factor_2,
    age                                              AS classroom_course_age,
    COUNT(*)                                         AS n,
    SUM(is_error)                                    AS n_error,
    ROUND(SUM(is_error) / COUNT(*), 4)               AS error_rate,
    SUM(is_correct)                                  AS n_correct,
    ROUND(PERCENTILE(CASE WHEN is_correct = 1 THEN rt_seconds END, 0.5), 4) AS median_rt

FROM base
GROUP BY factor_1, factor_2, age
ORDER BY factor_1, factor_2, age
