WITH stmts AS (
    SELECT
        user_id,
        activity_pack,
        COUNT(*)                                                            AS statements,
        SUM(CASE WHEN statement_result = 'Correct'   THEN 1 ELSE 0 END)   AS correct,
        SUM(CASE WHEN statement_result = 'Incorrect' THEN 1 ELSE 0 END)   AS incorrect,
        SUM(CASE WHEN statement_result = 'Help'      THEN 1 ELSE 0 END)   AS help,
        MAX(finished_at) / 1000.0                                          AS total_seconds
    FROM bi_silver_prod.staging_platform.all_fluency_test_statements
    WHERE activity_codename = 'A998'
      AND db_source         = 'platform_europe'
      AND response_at >= '2026-07-16' AND response_at < '2026-07-17'
    GROUP BY user_id, activity_pack
)
SELECT
    u.name || ' ' || u.surname                                                          AS student,
    MAX(CASE WHEN s.activity_pack = 39 THEN s.statements  END)                         AS pack39_stmts,
    MAX(CASE WHEN s.activity_pack = 39 THEN s.correct     END)                         AS pack39_correct,
    MAX(CASE WHEN s.activity_pack = 39 THEN s.incorrect   END)                         AS pack39_incorrect,
    MAX(CASE WHEN s.activity_pack = 39
        THEN ROUND(s.correct   / NULLIF(s.total_seconds, 0) * 60, 2) END)              AS pack39_correct_per_min,
    MAX(CASE WHEN s.activity_pack = 39
        THEN ROUND(s.incorrect / NULLIF(s.total_seconds, 0) * 60, 2) END)              AS pack39_incorrect_per_min,
    MAX(CASE WHEN s.activity_pack = 39
        THEN ROUND((s.correct - s.incorrect) / NULLIF(s.total_seconds, 0) * 60, 2) END) AS corrected_per_min,
    SUM(s.statements)                                                                   AS total_stmts
FROM stmts s
JOIN bronze_prod.source_context_platform_europe.`user` u
  ON CAST(u.id AS STRING) || '-E' = s.user_id
GROUP BY u.name, u.surname
ORDER BY total_stmts DESC;