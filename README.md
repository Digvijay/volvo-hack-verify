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
- Your team's encrypted **`<team>.env.enc`** file, handed to you by the organizers (decrypt it below)

No Azure CLI, no `az login`, no portal access needed.

## Decrypt your team `.env`

The organizers send your credentials as an **encrypted** `<team>.env.enc` file; the password comes
separately (out of band). Decrypt it once into a `.env` next to the script:

```powershell
# from the repo folder, with your .env.enc saved here
pwsh ./decrypt-env.ps1
# or point at a specific file:
pwsh ./decrypt-env.ps1 -In rg-team-05.env.enc
```

Enter the password when prompted; it writes `.env` next to the script. Keep both the `.env.enc` and
the password private. (AES-256; the `.enc` is opaque base64, so it passes content filters.)

## Run it

```powershell
git clone <this-repo-url>
cd volvo-hack-verify

# Decrypt your team file first (see above), or drop a plain .env here (see .env.example for the shape).
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
  on each of the three fact-sheet indexes (`allfactsheets-index`, `diesel-truck-index`,
  `electric-truck-index`).
- **Cosmos DB** - signs each request with an HMAC of the master key (`type=master`), then creates a
  temporary container, upserts / reads / queries a document, and deletes the container.
- **Blob storage** - uses the container `STORAGE_SAS` to list and read one blob.
- **End-to-end** - feeds a retrieved passage into the chat model, proving the services work together.

Everything is read-only except that one throwaway Cosmos container, which is removed immediately. It
never writes your keys anywhere or changes your data.

## Explore every capability (notebook)

Prefer to poke at the services yourself? Open [`explore.ipynb`](explore.ipynb) in VS Code. It is a
guided, run-top-to-bottom notebook that exercises **every operation your `.env` unlocks**, one cell
at a time, again with **no Azure sign-in**:

1. Call the chat model (inference)
2. Create embeddings
3. Search the fact sheets (three vector indexes: all / diesel / electric)
4. Create your **own** search index, upload docs, and query it
5. Cosmos DB create / write / read / query
6. Blob storage read (over the container SAS)
7. Build a container image locally (Docker)
8. Push it to your Azure Container Registry
9. Deploy it to Azure Container Apps and print the **public URL**
10. Test the deployed app, then clean everything up

### How to use it

1. Put your team `.env` next to the notebook (same folder as `verify-lab.ps1`).
2. Create the environment once: `python -m venv .venv` then
   `.venv\Scripts\python -m pip install -r requirements.txt`.
3. Open `explore.ipynb` in VS Code. If you see **"Install/Enable suggested extensions: Python +
   Jupyter"**, accept it (this repo recommends them) - they are required to run notebooks. The
   **`.venv` kernel is then preselected** (via `.vscode/settings.json`); if prompted, just confirm
   `Python (.venv)`.
4. Run the cells top to bottom with the Run button.

Sections 1-6 only need the keys. Sections 7-10 (build / push / deploy a container) additionally
need **Docker Desktop running** and use the deploy identity in your `.env` (a service principal, so
no interactive login). The final cell deletes the demo container app, index, and Cosmos container so
nothing keeps costing money. If you are on a corporate proxy and hit a TLS error, set
`INSECURE_SSL=true` in your `.env` (same switch as the app and the verify script).

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
- **Azure AI Search**: `SEARCH_ENDPOINT` + `SEARCH_KEY`, three chunked + vectorized indexes -
  `SEARCH_INDEX` (default `allfactsheets-index`), `SEARCH_INDEX_DIESEL` (`diesel-truck-index`),
  and `SEARCH_INDEX_ELECTRIC` (`electric-truck-index`). One key queries all three.
- **Cosmos DB**: `COSMOS_ENDPOINT` + `COSMOS_KEY`, database `COSMOS_DATABASE`.
- **Blob storage**: `STORAGE_CONNECTION_STRING` (or `STORAGE_SAS`), container `STORAGE_CONTAINER`.
- **Container registry** (optional, to push your own image): `ACR_LOGIN_SERVER` / `ACR_USERNAME` /
  `ACR_PASSWORD`.

## Starter app: a working quote studio

The repo also ships a small **working web app** (FastAPI + static UI) so you have a running
reference, not just a check. It walks the full flow using only your `.env` keys (no sign-in):

1. Pick a truck and **interpret** its configuration (chat model)
2. **Ground** it in the fact-sheet data (Azure AI Search hybrid + vector RAG over `allfactsheets-index`)
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
- `app/search.py` - hybrid (keyword + vector) retrieval over `allfactsheets-index` (default `SEARCH_INDEX`).
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
query. Because `allfactsheets-index` has a built-in vectorizer, the Search service embeds the query
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
