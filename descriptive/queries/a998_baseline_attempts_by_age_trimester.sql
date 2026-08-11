-- =============================================================================
-- A998 BASELINE: number of test sittings (attempts) per AGE x TRIMESTER
-- =============================================================================
-- Transpiled from the former Redshift original (now replaced).
-- Transpiled by the research-repo-transpile skill, following
--   references/OBJECT_MAPPING.md  and  references/REDSHIFT_TO_DATABRICKS_SQL.md
--
-- CHANGES vs the Redshift original (only these — logic kept faithful):
--   1. research.fluency_test_metrics
--        -> bi_gold_prod.dm_research.fluency_test_metrics
--      Mandatory `research` -> `dm_research` rename (OBJECT_MAPPING §2) plus the
--      three-part catalog.schema.table form. A two-part name would silently
--      resolve against whatever catalog the session happens to use.
--      NOTE: do NOT use `bi_gold_prod.research` — that is the pre-rename copy.
--   2. Dropped the `-- Active:` header line: it is a Redshift connection marker
--      written by the Cursor DB extension and has no meaning on Databricks.
--
-- NOT changed (verified against the dialect reference, all valid on DBSQL):
--   * `response_at::date`      — the `::` operator and `::date` are supported.
--   * `DATE 'yyyy-mm-dd'`      — typed date literals are supported.
--   * `GROUP BY 1, 2`          — positional grouping is fine here (the
--                                STAR_GROUP_BY_POS trap needs `count(t.*)`;
--                                we use `count(*)`).
--   * `ORDER BY <select alias>` — allowed; only WHERE may not reference aliases.
--   No getdate / varchar / float8 / quoted identifiers / to_char masks / regex
--   operators / UDFs present, so none of the §2 silent-failure traps apply.
--
-- >>> STILL UNVERIFIED (needs a Databricks connection to confirm):
--     (a) `activity_codename` and `classroom_course_age` exist with these names
--         in bi_gold_prod.dm_research.fluency_test_metrics.
--     (b) grain: whether one row = one sitting (see the note in the original).
--         Check with:  databricks --profile bi-prod tables get \
--                        bi_gold_prod.dm_research.fluency_test_metrics
--
-- Decisions applied (Learning_Team_Plots/Decisions.txt):
--   #1 A998 only · #2 ages 8-15 (6,7 dropped) · #4 age x trimester kept split
--   because packs change per trimester · #6 source = fluency_test_metrics
--
-- Trimester windows below are the CURRENT edited ones; keep them in sync with
-- the Redshift original so both versions stay comparable.
-- =============================================================================

SELECT
    classroom_course_age,

    CASE
        WHEN response_at::date BETWEEN DATE '2025-11-01' AND DATE '2025-12-20' THEN 'T1'
        WHEN response_at::date BETWEEN DATE '2026-02-15' AND DATE '2026-03-30' THEN 'T2'
        WHEN response_at::date BETWEEN DATE '2026-04-29' AND DATE '2026-06-05' THEN 'T3'
        ELSE 'other'                                             -- outside official windows; inspect, don't assume
    END                                        AS trimester,

    COUNT(*)                                   AS n_attempts     -- one row per sitting

FROM bi_gold_prod.dm_research.fluency_test_metrics               -- was: research.fluency_test_metrics
WHERE activity_codename = 'A998'
  AND classroom_course_age BETWEEN 8 AND 15
  AND response_at IS NOT NULL
  AND response_at >= DATE '2025-09-01'                           -- academic year 2025-26 only
GROUP BY 1, 2
ORDER BY classroom_course_age, trimester;
