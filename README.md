# Volvo Hackathon: verify your lab

A one-command check that your team's Azure environment is provisioned and that **you** can use
every part of it to build your solution. You sign in as your lab account and the script exercises
all the resources end to end with your own credentials.

## What it checks

- **Foundry chat model** and **embeddings** respond
- **Azure AI Search** lists and queries the hackathon data
- **Cosmos DB** create / write / read / query / delete
- **Blob storage** lists and reads the data set
- **Deploy rights** (you have Contributor on your resource group, plus a Container Apps
  environment and a container registry to run your app)
- A small **retrieval-augmented answer** that uses the services together, exactly like a real app

A green summary means you are ready to start building.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`)
- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`)
- Your lab account (username + password), handed to your team by the organizers

## Run it

```powershell
git clone <this-repo-url>
cd volvo-hack-verify

# Sign in as YOUR lab user (a browser opens).
# On your FIRST sign-in you'll be asked to set up multi-factor authentication
# (Microsoft Authenticator) - this is expected; follow the prompts once.
az login

# Verify (auto-discovers your team's resource group):
pwsh ./verify-lab.ps1
```

That's it. The script finds your team's resource group automatically, so you do not need to know
any resource names.

### If auto-discovery cannot pick your group

If your account can see more than one resource group, pass yours explicitly:

```powershell
pwsh ./verify-lab.ps1 -SubscriptionId <your-subscription-id> -ResourceGroup rg-team-0N
```

## Reading the result

- **PASS** (green): that capability works for you.
- **WARN** (yellow): non-blocking. The most common one is the search index still building right
  after provisioning; wait a couple of minutes and re-run.
- **FAIL** (red): share the failed line(s) with your coach.

## Notes

- **First sign-in sets up MFA.** The first time you sign in with your lab account you'll register
  multi-factor authentication (Microsoft Authenticator). This is a one-time step; after that,
  sign-in is quick.
- This repo contains **no secrets**. You provide your identity by signing in; your password and
  resource names are never stored here.
- The script only reads and does a tiny throwaway write (a temporary Cosmos container and a
  temporary tag on your resource group, both removed immediately). It does not change your data.
