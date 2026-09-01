-- =============================================================================
-- A998: QUAN comenca el racing dins d'una sessio (i que passa amb l'encert
-- abans i despres d'aquell moment)
-- =============================================================================
-- Pregunta: el racing es un estat de tota la sessio (l'alumne ja hi entra a tota
-- velocitat) o arrenca a partir d'un cert punt (es cansa, se li acaba el temps,
-- decideix acabar rapid)? El flag `racing_sitting` de la Decisio #12 es de
-- SESSIO SENCERA i per construccio no pot respondre aixo: es constant dins de la
-- sessio. Aixo demana un punt de canvi dins de la sessio.
--
-- DEFINICIO D'INICI ("onset"): la primera posicio on comencen RUN_LEN = 3
-- respostes CONSECUTIVES per sota d'1,5 s. Dues peces, cap arbitraria:
--   * 1,5 s es l'antimode de la distribucio de medianes de RT per sessio, el
--     mateix llindar de la Decisio #12, aqui a nivell d'item.
--   * exigir 3 seguides evita comptar com "inici del racing" una sola resposta
--     rapida (un fact que l'alumne domina es contesta en menys d'1,5 s sense cap
--     problema). Es una RATXA, no un item.
-- Si es vol una altra definicio, canvia els LEAD() del CTE `runs`: hi ha
-- LEAD(...,1) i LEAD(...,2) precisament perque RUN_LEN = 3.
--
-- GRAIN: una fila per pack run (session_id, activity_pack) -- ~400k files per a
-- ES_2025, prou petit per baixar-lo sencer i fer histogrames al notebook.
--
-- Columnes clau:
--   onset_position   posicio (1-based) on arrenca la primera ratxa rapida.
--                    NULL = aquesta sessio no arrenca mai (la majoria).
--   onset_rel        onset_position / sitting_n. Si el racing fos "es cansa al
--                    final", onset_rel s'acumularia prop d'1; si es "hi entra
--                    de cara", prop de 0.
--   n_before/k_before, n_after/k_after   encert abans i a partir de l'onset,
--                    DINS DE LA MATEIXA SESSIO. Es la comparacio que fa de
--                    control d'ell mateix: mateix alumne, mateix dia, mateix
--                    pack, nomes canvia el tram.
--   p50_rt_before / p50_rt_after   el mateix per al temps per item.
--   racing_sitting   el flag de sessio sencera de la Decisio #12, per poder
--                    veure quanta gent el flag captura i quanta se li escapa
--                    (una sessio que corre nomes els ultims 10 items te
--                    mediana global alta i no queda marcada).
--
-- Cap filtre d'analisi aplicat. El primer statement (statement_idx = 0) SI que
-- compta per a la ratxa (una sessio pot arrencar rapida des del primer item),
-- pero es marca a part amb `k_before`/`n_before` calculats des de idx >= 1 quan
-- l'onset es posterior; les metriques de sessio (p50_rt, acc) es calculen sobre
-- idx >= 1 perque l'item 0 absorbeix el compte enrere.
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

runs AS (
    SELECT
        s.*,
        LEAD(is_fast, 1) OVER (PARTITION BY session_id, activity_pack
                               ORDER BY statement_idx) AS fast_1,
        LEAD(is_fast, 2) OVER (PARTITION BY session_id, activity_pack
                               ORDER BY statement_idx) AS fast_2
    FROM stmts s
),

onset AS (
    SELECT
        session_id,
        activity_pack,
        MIN(CASE WHEN is_fast = 1 AND fast_1 = 1 AND fast_2 = 1
                 THEN statement_idx END)                 AS onset_idx
    FROM runs
    GROUP BY session_id, activity_pack
)

SELECT
    s.age                                                AS classroom_course_age,
    s.activity_pack,
    XXHASH64(CONCAT_WS('|', s.session_id, CAST(s.activity_pack AS STRING))) AS sitting_key,

    COUNT(*)                                             AS sitting_n,
    ROUND(SUM(s.rt_seconds), 2)                          AS sitting_sum_rt,
    ROUND(PERCENTILE(CASE WHEN s.statement_idx >= 1 THEN s.rt_seconds END, 0.5), 3) AS p50_rt,
    ROUND(AVG(CAST(CASE WHEN s.statement_idx >= 1 THEN s.is_correct END AS DOUBLE)), 4) AS sitting_acc,
    SUM(s.is_fast)                                       AS n_fast,

    o.onset_idx + 1                                      AS onset_position,
    ROUND((o.onset_idx + 1) / COUNT(*), 4)               AS onset_rel,

    SUM(CASE WHEN s.statement_idx >= 1
              AND (o.onset_idx IS NULL OR s.statement_idx < o.onset_idx)
             THEN 1 ELSE 0 END)                          AS n_before,
    SUM(CASE WHEN s.statement_idx >= 1
              AND (o.onset_idx IS NULL OR s.statement_idx < o.onset_idx)
             THEN s.is_correct ELSE 0 END)               AS k_before,
    SUM(CASE WHEN o.onset_idx IS NOT NULL AND s.statement_idx >= o.onset_idx
             THEN 1 ELSE 0 END)                          AS n_after,
    SUM(CASE WHEN o.onset_idx IS NOT NULL AND s.statement_idx >= o.onset_idx
             THEN s.is_correct ELSE 0 END)               AS k_after,
    ROUND(PERCENTILE(CASE WHEN s.statement_idx >= 1
                           AND (o.onset_idx IS NULL OR s.statement_idx < o.onset_idx)
                          THEN s.rt_seconds END, 0.5), 3) AS p50_rt_before,
    ROUND(PERCENTILE(CASE WHEN o.onset_idx IS NOT NULL AND s.statement_idx >= o.onset_idx
                          THEN s.rt_seconds END, 0.5), 3) AS p50_rt_after,

    CASE WHEN PERCENTILE(CASE WHEN s.statement_idx >= 1 THEN s.rt_seconds END, 0.5) < 1.5
              AND AVG(CAST(CASE WHEN s.statement_idx >= 1 THEN s.is_correct END AS DOUBLE)) < 0.25
         THEN TRUE ELSE FALSE END                        AS racing_sitting

FROM stmts s
INNER JOIN onset o
        ON o.session_id = s.session_id AND o.activity_pack = s.activity_pack
GROUP BY s.age, s.activity_pack, s.session_id, o.onset_idx
