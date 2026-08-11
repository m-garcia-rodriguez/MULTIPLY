-- Reaction times for every answer in the A998 activity.
-- Output shape: one row per answered statement (one operation attempt).
--   student_uuid | session_id | statement_idx | operation | user_answer
--   | statement_result | rt_seconds | response_at | academic_year_id
--
-- Source: bi_gold_prod.dm_research.fluency_test_statements (one row per user
-- answer to a fluency statement). "A998" is the activity_codename here -- the
-- statement_id column is a per-answer hash, NOT the human code, so we filter on
-- activity_codename. A998 is the multiplication/division fluency test.
--
-- Reaction time = statement_seconds_spent (seconds spent on that statement/answer).
-- Sanity check on the full activity: ~27.4M answers, ~394.8k students,
-- rt range 0.08 s .. 120 s, mean ~4.7 s (120 s = per-PACK ceiling, not per-statement --
-- see project memory a998-pack-duration-120s).
--
-- MIGRATION NOTES (2026-08-11, migrating this query from MULTIPLY_old/queries/
-- into the new repo -- NOT YET RE-RUN LIVE, verify before trusting results):
--   1. Schema prefix fixed: `research.*` -> `bi_gold_prod.dm_research.*`, per
--      the project's Databricks-migration convention (query-execution-workflow
--      memory). The original file still said `FROM research.fluency_test_statements`,
--      a pre-migration Redshift-era name that does not exist on Databricks.
--   2. `operation` is now normalised (see project memory a998-pack-reference /
--      the "separator gotcha"): live multiplications use U+00D7 '×' OR
--      U+00B7 '·' (never ASCII "X"/"x", and never mixed within one string).
--      The original comment on this file ("e.g. 6X2") describes a format that
--      does not occur in live data. REPLACE(operation, '·', '×') below makes
--      every multiplication use '×', so client code can match on '×' alone.
SELECT
    student_uuid,
    session_id,
    statement_idx,                       -- position of the answer within the session
    REPLACE(operation, '·', '×') AS operation,   -- normalised: '×' for every multiplication
    user_answer,
    statement_result,                    -- 'Correct' / 'Incorrect' / 'Help'
    statement_seconds_spent AS rt_seconds,
    response_at,
    academic_year_id
FROM bi_gold_prod.dm_research.fluency_test_statements
WHERE activity_codename = 'A998'
  AND statement_result  = 'Correct'      -- correct answers only
  AND statement_seconds_spent IS NOT NULL
-- Optional RT guards (uncomment to mirror the RT-cleaning step used elsewhere in MULTIPLY):
--   AND statement_seconds_spent > 0
--   AND statement_seconds_spent <= 40
ORDER BY student_uuid, session_id, statement_idx;
