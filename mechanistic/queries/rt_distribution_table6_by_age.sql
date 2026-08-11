-- =============================================================================
-- NOT VERIFIED -- DO NOT WIRE INTO cached_query() WITHOUT FIXING FIRST.
-- Copied as-is from MULTIPLY_old/queries/ on 2026-08-11 for provenance only.
-- rt_distribution.ipynb still reads rt_distribution_table6_by_age.csv directly
-- (a hand-exported CSV), NOT this file, until it is transpiled and confirmed.
--
-- Why this can't just be pointed at Databricks:
--   1. Postgres/Redshift dialect (`::float`, `::int`, `age()`, `date_part()`)
--      against engineering-layer tables (card_attempt, card, student), not the
--      bi_gold_prod.* warehouse names used everywhere else in this project.
--   2. The file's own header already flags 3 unconfirmed identifiers (the fact
--      table + answer-time column, the "first attempt" flag, and where the
--      birthdate lives) -- these were never verified against a live schema,
--      per the ">>> CONFIRM" comments below.
--   3. `card`/`card_attempt` look like the Fluency-zone practice tables, but
--      the confirmed live Fluency table is
--      bi_gold_prod.dwh_digital_practice.f_elementary_fluency_attempts
--      (see project memory: fluency-zone-attempts-table), whose columns don't
--      match this query's names at all (attempt_result, not `attempt`;
--      first_attempt_duration, not `answer_time_first`; classroom_course_age
--      from a join, not a birth_date column).
--
-- Recommended next step: run this through the research-repo-transpile skill,
-- or hand-verify the 3 identifiers above against
-- bi_gold_prod.dwh_digital_practice.f_elementary_fluency_attempts /
-- bi_gold_prod.dwh_global_dimensions_historic.d_students, before trusting it.
-- =============================================================================

-- RT histogram of FIRST-attempt answer times, table of 6, resolved by AGE and FACT.
-- Output shape (one row per non-empty histogram cell):
--   operation | age | rt_bin | n
-- Same 0.5 s bin width (BINW) as rt_distribution_table6.csv, so the Python side is unchanged.
--
-- This is the same source as rt_distribution_table6.csv (fluency-practice CardAttempt data,
-- the one with box_from A/B/C/D/E/Memory), with ONE extra grouping dimension: age.
--
-- >>> CONFIRM 3 identifiers against the Metabase question that produced rt_distribution_table6.csv:
--     1. the CardAttempt fact table + its answer-time column      -> here: ca.answer_time_first
--     2. the correct "first attempt" flag / column                -> here: attempt = 'first'
--     3. where the student birthdate lives                        -> here: s.birth_date
-- Everything else mirrors the existing query.

WITH BINW AS (SELECT 0.5::float AS w)

SELECT
    -- Innovamat notation: "6 X b" = b-th multiple of the 6 table (matches existing CSVs)
    '6 X ' || c.first_operand::int                        AS operation,

    -- AGE in whole years at the moment of the attempt.
    -- Swap to months for finer resolution:  floor(months_between(ca.created_at, s.birth_date))
    date_part('year', age(ca.created_at, s.birth_date))::int  AS age,

    -- 0.5 s histogram bin (left edge), identical to BINW in the notebook
    floor(ca.answer_time_first / (SELECT w FROM BINW)) * (SELECT w FROM BINW) AS rt_bin,

    count(*)                                              AS n

FROM card_attempt      ca                 -- <-- confirm fact table
JOIN card              c  ON c.id = ca.card_id
JOIN student           s  ON s.id = ca.student_id
WHERE c.operator        = 'multiplication'
  AND c.second_operand  = 6                 -- table of 6  (Innovamat: m = table number)
  AND c.first_operand BETWEEN 1 AND 9       -- 6x1 .. 6x9
  AND ca.attempt        = 'first'           -- <-- confirm first-attempt filter
  AND ca.answer_time_first IS NOT NULL
  AND ca.answer_time_first >  0
  AND ca.answer_time_first <= 40            -- same upper guard as the RT-cleaning step
  AND s.birth_date IS NOT NULL
  -- optional: restrict to a sensible school-age band so stray ages don't create empty columns
  AND date_part('year', age(ca.created_at, s.birth_date)) BETWEEN 6 AND 14
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
