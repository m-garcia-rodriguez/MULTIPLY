-- =============================================================================
-- A998: every attempt on a multiplication fact, ALL academic years and regions
-- =============================================================================
-- Step 1 for rapid-guessing detection: a plain attempt-level extraction. No
-- rapid-guessing flag or filter applied yet -- that gets decided on top of this
-- raw pull, most likely at the (session_id, activity_pack) "sitting" level the
-- way the existing racing_sitting heuristic works (median RT < 1.5s AND
-- accuracy < 25%, Decision #12) -- which is why session_id, activity_pack and
-- statement_idx travel along even though they weren't explicitly asked for:
-- they're what a sitting-level flag needs next.
--
-- Grain: one row per statement_id = one attempt at one multiplication fact.
-- Nothing dropped or aggregated -- "all attempts" taken literally, so unlike
-- most other A998 queries in this repo this does NOT apply:
--   - Decision #7 (drop statement_idx = 0)
--   - Decision #2 (restrict classroom_course_age to 8-15)
-- both were scoped to the ES-only poster work. Uncomment the two WHERE lines
-- below if you want this to match those figures instead.
--
-- REGION: no region column exists on either table -- academic_year_id is
-- "<REGION>_<YEAR>" (ES_2025, MX_2025, CO-A_2024, ...). Verified live
-- 2026-08-13: 10 regions currently have A998 data -- BR, CL, CO-A, CO-B,
-- EC-CO, EC-SI, ES, IT, MX, US.
--
-- MULTIPLICATION FILTER -- verified live across all 10 regions 2026-08-13:
--   multiplication separators: ×  (U+00D7, all regions)
--                               ·  (U+00B7 middle dot, ES and MX only)
--   division separators:       :  (all regions)
--                               ÷  (U+00F7 division sign, CO-B / MX / US only)
-- Classifying on ':' alone (the old ES-only rule) mis-files every ÷-division
-- row in CO-B/MX/US as a multiplication. Excluding BOTH ':' and '÷' fixes it.
-- No region uses an ASCII 'x'.
--
-- TRY_CAST instead of CAST on the parsed factors: defensive, because this now
-- covers 9 regions' operation formats that haven't been individually audited
-- the way ES has. A row that fails to parse comes back with NULL factors
-- (operation_raw is kept so it's visible) instead of crashing the query.
-- =============================================================================

SELECT
    REGEXP_EXTRACT(s.academic_year_id, '^(.+)_[0-9]{4}$', 1)        AS region,
    s.academic_year_id,
    m.classroom_course_age,
    s.student_uuid,
    s.session_id,
    s.activity_pack,
    s.statement_id,
    s.statement_idx,
    s.operation                                                    AS operation_raw,
    TRY_CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[0] AS INT)  AS factor_1,
    TRY_CAST(SPLIT(REPLACE(s.operation, '·', '×'), '×')[1] AS INT)  AS factor_2,
    s.statement_result,
    CASE WHEN s.statement_result = 'Correct' THEN 1 ELSE 0 END      AS is_correct,
    CAST(s.statement_seconds_spent AS DOUBLE)                       AS rt_seconds

FROM bi_gold_prod.dm_research.fluency_test_statements s
INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
        ON m.metric_id = s.metric_id

WHERE s.activity_codename        = 'A998'
  AND s.operation NOT LIKE '%:%'          -- exclude divisions (':' form)
  AND s.operation NOT LIKE '%÷%'          -- exclude divisions ('÷' form -- CO-B/MX/US)
  AND s.statement_seconds_spent IS NOT NULL   -- "time taken to respond" needs a value
  -- AND s.statement_idx >= 1                    -- Decision #7, uncomment to match other figures
  -- AND m.classroom_course_age BETWEEN 8 AND 15 -- Decision #2, uncomment to match the ES poster range

ORDER BY region, academic_year_id, classroom_course_age, student_uuid, session_id, statement_idx