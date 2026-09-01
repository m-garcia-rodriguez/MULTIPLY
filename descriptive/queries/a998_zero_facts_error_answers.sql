-- =============================================================================
-- A998 (Spain, ES_2025): what do pupils answer when the fact contains a ZERO?
-- =============================================================================
-- One row per (fact, classroom_course_age, user_answer) over the WRONG answers
-- only. Feeds the zero-facts panel of fluency_error_types.ipynb, which is the
-- A998 counterpart of the Fluency-zone figure in the same notebook.
--
-- WHY A998 AND NOT THE FLUENCY ZONE: the Fluency zone has no zero cards at all.
-- Checked live 2026-08-12 on f_elementary_fluency_attempts: filtering either
-- factor to 0 returns zero rows, and the factor inventory runs 1-12. So the
-- figure the Fluency query feeds cannot answer this question, and this pull uses
-- the A998 statements table instead.
--
-- ORIENTATIONS MERGED: lo = LEAST, hi = GREATEST, so 7x0 and 0x7 land in the
-- same row (lo = 0, hi = 7). The two orientations do differ a little -- Nx0 is
-- ~4 pp more error-prone than 0xN -- but merging is what the sibling Fluency
-- figure does, and it doubles the n per panel.
--
-- THE ANSWER IS A SINGLE DIGIT, AND THAT IS NOT A BUG: the product of any zero
-- fact is 0, so the first keystroke that is not 0 already makes the result
-- impossible and A998 submits the answer by itself. What gets recorded is that
-- first digit. Measured over ages 9-11: 79,522 wrong answers, of which 3 are
-- above 9 and 96 are NULL. So the x axis of the figure runs 1-9 and it shows a
-- distribution of FIRST DIGITS, not of complete answers -- a pupil who meant to
-- type 10 appears as a 1. Note this is the same keystroke mechanism that makes
-- two-digit A998 answers unreliable, except here it costs nothing, because a
-- one-digit answer has no second digit to lose.
--
-- Decisions applied (Learning_Team_Plots/Decisions.txt):
--   #1 A998 only  ·  #2 ages 8-15 (classroom_course_age)  ·  #5 multiplications
--   only  ·  #7 first statement of each pack-sitting dropped (statement_idx >= 1)
--
-- error rate = (Incorrect + Help) / n, the same convention as every other A998
-- query in this repo.
--
-- Markers rewritten from the notebook:
--   -- {YEARS}   academic year list (default ES_2025, Decision #8)
--   -- {AGES}    classroom_course_age range (default 8-15, Decision #2)
-- =============================================================================

WITH base AS (
    SELECT
        LEAST(CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[0] AS INT),
              CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[1] AS INT))    AS lo,
        GREATEST(CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[0] AS INT),
                 CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[1] AS INT)) AS hi,
        m.classroom_course_age                                               AS age,
        CASE WHEN s.statement_result IN ('Incorrect', 'Help') THEN 1 ELSE 0 END AS is_error,
        s.user_answer                                                        AS answer,
        s.statement_seconds_spent                                            AS duration

    FROM bi_gold_prod.dm_research.fluency_test_statements s
    INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
            ON m.metric_id = s.metric_id

    WHERE s.activity_codename        = 'A998'
      AND s.academic_year_id IN ('ES_2025')          -- {YEARS}
      AND s.operation NOT LIKE '%:%'                 -- multiplications only
      AND s.statement_idx           >= 1             -- Decision #7
      AND s.statement_seconds_spent IS NOT NULL
      AND m.classroom_course_age BETWEEN 8 AND 15    -- {AGES}
),

zero_facts AS (
    SELECT * FROM base WHERE lo = 0
),

-- Per fact x age: how many attempts and how many of them were wrong. Kept as
-- columns on every row so the notebook can compute both the error rate of the
-- fact and the % that each answer represents WITHIN its wrong answers.
cells AS (
    SELECT lo, hi, age,
           COUNT(*)        AS n_attempts,
           SUM(is_error)   AS n_wrong
    FROM zero_facts
    GROUP BY lo, hi, age
)

SELECT
    z.lo,
    z.hi,
    z.lo * z.hi                                                   AS product,
    z.age                                                         AS classroom_course_age,
    CAST(z.answer AS INT)                                         AS user_answer,
    COUNT(*)                                                      AS n,
    CAST(ROUND(PERCENTILE(z.duration, 0.5), 3) AS DOUBLE)         AS median_duration,
    c.n_attempts,
    c.n_wrong,
    CAST(ROUND(100.0 * c.n_wrong / c.n_attempts, 4) AS DOUBLE)    AS error_pct_cell

FROM zero_facts z
INNER JOIN cells c ON c.lo = z.lo AND c.hi = z.hi AND c.age = z.age

WHERE z.is_error = 1
  AND z.answer IS NOT NULL

GROUP BY z.lo, z.hi, z.age, z.answer, c.n_attempts, c.n_wrong
ORDER BY z.hi, z.age, user_answer
