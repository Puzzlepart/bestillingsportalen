#Runbook that creates the Microsoft 365 group for a provisioning request and makes sure the group site gets the requested language - for use with the Bestillingsportalen solution
#
# Why: Microsoft Graph ignores creationOptions SPSiteLanguage on POST /groups (sp-dev-docs #10875).
# The site then gets the root site's language. The behaviour is random per creation (about 28 %
# got the requested language in testing), so this runbook creates several candidate groups at
# once, keeps the first one whose site got the requested language and permanently deletes the rest.
# Background: Source/Scripts/provisioning-workaround/Bakgrunnsutredning-SPSiteLanguage.md
#
# Called by ProcessProvisionRequest instead of its own POST /groups when the
# 'EnableGroupLanguageRetry' setting is true. The logic app passes the exact group body it would
# otherwise have posted, base64 encoded (see the groupBody parameter). Per round:
#   1. Creates $batchSize groups: the first with the requested alias, the rest with alias-xxxxx
#      (5 characters from a GUID). Candidates are created without members, so members do not get
#      a welcome mail from every candidate; members are added to the winner afterwards.
#   2. Waits for the sites (about 20 s) and reads their language from the tenant admin API.
#   3. Keeps the first hit (the requested alias is preferred) and deletes the other candidates:
#      group deleted and purged from the Entra recycle bin via Graph, then GroupId cleared on the
#      site and the site removed via tenant CSOM. The admin API refuses to delete group sites
#      directly, and GroupSiteManager/Delete returns 403 for app-only.
#   4. No hit starts a new round, up to $maxRounds.
# When the rounds are done, the deleted candidate sites are also purged from the tenant recycle
# bin. They never had any content, and a site in the recycle bin keeps its URL for 93 days, which
# would block the requested alias for later requests.
#
# If the root site already has the requested language, the bug cannot change the outcome, so only
# one candidate is created.
#
# Output: the last output line is '##RESULT##' followed by JSON with groupId, alias, siteUrl,
# attempts, hits and the Graph group object. The logic app reads it via the job output. No hit
# after $maxRounds throws, so the job ends as Failed with the reason as the exception.
#
# Permissions (system-assigned managed identity of the Automation account, granted by deploy.ps1):
# Graph Group.ReadWrite.All, SharePoint Sites.FullControl.All.
[CmdletBinding()]
Param
(
    # The JSON body the logic app would otherwise POST to /groups (MembersRequestBody), base64
    # encoded. Azure Automation parses a parameter value that is valid JSON before the runbook
    # starts, and the runbook then got '@{description=...}' instead of the JSON. Base64 is never
    # valid JSON, so it arrives untouched like any other plain string. Plain JSON and an already
    # parsed object are also accepted, for manual runs.
    [Parameter (Mandatory = $true)]
    $groupBody,
    # The requested site URL (SiteURL on the request). Its parent path is used for the candidates.
    [Parameter (Mandatory = $true)]
    [string] $siteUrl,
    [Parameter (Mandatory = $true)]
    [string] $lcid,
    [string] $batchSize = '3',
    [string] $maxRounds = '3'
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date

$requestedLcid = [int] $lcid
$batch = [Math]::Max(1, [Math]::Min(10, [int] $batchSize))
$rounds = [Math]::Max(1, [int] $maxRounds)

$siteUri = [System.Uri] $siteUrl
$tenantRoot = "https://$($siteUri.Host)"
$adminUrl = "https://$($siteUri.Host.Split('.')[0])-admin.sharepoint.com"
$sitesBase = $siteUrl.TrimEnd('/').Substring(0, $siteUrl.TrimEnd('/').LastIndexOf('/'))

if ($groupBody -isnot [string]) {
    $groupBodyJson = $groupBody | ConvertTo-Json -Depth 10 -Compress
}
elseif ($groupBody.TrimStart().StartsWith('{')) {
    $groupBodyJson = $groupBody
}
elseif ($groupBody.TrimStart().StartsWith('@{')) {
    throw "groupBody arrived as PowerShell object text ($($groupBody.Substring(0, [Math]::Min(40, $groupBody.Length)))...): Azure Automation parsed the JSON before the runbook started. Pass groupBody base64 encoded, as ProcessProvisionRequest does from this version on."
}
else {
    $groupBodyJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($groupBody.Trim()))
}
$body = $groupBodyJson | ConvertFrom-Json -AsHashtable
$alias = [string] $body['mailNickname']
if (-not $alias) { throw 'groupBody has no mailNickname.' }
# Candidates get a 6 character suffix; keep the total within the 64 character mailNickname limit
$aliasBase = if ($alias.Length -gt 58) { $alias.Substring(0, 58) } else { $alias }
$members = @($body['members@odata.bind'] | Where-Object { $_ })
$body.Remove('members@odata.bind')

