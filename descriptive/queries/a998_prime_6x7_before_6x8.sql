-- =============================================================================
-- A998: haver vist 6x7 ABANS canvia el rendiment a 6x8 dins de la mateixa sessio?
-- =============================================================================
-- Continuacio de a998_position_effect_6x8.sql (mateix grain, mateixes claus, un
-- registre per intent de 6x8) amb l'exposicio previa afegida. Dues variables de
-- resultat, no una:
--   is_correct    encert de 6x8 (statement_result = 'Correct')
--   answered_42   la resposta escrita es EXACTAMENT '42', el producte de 6x7.
--                 Es la firma d'interferencia: no "falla", sino "falla DIENT el
--                 resultat del fact que acaba de veure".
--
-- EXPOSICIO (una fila per intent de 6x8, mirant nomes cap enrere dins del mateix
-- pack run, ordenat per statement_idx):
--   seen_6x7_before   0/1, ha aparegut 6x7 abans en aquesta sessio
--   n_6x7_before      quantes vegades
--   lag_items         distancia en items des de l'ultima aparicio de 6x7
--   prev_6x7_correct  si aquella ultima aparicio de 6x7 la va encertar
--
-- GRUP PLACEBO (afegit 2026-08-20):
--   seen_6x7_after / n_6x7_after / lead_items   el mateix mirant cap ENDAVANT: 6x7 surt
--                    DESPRES d'aquest 6x8 dins de la mateixa sessio, i a quina distancia.
--   Per que: la hipotesi alternativa a el priming es que els alumnes rapids fan mes items
--   i, per tant, topen mes sovint amb el 6x7 abans del 6x8. Aquests mateixos alumnes, si el
--   6x7 els surt DESPRES, tambe son rapids -- pero alli el 6x7 encara no els podia haver
--   activat res. Per tant: placebo mes rapid que el grup sense 6x7 = seleccio; placebo igual
--   que el grup sense 6x7, i nomes el grup "abans" mes rapid = compatible amb priming.
--   El notebook fa la comparacio dins d'una FINESTRA SIMETRICA de +-K items al voltant del
--   6x8 (nomes files amb K items abans i K items despres), de manera que els tres grups han
--   tingut la mateixa oportunitat estructural de veure el 6x7 a cada banda.
--
-- >>> EL CONFUSOR PRINCIPAL, I PER QUE CAL CONTROLAR PER POSICIO: la probabilitat
--     d'haver vist 6x7 abans creix MECANICAMENT amb la posicio de 6x8 (a la
--     posicio 3 gairebe ningu l'ha vist; a la posicio 40 gairebe tothom). I la
--     posicio, al seu torn, esta lligada a qui hi arriba i a quin ritme
--     (a998_position_effect_6x8.sql). Sense condicionar per posicio, l'efecte de
--     l'exposicio i l'efecte de la posicio son el mateix numero.
--     Condicionant per posicio, en canvi, l'exposicio queda gairebe aleatoritzada:
--     el pack sorteja els items de manera aproximadament uniforme (uniformitat
--     verificada a ~pocs % -- veure la nota a998-pack-fact-uniformity), aixi que
--     "em va sortir 6x7 abans o no" es essencialment un sorteig dins d'una mateixa
--     posicio i un mateix pack.
--
-- >>> EL PACK 16 NO TE 6x7. El seu conjunt real es {a×2, a×4, a×5, a×8} (verificat
--     en viu, no del document de especificacio). Per tant l'exposicio hi es
--     IMPOSSIBLE per construccio, i incloure'l nomes afegiria files amb
--     seen_6x7_before = 0 que no son comparables. La columna `pack_has_6x7` es
--     calcula des de les dades (MAX per pack x any), no des de la especificacio,
--     i el notebook filtra amb ella. Conseqüencia a dir en veu alta: l'edat 8 es
--     queda gairebe nomes amb el pack 20, i perd ~2/3 de la mostra.
--
-- CONTROLS DE ESPECIFICITAT (mateixa construccio, altres primes) -- serveixen per
-- distingir "6x7 activa el 42" de "qualsevol fact que comparteix un operand mou
-- alguna cosa":
--   seen_7x6_before        la forma commutada del mateix fact
--   seen_6xN_other_before  6xk amb k <> 7, 8  (comparteix el 6, no es el prime)
--   seen_Nx8_other_before  kx8 amb k <> 6     (comparteix el 8, no es el prime)
--   seen_42_numeral_before una divisio '42:k', l'unica manera que el numeral 42
--                          aparegui a la pantalla sense ser el resultat de 6x7.
--                          Si el 42 apareix per haver-lo LLEGIT i no per haver
--                          calculat 6x7, aquesta columna ho ha de captar.
--
-- ARTEFACTE DE PULSACIO I EL 42: `user_answer` es una pulsacio, no sempre una
-- resposta (nota a998-user-answer-keystroke-artefact). 42 te dos digits, aixi que
-- un '4' sol pot ser un 42 truncat i pot ser rebutjat abans d'acabar-lo. Es
-- retorna `answered_4_only` a part per poder posar cota superior i inferior a la
-- taxa de 42; answered_42 nomes compta la cadena exacta '42'.
--
-- RACING: es retorna el flag, no es filtra aqui. L'analisi principal el filtra al
-- notebook (Maria, 2026-08-18: analisi principal nomes amb sessions NO racing).
--
-- Decisions: #1 A998, #2 edats 8-15, #8 ES_2025 via -- {YEARS}. #7 (fora
-- statement_idx = 0) NO s'aplica aqui: un 6x8 a la posicio 1 te exposicio 0 per
-- construccio i el notebook decideix. #12 racing com a flag.
--
-- Separador: ES fa servir U+00D7 '×' i U+00B7 '·' per a la multiplicacio, mai una
-- x ASCII; tot es normalitza a '×' abans de comparar. Les divisions porten ':'.
-- =============================================================================

