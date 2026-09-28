<#
.SYNOPSIS
    Verify your Volvo hackathon lab end-to-end using the keys in your team's .env file.

.DESCRIPTION
    No Azure sign-in required. Put your team's .env next to this script (or pass -EnvFile) and run
    it. It exercises every resource with the keys in that file, so a green result proves your
    environment is ready to build on:
      - Foundry chat model + embeddings
      - Azure AI Search (list + query the hack data)
      - Cosmos DB (create / write / read / query / delete)
      - Blob storage (list + read the data set)
      - A small retrieval-augmented answer that uses the services together, like a real app.

    You only need PowerShell 7. The .env carries your keys; keep it private (it is gitignored).

.EXAMPLE
    pwsh ./verify-lab.ps1

.EXAMPLE
    pwsh ./verify-lab.ps1 -EnvFile C:\path\to\team-01.env
#>
[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot '.env')
)

$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result($name, $state, $detail = '') {
    $results.Add([pscustomobject]@{ Name = $name; State = $state; Detail = "$detail" })
    $color = switch ($state) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } default { 'Red' } }
    Write-Host ("  [{0}] {1}{2}" -f $state, $name, $(if ($detail) { " - $detail" } else { '' })) -ForegroundColor $color
}

function Invoke-Api($Method, $Uri, $Headers, $Body, $ContentType = 'application/json') {
    try {
        $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers; ErrorAction = 'Stop' }
        if ($null -ne $Body) { $p.Body = $Body; $p.ContentType = $ContentType }
        return @{ ok = $true; data = (Invoke-RestMethod @p) }
    }
    catch {
        $msg = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300) }
        return @{ ok = $false; error = ($msg -replace '\s+', ' ').Trim() }
    }
}

Write-Host "Verifying your Volvo hackathon lab (key-based)..." -ForegroundColor Cyan

# --- Load the team .env ------------------------------------------------------
if (-not (Test-Path $EnvFile)) {
    Write-Host "`nNo .env found at '$EnvFile'. Put your team's .env next to this script, or pass -EnvFile <path>." -ForegroundColor Red
    exit 2
}
$cfg = @{}
foreach ($line in Get-Content $EnvFile) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#') -or -not $t.Contains('=')) { continue }
    $i = $t.IndexOf('='); $k = $t.Substring(0, $i).Trim(); $v = $t.Substring($i + 1).Trim().Trim('"')
    $cfg[$k] = $v
}
function Cfg($k, $default = '') { if ($cfg.ContainsKey($k) -and $cfg[$k]) { $cfg[$k] } else { $default } }

$aoaiEndpoint = (Cfg 'AZURE_OPENAI_ENDPOINT').TrimEnd('/')
$aoaiKey = Cfg 'AZURE_OPENAI_KEY'
$apiVer = Cfg 'AZURE_OPENAI_API_VERSION' '2025-01-01-preview'
$chat = Cfg 'CHAT_DEPLOYMENT' 'gpt-5.6-luna'
$embed = Cfg 'EMBEDDING_DEPLOYMENT' 'text-embedding-3-large'
$searchEndpoint = (Cfg 'SEARCH_ENDPOINT').TrimEnd('/')
$searchKey = Cfg 'SEARCH_KEY'
$searchIndex = Cfg 'SEARCH_INDEX' 'hackdata-index'
$cosmosEndpoint = (Cfg 'COSMOS_ENDPOINT').TrimEnd('/')
$cosmosKey = Cfg 'COSMOS_KEY'
$cosmosDb = Cfg 'COSMOS_DATABASE' 'truckoffer'
$storageAccount = Cfg 'STORAGE_ACCOUNT'
$container = Cfg 'STORAGE_CONTAINER' 'hackdata'
$storageSas = (Cfg 'STORAGE_SAS').TrimStart('?')

Write-Host ""
Write-Host "Using .env: $EnvFile" -ForegroundColor Cyan
Write-Host "  Foundry : $aoaiEndpoint"
Write-Host "  Search  : $searchEndpoint"
Write-Host "  Cosmos  : $cosmosEndpoint"
Write-Host "  Storage : $storageAccount"
Write-Host ""

