-- =============================================================================
-- A998: com canvia el RITME (temps per item i % de respostes rapides) segons la
-- posicio dins del pack -- es a dir, hi ha un moment on comencen a fer racing?
-- =============================================================================
-- Companya de a998_position_effect_6x8.sql. Aquella pregunta "canvia l'encert de
-- 6x8 segons quan surt?"; aquesta pregunta "canvia el RITME segons quan surt?",
-- que es el que decideix si el "racing" es un estat de tota la sessio o una cosa
-- que arrenca a partir d'un cert punt.
--
-- GRAIN: una fila per (classroom_course_age, band, position).
--   position = statement_idx + 1
--   band     = tram de longitud de la sessio (nombre d'statements del pack run)
-- El band es imprescindible: comparar `statement_idx` cru entre sessions de
-- longitud diferent ja va donar un fals "efecte final de pack" al bloc
-- 66/67/76/77 (nota a998-endofpack-keyboard-noise). Dins d'un mateix band totes
-- les sessions tenen espai per arribar a la mateixa posicio, aixi que un canvi
-- de ritme al llarg de la posicio ja no pot venir de la barreja de longituds.
--
-- TOTS els statements, no nomes 6x8: el ritme es una propietat de la sessio i
-- amb un sol fact no hi hauria prou punts per posicio.
--
-- Metrica de "rapid": rt < 1.5 s. NO es un llindar triat a ull -- 1,5 s es
-- l'antimode de la distribucio de medianes de RT per sessio, i l'encert de la
-- sessio fa un salt exactament alli (8-18% per sota, 57,6% a 1,7 s). Mateix
-- llindar que fa servir el flag racing_sitting de la Decisio #12, aqui aplicat
-- a l'ITEM en lloc de a la sessio sencera.
--
-- No hi ha cap filtre d'analisi: ni racing, ni primer statement, ni res. Les
-- columnes permeten reconstruir qualsevol subpoblacio al notebook.
--
-- Scope: A998, ES_2025 (marcador -- {YEARS}), classroom_course_age 8-15.
-- =============================================================================

WITH stmts AS (
    SELECT
        s.session_id,
        s.activity_pack,
        s.statement_idx,
        s.statement_seconds_spent                                   AS rt_seconds,
        m.classroom_course_age                                      AS age,
        CASE WHEN s.statement_result = 'Correct' THEN 1 ELSE 0 END  AS is_correct,
        CASE WHEN s.statement_seconds_spent < 1.5 THEN 1 ELSE 0 END AS is_fast
    FROM bi_gold_prod.dm_research.fluency_test_statements s
    INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
            ON m.metric_id = s.metric_id
    WHERE s.activity_codename = 'A998'
      AND s.academic_year_id IN ('ES_2025')   -- {YEARS}
      AND m.classroom_course_age BETWEEN 8 AND 15
),

sit AS (
    SELECT session_id, activity_pack, COUNT(*) AS sitting_n
    FROM stmts GROUP BY session_id, activity_pack
),

joined AS (
    SELECT
        s.*,
        t.sitting_n,
        CASE WHEN t.sitting_n <= 10 THEN '1: 1-10 items'
             WHEN t.sitting_n <= 20 THEN '2: 11-20 items'
             WHEN t.sitting_n <= 35 THEN '3: 21-35 items'
             ELSE                       '4: 36+ items'  END AS band
    FROM stmts s
    INNER JOIN sit t
            ON t.session_id = s.session_id AND t.activity_pack = s.activity_pack
)

SELECT
    age                                                  AS classroom_course_age,
    band,
    statement_idx + 1                                    AS position,
    COUNT(*)                                             AS n,
    COUNT(DISTINCT CONCAT_WS('|', session_id, CAST(activity_pack AS STRING))) AS n_sittings,
    SUM(is_correct)                                      AS n_correct,
    SUM(is_fast)                                         AS n_fast,
    ROUND(PERCENTILE(rt_seconds, 0.25), 3)               AS p25_rt,
    ROUND(PERCENTILE(rt_seconds, 0.5), 3)                AS p50_rt,
    ROUND(PERCENTILE(rt_seconds, 0.75), 3)               AS p75_rt
FROM joined
GROUP BY age, band, statement_idx
ORDER BY age, band, position
