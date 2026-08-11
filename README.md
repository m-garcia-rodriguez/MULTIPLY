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
│   └── cache/                 # resultats cachejats (no versionat)
└── mechanistic/
    ├── queries/
    └── cache/
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

`cached_query(sql_path, cache_dir, refresh=False)` llegeix el fitxer `.sql`, calcula un **hash del seu contingut** i desa/llegeix el resultat a `cache_dir/<nom_sql>__<hash>.parquet`. El cache es identifica pel contingut de la query, no pel nom del fitxer ni per una marca de temps: si tornes a demanar la mateixa query es llegeix del disc; si edites el `.sql` (encara que sigui el mateix fitxer), el hash canvia i es torna a executar contra Databricks automàticament.

**Avantatge:** no cal esborrar el cache a mà quan canvies una query — el propi contingut decideix si cal recalcular. Passar `refresh=True` força tornar a consultar el warehouse encara que la query no hagi canviat (útil si les dades del warehouse s'han actualitzat). Cada categoria (`descriptive/`, `mechanistic/`) passa el seu propi `cache_dir`, així els resultats no es barregen.

## Descriptive vs. Mechanistic

Les dues carpetes separen l'anàlisi per **nivell d'abstracció**, no per tema:

- **`descriptive/`** — resultats que qualsevol persona pot entendre sense assumpcions estadístiques: taxes d'error, quina taula és més difícil, quina franja d'edat és més lenta. És comptar i comparar directament sobre les dades observades.
- **`mechanistic/`** — resultats que depenen d'un model explicatiu: ajustar els RT a distribucions lognormals, introduir models cognitius de recuperació de fets aritmètics, xarxes de confusió entre operacions. Aquí la conclusió no és directa de la dada, sinó del model que s'hi ajusta.

La regla pràctica: si el resultat es pot explicar a algú pel carrer sense parlar de distribucions ni de paràmetres, va a `descriptive/`; si cal explicar primer quin model s'ha assumit, va a `mechanistic/`.
