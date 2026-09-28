# Volvo Hackathon: verify your lab

A one-command check that your team's Azure environment is provisioned and that you can use every
part of it to build your solution. It uses the **keys in your team's `.env` file**, so there is
**no Azure sign-in** and nothing to install beyond PowerShell.

## What it checks

- **Foundry chat model** and **embeddings** respond
- **Azure AI Search** lists and queries the hackathon data
- **Cosmos DB** create / write / read / query / delete
- **Blob storage** lists and reads the data set
- A small **retrieval-augmented answer** that uses the services together, exactly like a real app

A green summary means you are ready to start building.

## Prerequisites

- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`)
- Your team's **`.env`** file, handed to you by the organizers

No Azure CLI, no `az login`, no portal access needed.

## Run it

```powershell
git clone <this-repo-url>
cd volvo-hack-verify

# Save the .env your coach gave you next to this script (see .env.example for the shape).
# Then run:
pwsh ./verify-lab.ps1
```

If your `.env` lives elsewhere, point at it:

```powershell
pwsh ./verify-lab.ps1 -EnvFile C:\path\to\team-01.env
```

## Reading the result

- **PASS** (green): that capability works for you.
- **WARN** (yellow): non-blocking. The most common one is the search index still building right
  after provisioning; wait a couple of minutes and re-run.
- **FAIL** (red): share the failed line(s) with your coach.

## How the check works

`verify-lab.ps1` loads your `.env` and calls each service directly over REST with its key - no
`az login`, no SDKs:

- **Foundry chat + embeddings** - `api-key` header on the OpenAI-compatible endpoint.
- **Azure AI Search** - `api-key` header to list indexes and run a hybrid (keyword + vector) query
  on `hackdata-index`.
- **Cosmos DB** - signs each request with an HMAC of the master key (`type=master`), then creates a
  temporary container, upserts / reads / queries a document, and deletes the container.
- **Blob storage** - uses the container `STORAGE_SAS` to list and read one blob.
- **End-to-end** - feeds a retrieved passage into the chat model, proving the services work together.

Everything is read-only except that one throwaway Cosmos container, which is removed immediately. It
never writes your keys anywhere or changes your data.

## See your credentials power a real app

Once the check is green, run the included starter web app to watch the **same `.env` keys** drive a
working application - pick a truck, interpret it, ground it in the data with AI Search, compose a
proposal, save it to Cosmos, and chat with the data:

```powershell
# from the repo folder, with your .env in place
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
.venv\Scripts\python -m uvicorn app.main:app --port 8000
```

Then open <http://localhost:8000>. If a page loads and the steps return results, your credentials
work end to end from real application code (no `az login`). See
[Starter app](#starter-app-a-working-quote-studio) below for what each step and route does.

## Using the same values in your app

The `.env` keys work directly from any language/SDK, from any machine, no sign-in required:

- **Foundry**: `AZURE_OPENAI_ENDPOINT` + `AZURE_OPENAI_KEY` (Azure OpenAI-compatible; `api-key` header),
  chat deployment `CHAT_DEPLOYMENT`, embeddings `EMBEDDING_DEPLOYMENT`.
- **Azure AI Search**: `SEARCH_ENDPOINT` + `SEARCH_KEY`, index `SEARCH_INDEX` (chunked + vectorized).
- **Cosmos DB**: `COSMOS_ENDPOINT` + `COSMOS_KEY`, database `COSMOS_DATABASE`.
- **Blob storage**: `STORAGE_CONNECTION_STRING` (or `STORAGE_SAS`), container `STORAGE_CONTAINER`.
- **Container registry** (optional, to push your own image): `ACR_LOGIN_SERVER` / `ACR_USERNAME` /
  `ACR_PASSWORD`.

## Starter app: a working quote studio

The repo also ships a small **working web app** (FastAPI + static UI) so you have a running
reference, not just a check. It walks the full flow using only your `.env` keys (no sign-in):

1. Pick a truck and **interpret** its configuration (chat model)
2. **Ground** it in the hackathon data (Azure AI Search hybrid + vector RAG over `hackdata-index`)
3. **Compose** a customer-ready proposal (chat model)
4. **Approve** to save the quote to Cosmos DB
5. **Ask the data** - a grounded sales chat with citations

Run it (from the repo folder, with your `.env` in place):

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
.venv\Scripts\python -m uvicorn app.main:app --port 8000
```

Then open <http://localhost:8000>. It authenticates with the same keys the verify script uses:
Foundry chat (`api-key`), AI Search (`api-key`), and Cosmos (`COSMOS_KEY`). It is a starting point
to fork and extend, not a finished product.

### How it works

A vanilla-JS single page (`app/static/`) calls a small FastAPI backend (`app/main.py`), which talks
to three Azure services with the `.env` keys. No agents framework, no SDK sign-in.

Module map:

- `app/config.py` - loads the `.env` and exposes the keys/endpoints.
- `app/aoai.py` - calls the Foundry chat model over the OpenAI-compatible `api-key` surface.
- `app/search.py` - hybrid (keyword + vector) retrieval over `hackdata-index`.
- `app/store.py` - saves/reads quotes in Cosmos with the account key.
- `app/main.py` - the API routes and the prompts that tie it together.
- `app/data/sample_trucks.json` - the bundled trucks you pick from.

Request flow (each step is one route):

| Route | What happens |
| --- | --- |
| `POST /api/interpret` | Chat model turns the chosen truck config into a structured summary. |
| `POST /api/ground` | Retrieves ~6 passages from AI Search, then the model derives feature value **only** from those passages and cites them. |
| `POST /api/compose` | Chat model writes a customer-ready proposal from the summary + grounded value. |
| `POST /api/approve` | Upserts the proposal into the Cosmos `quotes` container (created on first use). |
| `POST /api/chat` | Retrieves passages for the question and answers grounded in them, with `[n]` citations. |
| `GET /api/trucks`, `/api/quotes`, `/api/config`, `/health` | Read helpers used by the UI. |

The grounding (RAG) detail: the search request sends both a keyword `search` and a **text** vector
query. Because `hackdata-index` has a built-in vectorizer, the Search service embeds the query
server-side, so the app never calls the embeddings model itself. The retrieved `title`/`content`
become the only context passed to the model, and the prompt tells it to answer solely from those
sources (so it says "not covered" instead of inventing facts).

What is intentionally left out (so it runs from keys alone): the Foundry **Agent Service**, **File
Search**, the **MCP toolbox**, **image generation**, and `DefaultAzureCredential`. Those need an
Entra sign-in or a model that is not deployed here. To extend, edit the prompts in `app/main.py`,
add routes, or swap `sample_trucks.json`.

## Notes

- **Keep your `.env` private.** It contains keys. This repo gitignores `.env`, so it is never
  committed. `.env.example` shows the shape with placeholders and is safe to share.
- The script only reads and does a tiny throwaway write (a temporary Cosmos container, removed
  immediately). It does not change your data.
- **Corporate network / TLS proxy.** The app trusts your machine's certificate store (via
  `truststore`), so HTTPS works behind proxies that inject a self-signed root CA. If you still see
  `CERTIFICATE_VERIFY_FAILED`, set `INSECURE_SSL=true` in your `.env` as a last resort.
