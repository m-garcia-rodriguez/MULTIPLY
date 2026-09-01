-- =============================================================================
-- A998 (Spain 2025-26): commutativity, measured WITHIN student (paired)
-- =============================================================================
-- QUESTION: do pupils treat a×b and b×a as the same fact? Concretely, is
-- accuracy on the two directions of the same unordered pair {lo, hi} different,
-- and does the sign tell us whether they do better with the LARGER factor first?
--
-- >>> WHY THIS IS NOT JUST heatmap(a,b) - heatmap(b,a) <<<
-- Subtracting two POPULATION marginals (what the fact-level heatmap would give)
-- is vulnerable to an aggregation artefact (a Simpson's-paradox flavour): if
-- some pupils get a×b right and b×a wrong, and OTHER pupils do the reverse, the
-- two population error rates come out equal and the difference vanishes -- even
-- though no individual pupil is treating the two as equivalent. The marginals
-- are computed over different sets of pupils on each side of the subtraction,
-- so their difference does not answer a within-pupil question.
--
-- FIX: pair each pupil with THEMSELVES. For every pupil who attempted BOTH
-- directions of a pair during the year (not necessarily the same day or the
-- same sitting -- same academic year is enough), compute their own two
-- accuracies and difference. Statistical power then comes from having many
-- PUPILS per age (34k at age 8, 2k at age 15), not from many attempts per
-- pupil -- which is what makes this viable given each pupil only sits the test
-- ~3x/year for 1.5-2 minutes.
--
-- OUTPUT GRAIN: one row per (lo, hi, classroom_course_age), lo < hi.
--
-- THE TWO NUMBERS THAT MUST BE READ TOGETHER ---------------------------------
--   mean_diff      = AVG over pupils of (acc_big_first - acc_big_second).
--                    The SIGNED effect. Positive => pupils do better when the
--                    LARGER factor comes first (e.g. 8×7 beats 7×8).
--   mean_abs_diff  = AVG over pupils of |acc_big_first - acc_big_second|.
--                    The size of the within-pupil discrepancy regardless of
--                    direction. THIS IS THE PIECE THE MARGINAL SUBTRACTION
--                    CANNOT SEE: if mean_diff ~ 0 but mean_abs_diff is large,
--                    individual pupils DO respond differently to the two
--                    directions and merely cancel each other out in aggregate.
--                    Only when BOTH are near zero can we say the direction has
--                    stopped mattering at that age.
-- sd_diff is returned too (free, and it is the dispersion behind mean_abs_diff).
--
-- THE SAME THING AS A PARTITION OF PUPILS (added with Maria 2026-07-30) -------
-- mean_diff and mean_abs_diff are averages of a continuous per-pupil quantity,
-- which hides HOW MANY pupils sit in each of the qualitatively different cases.
-- So the same paired data is also returned as four mutually exclusive, jointly
-- exhaustive shares of the pupils in the cell:
--   pct_both_right       got EVERY attempt right in BOTH directions
--   pct_only_big_first   perfect on big-first, not perfect on big-second
--   pct_only_big_second  perfect on big-second, not perfect on big-first
--   pct_neither_right    not perfect in either direction
-- The four sum to 100 by construction. The two middle ones are the pupils who
-- do NOT treat a×b and b×a as the same fact, split by which way they fail;
-- their SUM is the direction-disagreement rate and their DIFFERENCE is the
-- direction bias, i.e. the discrete counterpart of mean_abs_diff / mean_diff.
--
-- "RIGHT" = acc = 1.0 IN THAT DIRECTION, not acc > 0.5 (decided with Maria
-- 2026-07-30). With MIN_ATTEMPTS = 1 nearly every pupil has a single attempt per
-- direction (n_attempts_per_student_avg ~ 2.3 across both directions), so the
-- two definitions coincide for almost the whole sample; "all correct" is the one
-- that keeps meaning the same thing for the minority with 2+ attempts.
-- CAVEAT, same as for mean_abs_diff: with one attempt per direction a single
-- slip moves a pupil out of pct_both_right and into an "only" bucket, so the
-- two "only" shares are an UPPER BOUND on real direction-dependence. Trust the
-- trend across ages, not the absolute level.
--
-- DIRECTION CONVENTION: 'big_first' = the larger factor is written first
-- (f1 >= f2, e.g. 8×7); 'big_second' = the smaller is first (7×8). Chosen so
-- the sign of mean_diff has one fixed, readable meaning across the whole matrix.
--
-- INCLUSION RULE (decided with Maria 2026-07-29): a pupil enters a (pair, age)
-- cell if they have >= N attempts in EACH direction, N = 1 by default.
-- >>> N IS NOT EDITED HERE. The notebook (commutativity.ipynb, first cell) owns
--     it as MIN_ATTEMPTS_PER_DIRECTION and rewrites the two marked HAVING lines
--     below before running. The literals below are the DEFAULT, so this file
--     still runs standalone; the notebook fails loudly if the markers drift.
-- N = 1 is deliberately permissive -- keeps the pupil count high. The cost is
-- that a pupil with a single attempt
-- per direction can only score 0, +1 or -1, which inflates mean_abs_diff with
-- per-attempt noise (a pupil who simply slipped once looks like a pupil who
-- does not know the pair). So mean_abs_diff is an UPPER BOUND on real
-- within-pupil inconsistency; the trend across ages is the trustworthy signal,
-- not its absolute level. n_attempts_per_student_avg is returned to show how
-- much of the sample is in that thin regime.
--
-- ONLY OFF-DIAGONAL PAIRS: f1 = f2 (squares like 6×6) is excluded -- a square
-- has only one direction, so commutativity is undefined for it.
--
-- ===========================================================================
-- TWO ACADEMIC YEARS (ES_2024 + ES_2025) AND HOW AGE IS RESOLVED
-- ===========================================================================
-- HOW IS AGE COMPUTED ONCE MORE THAN ONE YEAR IS IN SCOPE? The concern is the
-- one flagged in the fluency-test-statements-columns memory: a dimension table
-- read "as of today" would attribute an OLD sitting to the pupil's CURRENT
-- course, silently shifting every age in the earlier year.
-- That risk does NOT apply here, verified empirically on 2026-07-29:
-- `fluency_test_metrics.classroom_course_age` is a PER-SITTING SNAPSHOT, not a
-- lookup against the live dimension. Test: of the ~96.9k pupils with A998
-- sittings in BOTH ES_2024 and ES_2025, 96,178 (99.3%) show exactly
-- age(ES_2025) - age(ES_2024) = +1, as they must if each row carries the age at
-- the time of its own sitting. So no join to d_students / the _historic
-- dimension is needed: metrics already holds the right age per year.
-- (The ~700 exceptions: 559 with delta 0 = repeaters, plus a long thin tail of
-- +2/-1 etc. = off-level placements. Real pupil movement, not a data defect.)
--
-- >>> WHY academic_year_id IS PART OF THE PAIRING KEY <<<
-- Those 559 repeaters sit the SAME classroom_course_age in both years. If the
-- pairing grouped only by (pupil, pair, age), their two separate years of
-- attempts would be silently merged into ONE paired observation -- mixing a
-- 2024 attempt in one direction with a 2025 attempt in the other, across a
-- whole year of learning. academic_year_id is therefore in the GROUP BY of
-- per_student_pair, so a pupil pairs only against themselves WITHIN a year.
--
-- OUTPUT KEEPS THE YEAR SPLIT rather than pooling: two years at the same age
-- are an independent replication of each other, which is worth seeing. Pooling
-- afterwards (weighted by n_students) is trivial in the notebook; un-pooling is
-- not. NOTE the two years are NOT equally deep at every age -- ES_2024 has far
-- fewer older pupils (age 15: 3.4k attempts vs 56.3k in ES_2025) -- so compare
-- ages, not raw year totals.
--
-- The year list is the notebook's to set (marked "-- {YEARS}" below), same
-- mechanism as MIN_ATTEMPTS. Years available for A998/ES: ES_2022 and ES_2023
-- exist but cover only a couple of months each (Apr-Jun 2023 and Jan-Feb 2024),
-- so they are not comparable full years and are left out of the default.
--
-- Decisions applied (Learning_Team_Plots/Decisions.txt):
--   #1 A998 only  ·  #2 ages 8-15 (classroom_course_age)  ·  #5 multiplication
--   only  ·  #7 first statement of each pack-sitting dropped
-- Separator gotcha ('×' and '·' both live in the data) handled as in the other
-- queries -- see a998_fact_heatmap_by_age.sql for the full writeup.
--
-- ACCURACY, NOT SPEED: commutativity is a property of the RESULT, so this
-- query is about correctness only. statement_result 'Help' counts as NOT
-- correct (consistent with the error_rate convention elsewhere in the notebook).
-- Response time is deliberately absent.
--
-- Scope: Spanish academic years, set by the notebook (default ES_2024+ES_2025).
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
      AND s.academic_year_id IN ('ES_2024', 'ES_2025')   -- {YEARS}
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

-- collapse each attempt onto its unordered pair + which direction it was
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

-- ONE ROW PER (pupil, YEAR, pair, age): the pupil's own accuracy in each
-- direction. The year is in the key so repeaters cannot have two years of
-- attempts merged into a single paired observation (see header).
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
),

