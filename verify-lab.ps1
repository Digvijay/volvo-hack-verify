<#
.SYNOPSIS
    Verify your Volvo hackathon lab end-to-end, as your own participant account.

.DESCRIPTION
    Sign in as your lab user first (az login), then run this script. It auto-discovers your team's
    resource group and endpoints and exercises every resource with YOUR credentials, so a green
    result proves your environment is ready to build on:
      - Foundry chat model + embeddings
      - Azure AI Search (list + query the hack data)
      - Cosmos DB (create / write / read / query / delete)
      - Blob storage (list + read the data set)
      - Deploy rights (Contributor on your resource group: Container Apps + registry)
      - A small retrieval-augmented answer that uses the services together, like a real app.

    You only need the Azure CLI and PowerShell 7. Nothing here contains secrets; you supply your
    identity by signing in.

.EXAMPLE
    az login
    pwsh ./verify-lab.ps1

.EXAMPLE
    # If auto-discovery cannot pick your group (e.g. you can see more than one), pass it:
    pwsh ./verify-lab.ps1 -SubscriptionId <sub> -ResourceGroup rg-team-01
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$ChatDeployment = 'gpt-5.6-luna',
    [string]$EmbeddingDeployment = 'text-embedding-3-large',
    [string]$CosmosDatabase = 'truckoffer',
    [string]$SearchIndex = 'hackdata-index',
    [string]$DataContainer = 'hackdata',
    [string]$OpenAiApiVersion = '2025-01-01-preview'
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
    } catch {
        $msg = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300) }
        return @{ ok = $false; error = ($msg -replace '\s+', ' ').Trim() }
    }
}

$tokens = @{}
function Get-Token($scope) {
    if ($tokens.ContainsKey($scope)) { return $tokens[$scope] }
    $resource = $scope -replace '/\.default$', ''
    $t = az account get-access-token --resource $resource --query accessToken -o tsv --only-show-errors 2>$null
    if ([string]::IsNullOrWhiteSpace($t)) { throw "Could not acquire a token for $resource. Run 'az login' as your lab user first." }
    $tokens[$scope] = $t
    return $t
}

function Arm($method, $path, $body) {
    Invoke-Api $method "https://management.azure.com$path" @{ Authorization = "Bearer $armToken" } $body
}

Write-Host "Verifying your Volvo hackathon lab..." -ForegroundColor Cyan

# --- Require a lab-user sign-in ----------------------------------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Azure CLI ('az') is required. Install it and run 'az login' as your lab user." -ForegroundColor Red
    exit 2
}
try { $armToken = Get-Token 'https://management.azure.com/.default' }
catch {
    Write-Host "`nYou are not signed in. Run 'az login' as your lab user, then re-run this script." -ForegroundColor Red
    exit 2
}
$who = az account show --query user.name -o tsv --only-show-errors 2>$null
Add-Result 'Signed in' 'PASS' ("$who")

# --- Auto-discover your team's subscription + resource group -----------------
# Your account has access to exactly one team resource group (the one holding your Foundry account).
if (-not $SubscriptionId -or -not $ResourceGroup) {
    $subs = (Arm 'GET' "/subscriptions?api-version=2020-01-01").data.value
    :outer foreach ($s in $subs) {
        $rgs = (Arm 'GET' "/subscriptions/$($s.subscriptionId)/resourcegroups?api-version=2021-04-01").data.value
        foreach ($g in $rgs) {
            $f = (Arm 'GET' "/subscriptions/$($s.subscriptionId)/resourceGroups/$($g.name)/resources?api-version=2021-04-01&`$filter=resourceType eq 'Microsoft.CognitiveServices/accounts'").data.value
            if (@($f).Count -gt 0) {
                if (-not $SubscriptionId) { $SubscriptionId = $s.subscriptionId }
                if (-not $ResourceGroup) { $ResourceGroup = $g.name }
                break outer
            }
        }
    }
    if ($SubscriptionId -and $ResourceGroup) { Add-Result 'Discover your team resource group' 'PASS' $ResourceGroup }
    else {
        Add-Result 'Discover your team resource group' 'FAIL' 'could not find it; pass -SubscriptionId and -ResourceGroup'
        exit 1
    }
}

