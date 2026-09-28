"""Volvo hackathon starter app: a key-only truck-quote studio.

Flow: interpret -> ground (AI Search RAG) -> compose -> approve (save to Cosmos),
plus a grounded sales chat. No Azure sign-in: everything uses the team .env keys.
"""
import json
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import aoai, config, search, store

APP_DIR = Path(__file__).resolve().parent
app = FastAPI(title="Volvo Hack Starter")

SAMPLE_TRUCKS = json.loads((APP_DIR / "data" / "sample_trucks.json").read_text(encoding="utf-8"))
TRUCKS_BY_ID = {t["id"]: t for t in SAMPLE_TRUCKS}


class InterpretReq(BaseModel):
    truckId: str | None = None
    config: dict | None = None


class GroundReq(BaseModel):
    summary: dict


class ComposeReq(BaseModel):
    summary: dict
    valued: dict


class ApproveReq(BaseModel):
    quote: dict
    summary: dict | None = None
    valued: dict | None = None


class ChatReq(BaseModel):
    question: str


app.mount("/static", StaticFiles(directory=APP_DIR / "static"), name="static")


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    return (APP_DIR / "static" / "index.html").read_text(encoding="utf-8")


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "missing": config.missing()}


@app.get("/api/config")
def api_config() -> dict:
    return config.safe()


@app.get("/api/trucks")
def trucks() -> list:
    return SAMPLE_TRUCKS


@app.get("/api/trucks/{truck_id}")
def truck(truck_id: str) -> dict:
    t = TRUCKS_BY_ID.get(truck_id)
    if not t:
        raise HTTPException(404, "unknown truck")
    return t


def _sources(passages: list[dict]) -> list[dict]:
    return [{"n": i + 1, "title": p["title"]} for i, p in enumerate(passages)]


def _context(passages: list[dict]) -> str:
    return "\n\n".join(f"[{i + 1}] {p['title']}\n{p['content'][:1200]}" for i, p in enumerate(passages))


@app.post("/api/interpret")
def interpret(req: InterpretReq) -> dict:
    cfg = req.config or TRUCKS_BY_ID.get(req.truckId or "")
    if not cfg:
        raise HTTPException(400, "provide truckId or config")
    messages = [
        {"role": "system", "content": "You interpret a Volvo truck configuration into a concise structured summary. Respond as JSON only."},
        {"role": "user", "content": (
            f"Truck configuration:\n{json.dumps(cfg, indent=2)}\n\n"
            'Return JSON: {"model": string, "intendedUse": string, "highlights": [string], '
            '"configuration": object}.'
        )},
    ]
    return aoai.chat_json(messages, max_tokens=1500)


@app.post("/api/ground")
def ground(req: GroundReq) -> dict:
    s = req.summary
    query = f"{s.get('model', 'Volvo truck')} {s.get('intendedUse', '')} " + " ".join(s.get("highlights", []))
    passages = search.retrieve(query, top=6)
    messages = [
        {"role": "system", "content": "You ground a truck's key features in the provided source passages. Use ONLY the sources and cite the source number in 'source'. Respond as JSON only."},
        {"role": "user", "content": (
            f"Truck summary:\n{json.dumps(s)}\n\nSources:\n{_context(passages)}\n\n"
            'Return JSON: {"items":[{"feature":string,"customerValue":string,"evidence":string,"source":string}]}. '
            "Omit any claim the sources do not support."
        )},
    ]
    data = aoai.chat_json(messages, max_tokens=2500)
    data["_sources"] = _sources(passages)
    return data


@app.post("/api/compose")
def compose(req: ComposeReq) -> dict:
    messages = [
        {"role": "system", "content": "You compose a concise, customer-ready Volvo truck proposal. Warm and factual, never invent specifications. Respond as JSON only."},
        {"role": "user", "content": (
            f"Summary:\n{json.dumps(req.summary)}\n\nGrounded value:\n{json.dumps(req.valued)}\n\n"
            'Return JSON: {"title":string,"customerName":string,"headline":string,'
            '"sections":[{"heading":string,"body":string}],"closing":string}.'
        )},
    ]
    return aoai.chat_json(messages, max_tokens=3000)


@app.post("/api/approve")
def approve(req: ApproveReq) -> dict:
    doc = dict(req.quote)
    if req.summary is not None:
        doc["summary"] = req.summary
    if req.valued is not None:
        doc["valued"] = req.valued
    doc.setdefault("customerName", "Customer")
    doc.setdefault("title", "Volvo proposal")
    return {"quoteId": store.save_quote(doc)}


@app.get("/api/quotes")
def quotes() -> list:
    return store.list_quotes()


@app.get("/api/quotes/{quote_id}")
def quote_detail(quote_id: str) -> dict:
    q = store.get_quote(quote_id)
    if not q:
        raise HTTPException(404, "not found")
    return q


@app.post("/api/chat")
def chat(req: ChatReq) -> dict:
    passages = search.retrieve(req.question, top=5)
    messages = [
        {"role": "system", "content": "You are a Volvo trucks sales assistant. Answer ONLY from the sources and cite [n]. If the sources do not cover it, say so."},
        {"role": "user", "content": f"Question: {req.question}\n\nSources:\n{_context(passages)}"},
    ]
    return {"answer": aoai.chat(messages, max_tokens=1200), "sources": _sources(passages)}
