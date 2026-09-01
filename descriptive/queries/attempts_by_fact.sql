-- =============================================================================
-- Fluency zone: how practice attempts are distributed across the 144 facts
-- Feeds queries/attempts_by_fact.csv -> attempts_students_heatmaps.png/pdf
--
-- OUTPUT GRAIN: one row per ordered fact (op_a X op_b), 1-12 x 1-12.
--   n_attempts  = card presentations (one row of the table = one card shown)
--   n_students  = distinct pupils who saw that fact at least once
--
-- COUNTING CHOICE: n_attempts counts CARDS, not tries. A card can carry two
-- tries (first_/second_attempt_*), so if you want "answers given" instead,
-- add SUM(CASE WHEN attempt_result <> 'Correct at first' THEN 1 ELSE 0 END)
-- to COUNT(*) -- that is the unpivoted grain used by
-- fluency_hardest_facts_error_answers.sql. Card-level is the right denominator
-- for "how often is this fact practised".
--
-- JOIN GOTCHA: this table joins d_students on student_uuid = student_uuid,
-- NOT on unique_id (the A998 tables are the other way round). The wrong join
-- parses fine and returns zero rows. Historic dimension so an attempt is
-- attributed to the course the pupil was in at the time.
--
-- Decisions applied: #1 (Fluency zone), #2 (ages 8-15; this app in practice
-- only has 8-11), #5 (multiplications only), #8 (ES_2025).
--
-- READ WITH CARE -- THE HEATMAP IS NOT AN EXPOSURE MAP. Fluency is a Leitner
-- system: which cards a pupil sees depends on their own history, so a fact
-- that pupils fail gets shown again and accumulates attempts. High n_attempts
-- therefore mixes "scheduled often" with "failed often", and n_students is the
-- cleaner reach measure of the two panels.
--
-- Markers rewritten by the notebook: -- {YEARS}  -- {AGES}
-- =============================================================================

WITH base AS (
    SELECT
        a.student_uuid,
        TRY_CAST(TRIM(SPLIT(a.operation, 'X')[0]) AS INT) AS op_a,
        TRY_CAST(TRIM(SPLIT(a.operation, 'X')[1]) AS INT) AS op_b

    FROM bi_gold_prod.dwh_digital_practice.f_elementary_fluency_attempts a
    INNER JOIN bi_gold_prod.dwh_global_dimensions_historic.d_students s
            ON s.student_uuid     = a.student_uuid
           AND s.academic_year_id = a.academic_year_id

    WHERE a.academic_year_id IN ('ES_2025')       -- {YEARS}
      AND a.operation_type = 'multiplication'     -- Decision #5
      AND s.classroom_course_age BETWEEN 8 AND 15 -- {AGES}
)

SELECT
    CONCAT(CAST(op_a AS STRING), ' X ', CAST(op_b AS STRING)) AS operation,
    COUNT(*)                        AS n_attempts,
    COUNT(DISTINCT student_uuid)    AS n_students
FROM base
WHERE op_a BETWEEN 1 AND 12
  AND op_b BETWEEN 1 AND 12
GROUP BY op_a, op_b
ORDER BY op_a, op_b