-- =============================================================================
-- A998 (Spain, ES_2025): what do pupils answer when they get a NINE fact wrong?
-- =============================================================================
-- Sibling of a998_zero_facts_error_answers.sql, same shape, same conventions:
-- one row per (fact, classroom_course_age, user_answer) over the WRONG answers
-- only. Feeds the nine-table panel of fluency_error_types.ipynb.
--
-- WHY A998 AND NOT THE FLUENCY ZONE: same reason as the zero pull is A998 --
-- the point of these two cells is to look at the tables the Fluency figure of
-- this notebook does not cover, using the A998 statements table. Note the
-- Fluency zone DOES have nine cards (its factor inventory runs 1-12), so a
-- Fluency counterpart of this figure is possible; it is simply not this file.
--
-- ORIENTATIONS MERGED: lo = LEAST, hi = GREATEST, so 9x7 and 7x9 land in the
-- same row (lo = 7, hi = 9). Same choice as the zero pull and as the sibling
-- Fluency figure; it doubles the n per panel. The orientations do differ a
-- little in A998 (see a998_commutativity_paired_by_age.sql), so if that
-- asymmetry is ever the question, this is the wrong file to ask it with.
--
-- "THE NINE TABLE" = any fact with a 9 in it, i.e. lo = 9 OR hi = 9. A998's
-- factor inventory runs 0-9 (10x10 heatmap in a998_fact_heatmap_by_age.sql),
-- so in practice this is 0x9 ... 9x9, ten facts. Written as an OR anyway so it
-- keeps working if a factor 10+ ever appears.
--
-- THE ANSWER HERE IS *NOT* A SINGLE DIGIT, UNLIKE THE ZERO PULL: the product of
-- a nine fact is two digits from 2x9 = 18 up, so a one-digit wrong answer is
-- NOT a complete answer -- it is A998 submitting by itself as soon as the first
-- keystroke makes the product impossible (Decision #11), i.e. half an answer.
-- The notebook keeps those bars on the same 0-99 axis as the rest of the
-- figures, does not label them with an operation, and prints how much of the
-- mass they carry so the artefact is visible instead of implicit. The two facts
-- whose product IS one digit (0x9 = 0 and 1x9 = 9) are the exception and the
-- notebook says so where it happens.
--
-- Decisions applied (Learning_Team_Plots/Decisions.txt):
--   #1 A998 only  ·  #2 ages 8-15 (classroom_course_age)  ·  #5 multiplications
--   only  ·  #7 first statement of each pack-sitting dropped (statement_idx >= 1)
--
-- NO RAPID-GUESSING FILTER, deliberately: this file mirrors the zero pull,
-- which has none either, so the two A998 cells of the notebook count the same
-- population. The fast-typing population is not dropped, it is measured -- the
-- notebook prints the median duration of the one-digit answers against the
-- two-digit ones, which is how the zero cell separates "answer" from "keystroke"
-- as well. If you ever want it filtered, copy the NOT (... < 1.2) line from
-- a998_table_difficulty_by_age.sql into `base` and do it in BOTH files.
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

nine_facts AS (
    SELECT * FROM base WHERE lo = 9 OR hi = 9
),

-- Per fact x age: how many attempts and how many of them were wrong. Kept as
-- columns on every row so the notebook can compute both the error rate of the
-- fact and the % that each answer represents WITHIN its wrong answers.
cells AS (
    SELECT lo, hi, age,
           COUNT(*)        AS n_attempts,
           SUM(is_error)   AS n_wrong
    FROM nine_facts
    GROUP BY lo, hi, age
)

SELECT
    z.lo,
    z.hi,
    -- the factor that is NOT the 9 (for 9x9 it is 9 itself): the notebook uses
    -- it to name the panel and to look for "answered the other factor"-type
    -- responses without having to re-derive it.
    CASE WHEN z.hi = 9 THEN z.lo ELSE z.hi END                    AS other_factor,
    z.lo * z.hi                                                   AS product,
    z.age                                                         AS classroom_course_age,
    -- TRY_CAST i no CAST: user_answer es text i A998 hi guarda coses com
    -- '3333339333', que desborda l'INT i (amb ANSI mode) fa petar la query
    -- sencera en lloc de tornar NULL. Trobat el 2026-08-25 executant
    -- justament aquest fitxer.
    TRY_CAST(z.answer AS INT)                                     AS user_answer,
    COUNT(*)                                                      AS n,
    CAST(ROUND(PERCENTILE(z.duration, 0.5), 3) AS DOUBLE)         AS median_duration,
    c.n_attempts,
    c.n_wrong,
    CAST(ROUND(100.0 * c.n_wrong / c.n_attempts, 4) AS DOUBLE)    AS error_pct_cell

FROM nine_facts z
INNER JOIN cells c ON c.lo = z.lo AND c.hi = z.hi AND c.age = z.age

WHERE z.is_error = 1
  AND z.answer IS NOT NULL

GROUP BY z.lo, z.hi, z.age, z.answer, c.n_attempts, c.n_wrong
ORDER BY z.lo, z.hi, z.age, user_answer
