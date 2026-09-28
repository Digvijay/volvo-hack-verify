"""Configuration loaded from the team .env (keys only, no Azure sign-in)."""
import os
from pathlib import Path

from dotenv import load_dotenv

# The .env sits at the repo root, one level above this package.
_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(_ROOT / ".env")


def _get(name: str, default: str = "") -> str:
    v = os.getenv(name, default)
    return v.strip() if isinstance(v, str) else v


AOAI_ENDPOINT = _get("AZURE_OPENAI_ENDPOINT").rstrip("/")
AOAI_KEY = _get("AZURE_OPENAI_KEY")
AOAI_API_VERSION = _get("AZURE_OPENAI_API_VERSION", "2025-01-01-preview")
CHAT_DEPLOYMENT = _get("CHAT_DEPLOYMENT", "gpt-5.6-luna")
EMBEDDING_DEPLOYMENT = _get("EMBEDDING_DEPLOYMENT", "text-embedding-3-large")

SEARCH_ENDPOINT = _get("SEARCH_ENDPOINT").rstrip("/")
SEARCH_KEY = _get("SEARCH_KEY")
SEARCH_INDEX = _get("SEARCH_INDEX", "hackdata-index")

COSMOS_ENDPOINT = _get("COSMOS_ENDPOINT")
COSMOS_KEY = _get("COSMOS_KEY")
COSMOS_DATABASE = _get("COSMOS_DATABASE", "truckoffer")
QUOTES_CONTAINER = "quotes"


def missing() -> list[str]:
    """Return the names of required settings that are absent from the .env."""
    required = {
        "AZURE_OPENAI_ENDPOINT": AOAI_ENDPOINT,
        "AZURE_OPENAI_KEY": AOAI_KEY,
        "SEARCH_ENDPOINT": SEARCH_ENDPOINT,
        "SEARCH_KEY": SEARCH_KEY,
        "COSMOS_ENDPOINT": COSMOS_ENDPOINT,
        "COSMOS_KEY": COSMOS_KEY,
    }
    return [k for k, v in required.items() if not v]


def safe() -> dict:
    """Display-safe config for the UI (no secrets)."""
    return {
        "foundryEndpoint": AOAI_ENDPOINT,
        "chatDeployment": CHAT_DEPLOYMENT,
        "searchEndpoint": SEARCH_ENDPOINT,
        "searchIndex": SEARCH_INDEX,
        "cosmosEndpoint": COSMOS_ENDPOINT,
        "cosmosDatabase": COSMOS_DATABASE,
    }
