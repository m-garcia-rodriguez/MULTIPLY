-- =============================================================================
-- A998 (Spain, ES_2025): per-PUPIL speed and accuracy, by classroom age
-- =============================================================================
-- One row per (student, classroom_course_age). Feeds the course-by-course
-- statistics figures in curso-a-curso.ipynb: median response time per pupil and
-- error rate per pupil, summarised as median + Q1-Q3 per course, plus the
-- distribution overlap between the youngest and the oldest course.
--
-- Replaces the Fluency-zone CSV the original figure used
-- (MULTIPLY_old/queries/student_rt_by_age.csv, columns median_rt / err_rate,
-- facts up to 12, first-attempt logic). That CSV has no recoverable query, and
-- it is a DIFFERENT construct: Fluency gives the pupil a second attempt, so its
-- "error rate" is a first-attempt error rate and its RT is a first-attempt RT.
-- A998 is a single pass, so here:
--   error rate  = (Incorrect + Help) / n statements     -- same convention as
--                 a998_fact_heatmap_by_age.sql and a998_table_difficulty_by_age.sql
--   median_rt   = MEDIAN statement_seconds_spent over CORRECT answers ONLY
--                 (2026-07-29 decision, consistent with rt_A998_answers.sql:
--                 a fast wrong answer is not evidence of fluency)
--
-- Grain note: aggregated over ALL of the pupil's A998 sittings in the year, not
-- per sitting -- one number per pupil, which is what a per-pupil distribution
-- needs. Grouping by (student, age) rather than student alone would split a
-- pupil who changed classroom age mid-year; checked at age 8, where
-- COUNT(*) = COUNT(DISTINCT student_uuid) = 27,543, so this does not happen in
-- practice for ES_2025.
--
-- Decisions applied (Learning_Team_Plots/Decisions.txt):
--   #1 A998 only  ·  #2 ages 8-15 (classroom_course_age)  ·  #7 first statement
--   of each pack-sitting dropped (statement_idx >= 1)
-- Multiplications only (operation NOT LIKE '%:%'), to keep this figure about the
-- multiplication table like every other A998 figure in the poster. Decision #5
-- would also allow divisions -- drop the filter to include them.
--
-- MIN_STATEMENTS = 10, and NO minimum on correct answers. A per-pupil median
-- over 3 statements is noise, so pupils with fewer than 10 statements are
-- excluded here (19,488 of 152,065 pupils at ages 8-12, checked live
-- 2026-08-12 -- this is an active filter, not a formality).
--
-- Deliberately NOT filtered on n_correct: an EARLIER version of this query also
-- required 5 correct answers, which biased the error-rate panel badly. A pupil
-- with fewer than 5 correct answers is a pupil who got almost everything wrong,
-- so excluding them removes exactly the highest-error pupils -- and it hits the
-- youngest course hardest (2,957 pupils at age 8 vs 213 at age 12). Measured
-- effect on the median error rate at age 8: 34.5% without the guard, 29.4% with
-- it, a 5.1 pp optimistic bias, against 0.2-0.7 pp at ages 10-12.
-- The error rate needs no correct answers to be defined, so it must use every
-- pupil. `median_rt` DOES need them: it is NULL (0 correct) or noisy (1-4
-- correct) for those pupils, so the notebook -- not this query -- applies
-- `n_correct >= 5` to the response-time panel only. That is why both `n` and
-- `n_correct` are returned: the two panels have different denominators, and the
-- notebook prints both.
--
-- CAST AS DOUBLE on the percentage: 100.0 * SUM(...) / COUNT(*) comes back as
-- DECIMAL from Spark and then as decimal.Decimal objects in pandas, which
-- breaks numpy (np.percentile, np.linspace on the column). cached_query.py also
-- normalises this now, but casting here keeps the query correct on its own.
-- =============================================================================

WITH stmts AS (
    SELECT
        m.student_uuid,
        m.classroom_course_age                                  AS age,
        CASE WHEN s.statement_result IN ('Incorrect', 'Help')
             THEN 1 ELSE 0 END                                  AS is_error,
        CASE WHEN s.statement_result = 'Correct'
             THEN 1 ELSE 0 END                                  AS is_correct,
        s.statement_seconds_spent                               AS rt_seconds

    FROM bi_gold_prod.dm_research.fluency_test_statements s
    INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
            ON m.metric_id = s.metric_id

    WHERE s.activity_codename        = 'A998'
      AND s.academic_year_id         = 'ES_2025'
      AND s.operation NOT LIKE '%:%'          -- multiplications only
      AND s.statement_idx           >= 1      -- drop first statement (Decision #7)
      AND s.statement_seconds_spent IS NOT NULL
      AND m.classroom_course_age BETWEEN 8 AND 15   -- Decision #2
)

SELECT
    student_uuid,
    age                                                          AS classroom_course_age,
    COUNT(*)                                                     AS n,
    SUM(is_error)                                                AS n_error,
    SUM(is_correct)                                              AS n_correct,
    CAST(100.0 * SUM(is_error) / COUNT(*) AS DOUBLE)             AS err_pct,
    PERCENTILE(CASE WHEN is_correct = 1 THEN rt_seconds END, 0.5) AS median_rt

FROM stmts
GROUP BY student_uuid, age
HAVING COUNT(*) >= 10
ORDER BY age, student_uuid
