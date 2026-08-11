# MULTIPLY

Estudi cognitiu sobre com els alumnes de primària aprenen les taules de multiplicar, tant en precisió (accuracy) com en velocitat de recuperació (RT). S'utilitzen dues fonts del data warehouse d'Innovamat: el test **A998** (`bi_gold_prod.dm_research.fluency_test_statements` / `fluency_test_metrics`) i la **Fluency zone** (`bi_gold_prod.dwh_digital_practice.f_elementary_fluency_attempts`), aquesta última com a comparació.

L'anàlisi complet, decisions preses i resultats es documenten a la pàgina de Confluence de l'estudi (espai Research, [Multiply](https://innovamat.atlassian.net/wiki/spaces/R/pages/3342729218/Multiply)). Aquest repositori conté només el codi: consultes SQL, connector, i notebooks/scripts d'anàlisi.

## Estructura

```
MULTIPLY/
├── databricks_connector.py   # connexió OAuth M2M a Databricks (query() -> pd.DataFrame)
├── cached_query.py            # wrapper de query() amb cache basat en hash del .sql
├── .env                       # credencials (no versionat)
├── requirements.txt
├── descriptive/
│   ├── queries/               # .sql d'aquesta categoria
│   ├── cache/                 # resultats cachejats en .parquet (no versionat)
│   ├── reference/              # fitxers manuals que NO venen d'una query (p. ex. dades d'adults)
│   └── plots/                  # figures generades pels notebooks (no versionat)
└── mechanistic/
    ├── queries/
    ├── cache/
    └── plots/
```

## Com funcionen les queries i el cache

Cada pregunta de dades és un fitxer `.sql` dins `queries/`, mai una query escrita directament al notebook. Per executar-la, no es crida `databricks_connector.query()` directament sinó `cached_query()`, que hi afegeix una capa de cache:

```python
from cached_query import cached_query

df = cached_query(
    "descriptive/queries/a998_table_difficulty_by_age.sql",
    cache_dir="descriptive/cache",
)
```

`cached_query(sql_path, cache_dir, sql_text=None, refresh=False)` llegeix el fitxer `.sql`, calcula un **hash del text que s'executa de veritat** i desa/llegeix el resultat a `cache_dir/<nom_sql>__<hash>.parquet`. Per defecte hasheja el contingut del fitxer; alguns notebooks (`commutativity.ipynb`, `fluency_error_types.ipynb`, la query principal de `corrected_operations_boxplot.ipynb`) primer substitueixen marcadors com `-- {YEARS}` o `-- {MIN_ATTEMPTS}` segons un paràmetre del notebook — en aquest cas passen el text ja substituït a `sql_text=`, perquè el cache es basi en la query que realment s'ha executat, no en el fitxer sense tocar. Així, canviar `MIN_ATTEMPTS_PER_DIRECTION` de 1 a 2, per exemple, sempre genera un cache nou en lloc de reaprofitar per error el resultat d'un altre paràmetre.

**Avantatge:** no cal esborrar el cache a mà quan canvies una query — el propi contingut (ja substituït) decideix si cal recalcular. Passar `refresh=True` força tornar a consultar el warehouse encara que la query no hagi canviat (útil si les dades del warehouse s'han actualitzat). Cada categoria (`descriptive/`, `mechanistic/`) passa el seu propi `cache_dir`, així els resultats no es barregen.

**Queries petites de diagnòstic no es cachejen.** Alguns notebooks fan consultes curtes i pensades per tornar a mesurar sempre en viu (`DESCRIBE TABLE ...`, comptar files per detectar un JOIN que fa fan-out, l'autoverificació de durades a `fluency_error_types.ipynb`). Aquestes segueixen cridant `databricks_connector.query()` directament — cachejar-les amagaria precisament la deriva que estan pensades per detectar.

**`reference/` és per fitxers que no vénen de cap query.** L'únic cas pendent ara és `rt_distribution_table6_adult.csv` (opcional, usat per `rt_distribution.ipynb`): encara no s'ha copiat al repo nou. L'antiga referència manual `learning_team_per_min.csv` ja no existeix com a CSV — ara és `queries/learning_team_per_min.sql` (una còpia a `descriptive/queries/` i una a `mechanistic/queries/`, cada categoria amb el seu propi cache), connectada via `cached_query()` a `corrected_operations_boxplot.ipynb` i `rt_w_F2.ipynb`. La query reprodueix el mateix mètode que tenia el CSV (sessió completa, primera declaració inclosa, sense el filtre de la Decisió #7), així que el node d'adults segueix sent un benchmark indicatiu, no una extensió directa de les corbes d'alumnes.

## Queries pendents de verificar o reconstruir

No totes les dades que alimenten els notebooks tenen una query fiable darrere:

- **`mechanistic/queries/rt_A998_answers.sql`** — recuperada de l'arxiu antic i corregida (prefix `bi_gold_prod.dm_research.*` i normalització `·`→`×` de `operation`), ja connectada a `rt_w_F2.ipynb` via `cached_query()`, però **encara no s'ha tornat a executar en viu** — val la pena confirmar-ho abans de confiar en els resultats.
- **`mechanistic/queries/rt_distribution_table6_by_age.sql`** — recuperada de l'arxiu antic però marcada **NO VERIFICADA**: està escrita contra taules d'enginyeria en dialecte Postgres/Redshift (`card_attempt`, `card`, `student`), no contra `bi_gold_prod.*`, i el fitxer original ja marcava 3 identificadors sense confirmar. `rt_distribution.ipynb` segueix llegint el CSV manual, no aquesta query.
- **`rt_distribution.ipynb`** — a més de l'anterior, `rt_distribution_table6.csv`, `rt_distribution_by_grade.csv`, `rt_box_table6.csv` i `rt_box_table6_grade11.csv` no tenen cap `.sql` desat enlloc: són extraccions manuals (probablement de Metabase) d'abans que existís la convenció de guardar cada query. Els dos punts de control intermedis del propi notebook (`rt_distribution_table6_clean.parquet` i `..._grade11_clean.parquet`) sí que ja estan migrats a parquet dins `mechanistic/cache/`.
- **`inicial.ipynb`** — les 8 fonts que utilitza (`attempts_by_fact.csv`, `mastery_by_fact.csv`, `response_time_by_fact.csv`, `error_rate_by_fact.csv`, `error_rt_by_fact_age.csv`, `student_rt_by_age.csv`, `acc_by_op_age.csv`, `asym_by_op_age.csv`) no tenen cap query desada. Cal reconstruir-les (o acceptar aquest notebook com a històric/no reproduïble) abans de connectar-lo a `cached_query()`.
- **`a998_corrected_mult_per_min.csv`** (a `rt_w_F2.ipynb`) — sense query pròpia i, per la data, sembla la versió antiga i sorollosa que la Decisió #7 va corregir (l'origen de les taxes de −92 op/min). Ja existeix la versió corregida i amb query (`a998_corrected_ops_by_age.sql`, connectada a `corrected_operations_boxplot.ipynb`) — val la pena revisar si `rt_w_F2.ipynb` hauria de reutilitzar-la en lloc del CSV antic.

## Descriptive vs. Mechanistic

Les dues carpetes separen l'anàlisi per **nivell d'abstracció**, no per tema:

- **`descriptive/`** — resultats que qualsevol persona pot entendre sense assumpcions estadístiques: taxes d'error, quina taula és més difícil, quina franja d'edat és més lenta. És comptar i comparar directament sobre les dades observades.
- **`mechanistic/`** — resultats que depenen d'un model explicatiu: ajustar els RT a distribucions lognormals, introduir models cognitius de recuperació de fets aritmètics, xarxes de confusió entre operacions. Aquí la conclusió no és directa de la dada, sinó del model que s'hi ajusta.

La regla pràctica: si el resultat es pot explicar a algú pel carrer sense parlar de distribucions ni de paràmetres, va a `descriptive/`; si cal explicar primer quin model s'ha assumit, va a `mechanistic/`.
