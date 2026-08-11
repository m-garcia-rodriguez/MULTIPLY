-- =============================================================================
-- A998 (Spain, 2025-26): operations PER MINUTE per pack-sitting, both age views
-- =============================================================================
-- Feeds the boxplot of operations per minute, comparable four ways from one pull:
--     age definition : student_course_age   vs   classroom_course_age
--     scoring        : corrected (correct - incorrect)   vs   raw correct
-- split by trimester within each age.
--
-- Grain  : ONE ROW PER PACK-SITTING = (session_id, activity_pack).
--          A sitting can hold several packs, so this is not one row per test.
--
-- DECISION #7 -- THE FIRST STATEMENT IS DROPPED ------------------------------
-- statement_idx = 0 is excluded from both the numerator and the denominator: it
-- is not representative of the pupil's level. Counting starts at the SECOND
-- statement (statement_idx >= 1), and the denominator is the summed time of
-- exactly those statements, so numerator and denominator always cover the same
-- items.
-- This is also principled rather than cosmetic: statement_seconds_spent for
-- idx = 0 measures pack start -> first answer, so it absorbs the countdown and
-- the pupil orienting themselves. Leaving it in inflates the denominator and
-- drags every rate down, most severely for the youngest pupils.
--
--   Denominator = the summed time of those same statements (idx >= 1). Plain and
--   simple, no further conditions:
--       ops_per_min = (n_correct - n_incorrect) / (seconds(idx >= 1) / 60)
--
-- Both a corrected and an uncorrected rate are returned:
--     corrected_per_min = (n_correct - n_incorrect) / minutes
--     correct_per_min   =  n_correct               / minutes
-- Raw counts and seconds_used are kept so the notebook can re-derive, filter on
-- the denominator, or audit any row without another query.
--
-- >>> DENOMINATOR CAVEAT: a rate explodes when the denominator is tiny. A pack is
--     a 120 s timed test that streams operations endlessly, so a healthy sitting
--     has ~115 s of time; a sitting with only a few seconds was abandoned. The
--     notebook enforces a minimum denominator and reports how many rows it drops.
--     This is exactly what went wrong in the old (lost) per-minute query, where
--     a single wrong answer in 0.6 s produced -66 operations/min.
--
-- SCOPE: academic_year_id = 'ES_2025' ---------------------------------------
-- Spain only, one academic year. The full table also holds BR, CL, CO-A, CO-B,
-- EC-CO, EC-SI, IT and MX, and mixing them would confound three things with age:
-- school calendars differ (southern-hemisphere years run Feb-Dec); the course ->
-- age mapping and the curricular position of the times tables differ; and pack
-- assignment is national (R-Indicacions is the Spanish document).
-- Because ES_2025 is the LATEST Spanish year, the CURRENT student dimension is
-- the correct one -- no stale-state risk that would justify the _historic table.
--
-- THE TWO AGES --------------------------------------------------------------
-- Both from bi_gold_prod.dwh_global_dimensions.d_students, joined on student_uuid
-- (documented PK, grain = one row per student):
--     student_course_age    the course assigned to the pupil
--     classroom_course_age  the course the pupil's classroom is doing
-- They diverge for repeaters, early entry and pupils placed off-level. Both are
-- NOMINAL course ages -- the warehouse holds no birth date, so a true biological
-- age cannot be computed. Never label these plain "age" without that caveat.
-- LEFT JOIN on purpose: a missing dimension row keeps NULL ages visible.
--
-- OTHER FILTERS -------------------------------------------------------------
-- * activity_codename = 'A998'                        (Decision #1)
-- * activity_pack IS NOT NULL                         pack is the analysis unit
-- * single run per pack-sitting (statement_idx = 0 appears exactly once): some
--   groups hold TWO runs of the same pack and so twice the clock. NOTE the WHERE
--   clause must NOT filter out idx = 0, or this check would be blind -- which is
--   why the first statement is dropped inside the aggregates, not in the WHERE.
-- * NO age filter here -- Decision #2 (ages 8-15) is applied in the notebook so
--   the 6/7 rows are counted and reported before being dropped.
-- * Operation type is NOT split (multiplications use U+00D7 '×', divisions ':').
-- * Trimester windows are the same dates as
--   a998_baseline_attempts_by_age_trimester.sql, which owns them. The notebook
--   parses both files and fails loudly if they drift, so edit both or neither.
-- =============================================================================

WITH pack_sittings AS (
    SELECT
        s.session_id,
        s.activity_pack,
        MAX(s.student_uuid)   AS student_uuid,      -- constant within a sitting
        MIN(s.response_at)    AS sitting_at,        -- session-level ts, fine for a date

        COUNT(*)              AS n_statements_all,  -- includes the dropped first one
        SUM(CASE WHEN s.statement_idx = 0 THEN 1 ELSE 0 END) AS n_runs,

        -- Decision #7: everything below counts from the SECOND statement onward
        SUM(CASE WHEN s.statement_idx >= 1 THEN 1 ELSE 0 END)              AS n_ops,
        SUM(CASE WHEN s.statement_idx >= 1 AND s.statement_result = 'Correct'
                 THEN 1 ELSE 0 END)                                        AS n_correct,
        SUM(CASE WHEN s.statement_idx >= 1 AND s.statement_result = 'Incorrect'
                 THEN 1 ELSE 0 END)                                        AS n_incorrect,
        SUM(CASE WHEN s.statement_idx >= 1 THEN s.statement_seconds_spent
                 ELSE 0 END)                                               AS seconds_used
    FROM bi_gold_prod.dm_research.fluency_test_statements s
    WHERE s.activity_codename = 'A998'
      AND s.academic_year_id  = 'ES_2025'
      AND s.activity_pack IS NOT NULL
      AND s.response_at IS NOT NULL
      AND s.statement_seconds_spent IS NOT NULL
    GROUP BY s.session_id, s.activity_pack
    HAVING SUM(CASE WHEN s.statement_idx = 0 THEN 1 ELSE 0 END) = 1   -- one run only
       AND SUM(CASE WHEN s.statement_idx >= 1 THEN 1 ELSE 0 END) >= 1
)

SELECT
    p.activity_pack,
    p.student_uuid,
    p.sitting_at,

    CASE
        WHEN p.sitting_at::date BETWEEN DATE '2025-11-01' AND DATE '2025-12-20' THEN 'T1'
        WHEN p.sitting_at::date BETWEEN DATE '2026-02-15' AND DATE '2026-03-30' THEN 'T2'
        WHEN p.sitting_at::date BETWEEN DATE '2026-04-29' AND DATE '2026-06-05' THEN 'T3'
        ELSE 'other'
    END                                                     AS trimester,

    stu.student_course_age,
    stu.classroom_course_age,

    p.n_statements_all,
    p.n_ops,
    p.n_correct,
    p.n_incorrect,
    p.n_ops - p.n_correct - p.n_incorrect                   AS n_other,
    p.n_correct - p.n_incorrect                             AS corrected,
    ROUND(p.seconds_used, 3)                                AS seconds_used,

    -- Decision #7: always report per minute
    ROUND((p.n_correct - p.n_incorrect) / NULLIF(p.seconds_used / 60.0, 0), 3)
                                                            AS corrected_per_min,
    ROUND( p.n_correct                  / NULLIF(p.seconds_used / 60.0, 0), 3)
                                                            AS correct_per_min

FROM pack_sittings p
LEFT JOIN bi_gold_prod.dwh_global_dimensions.d_students stu
       ON stu.student_uuid = p.student_uuid