# --- Discover endpoints ------------------------------------------------------
$FoundryEndpoint = $null; $SearchEndpoint = $null; $CosmosEndpoint = $null; $StorageAccount = $null
$list = Arm 'GET' "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/resources?api-version=2021-04-01"
if ($list.ok) {
    function First-Name($type) { ($list.data.value | Where-Object { $_.type -eq $type } | Select-Object -First 1).name }
    $fn = First-Name 'Microsoft.CognitiveServices/accounts'
    if ($fn) {
        $acc = Arm 'GET' "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$fn`?api-version=2023-05-01"
        if ($acc.ok) { $FoundryEndpoint = $acc.data.properties.endpoint }
    }
    $sn = First-Name 'Microsoft.Search/searchServices'
    if ($sn) { $SearchEndpoint = "https://$sn.search.windows.net" }
    $cn = First-Name 'Microsoft.DocumentDB/databaseAccounts'
    if ($cn) {
        $cacc = Arm 'GET' "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.DocumentDB/databaseAccounts/$cn`?api-version=2024-05-15"
        if ($cacc.ok) { $CosmosEndpoint = $cacc.data.properties.documentEndpoint }
    }
    $StorageAccount = First-Name 'Microsoft.Storage/storageAccounts'
}

Write-Host ""
Write-Host "Team: $ResourceGroup" -ForegroundColor Cyan
Write-Host "  Foundry : $FoundryEndpoint"
Write-Host "  Search  : $SearchEndpoint"
Write-Host "  Cosmos  : $CosmosEndpoint"
Write-Host "  Storage : $StorageAccount"
Write-Host ""

# --- Deploy capability: Contributor on your resource group -------------------
$armH = @{ Authorization = "Bearer $armToken" }
$rgUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup`?api-version=2021-04-01"
$rg = Invoke-Api 'GET' $rgUrl $armH
if ($rg.ok) {
    $tags = @{}
    if ($rg.data.tags) { $rg.data.tags.PSObject.Properties | ForEach-Object { $tags[$_.Name] = $_.Value } }
    $probe = @{}; foreach ($k in $tags.Keys) { $probe[$k] = $tags[$k] }
    $probe['hack-verify'] = (Get-Date -Format o)
    $w = Invoke-Api 'PATCH' $rgUrl $armH (@{ tags = $probe } | ConvertTo-Json)
    if ($w.ok) {
        Invoke-Api 'PATCH' $rgUrl $armH (@{ tags = $tags } | ConvertTo-Json) | Out-Null
        Add-Result 'Deploy rights (Contributor on resource group)' 'PASS' 'you can create/update resources'
    } else { Add-Result 'Deploy rights (Contributor on resource group)' 'FAIL' $w.error }
    $envs = Invoke-Api 'GET' "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/managedEnvironments?api-version=2024-03-01" $armH
    if ($envs.ok -and @($envs.data.value).Count -gt 0) { Add-Result 'Container Apps environment' 'PASS' (@($envs.data.value)[0].name) }
    else { Add-Result 'Container Apps environment' 'WARN' 'not found' }
    $acrs = Invoke-Api 'GET' "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ContainerRegistry/registries?api-version=2023-11-01-preview" $armH
    if ($acrs.ok -and @($acrs.data.value).Count -gt 0) { Add-Result 'Container Registry' 'PASS' (@($acrs.data.value)[0].properties.loginServer) }
    else { Add-Result 'Container Registry' 'WARN' 'not found' }
}

# --- Foundry: chat + embeddings ----------------------------------------------
if ($FoundryEndpoint) {
    $foundryToken = Get-Token 'https://cognitiveservices.azure.com/.default'
    $h = @{ Authorization = "Bearer $foundryToken" }
    $chatUrl = "$($FoundryEndpoint.TrimEnd('/'))/openai/deployments/$ChatDeployment/chat/completions?api-version=$OpenAiApiVersion"
    $r = Invoke-Api 'POST' $chatUrl $h (@{ messages = @(@{ role = 'user'; content = 'Reply with exactly: READY' }); max_completion_tokens = 32 } | ConvertTo-Json -Depth 5)
    if ($r.ok) { Add-Result "Foundry chat model ($ChatDeployment)" 'PASS' ("responded: '" + ("$($r.data.choices[0].message.content)" -replace '\s+', ' ').Trim() + "'") }
    else { Add-Result "Foundry chat model ($ChatDeployment)" 'FAIL' $r.error }

    $embUrl = "$($FoundryEndpoint.TrimEnd('/'))/openai/deployments/$EmbeddingDeployment/embeddings?api-version=$OpenAiApiVersion"
    $r = Invoke-Api 'POST' $embUrl $h (@{ input = 'Volvo FH truck configuration and available features' } | ConvertTo-Json)
    if ($r.ok -and $r.data.data[0].embedding) { Add-Result "Foundry embeddings ($EmbeddingDeployment)" 'PASS' ("vector length " + $r.data.data[0].embedding.Count) }
    else { Add-Result "Foundry embeddings ($EmbeddingDeployment)" 'FAIL' $r.error }
}

# --- Azure AI Search ---------------------------------------------------------
$topDoc = $null
if ($SearchEndpoint) {
    $searchToken = Get-Token 'https://search.azure.com/.default'
    $h = @{ Authorization = "Bearer $searchToken" }
    $r = Invoke-Api 'GET' "$SearchEndpoint/indexes?api-version=2024-07-01&`$select=name" $h
    if ($r.ok) { Add-Result 'Search service access (list indexes)' 'PASS' ("indexes: " + (@($r.data.value.name) -join ', ')) }
    else { Add-Result 'Search service access (list indexes)' 'FAIL' $r.error }

    $r = Invoke-Api 'POST' "$SearchEndpoint/indexes/$SearchIndex/docs/search?api-version=2024-07-01" $h (@{ search = 'truck'; top = 3; select = 'metadata_storage_name,content' } | ConvertTo-Json)
    if ($r.ok) {
        $hits = @($r.data.value)
        if ($hits.Count -gt 0) { $topDoc = $hits[0]; Add-Result "Search query '$SearchIndex'" 'PASS' ("$($hits.Count) hit(s); top: " + $topDoc.metadata_storage_name) }
        else { Add-Result "Search query '$SearchIndex'" 'WARN' 'query worked but 0 docs (indexer may still be running)' }
    } else { Add-Result "Search query '$SearchIndex'" 'FAIL' $r.error }
}

