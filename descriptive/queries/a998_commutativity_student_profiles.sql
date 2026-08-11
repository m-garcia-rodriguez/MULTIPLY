-- =============================================================================
-- A998: per-pupil response PROFILES for the commutativity permutation test
-- =============================================================================
-- WHY THIS FILE EXISTS. a998_commutativity_paired_by_age.sql already returns the
-- averages (mean_diff, mean_abs_diff, the four pupil shares). Averages cannot be
-- permuted -- a randomization test needs the per-pupil numbers that go INTO the
-- average. This query returns exactly those, for the same population, same
-- filters and same inclusion rule, so the two files must agree when this one is
-- averaged (the notebook asserts it).
--
-- OUTPUT GRAIN: one row per (year, pair, age, RESPONSE PROFILE), where a profile
-- is the quadruple (n_bf, ok_bf, n_bs, ok_bs) = attempts and hits in each
-- direction. n_students counts the pupils sharing that profile.
--
-- WHY PROFILES INSTEAD OF ONE ROW PER PUPIL. The permutation being run (NULL A,
-- see the notebook markdown) only ever looks at those four numbers, never at
-- WHICH pupil produced them. With ~1 attempt per direction the quadruple takes
-- very few distinct values, so collapsing to profiles is lossless for this test
-- and turns ~660k rows into ~15k: a small CSV, a fast query, and no pupil
-- identifiers written to disk. The notebook expands the profiles back with
-- np.repeat(..., n_students) before permuting, so every pupil is still drawn
-- independently.
-- (It is lossless ONLY because the statistic is a per-pupil function of the
-- quadruple. A test that needed to pool a pupil's attempts ACROSS pairs -- the
-- null for mean_abs_diff -- would need student_uuid back in the GROUP BY.)
--
-- Every filter below is copied verbatim from a998_commutativity_paired_by_age.sql
-- (Decisions #1, #2, #5, #7; '·'/'×' separator gotcha; squares excluded; 'Help'
-- counts as not correct). The two marked lines are rewritten by the notebook:
--   -- {YEARS}          academic year list (default ES_2025, Decision #8)
--   -- {MIN_ATTEMPTS}   minimum attempts per direction (default 1)
-- If either marker drifts, the notebook fails loudly rather than running a
-- population different from the one it is comparing against.
-- =============================================================================

WITH base AS (
    SELECT
        s.student_uuid,
        s.academic_year_id,
        CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[0] AS INT) AS f1,
        CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[1] AS INT) AS f2,
        m.classroom_course_age                                      AS age,
        CASE WHEN s.statement_result = 'Correct' THEN 1 ELSE 0 END  AS is_correct

    FROM bi_gold_prod.dm_research.fluency_test_statements s
    INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
            ON m.metric_id = s.metric_id

    WHERE s.activity_codename        = 'A998'
      AND s.academic_year_id IN ('ES_2025')   -- {YEARS}
      AND s.operation NOT LIKE '%:%'          -- multiplications only (Decision #5)
      AND s.statement_idx           >= 1      -- drop first statement (Decision #7)
      AND s.statement_seconds_spent IS NOT NULL
      AND m.classroom_course_age BETWEEN 8 AND 15   -- Decision #2
),

tagged AS (
    SELECT
        student_uuid,
        academic_year_id,
        age,
        LEAST(f1, f2)                                            AS lo,
        GREATEST(f1, f2)                                         AS hi,
        CASE WHEN f1 >= f2 THEN 'big_first' ELSE 'big_second' END AS direction,
        is_correct
    FROM base
    WHERE f1 <> f2        -- squares have no second direction
),

per_student_pair AS (
    SELECT
        student_uuid,
        academic_year_id,
        age,
        lo,
        hi,
        SUM(CASE WHEN direction = 'big_first'  THEN 1 ELSE 0 END) AS n_bf,
        SUM(CASE WHEN direction = 'big_second' THEN 1 ELSE 0 END) AS n_bs,
        SUM(CASE WHEN direction = 'big_first'  THEN is_correct ELSE 0 END) AS ok_bf,
        SUM(CASE WHEN direction = 'big_second' THEN is_correct ELSE 0 END) AS ok_bs
    FROM tagged
    GROUP BY student_uuid, academic_year_id, age, lo, hi
    HAVING SUM(CASE WHEN direction = 'big_first'  THEN 1 ELSE 0 END) >= 1  -- {MIN_ATTEMPTS}
       AND SUM(CASE WHEN direction = 'big_second' THEN 1 ELSE 0 END) >= 1  -- {MIN_ATTEMPTS}
)

SELECT
    academic_year_id,
    lo,
    hi,
    age          AS classroom_course_age,
    n_bf,
    ok_bf,
    n_bs,
    ok_bs,
    COUNT(*)     AS n_students
FROM per_student_pair
GROUP BY academic_year_id, lo, hi, age, n_bf, ok_bf, n_bs, ok_bs
ORDER BY academic_year_id, lo, hi, age, n_bf, ok_bf, n_bs, ok_bs
