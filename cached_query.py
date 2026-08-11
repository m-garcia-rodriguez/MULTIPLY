# cached_query.py
from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Optional, Union

import pandas as pd

from databricks_connector import query


def cached_query(
    sql_path: Union[str, Path],
    cache_dir: Union[str, Path],
    refresh: bool = False,
    query_tags: Optional[dict[str, str]] = None,
) -> pd.DataFrame:
    """
    Run a .sql file against Databricks, caching the result on disk.

    The cache key is a hash of the SQL FILE'S CONTENT, not its filename or
    path. Editing the query text is therefore automatically a cache miss --
    there is never a stale cache to delete by hand.

    Usage:
        from cached_query import cached_query

        df = cached_query(
            "descriptive/queries/a998_table_difficulty_by_age.sql",
            cache_dir="descriptive/cache",
        )

        # Force a re-run against the warehouse (e.g. upstream data changed)
        df = cached_query(sql_path, cache_dir, refresh=True)
    """
    sql_path = Path(sql_path)
    sql_string = sql_path.read_text(encoding="utf-8")

    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)

    query_hash = hashlib.sha256(sql_string.encode("utf-8")).hexdigest()[:16]
    cache_file = cache_dir / f"{sql_path.stem}__{query_hash}.parquet"

    if not refresh and cache_file.exists():
        return pd.read_parquet(cache_file)

    result = query(sql_string, query_tags=query_tags)
    result.to_parquet(cache_file, index=False)
    return result
