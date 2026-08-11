# databricks_connector.py
from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

import pandas as pd
from databricks import sql
from databricks.sdk.core import Config, oauth_service_principal
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

DEFAULT_QUERY_TAGS = {
    "databricks_project": "research",
    "databricks_project_process": "maria_garcia_analysis",
}


def _credential_provider():
    """OAuth M2M for a Databricks service principal."""
    hostname = os.environ["DATABRICKS_SERVER_HOSTNAME"]
    config = Config(
        host=f"https://{hostname}",
        client_id=os.environ["DATABRICKS_CLIENT_ID"],
        client_secret=os.environ["DATABRICKS_CLIENT_SECRET"],
    )
    return oauth_service_principal(config)


def query(
    sql_string: str,
    query_tags: Optional[dict[str, str]] = None,
) -> pd.DataFrame:
    """
    Execute SQL on Databricks and return a pandas DataFrame.

    Usage:
        from databricks_connector import query
        df = query("SELECT * FROM range(10)")
        df = query("SELECT 1", query_tags={"team": "data"})
    """
    tags = {**DEFAULT_QUERY_TAGS, **(query_tags or {})}

    connection = sql.connect(
        server_hostname=os.environ["DATABRICKS_SERVER_HOSTNAME"],
        http_path=os.environ["DATABRICKS_HTTP_PATH"],
        credentials_provider=_credential_provider,
        query_tags=tags,
    )
    try:
        cursor = connection.cursor()
        try:
            cursor.execute(sql_string, query_tags=tags)
            return cursor.fetchall_arrow().to_pandas()
        finally:
            cursor.close()
    finally:
        connection.close()