# cached_query.py
from __future__ import annotations

import decimal
import hashlib
from pathlib import Path
from typing import Optional, Union

import pandas as pd

from databricks_connector import query


def _floatify_decimals(df: pd.DataFrame) -> pd.DataFrame:
    """
    Databricks/Spark returns NUMERIC/DECIMAL columns (typically anything that
    passed through ROUND(), or a division involving a DECIMAL-typed source
    column) as python decimal.Decimal objects once they round-trip through
    pandas -- whether that's straight off query() or read back from a cached
    .parquet file, since parquet stores them as decimal128 and pyarrow hands
    them back to pandas as `object` columns of Decimal, not float64.

    numpy/pandas math (np.percentile, .median(), arithmetic with a plain
    float, etc.) can't operate on Decimal -- e.g.
        TypeError: unsupported operand type(s) for *: 'decimal.Decimal' and 'float'
    so any column that actually holds Decimal values is cast to float64
    here, in place, before the DataFrame is returned. This runs on every
    return path (fresh query AND cache hit) so it's self-healing: existing
    cache files written before this fix don't need to be deleted, they just
    get normalised on next read.
    """
    for col in df.columns:
        if df[col].dtype == object:
            sample = df[col].dropna()
            if len(sample) and isinstance(sample.iloc[0], decimal.Decimal):
                df[col] = df[col].astype(float)
    return df


def cached_query(
    sql_path: Union[str, Path],
    cache_dir: Union[str, Path],
    sql_text: Optional[str] = None,
    refresh: bool = False,
    query_tags: Optional[dict[str, str]] = None,
) -> pd.DataFrame:
    """
    Run a .sql file against Databricks, caching the result on disk.

    The cache key is a hash of the SQL TEXT ACTUALLY EXECUTED, not the
    filename or path. Editing the query is therefore automatically a cache
    miss -- there is never a stale cache to delete by hand.

    sql_path : path to the canonical .sql file. Used (a) as the source of the
               query when `sql_text` is not given, and (b) for the
               human-readable part of the cache filename either way.
    sql_text : pass this when the notebook rewrites markers in the file
               before running it (e.g. substituting -- {YEARS} or
               -- {MIN_ATTEMPTS}). The cache is keyed off `sql_text`, so two
               different parameter values for the same .sql never collide,
               and a marker substitution that changes the query is always a
               cache miss -- exactly like editing the file would be.

    Usage:
        from cached_query import cached_query

        # simple case: run the file as-is
        df = cached_query(
            "descriptive/queries/a998_table_difficulty_by_age.sql",
            cache_dir="descriptive/cache",
        )

        # marker-substitution case: cache keyed off the substituted text
        sql_raw = Path(sql_path).read_text(encoding="utf-8")
        sql_text = sql_raw.replace("-- {YEARS}", ...)
        df = cached_query(sql_path, cache_dir, sql_text=sql_text)

        # force a re-run against the warehouse (e.g. upstream data changed)
        df = cached_query(sql_path, cache_dir, refresh=True)
    """
    sql_path = Path(sql_path)
    raw_text = sql_path.read_text(encoding="utf-8")
    text_to_run = sql_text if sql_text is not None else raw_text

    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)

    query_hash = hashlib.sha256(text_to_run.encode("utf-8")).hexdigest()[:16]
    cache_file = cache_dir / f"{sql_path.stem}__{query_hash}.parquet"

    if not refresh and cache_file.exists():
        return _floatify_decimals(pd.read_parquet(cache_file))

    result = query(text_to_run.strip().rstrip(";"), query_tags=query_tags)
    result = _floatify_decimals(result)
    result.to_parquet(cache_file, index=False)
    return result
