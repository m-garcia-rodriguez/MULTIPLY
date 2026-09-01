-- =============================================================================
-- A998: does WHEN 6x8 appears inside the pack change the chance of getting it
-- right?  (fatigue / warm-up / clock control)
-- =============================================================================
-- Motivation: this is the CONTROL step for the "does seeing a similar fact
-- just before change the answer?" question. Before any priming effect can be
-- read as priming, we need to know whether position-in-the-test by itself
-- moves accuracy on a fixed fact. 6x8 is used because it is the hardest fact
-- in the ranking (see the hardest_table / error_types work), so it has the
-- most room to move in either direction.
--
-- GRAIN OF THE OUTPUT: one row per 6x8 ATTEMPT (not aggregated). ~61.5k rows
-- for ES_2025 x ages 8-15, small enough to download and bin in the notebook,
-- which is what lets the notebook change the binning, the racing filter and
-- the accuracy definition without a new warehouse round-trip.
--
-- THE TWO VARIABLES ASKED FOR
--   position  = statement_idx + 1, i.e. 1st, 2nd, 3rd ... operation of the
--               pack run. `statement_idx` is 0-based in the warehouse.
--   elapsed_s = SUM(statement_seconds_spent) of every statement BEFORE this
--               one in the same pack run, i.e. seconds of test already
--               elapsed when 6x8 appeared.
--
-- Why elapsed_s is built by hand instead of using timestamps: `response_at` is
-- a SESSION-level timestamp, identical for every statement of a
-- (session_id, activity_pack) group, so any first-to-last difference is
-- exactly 0. Duration has to come from statement_seconds_spent. Verified on
-- ES_2025: statement_seconds_spent is NEVER NULL (0 null rows), so the
-- cumulative sum has no holes.
--
-- UNIT OF "THE TEST" = ONE PACK RUN (session_id, activity_pack).
-- Chosen because the pack carries the clock (120 s budget, measured; see the
-- a998-pack-duration-120s note) and statement_idx restarts at 0 with it.
-- In ES_2025 this is not really a choice anyway: 399,577 (session_id, pack)
-- sittings come from 399,560 distinct sessions, so a session is a pack for
-- all but ~17 cases -- pack-clock and session-clock coincide.
--
-- REPEATED RUNS OF THE SAME PACK IN ONE SESSION: detected via a second
-- statement_idx = 0 inside the same (session_id, activity_pack). Exactly 4 of
-- 399,577 ES_2025 sittings do this (and they are the ones whose summed time
-- reaches ~2 x 120 s = 238.8 s). Their positions and their cumulative clock
-- are both meaningless, so the flag `multi_run_sitting` is RETURNED and the
-- notebook drops them -- same "return the flag, don't filter in SQL" pattern
-- used for racing sittings.
--
-- ACCURACY. statement_result has exactly three values here: Correct,
-- Incorrect, Help (Help = pupil could not answer unaided; counted as an
-- error, as everywhere else in this repo). Two definitions are supported
-- downstream, because of the keystroke artefact:
--   strict  -- is_correct = 1 only for 'Correct'
--   typed   -- drop the rows where the answer is a single digit (48 is a
--              two-digit product, so a 1-digit wrong answer is a rejected
--              FIRST KEYSTROKE, not an intended answer -- 14,665 of the
--              29,719 wrong 6x8 rows in ES_2025 are of this kind)
-- `answer_class` carries the split so the notebook can do either. This
-- matters here specifically: typing behaviour could change with time-on-task,
-- so the two definitions must be allowed to disagree.
--
-- SITTING-LEVEL COVARIATES (the real confound). Position is not randomly
-- assigned: only fast pupils reach position 30, and long sittings are
-- disproportionately racing sittings (median RT < 1.5 s, accuracy < 25%,
-- Decision #12) which are ~5x longer than normal ones. So the query returns
--   sitting_n, sitting_median_rt, sitting_acc, racing_sitting
-- for the racing filter, and
--   n_other, n_other_correct
-- = the pupil's own accuracy on every OTHER statement of the same sitting.
-- That is the within-sitting baseline: comparing 6x8 against the same pupil's
-- own hit rate in the same sitting removes the "who survives to late
-- positions" composition effect, which a raw accuracy-vs-position curve
-- cannot.
-- sitting_median_rt / sitting_acc / n_other are computed over statement_idx
-- >= 1: the idx = 0 item absorbs the countdown and orientation time, so
-- including it would bias the sitting median RT upwards.
--
-- REPEATS OF 6x8 WITHIN ONE SITTING: `occurrence_no` (1 = first time 6x8 was
-- shown in that sitting). ~14% of sittings that show 6x8 show it more than
-- once, and a second look at the same fact is not the same event as a first
-- look at a later position. The notebook can restrict to occurrence_no = 1.
--
-- Decisions applied / deliberately NOT applied
--   #1  A998 only .......................................... applied
--   #2  ages 8-15 (classroom_course_age) ................... applied
--   #8  ES_2025 only ....................................... applied, via the
--       -- {YEARS} marker so another year is a one-line change
--   #5  multiplication -- irrelevant, the fact is fixed to 6x8
--   #7  drop statement_idx = 0 ............... NOT applied in SQL. Position 1
--       IS one of the points of this analysis. The rows are returned and the
--       notebook's DROP_FIRST_POSITION switch (default True, per #7) decides.
--       Note idx = 0 statements always CONTRIBUTE to elapsed_s regardless --
--       the clock ran, whether or not we analyse that item.
--   #12 racing sittings ...................... returned as a flag, not filtered
--
-- PACKS: 6x8 exists in packs 16 (tables 2,4,5,8), 20 (2-9) and 39 (0-9); it
-- does NOT exist in pack 14 (tables 2,5 only), which is most of age 8's T1.
-- All packs containing it are kept (Maria, 2026-08-18) so age 8 keeps a real
-- sample, and `activity_pack` is returned so the notebook can check that the
-- position effect is not just a pack effect. ES_2025 counts, ages 8-15:
--   pack 16: 12,913 (age 8: 12,380)   pack 20: 19,443 (ages 8-9: 18,963)
--   pack 39: 29,039 (ages 9-15)
--
-- Separator: ES uses U+00D7 'x' and U+00B7 middle dot for multiplication,
-- never an ASCII x. Normalised with REPLACE(operation, '·', '×') before
-- matching '6×8'. See the a998-pack-reference note before extending this
-- query to another region (CO-B / MX / US also use U+00F7 for division).
--
-- Keys are hashed (student_key, sitting_key) -- the notebook only needs them
-- to group and to cluster, never to identify anyone.
-- =============================================================================

WITH stmts AS (
    SELECT
        s.session_id,
        s.activity_pack,
        s.statement_idx,
        s.statement_seconds_spent                                   AS rt_seconds,
        REPLACE(s.operation, '·', '×')                              AS op_norm,
        s.statement_result,
        s.user_answer,
        s.student_uuid,
        m.classroom_course_age                                      AS age,
        s.academic_year_id,
        CASE WHEN s.statement_result = 'Correct' THEN 1 ELSE 0 END  AS is_correct

    FROM bi_gold_prod.dm_research.fluency_test_statements s
    INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
            ON m.metric_id = s.metric_id

    WHERE s.activity_codename = 'A998'
      AND s.academic_year_id IN ('ES_2025')   -- {YEARS}
      AND m.classroom_course_age BETWEEN 8 AND 15   -- Decision #2
),

-- One row per pack run. Everything the notebook needs to decide whether a
-- sitting is usable, plus the within-sitting baseline on the OTHER facts.
sitting AS (
    SELECT
        session_id,
        activity_pack,
        COUNT(*)                                                     AS sitting_n,
        SUM(rt_seconds)                                              AS sitting_sum_rt,
        MAX(statement_idx)                                           AS sitting_max_idx,
        SUM(CASE WHEN statement_idx = 0 THEN 1 ELSE 0 END)           AS n_starts,
        COUNT(DISTINCT statement_idx)                                AS n_distinct_idx,
        PERCENTILE(CASE WHEN statement_idx >= 1 THEN rt_seconds END, 0.5) AS sitting_median_rt,
        AVG(CAST(CASE WHEN statement_idx >= 1 THEN is_correct END AS DOUBLE))  AS sitting_acc,
        SUM(CASE WHEN statement_idx >= 1 AND op_norm <> '6×8'
                 THEN 1 ELSE 0 END)                                  AS n_other,
        SUM(CASE WHEN statement_idx >= 1 AND op_norm <> '6×8'
                 THEN is_correct ELSE 0 END)                         AS n_other_correct
    FROM stmts
    GROUP BY session_id, activity_pack
),

-- Cumulative clock. The window runs over EVERY statement of the sitting
-- (including idx = 0 and including the other facts) -- that is the whole
-- point of "time elapsed since the start of the test".
seq AS (
    SELECT
        s.*,
        COALESCE(SUM(s.rt_seconds) OVER (
            PARTITION BY s.session_id, s.activity_pack
            ORDER BY s.statement_idx
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), 0)                                                        AS elapsed_s
    FROM stmts s
),

six_by_eight AS (
    SELECT
        seq.*,
        ROW_NUMBER() OVER (
            PARTITION BY seq.session_id, seq.activity_pack
            ORDER BY seq.statement_idx
        )                                                            AS occurrence_no
    FROM seq
    WHERE seq.op_norm = '6×8'
)

SELECT
    x.academic_year_id,
    x.activity_pack,
    x.age                                        AS classroom_course_age,
    XXHASH64(x.student_uuid)                         AS student_key,
    XXHASH64(CONCAT_WS('|', x.session_id, CAST(x.activity_pack AS STRING)))          AS sitting_key,

    x.statement_idx,
    x.statement_idx + 1                          AS position,
    ROUND(x.elapsed_s, 3)                        AS elapsed_s,
    x.rt_seconds,
    x.occurrence_no,

    x.statement_result,
    x.is_correct,
    CASE
        WHEN x.statement_result = 'Correct'                       THEN 'correct'
        WHEN x.statement_result = 'Help'                          THEN 'help'
        WHEN x.user_answer IS NULL                                THEN 'no_answer'
        WHEN LENGTH(TRIM(x.user_answer)) = 1                      THEN 'wrong_1digit'
        WHEN LENGTH(TRIM(x.user_answer)) = 2                      THEN 'wrong_2digit'
        ELSE 'wrong_other'
    END                                          AS answer_class,

    -- sitting context
    st.sitting_n,
    st.sitting_max_idx,
    ROUND(st.sitting_sum_rt, 3)                  AS sitting_sum_rt,
    ROUND(st.sitting_median_rt, 3)               AS sitting_median_rt,
    ROUND(st.sitting_acc, 4)                     AS sitting_acc,
    st.n_other,
    st.n_other_correct,
    CASE WHEN st.sitting_median_rt < 1.5 AND st.sitting_acc < 0.25
         THEN TRUE ELSE FALSE END                AS racing_sitting,
    CASE WHEN st.n_starts > 1 OR st.n_distinct_idx <> st.sitting_n
         THEN TRUE ELSE FALSE END                AS multi_run_sitting

FROM six_by_eight x
INNER JOIN sitting st
        ON st.session_id     = x.session_id
       AND st.activity_pack  = x.activity_pack