# --- Foundry: chat + embeddings ----------------------------------------------
if ($aoaiEndpoint -and $aoaiKey) {
    $h = @{ 'api-key' = $aoaiKey }
    $r = Invoke-Api 'POST' "$aoaiEndpoint/openai/deployments/$chat/chat/completions?api-version=$apiVer" $h (@{ messages = @(@{ role = 'user'; content = 'Reply with exactly: READY' }); max_completion_tokens = 32 } | ConvertTo-Json -Depth 5)
    if ($r.ok) { Add-Result "Foundry chat model ($chat)" 'PASS' ("responded: '" + ("$($r.data.choices[0].message.content)" -replace '\s+', ' ').Trim() + "'") }
    else { Add-Result "Foundry chat model ($chat)" 'FAIL' $r.error }

    $r = Invoke-Api 'POST' "$aoaiEndpoint/openai/deployments/$embed/embeddings?api-version=$apiVer" $h (@{ input = 'Volvo FH truck configuration and available features' } | ConvertTo-Json)
    if ($r.ok -and $r.data.data[0].embedding) { Add-Result "Foundry embeddings ($embed)" 'PASS' ("vector length " + $r.data.data[0].embedding.Count) }
    else { Add-Result "Foundry embeddings ($embed)" 'FAIL' $r.error }
}
else { Add-Result 'Foundry' 'FAIL' 'AZURE_OPENAI_ENDPOINT / AZURE_OPENAI_KEY missing from .env' }

# --- Azure AI Search ---------------------------------------------------------
$topDoc = $null
if ($searchEndpoint -and $searchKey) {
    $h = @{ 'api-key' = $searchKey }
    $r = Invoke-Api 'GET' "$searchEndpoint/indexes?api-version=2024-07-01&`$select=name" $h
    if ($r.ok) { Add-Result 'Search service access (list indexes)' 'PASS' ("indexes: " + (@($r.data.value.name) -join ', ')) }
    else { Add-Result 'Search service access (list indexes)' 'FAIL' $r.error }

    $r = Invoke-Api 'POST' "$searchEndpoint/indexes/$searchIndex/docs/search?api-version=2024-07-01" $h (@{ search = 'truck'; top = 3; select = 'title,content' } | ConvertTo-Json)
    if ($r.ok) {
        $hits = @($r.data.value)
        if ($hits.Count -gt 0) { $topDoc = $hits[0]; Add-Result "Search query '$searchIndex'" 'PASS' ("$($hits.Count) hit(s); top: " + $topDoc.title) }
        else { Add-Result "Search query '$searchIndex'" 'WARN' 'query worked but 0 docs (indexer may still be running)' }
    }
    else { Add-Result "Search query '$searchIndex'" 'FAIL' $r.error }
}
else { Add-Result 'Azure AI Search' 'FAIL' 'SEARCH_ENDPOINT / SEARCH_KEY missing from .env' }

# --- Cosmos DB: create / write / read / query / delete -----------------------
# Cosmos master-key auth: sign each request with an HMAC-SHA256 of verb/type/link/date.
if ($cosmosEndpoint -and $cosmosKey) {
    $base = $cosmosEndpoint.TrimEnd('/')
    function Cosmos-Headers($verb, $resType, $resLink, $extra) {
        $date = [DateTime]::UtcNow.ToString('r').ToLowerInvariant()
        $payload = ("{0}`n{1}`n{2}`n{3}`n`n" -f $verb.ToLowerInvariant(), $resType.ToLowerInvariant(), $resLink, $date)
        $hm = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($cosmosKey))
        $sig = [Convert]::ToBase64String($hm.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload)))
        $h = @{ Authorization = [uri]::EscapeDataString("type=master&ver=1.0&sig=$sig"); 'x-ms-date' = $date; 'x-ms-version' = '2018-12-31' }
        if ($extra) { foreach ($k in $extra.Keys) { $h[$k] = $extra[$k] } }
        return $h
    }
    $r = Invoke-Api 'GET' "$base/dbs" (Cosmos-Headers 'GET' 'dbs' '' $null)
    if ($r.ok) { Add-Result 'Cosmos data-plane access (list databases)' 'PASS' ("databases: " + (@($r.data.Databases.id) -join ', ')) }
    else { Add-Result 'Cosmos data-plane access (list databases)' 'FAIL' $r.error }

    $coll = "verify-" + (-join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }))
    $createColl = Invoke-Api 'POST' "$base/dbs/$cosmosDb/colls" (Cosmos-Headers 'POST' 'colls' "dbs/$cosmosDb" $null) (@{ id = $coll; partitionKey = @{ paths = @('/pk'); kind = 'Hash' } } | ConvertTo-Json -Depth 5)
    if ($createColl.ok) {
        $collLink = "dbs/$cosmosDb/colls/$coll"
        $up = Invoke-Api 'POST' "$base/$collLink/docs" (Cosmos-Headers 'POST' 'docs' $collLink @{ 'x-ms-documentdb-is-upsert' = 'true'; 'x-ms-documentdb-partitionkey' = '["v1"]' }) (@{ id = 'doc1'; pk = 'v1'; msg = 'hello' } | ConvertTo-Json)
        $rd = Invoke-Api 'GET' "$base/$collLink/docs/doc1" (Cosmos-Headers 'GET' 'docs' "$collLink/docs/doc1" @{ 'x-ms-documentdb-partitionkey' = '["v1"]' })
        $qy = Invoke-Api 'POST' "$base/$collLink/docs" (Cosmos-Headers 'POST' 'docs' $collLink @{ 'x-ms-documentdb-isquery' = 'true'; 'x-ms-documentdb-query-enablecrosspartition' = 'true' }) (@{ query = 'SELECT * FROM c'; parameters = @() } | ConvertTo-Json) 'application/query+json'
        Invoke-Api 'DELETE' "$base/$collLink" (Cosmos-Headers 'DELETE' 'colls' $collLink $null) | Out-Null
        if ($up.ok -and $rd.ok -and $qy.ok) { Add-Result "Cosmos read/write ($cosmosDb)" 'PASS' 'created container, upserted, read, queried, deleted' }
        else { Add-Result "Cosmos read/write ($cosmosDb)" 'FAIL' (@($up.error, $rd.error, $qy.error | Where-Object { $_ }) -join '; ') }
    }
    else { Add-Result "Cosmos read/write ($cosmosDb)" 'WARN' ("container create denied: " + $createColl.error) }
}
else { Add-Result 'Cosmos DB' 'FAIL' 'COSMOS_ENDPOINT / COSMOS_KEY missing from .env' }

