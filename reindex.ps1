<#
Reindex the fact-sheet search indexes after you ADD or REMOVE blobs in your storage container.

  pwsh ./reindex.ps1                              # re-run all three indexers - picks up ADDED / changed files
  pwsh ./reindex.ps1 -Index allfactsheets-index   # just one index
  pwsh ./reindex.ps1 -Rebuild                     # drop + recreate + run all three from the CURRENT blobs
                                                  #   use this to also reflect REMOVED files
  pwsh ./reindex.ps1 -Rebuild -Index diesel-truck-index

Reads SEARCH_*, AZURE_OPENAI_ENDPOINT, EMBEDDING_DEPLOYMENT, STORAGE_ACCOUNT/CONTAINER,
AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP from your .env. No az login (api-key only).

Add vs remove:
  - Adding files: a plain re-run is enough. The indexer tracks blob LastModified and only
    processes new/changed files.
  - Removing files: the datasource has no deletion policy, so a plain re-run leaves the deleted
    file's chunks behind. -Rebuild drops the index and rebuilds it from what is actually in the
    folder now, so removals are reflected.
#>
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot '.env'),
    [ValidateSet('allfactsheets-index', 'diesel-truck-index', 'electric-truck-index')]
    [string]$Index,
    [switch]$Rebuild
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $EnvFile)) { throw "env file not found: $EnvFile (decrypt your .env first)" }

$h = @{}
foreach ($l in Get-Content $EnvFile) { if ($l -match '=' -and $l -notmatch '^\s*#') { $k, $v = $l -split '=', 2; $h[$k.Trim()] = $v.Trim() } }

$ep = $h['SEARCH_ENDPOINT'].TrimEnd('/'); $key = $h['SEARCH_KEY']
$hdr = @{ 'api-key' = $key; 'Content-Type' = 'application/json' }
$api = '2024-07-01'

# The three provided indexes and the blob folder each one reads from.
$map = @(
    [pscustomobject]@{ Index = 'allfactsheets-index'; Prefix = 'factsheets/all' }
    [pscustomobject]@{ Index = 'diesel-truck-index'; Prefix = 'factsheets/diesel' }
    [pscustomobject]@{ Index = 'electric-truck-index'; Prefix = 'factsheets/electric' }
)
if ($Index) { $map = @($map | Where-Object { $_.Index -eq $Index }) }

function Docs($ix) { try { Invoke-RestMethod -Uri "$ep/indexes/$ix/docs/`$count?api-version=$api" -Headers @{ 'api-key' = $key } } catch { '?' } }
function Start-Indexer($ixer) { try { Invoke-RestMethod -Method Post -Uri "$ep/indexers/$ixer/run?api-version=$api" -Headers $hdr | Out-Null } catch { if ("$_" -notmatch 'in progress|concurrent') { throw } } }
function Wait-Indexer($ixer) {
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep 10
        try { $st = (Invoke-RestMethod -Uri "$ep/indexers/$ixer/status?api-version=$api" -Headers $hdr).lastResult } catch { continue }
        if ($st -and $st.status -ne 'inProgress') { return $st.status }
    }
    return 'still running'
}

if (-not $Rebuild) {
    foreach ($m in $map) {
        $ixer = ($m.Index -replace '-index$', '') + '-indexer'
        Write-Host "run $ixer  (incremental - picks up added / changed files) ..." -ForegroundColor Cyan
        Start-Indexer $ixer
        $s = Wait-Indexer $ixer
        Write-Host "  $($m.Index): $s - $(Docs $m.Index) chunk doc(s)" -ForegroundColor Green
    }
    Write-Host "Removed files are NOT reflected by a plain re-run - use  -Rebuild  for that." -ForegroundColor Yellow
    return
}

# --- Rebuild: drop + recreate + run from the current blobs (reflects adds AND removes) --------
$aoai = $h['AZURE_OPENAI_ENDPOINT'].TrimEnd('/'); $embed = $h['EMBEDDING_DEPLOYMENT']
$container = $h['STORAGE_CONTAINER']
$storResId = "/subscriptions/$($h['AZURE_SUBSCRIPTION_ID'])/resourceGroups/$($h['AZURE_RESOURCE_GROUP'])/providers/Microsoft.Storage/storageAccounts/$($h['STORAGE_ACCOUNT'])"

