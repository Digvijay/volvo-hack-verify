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

## Using the same values in your app

The `.env` keys work directly from any language/SDK, from any machine, no sign-in required:

- **Foundry**: `AZURE_OPENAI_ENDPOINT` + `AZURE_OPENAI_KEY` (Azure OpenAI-compatible; `api-key` header),
  chat deployment `CHAT_DEPLOYMENT`, embeddings `EMBEDDING_DEPLOYMENT`.
- **Azure AI Search**: `SEARCH_ENDPOINT` + `SEARCH_KEY`, index `SEARCH_INDEX` (chunked + vectorized).
- **Cosmos DB**: `COSMOS_ENDPOINT` + `COSMOS_KEY`, database `COSMOS_DATABASE`.
- **Blob storage**: `STORAGE_CONNECTION_STRING` (or `STORAGE_SAS`), container `STORAGE_CONTAINER`.
- **Container registry** (optional, to push your own image): `ACR_LOGIN_SERVER` / `ACR_USERNAME` /
  `ACR_PASSWORD`.

## Notes

- **Keep your `.env` private.** It contains keys. This repo gitignores `.env`, so it is never
  committed. `.env.example` shows the shape with placeholders and is safe to share.
- The script only reads and does a tiny throwaway write (a temporary Cosmos container, removed
  immediately). It does not change your data.