function Log([string] $Message) {
    Write-Output ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message)
}
function Get-ErrorText($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    while ($ex.InnerException) { $ex = $ex.InnerException }
    return "$($ex.GetType().Name): $($ex.Message)"
}

# ---------------------------------------------------------------------------
# Connections. SharePoint admin, Graph and tenant CSOM each get their own connection: in testing a
# shared PnP connection lost its SharePoint context after groups were permanently deleted, and every
# later call on it failed with 'holds no SharePoint context'. Connections are warmed up with retry
# for the same reason as in ConfigureSpace (transient managed identity endpoint failures).
# ---------------------------------------------------------------------------
function New-AdminConnection {
    for ($attempt = 1; ; $attempt++) {
        try {
            $c = Connect-PnPOnline -Url $adminUrl -ManagedIdentity -ReturnConnection
            $null = Get-PnPContext -Connection $c
            $null = Get-PnPTenantSite -Identity $tenantRoot -Connection $c
            return $c
        }
        catch {
            if ($attempt -ge 4) { throw }
            Start-Sleep -Seconds (10 * $attempt)
        }
    }
}
function Test-ConnectionContext($Connection) {
    try { return [bool] (Get-PnPContext -Connection $Connection) } catch { return $false }
}
function Get-AdminConnection {
    if (-not $script:admin -or -not (Test-ConnectionContext $script:admin)) { $script:admin = New-AdminConnection }
    return $script:admin
}
function Get-GraphConnection {
    if (-not $script:graph -or -not (Test-ConnectionContext $script:graph)) { $script:graph = New-AdminConnection }
    return $script:graph
}
function Invoke-Graph([string] $Method, [string] $Url, $Content) {
    $p = @{ Url = $Url; Method = $Method; Connection = (Get-GraphConnection) }
    if ($null -ne $Content) { $p.Content = $Content }
    return Invoke-PnPGraphMethod @p
}
function Test-NotFound($ErrorRecord) {
    return (Get-ErrorText $ErrorRecord) -match 'NotFound|\b404\b|does not exist|ResourceNotFound'
}
function Get-CsomContext {
    if (-not $script:csom -or -not (Test-ConnectionContext $script:csom)) { $script:csom = New-AdminConnection }
    return Get-PnPContext -Connection $script:csom
}