diffs AS (
    SELECT
        academic_year_id,
        age,
        lo,
        hi,
        n_bf + n_bs                                       AS n_attempts,
        ok_bf / n_bf                                      AS acc_bf,
        ok_bs / n_bs                                      AS acc_bs,
        ok_bf / n_bf - ok_bs / n_bs                       AS diff,
        ABS(ok_bf / n_bf - ok_bs / n_bs)                   AS abs_diff,

        -- discrete partition: "right in a direction" = every attempt correct
        CASE WHEN ok_bf = n_bf THEN 1 ELSE 0 END          AS perfect_bf,
        CASE WHEN ok_bs = n_bs THEN 1 ELSE 0 END          AS perfect_bs
    FROM per_student_pair
)

SELECT
    academic_year_id,
    lo,
    hi,
    age                                          AS classroom_course_age,
    COUNT(*)                                     AS n_students,
    ROUND(AVG(n_attempts), 2)                    AS n_attempts_per_student_avg,

    ROUND(AVG(acc_bf), 4)                        AS acc_big_first,
    ROUND(AVG(acc_bs), 4)                        AS acc_big_second,

    ROUND(AVG(diff), 4)                          AS mean_diff,       -- signed
    ROUND(AVG(abs_diff), 4)                      AS mean_abs_diff,   -- magnitude
    ROUND(STDDEV(diff), 4)                       AS sd_diff,

    -- Four shares of the pupils in the cell; they sum to 100 by construction
    -- (the notebook asserts it). CAST AS DOUBLE because 100.0 is a DECIMAL
    -- literal in Spark: without the cast the driver hands back decimal.Decimal
    -- objects, which then blow up inside np.average / np.allclose.
    CAST(ROUND(100.0 * AVG(CASE WHEN perfect_bf = 1 AND perfect_bs = 1
                                THEN 1.0 ELSE 0.0 END), 4) AS DOUBLE) AS pct_both_right,
    CAST(ROUND(100.0 * AVG(CASE WHEN perfect_bf = 1 AND perfect_bs = 0
                                THEN 1.0 ELSE 0.0 END), 4) AS DOUBLE) AS pct_only_big_first,
    CAST(ROUND(100.0 * AVG(CASE WHEN perfect_bf = 0 AND perfect_bs = 1
                                THEN 1.0 ELSE 0.0 END), 4) AS DOUBLE) AS pct_only_big_second,
    CAST(ROUND(100.0 * AVG(CASE WHEN perfect_bf = 0 AND perfect_bs = 0
                                THEN 1.0 ELSE 0.0 END), 4) AS DOUBLE) AS pct_neither_right

FROM diffs
GROUP BY academic_year_id, lo, hi, age
ORDER BY academic_year_id, lo, hi, age
