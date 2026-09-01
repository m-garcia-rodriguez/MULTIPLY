-- =============================================================================
-- FLUENCY ZONE (Spain 2025-26): what do pupils answer when they get the same 5
-- hardest multiplications wrong? Same plots as error_types.ipynb, other app
-- =============================================================================
-- WHY THIS FILE EXISTS. a998_hardest_facts_error_answers.sql had to split its
-- histograms in two because the A998 grades keystroke by keystroke: a wrong
-- first digit is submitted on the spot, so half of its "wrong answers" are only
-- the first digit typed (Decision #11). The Fluency zone is a different app --
-- Leitner flashcards, two attempts per card, no timer -- and it does NOT behave
-- that way. Measured on this table, ES_2025, multiplications, ages 8-11:
--   . of the single-digit wrong first answers to a two-digit product, 63.9% ARE
--     the tens digit of the correct product (A998: 1.06%, a ~16x hole). Here
--     nothing is submitted until the pupil submits, so the digit they typed
--     first is exactly what gets recorded.
--   . median duration is 4.93 s for a correct first attempt and 10.02 s for a
--     wrong one. Errors are SLOWER than correct answers, the opposite of the
--     A998 (4.20 s correct vs 1.40-1.63 s wrong, i.e. instant rejection).
--   . there is no 66/67/76/77 block (Decision #12): the most frequent wrong
--     answers to the 5 facts are 54, 56, 42, 24, 45, 64, 46, 36 -- all
--     arithmetic, all at 7.6-10 s. No fast-keystroke population to separate.
-- So one histogram per attempt is enough, and no sitting-level speed flag is
-- needed. The notebook re-runs those three checks on live data instead of
-- trusting this comment.
--
-- OUTPUT GRAIN: one row per (lo, hi, classroom_course_age, attempt_no,
-- user_answer). Wrong answers only; the correct product travels as `product` so
-- the notebook can mark it without drawing a bar for it.
--   attempt_no = 1  the spontaneous answer (every card not 'Correct at first')
--   attempt_no = 2  the second try (only cards that ended 'Incorrect'; a card
--                   that ended 'Correct at second' has no wrong second answer)
--   recovered_at_second = 1 on attempt 1 when the card ended 'Correct at
--                   second'. It is what the notebook colours by: a slip the
--                   pupil fixes immediately is not the same as a gap. Always 0
--                   on attempt 2, by construction.
--
-- WHICH 5 FACTS. The same five as the A998 notebook (4x8, 5x8, 6x8, 7x8, 8x8),
-- rewritten through the -- {FACTS} marker, because the point is comparing the
-- same operation across the two apps. They are also near the top of Fluency's
-- own difficulty ranking for tables <= 9 -- 6x8 39.6%, 8x8 39.3%, 7x8 39.3% --
-- and `fluency_rank` / `fluency_error_pct` return where each one really sits in
-- THIS app, over all facts, so the choice stays auditable.
-- CAREFUL: Fluency also drills tables 10, 11 and 12, which the A998 does not
-- have, and those dominate its difficulty ranking (12x12 62.5%, 11x11 59.7%,
-- 11x12 58.0%). Nothing here says the 5 facts below are Fluency's hardest.
--
-- JOIN GOTCHA. This table's `student_uuid` joins d_students on **student_uuid**,
-- NOT on `unique_id`. The A998 tables are the other way round (their
-- student_uuid holds the hashed id that d_students calls unique_id), so copying
-- that join here returns ZERO rows silently. d_students carries both columns.
-- The historic dimension is the right one: sittings span academic years and the
-- current dimension would attribute an old attempt to the pupil's latest course.
--
-- Decisions applied (Learning_Team_Plots/Decisions.txt):
--   #1 Fluency as the comparison zone  .  #2 ages 8-15 via classroom_course_age
--   (in practice this app only has 8-11)  .  #3 the query stays as .sql and the
--   notebook prints how the data was gathered  .  #5 multiplications only
--   .  #8 ES_2025 only
-- Decision #7 (drop the first statement) does NOT apply: Fluency has no pack
-- with a countdown, so there is no unrepresentative opening item to drop.
--
-- ERROR TYPOLOGY (`error_type`), same priority order as the A998 query so the
-- two are readable side by side:
--   no_answer       no value recorded. 43% of wrong first attempts on cards that
--                   ended 'Correct at second' and 35% of those that ended
--                   'Incorrect' -- a big group here, worth watching, plotted
--                   nowhere because it has no place on a number axis.
--   equals_product  graded wrong yet the answer equals the product.
--   zero            answered 0.
--   too_many_digits more digits than the product can have. 5% of wrong answers,
--                   and almost all of them are the right answer with an extra
--                   keystroke: 400 for 40, 322 for 32, 567/566/556 for 56, 488
--                   for 48. Typing, not arithmetic -- and four values in the
--                   hundreds would stretch the axis and hide everything else.
--   fewer_digits    fewer digits than the product (12.6% of wrong answers). NOT
--                   the A998 artefact: 63.9% of these are the correct tens
--                   digit, so they read as the pupil submitting half-typed.
--                   Plotted on the same axis as the rest -- unlike the A998,
--                   where they were a different object.
--   sum             answered lo + hi.
--   neighbour       product ± lo or ± hi: one step away in one of the two tables.
--   off_by_one      |answer - product| in {1, 2} and not already a neighbour.
--   reversed        two-digit product answered with its digits swapped.
--   table_multiple  a non-zero multiple of lo or hi, further than one step away.
--   other_product   somewhere in the 0-12 multiplication table (this app goes up
--                   to 12), but a multiple of neither factor.
--   other           anything else.
--
-- Lines marked below are rewritten by the notebook; if a marker drifts the
-- notebook fails loudly rather than silently querying a different population:
--   -- {YEARS}   academic year list (default ES_2025, Decision #8)
--   -- {FACTS}   the (lo, hi) pairs to keep, unordered pairs with lo <= hi
--   -- {AGES}    classroom_course_age range (default 8-15, Decision #2)
--
-- RAPID-GUESSING FILTER (Maria, 2026-08-14): drop wrong answers with
-- duration < 1.2s from the `attempts` CTE, i.e. from the answer/error-type
-- histograms in fluency_error_types.ipynb. Applied in `attempts`, not `base`
-- or `scoped`, because every row of `attempts` is already a wrong answer (see
-- "OUTPUT GRAIN" above) -- unlike the A998 filter (hardest_table.ipynb /
-- a998_table_difficulty_by_age.sql), there is no mix of correct+incorrect
-- rows here to bias, so this is a plain "drop fast wrong answers" cut, not an
-- asymmetric one.
-- >>> WORTH KNOWING BEFORE TRUSTING A BIG EFFECT: per this file's own header
--     comment, Fluency errors are SLOWER than correct answers here (median
--     10.02s wrong vs 4.93s correct), the opposite of the A998's instant
--     rejections -- there is no 66/67/76/77-style keystroke block to remove.
--     Verified live on 2026-08-14 (ES_2025, ages 8-15, these 5 facts): only
--     0.646% of wrong FIRST attempts (5,243 / 811,707) and 3.528% of wrong
--     SECOND attempts (11,944 / 338,590) are under 1.2s. So this filter
--     removes a small, real slice -- not nothing -- but nowhere near the
--     scale of the A998 artefact it is modelled on.
-- >>> NOT APPLIED to `cell_totals` (n_cards, n_wrong_first, n_wrong_second,
--     error_pct_first_cell): those describe how many CARDS were missed, a
--     card-level fact, so they stay computed on every attempt regardless of
--     typing speed. Only the per-answer histograms (`n`, `error_type`,
--     `median_duration`) are computed on the >=1.2s subset. This means
--     error_pct_first_cell will no longer equal SUM(n) / n_cards for a given
--     (fact, age) -- that gap IS the number of fast guesses removed.
-- =============================================================================

WITH base AS (
    SELECT
        LEAST(CAST(TRIM(SPLIT(a.operation, 'X')[0]) AS INT),
              CAST(TRIM(SPLIT(a.operation, 'X')[1]) AS INT))  AS lo,
        GREATEST(CAST(TRIM(SPLIT(a.operation, 'X')[0]) AS INT),
                 CAST(TRIM(SPLIT(a.operation, 'X')[1]) AS INT)) AS hi,
        s.classroom_course_age                                 AS age,
        a.attempt_result                                       AS res,
        TRY_CAST(a.first_attempt_answer_value  AS DOUBLE)      AS answer_1,
        TRY_CAST(a.second_attempt_answer_value AS DOUBLE)      AS answer_2,
        a.first_attempt_duration                               AS duration_1,
        a.second_attempt_duration                              AS duration_2,
        a.box_from                                             AS box_from

    FROM bi_gold_prod.dwh_digital_practice.f_elementary_fluency_attempts a
    -- student_uuid = student_uuid here, NOT unique_id (see the gotcha above)
    INNER JOIN bi_gold_prod.dwh_global_dimensions_historic.d_students s
            ON s.student_uuid      = a.student_uuid
           AND s.academic_year_id  = a.academic_year_id

    WHERE a.academic_year_id IN ('ES_2025')       -- {YEARS}
      AND a.operation_type = 'multiplication'     -- Decision #5
      AND s.classroom_course_age BETWEEN 8 AND 15 -- {AGES}
),

-- where each fact sits in THIS app's own ranking, over ALL facts (tables up to
-- 12 included), so picking the A998 five stays auditable rather than implied
fluency_ranking AS (
    SELECT
        lo,
        hi,
        COUNT(*) AS n_fact,
        AVG(CASE WHEN res = 'Correct at first' THEN 0.0 ELSE 1.0 END) AS err_fact,
        ROW_NUMBER() OVER (
            ORDER BY AVG(CASE WHEN res = 'Correct at first' THEN 0.0 ELSE 1.0 END) DESC
        ) AS fluency_rank
    FROM base
    GROUP BY lo, hi
    HAVING COUNT(*) >= 2000
),

scoped AS (
    SELECT * FROM base
    WHERE (lo, hi) IN ((4, 8), (5, 8), (6, 8), (7, 8), (8, 8))   -- {FACTS}
),

-- per (fact, age) denominators: cards seen, and how many were missed at each try
cell_totals AS (
    SELECT
        lo,
        hi,
        age,
        COUNT(*)                                                        AS n_cards,
        SUM(CASE WHEN res = 'Correct at first' THEN 1 ELSE 0 END)       AS n_correct_first,
        SUM(CASE WHEN res <> 'Correct at first' THEN 1 ELSE 0 END)      AS n_wrong_first,
        SUM(CASE WHEN res = 'Correct at second' THEN 1 ELSE 0 END)      AS n_recovered,
        SUM(CASE WHEN res = 'Incorrect' THEN 1 ELSE 0 END)              AS n_wrong_second
    FROM scoped
    GROUP BY lo, hi, age
),

-- the two attempts, unpivoted. Attempt 2 only exists for cards that ended
-- 'Incorrect': if the card ended 'Correct at second' the second answer was
-- right, so it is not a wrong answer and must not enter the histogram.
attempts AS (
    SELECT lo, hi, age, 1 AS attempt_no, answer_1 AS answer, duration_1 AS duration,
           CASE WHEN res = 'Correct at second' THEN 1 ELSE 0 END AS recovered_at_second,
           box_from
    FROM scoped
    WHERE res <> 'Correct at first'
      AND (duration_1 IS NULL OR duration_1 >= 1.2)  -- rapid-guessing filter, see caveat above

    UNION ALL

    SELECT lo, hi, age, 2 AS attempt_no, answer_2 AS answer, duration_2 AS duration,
           0 AS recovered_at_second,
           box_from
    FROM scoped
    WHERE res = 'Incorrect'
      AND (duration_2 IS NULL OR duration_2 >= 1.2)  -- rapid-guessing filter, see caveat above
),

labelled AS (
    SELECT
        a.lo,
        a.hi,
        a.lo * a.hi AS product,
        a.age,
        a.attempt_no,
        a.recovered_at_second,
        -- TRY_CAST i no CAST: `answer` ja es un DOUBLE (TRY_CAST del text
        -- original), pero un valor absurdament gran hi cap i despres desborda
        -- l'INT. Amb ANSI mode aixo no torna NULL, PETA la query sencera --
        -- exactament el que va passar el 2026-08-25 amb la germana d'A998
        -- d'aquest fitxer i una resposta de 10 xifres ('3333339333').
        -- Amb TRY_CAST la fila torna amb user_answer NULL i el notebook la
        -- compta i la deixa fora de l'histograma en lloc de perdre la consulta.
        TRY_CAST(a.answer AS INT) AS answer,
        a.duration,
        CASE
            WHEN a.answer IS NULL                                   THEN 'no_answer'
            WHEN a.answer = a.lo * a.hi                             THEN 'equals_product'
            WHEN a.answer = 0                                       THEN 'zero'
            WHEN a.answer > 99 AND a.lo * a.hi <= 99                THEN 'too_many_digits'
            WHEN a.answer < 10 AND a.lo * a.hi >= 10                THEN 'fewer_digits'
            WHEN a.answer = a.lo + a.hi                             THEN 'sum'
            WHEN a.answer IN (a.lo * a.hi - a.lo, a.lo * a.hi + a.lo,
                              a.lo * a.hi - a.hi, a.lo * a.hi + a.hi)
                                                                    THEN 'neighbour'
            WHEN ABS(a.answer - a.lo * a.hi) <= 2                   THEN 'off_by_one'
            WHEN a.lo * a.hi BETWEEN 10 AND 99
                 AND a.answer = MOD(a.lo * a.hi, 10) * 10 + DIV(a.lo * a.hi, 10)
                                                                    THEN 'reversed'
            WHEN MOD(a.answer, a.lo) = 0 OR MOD(a.answer, a.hi) = 0  THEN 'table_multiple'
            WHEN EXISTS (SELECT 1
                         FROM (SELECT explode(sequence(0, 12)) AS x) tx
                         CROSS JOIN (SELECT explode(sequence(0, 12)) AS y) ty
                         WHERE tx.x * ty.y = a.answer)               THEN 'other_product'
            ELSE 'other'
        END AS error_type
    FROM attempts a
)

SELECT
    l.lo,
    l.hi,
    l.product,
    l.age                                                        AS classroom_course_age,
    l.attempt_no,
    l.recovered_at_second,
    l.answer                                                     AS user_answer,
    l.error_type,
    COUNT(*)                                                     AS n,
    CAST(ROUND(PERCENTILE(l.duration, 0.5), 3) AS DOUBLE)        AS median_duration,
    c.n_cards,
    c.n_correct_first,
    c.n_wrong_first,
    c.n_recovered,
    c.n_wrong_second,
    CAST(ROUND(100.0 * c.n_wrong_first / c.n_cards, 4) AS DOUBLE) AS error_pct_first_cell,
    r.fluency_rank,
    CAST(ROUND(100.0 * r.err_fact, 4) AS DOUBLE)                 AS fluency_error_pct,
    r.n_fact                                                     AS n_fact_all_ages

FROM labelled l
INNER JOIN cell_totals c ON c.lo = l.lo AND c.hi = l.hi AND c.age = l.age
LEFT  JOIN fluency_ranking r ON r.lo = l.lo AND r.hi = l.hi
GROUP BY l.lo, l.hi, l.product, l.age, l.attempt_no, l.recovered_at_second,
         l.answer, l.error_type, c.n_cards, c.n_correct_first, c.n_wrong_first,
         c.n_recovered, c.n_wrong_second, r.fluency_rank, r.err_fact, r.n_fact
ORDER BY l.lo, l.hi, l.age, l.attempt_no, n DESC