WITH stmts AS (
    SELECT
        s.session_id,
        s.activity_pack,
        s.statement_idx,
        s.statement_seconds_spent                                   AS rt_seconds,
        REPLACE(s.operation, '·', '×')                              AS op_norm,
        s.statement_result,
        s.user_answer,
        s.student_uuid,
        s.academic_year_id,
        m.classroom_course_age                                      AS age,
        CASE WHEN s.statement_result = 'Correct' THEN 1 ELSE 0 END  AS is_correct
    FROM bi_gold_prod.dm_research.fluency_test_statements s
    INNER JOIN bi_gold_prod.dm_research.fluency_test_metrics m
            ON m.metric_id = s.metric_id
    WHERE s.activity_codename = 'A998'
      AND s.academic_year_id IN ('ES_2025')   -- {YEARS}
      AND m.classroom_course_age BETWEEN 8 AND 15
),

flags AS (
    SELECT
        *,
        CASE WHEN op_norm = '6×7' THEN 1 ELSE 0 END AS is_6x7,
        CASE WHEN op_norm = '7×6' THEN 1 ELSE 0 END AS is_7x6,
        CASE WHEN op_norm LIKE '6×%' AND op_norm NOT IN ('6×7', '6×8')
             THEN 1 ELSE 0 END                      AS is_6xN_other,
        CASE WHEN op_norm LIKE '%×8' AND op_norm <> '6×8'
             THEN 1 ELSE 0 END                      AS is_Nx8_other,
        CASE WHEN op_norm LIKE '42:%' THEN 1 ELSE 0 END AS is_42_numeral
    FROM stmts
),

-- Quins packs contenen realment 6x7, mesurat a les dades (el pack 16 no).
pack_content AS (
    SELECT academic_year_id, activity_pack,
           MAX(is_6x7) AS pack_has_6x7,
           MAX(is_7x6) AS pack_has_7x6
    FROM flags
    GROUP BY academic_year_id, activity_pack
),

