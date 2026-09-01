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
-- FAST WRONG ANSWERS: THE PUPIL IS DROPPED (added 2026-08-25, Maria) --------
-- A wrong answer under 1.5 s is not an error about the fact, it is a guess or a
-- stray keypress. Decision: exclude the whole PUPIL (within the academic year)
-- as soon as they produce ONE such answer, rather than dropping that attempt or
-- that sitting. Implemented as `fast_wrong` (per attempt) -> `has_fast_wrong`
-- (per pupil, window) -> the marked filter line inside `tagged`.
--   -- {FAST_WRONG_RT}      threshold in seconds (notebook: FAST_WRONG_MAX_RT)
--   -- {FAST_WRONG_FILTER}  `has_fast_wrong = 0` filters, `1 = 1` keeps everyone
-- Both markers are rewritten by commutativity.ipynb (cell 0: EXCLUDE_FAST_WRONG_
-- STUDENTS, FAST_WRONG_MAX_RT) exactly like -- {YEARS} and -- {MIN_ATTEMPTS};
-- the literals below are the DEFAULT so this file still runs standalone.
--
-- READ THIS BEFORE READING ANY TREND. The filter selects on the OUTCOME (being
-- wrong), so the pupils that survive it are by construction more accurate than
-- the population: every level in the output moves up and none of that movement
-- is learning. Worse for age trends -- guessing is not equally common at every
-- age, so the share of pupils removed varies by age, and part of any age curve
-- becomes "who survived the filter" instead of "who knows the fact". The
-- notebook prints the per-age drop rate next to the results for this reason.
-- The rule also cannot tell a guess from a genuinely fast slip on an easy fact.
-- =============================================================================

WITH base AS (
    SELECT
        s.student_uuid,
        s.academic_year_id,
        CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[0] AS INT) AS f1,
        CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[1] AS INT) AS f2,
        m.classroom_course_age                                      AS age,
        CASE WHEN s.statement_result = 'Correct' THEN 1 ELSE 0 END  AS is_correct,

        -- FAST WRONG ANSWER (added 2026-08-25): a wrong answer given in under
        -- FAST_WRONG_MAX_RT seconds. 'Correct' is tested FIRST so a fast RIGHT
        -- answer is never flagged; anything that is not 'Correct' (including
        -- 'Help', which counts as wrong everywhere in this analysis) and lands
        -- under the threshold is. A NULL statement_result falls in the second
        -- branch, the same convention as is_correct above.
        CASE WHEN s.statement_result = 'Correct' THEN 0
             WHEN s.statement_seconds_spent < 1.5   -- {FAST_WRONG_RT}
             THEN 1 ELSE 0 END                                       AS fast_wrong

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

-- ONE FLAG PER PUPIL (added 2026-08-25): did this pupil EVER answer wrong in
-- under the threshold, anywhere in this year's A998 multiplications? The
-- decision (Maria, 2026-08-25) is to drop the PUPIL, not the attempt: a pupil
-- who guesses is treated as not having been measured, so none of their other
-- attempts enters any pair either.
-- The window spans everything `base` returns for that pupil in that academic
-- year -- including the squares that `tagged` drops below -- because the
-- question is about the pupil's behaviour, not about one pair. The year is in
-- the partition for the same reason it is in the pairing key: a repeater must
-- not lose their ES_2025 attempts because of an ES_2024 guess.
fast_wrong_flag AS (
    SELECT
        b.*,
        MAX(fast_wrong) OVER (PARTITION BY student_uuid, academic_year_id) AS has_fast_wrong
    FROM base b
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
    FROM fast_wrong_flag
    WHERE f1 <> f2        -- squares have no second direction
      AND has_fast_wrong = 0   -- {FAST_WRONG_FILTER}
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