# ---------------------------------------------------------------------------
# Helpers (no Write-Output, so return values are not mixed with log lines)
# ---------------------------------------------------------------------------
function Get-LiveSite([string] $Url) {
    try { return Get-PnPTenantSite -Identity $Url -Connection (Get-AdminConnection) -ErrorAction SilentlyContinue } catch { return $null }
}
function Get-DeletedSite([string] $Url) {
    try { return Get-PnPTenantDeletedSite -Identity $Url -Connection (Get-AdminConnection) -ErrorAction SilentlyContinue } catch { return $null }
}
function Get-SiteLcid($Site) {
    # The PnP model (SPOSite) exposes SiteProperties.Lcid as LocaleId
    $v = if ($Site.PSObject.Properties['LocaleId']) { $Site.LocaleId } else { $Site.Lcid }
    if ($null -eq $v) { return $null }
    return [int] $v
}
function Get-GroupState([string] $Id) {
    # Live, Deleted (in the Entra recycle bin), Gone or Error. An error is never taken as "gone".
    try { Invoke-Graph Get ('v1.0/groups/' + $Id + '?$select=id') | Out-Null; return 'Live' }
    catch { if (-not (Test-NotFound $_)) { return 'Error' } }
    try { Invoke-Graph Get ('v1.0/directory/deletedItems/' + $Id + '?$select=id') | Out-Null; return 'Deleted' }
    catch { if (-not (Test-NotFound $_)) { return 'Error' } }
    return 'Gone'
}
function Test-AliasInUse([string] $A) {
    if ((Get-LiveSite "$sitesBase/$A") -or (Get-DeletedSite "$sitesBase/$A")) { return $true }
    try { if ((Invoke-Graph Get ("v1.0/groups?`$filter=mailNickname eq '$A'&`$select=id")).value) { return $true } } catch { }
    return $false
}
function Remove-GroupsPermanently([string[]] $Ids, [int] $TimeoutSeconds = 180) {
    # Delete and purge from the Entra recycle bin. Returns the ids not confirmed gone.
    $remaining = [System.Collections.Generic.List[string]]::new()
    $Ids | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { $remaining.Add($_) }
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($remaining.Count -and (Get-Date) -lt $end) {
        foreach ($id in @($remaining)) {
            switch (Get-GroupState $id) {
                'Live'    { try { Invoke-Graph Delete ('v1.0/groups/' + $id) | Out-Null } catch { } }
                'Deleted' { try { Invoke-Graph Delete ('v1.0/directory/deletedItems/' + $id) | Out-Null } catch { } }
                'Gone'    { $remaining.Remove($id) | Out-Null }
            }
        }
        if ($remaining.Count) { Start-Sleep -Seconds 5 }
    }
    return , @($remaining)
}
function Remove-OrphanedGroupSite([string] $Url) {
    # The admin API refuses to delete a site that has a GroupId, also after the group is deleted.
    # ClearGroupId requires the group to be permanently deleted.
    $ctx = Get-CsomContext
    $tenant = [Microsoft.Online.SharePoint.TenantAdministration.Tenant]::new($ctx)
    $props = $tenant.GetSitePropertiesByUrl($Url, $false)
    $ctx.Load($props)
    $ctx.ExecuteQuery()
    if ($props.GroupId -ne [guid]::Empty) {
        $props.ClearGroupId = $true
        $props.Update() | Out-Null
        $ctx.ExecuteQuery()
    }
    $op = $tenant.RemoveSite($Url)
    $ctx.Load($op)
    $ctx.ExecuteQuery()
}
function Remove-Candidates($List) {
    # Deletes group and site for the candidates. Returns error messages, empty on success.
    $List = @($List | Where-Object GroupId)
    $errors = @()
    if (-not $List) { return , $errors }
    $notPurged = Remove-GroupsPermanently @($List | ForEach-Object GroupId)
    foreach ($c in $List) {
        if ($notPurged -contains $c.GroupId) { $errors += "$($c.Alias): group not confirmed permanently deleted"; continue }
        if (-not (Get-LiveSite $c.SiteUrl)) { $script:sitesToPurge.Add($c.SiteUrl); continue }
        try { Remove-OrphanedGroupSite $c.SiteUrl; $script:sitesToPurge.Add($c.SiteUrl) } catch { $errors += "$($c.Alias): $(Get-ErrorText $_)" }
    }
    return , $errors
}
function Clear-CandidateRecycleBin([int] $TimeoutSeconds = 180) {
    # Purges the sites Remove-Candidates deleted from the tenant recycle bin. RemoveSite moves a site
    # there asynchronously, so a site that is still live is waited for. All sites are polled at once,
    # so sites from earlier rounds are usually already there. Returns the URLs not confirmed gone.
    $remaining = [System.Collections.Generic.List[string]]::new()
    $script:sitesToPurge | Select-Object -Unique | ForEach-Object { $remaining.Add($_) }
    $script:sitesToPurge.Clear()
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($remaining.Count -and (Get-Date) -lt $end) {
        foreach ($u in @($remaining)) {
            if (Get-LiveSite $u) { continue }
            if (Get-DeletedSite $u) {
                try { Remove-PnPTenantDeletedSite -Identity $u -Force -Connection (Get-AdminConnection) | Out-Null } catch { }
                if (Get-DeletedSite $u) { continue }
            }
            $remaining.Remove($u) | Out-Null
        }
        if ($remaining.Count) { Start-Sleep -Seconds 10 }
    }
    return , @($remaining)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Log "Requested alias '$alias', LCID $requestedLcid, up to $rounds round(s) of $batch candidate(s)"

$rootLcid = Get-SiteLcid (Get-LiveSite $tenantRoot)
if ($rootLcid -eq $requestedLcid -and $batch -gt 1) {
    Log "Root site has the requested language ($requestedLcid) - the bug cannot change the outcome, creating one candidate per round"
    $batch = 1
}
if (Test-AliasInUse $alias) { throw "Alias '$alias' or $sitesBase/$alias is already in use." }

$winner = $null
$attempts = 0
$hits = 0
$cleanupErrors = @()
$allCreated = [System.Collections.Generic.List[object]]::new()
$script:sitesToPurge = [System.Collections.Generic.List[string]]::new()

try {
    for ($round = 1; $round -le $rounds -and -not $winner; $round++) {
        $candidates = @()
        for ($i = 1; $i -le $batch; $i++) {
            $a = if ($round -eq 1 -and $i -eq 1) { $alias } else { "$aliasBase-$(([guid]::NewGuid().ToString('N')).Substring(0, 5))" }
            $candidates += [pscustomobject]@{ Alias = $a; SiteUrl = "$sitesBase/$a"; GroupId = $null; Lcid = $null; Outcome = 'Pending' }
        }

        foreach ($c in $candidates) {
            $candidateBody = $body.Clone()
            $candidateBody['mailNickname'] = $c.Alias
            try {
                $c.GroupId = (Invoke-Graph Post 'v1.0/groups' $candidateBody).id
                $attempts++
                $allCreated.Add($c)
            }
            catch { $c.Outcome = 'CreateFailed'; Log "Creating '$($c.Alias)' failed: $(Get-ErrorText $_)" }
        }

        $waitEnd = (Get-Date).AddMinutes(10)
        while ((Get-Date) -lt $waitEnd -and ($candidates | Where-Object Outcome -eq 'Pending')) {
            Start-Sleep -Seconds 10
            foreach ($c in ($candidates | Where-Object Outcome -eq 'Pending')) {
                $s = Get-LiveSite $c.SiteUrl
                if (-not $s -or $s.Status -ne 'Active' -or $s.GroupId.Guid -ne $c.GroupId) { continue }
                $c.Lcid = Get-SiteLcid $s
                $c.Outcome = if ($c.Lcid -eq $requestedLcid) { 'Hit' } else { 'Miss' }
            }
        }
        foreach ($c in ($candidates | Where-Object Outcome -eq 'Pending')) { $c.Outcome = 'NoSite' }
        Log "Round $($round): $(($candidates | ForEach-Object { "$($_.Alias)=$($_.Outcome)$(if ($_.Lcid) { "($($_.Lcid))" })" }) -join ', ')"

        $roundHits = @($candidates | Where-Object Outcome -eq 'Hit')
        $hits += $roundHits.Count
        $winner = ($roundHits | Where-Object Alias -eq $alias | Select-Object -First 1)
        if (-not $winner) { $winner = $roundHits | Select-Object -First 1 }

        $losers = @($candidates | Where-Object { $_ -ne $winner -and $_.GroupId })
        if ($losers) {
            $errs = Remove-Candidates $losers
            $cleanupErrors += $errs
            Log "Deleted $($losers.Count) candidate(s)$(if ($errs) { ", $($errs.Count) not cleaned up" })"
        }
    }
}
catch {
    # Never leave candidates behind when the runbook fails halfway
    $err = Get-ErrorText $_
    $left = @($allCreated | Where-Object { $_ -ne $winner })
    if ($left) { Remove-Candidates $left | Out-Null }
    Clear-CandidateRecycleBin | Out-Null
    throw "Group creation failed: $err"
}

$purgeCount = @($script:sitesToPurge | Select-Object -Unique).Count
if ($purgeCount) {
    $notPurged = Clear-CandidateRecycleBin
    Log "Purged $($purgeCount - $notPurged.Count) of $purgeCount deleted candidate site(s) from the recycle bin"
    $cleanupErrors += @($notPurged | ForEach-Object { "$($_): not purged from the recycle bin" })
}
foreach ($e in $cleanupErrors) { Log "Not cleaned up: $e" }
$minutes = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

if (-not $winner) {
    throw "No candidate got language $requestedLcid after $attempts attempt(s) in $minutes min (root site language $rootLcid). Raise GroupLanguageRetryParallel or GroupLanguageRetryMaxRounds, or try again."
}
Log "Kept $($winner.SiteUrl) after $attempts attempt(s), $hits hit(s), $minutes min"

# Members are added after the winner is chosen. Graph accepts at most 20 per PATCH. A failure from
# here on also deletes the kept group: the job fails either way, and a group left behind blocks the
# alias when the request is ordered again.
try {
    for ($i = 0; $i -lt $members.Count; $i += 20) {
        $chunk = $members[$i..([Math]::Min($i + 19, $members.Count - 1))]
        # [string[]] because Where-Object above wraps the strings in PSObject, and Invoke-PnPGraphMethod
        # serializes those (System.Text.Json) as objects: "Expected string(s) for ODataBind values"
        Invoke-Graph Patch ('v1.0/groups/' + $winner.GroupId) @{ 'members@odata.bind' = [string[]] $chunk } | Out-Null
    }
    if ($members) { Log "Added $($members.Count) member(s)" }

    $group = Invoke-Graph Get ('v1.0/groups/' + $winner.GroupId)
}
catch {
    $err = Get-ErrorText $_
    $errs = Remove-Candidates @($winner)
    Clear-CandidateRecycleBin | Out-Null
    throw "Adding members to $($winner.SiteUrl) failed: $err. $(if ($errs) { "The group could not be deleted: $($errs -join '; ')" } else { 'The group was deleted.' })"
}
$result = [ordered]@{
    groupId  = $winner.GroupId
    alias    = $winner.Alias
    siteUrl  = $winner.SiteUrl
    lcid     = $winner.Lcid
    attempts = $attempts
    hits     = $hits
    minutes  = $minutes
    group    = $group
}
Write-Output ('##RESULT##' + ($result | ConvertTo-Json -Depth 10 -Compress))