# --- Blob storage: list + read (SAS) ----------------------------------------
if ($storageAccount -and $storageSas) {
    $blobBase = "https://$storageAccount.blob.core.windows.net"
    $h = @{ 'x-ms-version' = '2021-08-06' }
    $r = Invoke-Api 'GET' "$blobBase/$container`?restype=container&comp=list&$storageSas" $h
    if ($r.ok) {
        # Regex, not [xml]: the list response carries a BOM that breaks the XmlDocument cast.
        $blobNames = @([regex]::Matches("$($r.data)", '<Name>(.*?)</Name>') | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) })
        Add-Result "Blob list ($container)" 'PASS' ("$($blobNames.Count) blob(s)")
        if ($blobNames.Count -gt 0) {
            # EscapeUriString (not EscapeDataString) so virtual-directory '/' stays literal.
            $b = Invoke-Api 'GET' ("$blobBase/$container/" + [uri]::EscapeUriString($blobNames[0]) + "?$storageSas") $h
            if ($b.ok) { Add-Result 'Blob read' 'PASS' ("read: " + $blobNames[0]) } else { Add-Result 'Blob read' 'FAIL' $b.error }
        }
    }
    else { Add-Result "Blob list ($container)" 'FAIL' $r.error }
}
else { Add-Result 'Blob storage' 'FAIL' 'STORAGE_ACCOUNT / STORAGE_SAS missing from .env' }

# --- Integration: retrieval-augmented answer (services together) -------------
if ($aoaiEndpoint -and $aoaiKey -and $topDoc -and $topDoc.content) {
    $h = @{ 'api-key' = $aoaiKey }
    $snippet = ("$($topDoc.content)").Trim(); if ($snippet.Length -gt 900) { $snippet = $snippet.Substring(0, 900) }
    $ragBody = @{
        messages              = @(
            @{ role = 'system'; content = 'Answer only from the provided source text.' }
            @{ role = 'user'; content = "Source from '$($topDoc.title)':`n$snippet`n`nIn one sentence, what does this document cover?" }
        )
        max_completion_tokens = 200
    } | ConvertTo-Json -Depth 6
    $r = Invoke-Api 'POST' "$aoaiEndpoint/openai/deployments/$chat/chat/completions?api-version=$apiVer" $h $ragBody
    if ($r.ok) { Add-Result 'End-to-end RAG (search + chat)' 'PASS' (("$($r.data.choices[0].message.content)" -replace '\s+', ' ').Trim()) }
    else { Add-Result 'End-to-end RAG (search + chat)' 'FAIL' $r.error }
}
else {
    Add-Result 'End-to-end RAG (search + chat)' 'WARN' 'skipped (no indexed document yet)'
}

# --- Summary -----------------------------------------------------------------
$fail = ($results | Where-Object State -eq 'FAIL').Count
$warn = ($results | Where-Object State -eq 'WARN').Count
$pass = ($results | Where-Object State -eq 'PASS').Count
Write-Host ""
Write-Host ("Summary: {0} passed, {1} warning(s), {2} failed." -f $pass, $warn, $fail) `
    -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })
if ($fail -gt 0) {
    Write-Host "Something is not ready yet. Share the failed lines above with your coach." -ForegroundColor Red
    exit 1
}
Write-Host "Your lab is ready: you can run models, search, read/write data, and read the data set." -ForegroundColor Green
exit 0
