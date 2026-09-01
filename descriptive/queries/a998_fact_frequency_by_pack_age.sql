-- =============================================================================
-- A998: how many times was each individual FACT given, per pack and per age?
-- Feeds descriptive/test_administration_over_time.ipynb (uniformity histograms)
--
-- QUESTION: inside one pack, are the facts drawn uniformly? A pack is a fixed
-- set of facts (U Pack, see the a998-pack-reference memory) and the app draws
-- items from it for the ~120 s sitting. If the draw is uniform, every fact in
-- that pack should accumulate the same number of presentations, up to sampling
-- noise. This query gives the observed counts; the notebook compares them with
-- total / n_facts and with a binomial reference band.
--
-- OUTPUT GRAIN: one row per (academic_year_id, activity_pack,
-- classroom_course_age, fact).
--   n            = statements presented (one row of fluency_test_statements =
--                  one item shown to one pupil)
--   n_excl_first = same, dropping statement_idx = 0 (Decision #7). Kept as a
--                  separate column instead of a filter so the notebook can
--                  check whether the FIRST item of a sitting is drawn from the
--                  same distribution as the rest -- a fixed warm-up item would
--                  show up as a spike in n but not in n_excl_first.
--   n_pupils     = distinct pupils who were shown that fact at least once
--   mean_statement_idx = mean position of the fact inside the sitting. This is
--                  the mechanism column: the pack is TIMED (120 s), so a pupil
--                  never reaches the end of the item list. If the list is not
--                  a fresh random permutation per pupil, items that sit early
--                  get presented more often, and mean_statement_idx will be
--                  lower exactly for the over-represented facts. Plotting
--                  n/expected against it separates "the draw is biased" from
--                  "the draw is fine but the clock truncates it".
--
-- WHY academic_year_id IS IN THE GRAIN (verified live 2026-08-18, do not drop):
-- pack content is NOT stable across academic years. Pack 20 contains 72 facts
-- (tables 2-9 x multiplier 1-9... in fact x 0-9 = 80 slots) in ES_2023+, but in
-- ES_2022 it ALSO served the eight  x1  facts (2x1 ... 9x1, ~375 presentations
-- each and only in ES_2022). Pooling years therefore mixes two different pack
-- definitions and makes a legacy fact look like a "rare" fact -- a spurious
-- non-uniformity. Keeping the year in the grain lets the notebook (a) check
-- uniformity WITHIN a year, which is the honest test, and (b) report which
-- facts exist in only some years. Region is recoverable from academic_year_id
-- (prefix before the final _YYYY), so it is not a separate column.
--
-- NO ANALYSIS FILTERS -- deliberately, same stance as the rest of this
-- notebook. All regions, all academic years, all ages (Decision #2 not
-- applied), both operations, every statement_result, no rapid-guessing filter.
-- The question is "what was administered", not "how well was it answered", so
-- filtering answers would bias the exposure counts. Ages are kept as they come,
-- including NULL (a sitting whose classroom has no course age).
--
-- FACT NORMALISATION (see the a998-pack-reference memory for the full writeup):
-- four separator glyphs exist live and they vary by region --
--   multiplication  U+00D7 'x' (all regions)  and  U+00B7 '·' (ES, MX)
--   division        ':' (all regions)         and  U+00F7 '÷' (CO-B, MX, US)
-- Classify division as "contains ':' OR '÷'" -- NOT "not a multiplication" --
-- then normalise '·' -> U+00D7 and '÷' -> ':' so that one fact is one string.
-- No ASCII 'x' occurs anywhere in A998. Verified live 2026-08-18: operation is
-- always 3-4 chars, no whitespace, multiplication operands are single digits
-- 0-9 (100 possible facts), division is dividend 0-81 : divisor 1-9 (90 facts).
-- TRY_CAST on the operands so an unvetted future format yields NULL instead of
-- failing the whole query.
--
-- Optional narrowing: uncomment the -- {YEARS} line, or filter in pandas.
-- =============================================================================

WITH base AS (
    SELECT
        s.academic_year_id,
        s.activity_pack,
        m.classroom_course_age,
        s.student_uuid,
        s.statement_idx,
        CASE WHEN s.operation LIKE '%:%' OR s.operation LIKE '%÷%'
             THEN 'division' ELSE 'multiplication' END              AS op_type,
        CASE WHEN s.operation LIKE '%:%' OR s.operation LIKE '%÷%'
             THEN REPLACE(s.operation, '÷', ':')
             ELSE REPLACE(s.operation, '·', '×') END                AS fact

    FROM bi_gold_prod.dm_research.fluency_test_statements s
    INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
            ON m.metric_id = s.metric_id

    WHERE s.activity_codename = 'A998'
      AND s.operation IS NOT NULL
      -- AND s.academic_year_id IN ('ES_2025')   -- {YEARS}
)

SELECT
    academic_year_id,
    REGEXP_EXTRACT(academic_year_id, '^(.+)_[0-9]{4}$', 1)          AS region,
    activity_pack,
    classroom_course_age,
    op_type,
    fact,
    TRY_CAST(SPLIT(fact, '[×:]')[0] AS INT)                         AS operand_1,
    TRY_CAST(SPLIT(fact, '[×:]')[1] AS INT)                         AS operand_2,
    COUNT(*)                                                        AS n,
    COUNT(CASE WHEN statement_idx >= 1 THEN 1 END)                  AS n_excl_first,
    COUNT(DISTINCT student_uuid)                                    AS n_pupils,
    CAST(ROUND(AVG(statement_idx), 3) AS DOUBLE)                    AS mean_statement_idx

FROM base
GROUP BY academic_year_id, activity_pack, classroom_course_age, op_type, fact
ORDER BY academic_year_id, activity_pack, classroom_course_age, op_type, operand_1, operand_2
