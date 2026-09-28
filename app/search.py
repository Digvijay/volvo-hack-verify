"""Hybrid (keyword + vector) retrieval over the AI Search index, key-based.

The index carries an Azure OpenAI vectorizer, so a text vector query is embedded
server-side by the Search service. The caller only needs the query api-key.
"""
import httpx

from . import config


def retrieve(query: str, top: int = 6) -> list[dict]:
    if not query.strip():
        return []
    url = f"{config.SEARCH_ENDPOINT}/indexes/{config.SEARCH_INDEX}/docs/search?api-version=2024-07-01"
    body = {
        "search": query,
        "top": top,
        "select": "title,content",
        "vectorQueries": [
            {"kind": "text", "text": query, "fields": "content_vector", "k": top}
        ],
    }
    headers = {"api-key": config.SEARCH_KEY, "Content-Type": "application/json"}
    with httpx.Client(timeout=60, verify=config.SSL_VERIFY) as client:
        r = client.post(url, headers=headers, json=body)
        r.raise_for_status()
        docs = r.json().get("value", [])
    return [{"title": d.get("title") or "", "content": d.get("content") or ""} for d in docs]