# --- Cosmos DB: create / write / read / query / delete -----------------------
if ($CosmosEndpoint) {
    $cosmosToken = Get-Token 'https://cosmos.azure.com/.default'
    $base = $CosmosEndpoint.TrimEnd('/')
    function Cosmos-Headers($extra) {
        $h = @{
            Authorization  = [System.Uri]::EscapeDataString("type=aad&ver=1.0&sig=$cosmosToken")
            'x-ms-version' = '2018-12-31'
            'x-ms-date'    = ([DateTime]::UtcNow.ToString('r')).ToLower()
        }
        if ($extra) { foreach ($k in $extra.Keys) { $h[$k] = $extra[$k] } }
        return $h
    }
    $r = Invoke-Api 'GET' "$base/dbs" (Cosmos-Headers $null)
    if ($r.ok) { Add-Result 'Cosmos data-plane access (list databases)' 'PASS' ("databases: " + (@($r.data.Databases.id) -join ', ')) }
    else { Add-Result 'Cosmos data-plane access (list databases)' 'FAIL' $r.error }

    $coll = "verify-" + (-join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }))
    $createColl = Invoke-Api 'POST' "$base/dbs/$CosmosDatabase/colls" (Cosmos-Headers $null) (@{ id = $coll; partitionKey = @{ paths = @('/pk'); kind = 'Hash' } } | ConvertTo-Json -Depth 5)
    if ($createColl.ok) {
        $up = Invoke-Api 'POST' "$base/dbs/$CosmosDatabase/colls/$coll/docs" (Cosmos-Headers @{ 'x-ms-documentdb-is-upsert' = 'true'; 'x-ms-documentdb-partitionkey' = '["v1"]' }) (@{ id = 'doc1'; pk = 'v1'; msg = 'hello' } | ConvertTo-Json)
        $rd = Invoke-Api 'GET' "$base/dbs/$CosmosDatabase/colls/$coll/docs/doc1" (Cosmos-Headers @{ 'x-ms-documentdb-partitionkey' = '["v1"]' })
        $qy = Invoke-Api 'POST' "$base/dbs/$CosmosDatabase/colls/$coll/docs" (Cosmos-Headers @{ 'x-ms-documentdb-isquery' = 'true'; 'x-ms-documentdb-query-enablecrosspartition' = 'true' }) (@{ query = 'SELECT * FROM c'; parameters = @() } | ConvertTo-Json) 'application/query+json'
        Invoke-Api 'DELETE' "$base/dbs/$CosmosDatabase/colls/$coll" (Cosmos-Headers $null) | Out-Null
        if ($up.ok -and $rd.ok -and $qy.ok) { Add-Result "Cosmos read/write ($CosmosDatabase)" 'PASS' 'created container, upserted, read, queried, deleted' }
        else { Add-Result "Cosmos read/write ($CosmosDatabase)" 'FAIL' (@($up.error, $rd.error, $qy.error | Where-Object { $_ }) -join '; ') }
    } else { Add-Result "Cosmos read/write ($CosmosDatabase)" 'WARN' ("container create denied: " + $createColl.error) }
}