-- Dues finestres: `w` mira NOMES cap enrere (UNBOUNDED PRECEDING .. 1 PRECEDING) i
-- `wf` NOMES cap endavant (1 FOLLOWING .. UNBOUNDED FOLLOWING). La segona serveix per
-- al grup PLACEBO: alumnes que van veure 6x7 en aquella sessio pero DESPRES d'aquest
-- 6x8. Si el placebo tambe surt mes rapid que qui no el veu mai, el que mesuravem era
-- que els alumnes rapids fan mes items i per tant topen mes amb el 6x7 -- seleccio, no
-- priming. Es la comparacio que decideix (Maria, 2026-08-20).
hist AS (
    SELECT
        f.*,
        COALESCE(SUM(f.rt_seconds) OVER w, 0)            AS elapsed_s,
        COALESCE(MAX(f.is_6x7) OVER w, 0)                AS seen_6x7_before,
        COALESCE(SUM(f.is_6x7) OVER w, 0)                AS n_6x7_before,
        COALESCE(MAX(f.is_7x6) OVER w, 0)                AS seen_7x6_before,
        COALESCE(MAX(f.is_6xN_other) OVER w, 0)          AS seen_6xN_other_before,
        COALESCE(MAX(f.is_Nx8_other) OVER w, 0)          AS seen_Nx8_other_before,
        COALESCE(MAX(f.is_42_numeral) OVER w, 0)         AS seen_42_numeral_before,
        LAST_VALUE(CASE WHEN f.is_6x7 = 1 THEN f.statement_idx END)
            IGNORE NULLS OVER w                          AS prev_6x7_idx,
        LAST_VALUE(CASE WHEN f.is_6x7 = 1 THEN f.is_correct END)
            IGNORE NULLS OVER w                          AS prev_6x7_correct,

        -- cap endavant (placebo)
        COALESCE(MAX(f.is_6x7) OVER wf, 0)               AS seen_6x7_after,
        COALESCE(SUM(f.is_6x7) OVER wf, 0)               AS n_6x7_after,
        FIRST_VALUE(CASE WHEN f.is_6x7 = 1 THEN f.statement_idx END)
            IGNORE NULLS OVER wf                         AS next_6x7_idx
    FROM flags f
    WINDOW w AS (PARTITION BY f.session_id, f.activity_pack
                 ORDER BY f.statement_idx
                 ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
           wf AS (PARTITION BY f.session_id, f.activity_pack
                  ORDER BY f.statement_idx
                  ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING)
),

sitting AS (
    SELECT
        session_id,
        activity_pack,
        COUNT(*)                                                     AS sitting_n,
        SUM(CASE WHEN statement_idx = 0 THEN 1 ELSE 0 END)           AS n_starts,
        COUNT(DISTINCT statement_idx)                                AS n_distinct_idx,
        PERCENTILE(CASE WHEN statement_idx >= 1 THEN rt_seconds END, 0.5) AS sitting_median_rt,
        AVG(CAST(CASE WHEN statement_idx >= 1 THEN is_correct END AS DOUBLE)) AS sitting_acc,
        SUM(CASE WHEN statement_idx >= 1 AND op_norm <> '6×8' THEN 1 ELSE 0 END) AS n_other,
        SUM(CASE WHEN statement_idx >= 1 AND op_norm <> '6×8' THEN is_correct ELSE 0 END) AS n_other_correct
    FROM stmts
    GROUP BY session_id, activity_pack
),

target AS (
    SELECT
        h.*,
        ROW_NUMBER() OVER (PARTITION BY h.session_id, h.activity_pack
                           ORDER BY h.statement_idx)                 AS occurrence_no
    FROM hist h
    WHERE h.op_norm = '6×8'
)

SELECT
    t.academic_year_id,
    t.activity_pack,
    pc.pack_has_6x7,
    pc.pack_has_7x6,
    t.age                                        AS classroom_course_age,
    XXHASH64(t.student_uuid)                     AS student_key,
    XXHASH64(CONCAT_WS('|', t.session_id, CAST(t.activity_pack AS STRING))) AS sitting_key,

    t.statement_idx,
    t.statement_idx + 1                          AS position,
    ROUND(t.elapsed_s, 3)                        AS elapsed_s,
    t.rt_seconds,
    t.occurrence_no,

    -- exposicio
    t.seen_6x7_before,
    t.n_6x7_before,
    t.statement_idx - t.prev_6x7_idx             AS lag_items,
    t.prev_6x7_correct,
    -- placebo: 6x7 apareix DESPRES d'aquest 6x8, a la mateixa sessio
    t.seen_6x7_after,
    t.n_6x7_after,
    t.next_6x7_idx - t.statement_idx             AS lead_items,

    t.seen_7x6_before,
    t.seen_6xN_other_before,
    t.seen_Nx8_other_before,
    t.seen_42_numeral_before,

    -- resultats
    t.is_correct,
    CASE WHEN TRIM(t.user_answer) = '42' THEN 1 ELSE 0 END  AS answered_42,
    CASE WHEN TRIM(t.user_answer) = '4'  THEN 1 ELSE 0 END  AS answered_4_only,
    t.statement_result,
    CASE
        WHEN t.statement_result = 'Correct'        THEN 'correct'
        WHEN t.statement_result = 'Help'           THEN 'help'
        WHEN t.user_answer IS NULL                 THEN 'no_answer'
        WHEN LENGTH(TRIM(t.user_answer)) = 1       THEN 'wrong_1digit'
        WHEN LENGTH(TRIM(t.user_answer)) = 2       THEN 'wrong_2digit'
        ELSE 'wrong_other'
    END                                          AS answer_class,

    -- context de la sessio
    st.sitting_n,
    ROUND(st.sitting_median_rt, 3)               AS sitting_median_rt,
    ROUND(st.sitting_acc, 4)                     AS sitting_acc,
    st.n_other,
    st.n_other_correct,
    CASE WHEN st.sitting_median_rt < 1.5 AND st.sitting_acc < 0.25
         THEN TRUE ELSE FALSE END                AS racing_sitting,
    CASE WHEN st.n_starts > 1 OR st.n_distinct_idx <> st.sitting_n
         THEN TRUE ELSE FALSE END                AS multi_run_sitting

FROM target t
INNER JOIN sitting st
        ON st.session_id = t.session_id AND st.activity_pack = t.activity_pack
INNER JOIN pack_content pc
        ON pc.academic_year_id = t.academic_year_id AND pc.activity_pack = t.activity_pack
