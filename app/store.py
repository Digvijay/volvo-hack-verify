"""Cosmos DB quote persistence using the account key (no Azure sign-in)."""
import time
import uuid

from azure.cosmos import CosmosClient, PartitionKey

from . import config

_container = None


def _quotes():
    global _container
    if _container is None:
        client = CosmosClient(config.COSMOS_ENDPOINT, credential=config.COSMOS_KEY)
        db = client.create_database_if_not_exists(config.COSMOS_DATABASE)
        _container = db.create_container_if_not_exists(
            id=config.QUOTES_CONTAINER, partition_key=PartitionKey(path="/id")
        )
    return _container


def save_quote(quote: dict) -> str:
    qid = quote.get("id") or f"q-{int(time.time())}-{uuid.uuid4().hex[:6]}"
    quote["id"] = qid
    quote["quoteId"] = qid
    quote["savedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    _quotes().upsert_item(quote)
    return qid


def list_quotes() -> list[dict]:
    q = "SELECT c.id, c.title, c.customerName, c.savedAt FROM c ORDER BY c.savedAt DESC"
    return list(_quotes().query_items(q, enable_cross_partition_query=True))


def get_quote(qid: str) -> dict | None:
    try:
        return _quotes().read_item(qid, partition_key=qid)
    except Exception:
        return None