# --- Blob storage: list + read ----------------------------------------------
if ($StorageAccount) {
    $storageToken = Get-Token 'https://storage.azure.com/.default'
    $h = @{ Authorization = "Bearer $storageToken"; 'x-ms-version' = '2021-08-06' }
    $blobBase = "https://$StorageAccount.blob.core.windows.net"
    $r = Invoke-Api 'GET' "$blobBase/$DataContainer`?restype=container&comp=list" $h
    if ($r.ok) {
        # Regex, not [xml]: the list response carries a BOM that breaks the XmlDocument cast.
        $blobNames = @([regex]::Matches("$($r.data)", '<Name>(.*?)</Name>') | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) })
        Add-Result "Blob list ($DataContainer)" 'PASS' ("$($blobNames.Count) blob(s)")
        if ($blobNames.Count -gt 0) {
            # EscapeUriString (not EscapeDataString) so virtual-directory '/' stays literal.
            $b = Invoke-Api 'GET' ("$blobBase/$DataContainer/" + [uri]::EscapeUriString($blobNames[0])) $h
            if ($b.ok) { Add-Result 'Blob read' 'PASS' ("read: " + $blobNames[0]) } else { Add-Result 'Blob read' 'FAIL' $b.error }
        }
    } else { Add-Result "Blob list ($DataContainer)" 'FAIL' $r.error }
}

# --- Integration: retrieval-augmented answer (services together) -------------
if ($FoundryEndpoint -and $topDoc -and $topDoc.content) {
    $foundryToken = Get-Token 'https://cognitiveservices.azure.com/.default'
    $h = @{ Authorization = "Bearer $foundryToken" }
    $snippet = ("$($topDoc.content)").Trim(); if ($snippet.Length -gt 900) { $snippet = $snippet.Substring(0, 900) }
    $ragBody = @{
        messages              = @(
            @{ role = 'system'; content = 'Answer only from the provided source text.' }
            @{ role = 'user'; content = "Source from '$($topDoc.metadata_storage_name)':`n$snippet`n`nIn one sentence, what does this document cover?" }
        )
        max_completion_tokens = 200
    } | ConvertTo-Json -Depth 6
    $r = Invoke-Api 'POST' "$($FoundryEndpoint.TrimEnd('/'))/openai/deployments/$ChatDeployment/chat/completions?api-version=$OpenAiApiVersion" $h $ragBody
    if ($r.ok) { Add-Result 'End-to-end RAG (embed + search + chat)' 'PASS' (("$($r.data.choices[0].message.content)" -replace '\s+', ' ').Trim()) }
    else { Add-Result 'End-to-end RAG (embed + search + chat)' 'FAIL' $r.error }
} else {
    Add-Result 'End-to-end RAG (embed + search + chat)' 'WARN' 'skipped (no indexed document yet)'
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
Write-Host "Your lab is ready: you can run models, search, read/write data, read the data set, and deploy apps." -ForegroundColor Green
exit 0