function Put-Obj($kind, $name, $obj) { Invoke-RestMethod -Method Put -Uri "$ep/$kind/$name`?api-version=$api" -Headers $hdr -Body ($obj | ConvertTo-Json -Depth 20) | Out-Null }
function Del-Obj($kind, $name) { try { Invoke-RestMethod -Method Delete -Uri "$ep/$kind/$name`?api-version=$api" -Headers $hdr | Out-Null } catch {} }

foreach ($m in $map) {
    $ix = $m.Index; $base = $ix -replace '-index$', ''; $ds = "$base-ds"; $sk = "$base-skillset"; $ixer = "$base-indexer"
    Write-Host "rebuild $ix  (folder $($m.Prefix)) ..." -ForegroundColor Cyan
    Del-Obj 'indexers' $ixer; Del-Obj 'skillsets' $sk; Del-Obj 'indexes' $ix; Del-Obj 'datasources' $ds

    Put-Obj 'indexes' $ix @{ name = $ix; fields = @(
            @{ name = 'chunk_id'; type = 'Edm.String'; key = $true; searchable = $true; filterable = $true; sortable = $true; analyzer = 'keyword' }
            @{ name = 'parent_id'; type = 'Edm.String'; searchable = $false; filterable = $true }
            @{ name = 'title'; type = 'Edm.String'; searchable = $true; filterable = $true }
            @{ name = 'metadata_storage_path'; type = 'Edm.String'; searchable = $false }
            @{ name = 'content'; type = 'Edm.String'; searchable = $true }
            @{ name = 'content_vector'; type = 'Collection(Edm.Single)'; searchable = $true; dimensions = 3072; vectorSearchProfile = 'hnsw-profile' }
        )
        vectorSearch = @{
            algorithms  = @(@{ name = 'hnsw-algo'; kind = 'hnsw' })
            vectorizers = @(@{ name = 'aoai-vectorizer'; kind = 'azureOpenAI'; azureOpenAIParameters = @{ resourceUri = $aoai; deploymentId = $embed; modelName = $embed } })
            profiles    = @(@{ name = 'hnsw-profile'; algorithm = 'hnsw-algo'; vectorizer = 'aoai-vectorizer' })
        }
        semantic     = @{ configurations = @(@{ name = 'semantic-config'; prioritizedFields = @{ titleField = @{ fieldName = 'title' }; prioritizedContentFields = @(@{ fieldName = 'content' }) } }) }
    }

    Put-Obj 'datasources' $ds @{ name = $ds; type = 'azureblob'; credentials = @{ connectionString = "ResourceId=$storResId;" }; container = @{ name = $container; query = $m.Prefix } }

    Put-Obj 'skillsets' $sk @{ name = $sk; skills = @(
            @{ '@odata.type' = '#Microsoft.Skills.Text.SplitSkill'; name = 'split'; textSplitMode = 'pages'; maximumPageLength = 2000; pageOverlapLength = 500; context = '/document'; inputs = @(@{ name = 'text'; source = '/document/content' }); outputs = @(@{ name = 'textItems'; targetName = 'pages' }) }
            @{ '@odata.type' = '#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill'; name = 'embed'; resourceUri = $aoai; deploymentId = $embed; modelName = $embed; dimensions = 3072; context = '/document/pages/*'; inputs = @(@{ name = 'text'; source = '/document/pages/*' }); outputs = @(@{ name = 'embedding'; targetName = 'content_vector' }) }
        )
        indexProjections = @{
            selectors  = @(@{ targetIndexName = $ix; parentKeyFieldName = 'parent_id'; sourceContext = '/document/pages/*'; mappings = @(
                        @{ name = 'content'; source = '/document/pages/*' }
                        @{ name = 'content_vector'; source = '/document/pages/*/content_vector' }
                        @{ name = 'title'; source = '/document/metadata_storage_name' }
                        @{ name = 'metadata_storage_path'; source = '/document/metadata_storage_path' }
                    ) })
            parameters = @{ projectionMode = 'skipIndexingParentDocuments' }
        }
    }

    Put-Obj 'indexers' $ixer @{ name = $ixer; dataSourceName = $ds; targetIndexName = $ix; skillsetName = $sk
        parameters = @{ maxFailedItems = -1; maxFailedItemsPerBatch = -1; configuration = @{ dataToExtract = 'contentAndMetadata'; failOnUnsupportedContentType = $false; failOnUnprocessableDocument = $false; indexStorageMetadataOnlyForOversizedDocuments = $true } }
    }

    Start-Indexer $ixer
    $s = Wait-Indexer $ixer
    Write-Host "  ${ix}: $s - $(Docs $ix) chunk doc(s)" -ForegroundColor Green
}
