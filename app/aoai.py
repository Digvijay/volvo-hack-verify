"""Azure OpenAI (Foundry) chat calls over the key-based, OpenAI-compatible surface."""
import json

import httpx

from . import config


def chat(messages: list[dict], *, json_mode: bool = False, max_tokens: int = 2000) -> str:
    url = (
        f"{config.AOAI_ENDPOINT}/openai/deployments/{config.CHAT_DEPLOYMENT}"
        f"/chat/completions?api-version={config.AOAI_API_VERSION}"
    )
    body: dict = {"messages": messages, "max_completion_tokens": max_tokens}
    if json_mode:
        body["response_format"] = {"type": "json_object"}
    # gpt-5.6 is a reasoning model; keep reasoning light so JSON answers are not starved of tokens.
    body["reasoning_effort"] = "low"
    headers = {"api-key": config.AOAI_KEY, "Content-Type": "application/json"}

    with httpx.Client(timeout=180) as client:
        r = client.post(url, headers=headers, json=body)
        if r.status_code == 400 and "reasoning_effort" in body:
            body.pop("reasoning_effort")
            r = client.post(url, headers=headers, json=body)
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"]


def chat_json(messages: list[dict], *, max_tokens: int = 2000) -> dict:
    return _loads(chat(messages, json_mode=True, max_tokens=max_tokens))


def _loads(text: str) -> dict:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text[:4].lower() == "json":
            text = text[4:]
        text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        i, j = text.find("{"), text.rfind("}")
        if i >= 0 and j > i:
            return json.loads(text[i:j + 1])
        raise
