-- =============================================================================
-- A998 (Spain, ES_2025): one 0/1 score per (pupil, multiplication fact)
-- =============================================================================
-- Feeds mds_facts.ipynb, which correlates pupils' hit/miss patterns across the
-- 100 facts and lays the facts out in 2D with MDS. What that analysis needs is a
-- pupil x fact matrix of 0/1 with holes in it, so the grain here is
--
--     ONE ROW PER (student, factor_1, factor_2)  =  the pupil's LAST attempt
--
-- and `is_correct` is that attempt's outcome. Missing cells (a pupil who never
-- saw 7x8) are ABSENT ROWS, never zeros: the notebook must read them as
-- unobserved, and every correlation is computed on the pupils who answered both
-- facts (pairwise complete observations).
--
-- WHY THE LAST ATTEMPT (Maria, 2026-08-13). A pupil can meet the same fact many
-- times in a year, so a single 0/1 needs a rule. The last attempt is the pupil's
-- most recent state of knowledge and it does not weight pupils who practise more
-- (unlike a mean) nor punish them (unlike "all attempts correct"). `n_attempts`
-- and `n_correct_all` travel along so the notebook can re-derive the majority
-- rule and the mean and check the map does not depend on the choice --
-- WITHOUT a second query.
--   Ordering: response_at DESC, then statement_idx DESC, then statement_id DESC.
--   `response_at` is SESSION-level (identical for every statement of a sitting),
--   so it cannot order two attempts inside one sitting -- that is what
--   statement_idx is for. statement_id is the final deterministic tie-break.
--
-- ORDERED PAIRS, NOT MERGED: factor_1 x factor_2 keeps the orientation the pupil
-- saw, so 7x8 and 8x7 are two different facts. That is what makes it exactly
-- 100 facts (0-9 x 0-9), which is what the MDS map is supposed to show. Every
-- multiplication operand in A998 is a single digit (see a998-pack-reference),
-- so `factor_1` and `factor_2` are always 0-9; the notebook asserts it.
--
-- `student_idx` INSTEAD OF `student_uuid`: the analysis only needs a key to
-- group rows by pupil (and to split the sample in halves), never the identity.
-- DENSE_RANK over the uuid gives a dense integer, which also keeps a ~3M-row
-- result small enough to cache as parquet. The uuid never leaves this query.
--   `student_age` = classroom_course_age of the pupil's MOST RECENT sitting, so
--   it is constant per pupil and the matrix has one age per row. `n_ages` says
--   how often a pupil spans two ages, i.e. how often that choice matters
--   (checked at age 8 for a sibling query: it did not happen in ES_2025).
--
-- SEPARATOR GOTCHA: multiplications live in the data with both U+00D7 'x' and
-- U+00B7 middle dot (19% of rows); '·' is normalised to '×' before SPLIT, or the
-- CAST throws CAST_INVALID_INPUT. Divisions are excluded via ':' (Decision #5:
-- classify on ':' -- an ASCII 'x' matches nothing).
--
-- Decisions applied (Learning_Team_Plots/Decisions.txt):
--   #1 A998 only  ·  #2 ages 8-15 (classroom_course_age)  ·  #5 multiplications
--   only  ·  #7 first statement of each pack-sitting dropped (statement_idx >= 1)
--   ·  #8 ES_2025 only  ·  #12 racing sittings flagged (see below)
--
-- -----------------------------------------------------------------------------
-- `racing_sitting` AND WHY THIS ANALYSIS FILTERS IT BY DEFAULT
-- -----------------------------------------------------------------------------
-- A (session_id, activity_pack) sitting is flagged when its MEDIAN
-- statement_seconds_spent < 1.5 s AND its accuracy < 25% -- both conditions, so
-- a genuinely fast and accurate pupil is never flagged. Those sittings average
-- ~42 statements at 8% correct and 1 s per item: nobody is multiplying
-- (Decision #12, threshold = the antimode of the sitting-median-RT
-- distribution, see a998-endofpack-keyboard-noise).
--
-- For a difficulty ranking that flag is a judgement call. For a CORRELATION
-- matrix it is not: a pupil who answers everything wrong is a row of zeros, and
-- rows of zeros make EVERY pair of facts correlate positively for a reason that
-- has nothing to do with arithmetic. So mds_facts.ipynb rewrites
-- -- {RACING_FILTER} to drop them and reports the map both ways.
--
-- The filter is applied in `scoped`, i.e. BEFORE the last-attempt window
-- function. That is deliberate: if it were applied afterwards, a racing attempt
-- that happens to be a pupil's most recent one would delete that pupil's cell
-- instead of falling back to their previous, real attempt.
--
-- Markers rewritten from the notebook (a marker that drifts makes the notebook
-- fail loudly instead of silently querying a different population):
--   -- {YEARS}          academic year list (default ES_2025, Decision #8)
--   -- {AGES}           classroom_course_age range (default 8-15, Decision #2)
--   -- {PACKS}          default all packs; set to activity_pack = 39 for the
--                       homogeneous-exposure robustness check (pack 39 is the
--                       only pack containing all of tables 0-9, so within it
--                       the holes in the matrix are not driven by which pack the
--                       pupil's age was assigned)
--   -- {RACING_FILTER}  default keeps everything; set to drop flagged sittings
--   -- {FAST_WRONG_RT}      seconds under which a WRONG answer counts as a guess
--   -- {FAST_WRONG_FILTER}  default `1 = 1` keeps everyone; set to
--                           `has_fast_wrong = 0` to drop every pupil who ever
--                           answered wrong that fast (commutativity.ipynb,
--                           EXCLUDE_FAST_WRONG_STUDENTS, added 2026-08-25).
--                           DEFAULTS TO OFF ON PURPOSE: mds_facts.ipynb reads
--                           this same file and must keep its old population.
--                           Note it selects on the outcome, so the survivors
--                           are more accurate than the population by
--                           construction -- levels move, and not because of
--                           learning.
--
-- NO ORDER BY on the final SELECT: this returns ~3M rows and a global sort buys
-- nothing -- the notebook indexes by (student_idx, factor_1, factor_2) anyway.
-- =============================================================================

WITH base AS (
    SELECT
        s.statement_id                                              AS statement_id,
        s.session_id                                                AS session_id,
        s.activity_pack                                             AS activity_pack,
        s.student_uuid                                              AS student_uuid,
        s.response_at                                               AS response_at,
        s.statement_idx                                             AS statement_idx,
        CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[0] AS INT)  AS f1,
        CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[1] AS INT)  AS f2,
        m.classroom_course_age                                      AS age,
        s.statement_seconds_spent                                   AS rt_seconds,
        CASE WHEN s.statement_result = 'Correct' THEN 1 ELSE 0 END  AS is_correct,

        -- FAST WRONG ANSWER (added 2026-08-25 for commutativity.ipynb): wrong
        -- answer under the threshold. 'Correct' is tested first so a fast RIGHT
        -- answer is never flagged; not-'Correct' (incl. 'Help' and NULL) under
        -- the threshold is.
        CASE WHEN s.statement_result = 'Correct' THEN 0
             WHEN s.statement_seconds_spent < 1.5           -- {FAST_WRONG_RT}
             THEN 1 ELSE 0 END                                       AS fast_wrong

    FROM bi_gold_prod.dm_research.fluency_test_statements s
    INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
            ON m.metric_id = s.metric_id

    WHERE s.activity_codename        = 'A998'
      AND s.academic_year_id IN ('ES_2025')         -- {YEARS}
      AND s.operation NOT LIKE '%:%'                -- multiplications only (Decision #5)
      AND s.statement_idx           >= 1            -- drop first statement (Decision #7)
      AND s.statement_seconds_spent IS NOT NULL
      AND m.classroom_course_age BETWEEN 8 AND 15   -- {AGES}
      AND 1 = 1                                     -- {PACKS}
),

-- one row per sitting: is the whole sitting a high-speed run? (Decision #12)
sitting AS (
    SELECT
        session_id,
        activity_pack,
        PERCENTILE(rt_seconds, 0.5)     AS sitting_med_rt,
        AVG(CAST(is_correct AS DOUBLE)) AS sitting_acc
    FROM base
    GROUP BY session_id, activity_pack
),

flagged AS (
    SELECT
        b.*,
        CASE WHEN g.sitting_med_rt < 1.5      -- {RACING_MED_RT}
              AND g.sitting_acc    < 0.25     -- {RACING_ACC}
             THEN 1 ELSE 0 END AS racing_sitting,
        -- PUPIL-LEVEL fast-wrong flag (added 2026-08-25): 1 if this pupil ever
        -- answered wrong under the threshold anywhere in the scope of this
        -- query. Partitioned by pupil only -- if -- {YEARS} is ever set to more
        -- than one year, the flag spans them (this query is single-year in both
        -- notebooks that use it).
        MAX(b.fast_wrong) OVER (PARTITION BY b.student_uuid) AS has_fast_wrong
    FROM base b
    INNER JOIN sitting g
            ON g.session_id    = b.session_id
           AND g.activity_pack = b.activity_pack
),

-- default: keep every attempt. The notebook rewrites the marker to drop the
-- flagged sittings BEFORE the last-attempt pick, so a pupil keeps their last
-- real attempt instead of losing the cell.
scoped AS (
    SELECT * FROM flagged
    WHERE 1 = 1   -- {RACING_FILTER}
      AND 1 = 1   -- {FAST_WRONG_FILTER}
),

-- the pupil's last attempt at each fact, plus how many times they met it
ranked AS (
    SELECT
        student_uuid,
        f1,
        f2,
        age,
        is_correct,
        rt_seconds,
        racing_sitting,
        activity_pack,
        ROW_NUMBER() OVER (PARTITION BY student_uuid, f1, f2
                           ORDER BY response_at DESC,
                                    statement_idx DESC,
                                    statement_id DESC)  AS rn,
        COUNT(*)        OVER (PARTITION BY student_uuid, f1, f2) AS n_attempts,
        SUM(is_correct) OVER (PARTITION BY student_uuid, f1, f2) AS n_correct_all
    FROM scoped
),

students AS (
    SELECT
        student_uuid,
        COUNT(*)                            AS n_statements,
        COUNT(DISTINCT age)                 AS n_ages,
        MAX_BY(age, response_at)            AS student_age
    FROM scoped
    GROUP BY student_uuid
),

students_idx AS (
    SELECT
        student_uuid,
        n_statements,
        n_ages,
        student_age,
        DENSE_RANK() OVER (ORDER BY student_uuid) AS student_idx
    FROM students
)

SELECT
    st.student_idx,
    st.student_age,
    st.n_ages,
    st.n_statements,
    r.f1                             AS factor_1,
    r.f2                             AS factor_2,
    r.f1 * r.f2                      AS product,
    r.is_correct,
    CAST(r.rt_seconds AS DOUBLE)     AS rt_seconds,
    r.racing_sitting,
    r.activity_pack,
    r.n_attempts,
    r.n_correct_all

FROM ranked r
INNER JOIN students_idx st ON st.student_uuid = r.student_uuid
WHERE r.rn = 1
