<#
.SYNOPSIS
    Oppretter et gruppetilknyttet teamområde med riktig språk ved å opprette flere kandidater
    og beholde den som fikk riktig språk.

.DESCRIPTION
    Workaround for at Microsoft Graph ignorerer SPSiteLanguage ved gruppeopprettelse
    (sp-dev-docs #10875). Feilen er tilfeldig per opprettelse: i test fikk ca. 28 % riktig språk.
    Se Bakgrunnsutredning-SPSiteLanguage.md i samme mappe.

    Fremgangsmåte per runde:
      1. Oppretter -BatchSize grupper samtidig via Graph (POST /groups med SPSiteLanguage), den
         første med -Alias og resten med -Alias-xxxxx (5 tegn fra en GUID)
      2. Venter til områdene finnes (ca. 20 s) og leser språket
      3. Beholder første treff (aliaset uten suffiks foretrekkes) og sletter resten permanent:
         gruppen slettes og tømmes fra Entra-papirkurven, deretter fjernes GroupId fra området
         (ClearGroupId) og området slettes. Admin-API-et nekter å slette gruppeområder direkte.
      4. Ingen treff gir ny runde, opp til -MaxRounds
    Når rundene er ferdige, tømmes de slettede områdene også fra SharePoints papirkurv. De har
    aldri hatt innhold, og et område i papirkurven holder på URL-en i 93 dager.

    Resultatet er et vanlig gruppeområde (GROUP#0), ofte med suffiks i URL og alias.
    Med -RequireExactAlias brukes bare aliaset uten suffiks: ett forsøk om gangen, og etter hver
    bom tømmes området fra papirkurven og skriptet venter til URL-en er frigjort (observert 10-30+ min).

    Medlemmer legges til først når treffet er valgt, så de ikke får e-post fra hver kandidat.
    Med -CreateTeam opprettes Teams-team, og med -HubUrl knyttes området til en hub.

    Kjøres lokalt (interaktiv innlogging) eller som runbook i Azure Automation (managed identity,
    oppdages automatisk). Skriptet sletter aldri noe det ikke selv har opprettet.

    Exit-koder lokalt: 0 suksess, 1 ingen treff/feil, 2 område OK men medlemmer, hub eller team feilet.

.PARAMETER AdminUrl          https://<tenant>-admin.sharepoint.com
.PARAMETER Title             Visningsnavn på gruppen
.PARAMETER Alias             Ønsket alias (mailNickname og /sites/<Alias>)
.PARAMETER Lcid              Ønsket språk. 1044 = norsk bokmål
.PARAMETER Owners            Eiere (UPN). Påkrevd med managed identity, ellers innlogget bruker
.PARAMETER Members           Medlemmer (UPN), legges til etter at treffet er valgt
.PARAMETER Description       Beskrivelse på gruppen. Standard: tittelen
.PARAMETER IsPublic          Offentlig gruppe. Standard: privat
.PARAMETER ManagedPath       Administrert bane for gruppeområder. Standard: sites
.PARAMETER BatchSize         Antall kandidater per runde. Standard 5
.PARAMETER MaxRounds         Maks antall runder. Standard 3
.PARAMETER RequireExactAlias Bruk bare aliaset uten suffiks, og vent på at URL-en frigjøres mellom forsøk
.PARAMETER CreateTeam        Opprett Teams-team på gruppen
.PARAMETER HubUrl            Knytt området til denne huben
.PARAMETER ManagedIdentity   Tving managed identity (oppdages ellers automatisk i Azure Automation)
.PARAMETER ClientId          App-registrering for interaktiv innlogging. Standard: Prosjektportalens PnP-app

.EXAMPLE
    .\New-PPSiteWithLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com `
        -Title "Prosjekt X" -Alias "prosjekt-x" -Owners "ola@contoso.com"

.EXAMPLE
    .\New-PPSiteWithLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com `
        -Title "Prosjekt X" -Alias "prosjekt-x" -Owners "ola@contoso.com" -Members "kari@contoso.com" `
        -BatchSize 5 -CreateTeam -HubUrl https://contoso.sharepoint.com/sites/prosjekthub

.EXAMPLE
    # Krever nøyaktig URL /sites/prosjekt-x. Kan ta lang tid.
    .\New-PPSiteWithLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com `
        -Title "Prosjekt X" -Alias "prosjekt-x" -RequireExactAlias -MaxRounds 4

.NOTES
    Krever PowerShell 7.4+ og PnP.PowerShell 3.2+.
    Interaktivt: SharePoint-admin, og rett til å opprette og slette M365-grupper permanent
    (Groups Administrator eller tilsvarende). Innloggingen huskes med -PersistLogin.
    Managed identity: Graph Group.ReadWrite.All og User.Read.All, SharePoint Sites.FullControl.All.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $AdminUrl,
    [Parameter(Mandatory)] [string] $Title,
    [Parameter(Mandatory)] [string] $Alias,
    [int]      $Lcid = 1044,
    [string[]] $Owners,
    [string[]] $Members,
    [string]   $Description = '',
    [switch]   $IsPublic,
    [string]   $ManagedPath = 'sites',
    [int]      $BatchSize = 5,
    [int]      $MaxRounds = 3,
    [switch]   $RequireExactAlias,
    [switch]   $CreateTeam,
    [string]   $HubUrl,
    [switch]   $ManagedIdentity,
    [string]   $ClientId = 'da6c31a6-b557-4ac3-9994-7315da06ea3a',
    [int]      $SiteReadyTimeoutMinutes = 10,
    [int]      $UrlReleaseTimeoutMinutes = 40
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
$AdminUrl = $AdminUrl.TrimEnd('/')
$tenantRoot = $AdminUrl -replace '-admin\.sharepoint\.com', '.sharepoint.com'
if ($RequireExactAlias) { $BatchSize = 1 }
if ($BatchSize -lt 1 -or $BatchSize -gt 10) { throw '-BatchSize må være mellom 1 og 10.' }
# Graph avviser tom description («Invalid value specified for property 'description'»), så tittelen brukes
if ([string]::IsNullOrWhiteSpace($Description)) { $Description = $Title }
if ($Alias.Length -gt 58) { throw '-Alias kan være maks 58 tegn (plass til suffikset -xxxxx innenfor grensen på 64).' }
$useMi = $ManagedIdentity -or [bool] ($env:AUTOMATION_ASSET_ACCOUNTID -or $PSPrivateMetadata.JobId)

function Log([string] $Message, [string] $Level = 'INFO') {
    Write-Output ("[{0:HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message)
}
function Get-ErrorText($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    while ($ex.InnerException) { $ex = $ex.InnerException }
    return "$($ex.GetType().Name): $($ex.Message)"
}
function Show-Progress([string] $Status, [int] $Percent = -1) {
    # Fremdriftslinje mens skriptet venter. Bare interaktivt: i Azure Automation blir det støy i jobbloggen.
    if ($useMi) { return }
    if ($Status) { Write-Progress -Activity "Oppretter $Alias med språk $Lcid" -Status $Status -PercentComplete $Percent }
    else { Write-Progress -Activity "Oppretter $Alias med språk $Lcid" -Completed }
}
function Get-SiteUrl([string] $A) { return "$tenantRoot/$ManagedPath/$A" }
function New-SuffixAlias { return "$Alias-$(([guid]::NewGuid().ToString('N')).Substring(0, 5))" }

# ---------------------------------------------------------------------------
# Tilkoblinger. Admin (SharePoint), Graph og tenant-CSOM har hver sin tilkobling: i runbook
# mistet en delt PnP-tilkobling SharePoint-konteksten etter permanent sletting av grupper.
# ---------------------------------------------------------------------------
function New-AdminConnection {
    if ($useMi) { return Connect-PnPOnline -Url $AdminUrl -ManagedIdentity -ReturnConnection }
    return Connect-PnPOnline -Url $AdminUrl -ClientId $ClientId -Interactive -PersistLogin -ReturnConnection
}
function Test-ConnectionContext($Connection) {
    try { return [bool] (Get-PnPContext -Connection $Connection) } catch { return $false }
}
function Repair-AdminConnection {
    if (-not (Test-ConnectionContext $script:admin)) { $script:admin = New-AdminConnection }
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
# Hjelpefunksjoner (logger ikke med Write-Output, så returverdiene ikke blandes med logg)
# ---------------------------------------------------------------------------
function Get-LiveSite([string] $Url) {
    try { return Get-PnPTenantSite -Identity $Url -Connection $script:admin -ErrorAction SilentlyContinue } catch { return $null }
}
function Get-DeletedSite([string] $Url) {
    try { return Get-PnPTenantDeletedSite -Identity $Url -Connection $script:admin -ErrorAction SilentlyContinue } catch { return $null }
}
function Get-SiteLcid($Site) {
    # PnP-modellen (SPOSite) kaller SiteProperties.Lcid for LocaleId
    $v = if ($Site.PSObject.Properties['LocaleId']) { $Site.LocaleId } else { $Site.Lcid }
    if ($null -eq $v) { return $null }
    return [int] $v
}
function Get-GroupState([string] $Id) {
    # Live, Deleted (i Entra-papirkurven), Gone eller Error. Feil tolkes aldri som «borte».
    try { Invoke-Graph Get ('v1.0/groups/' + $Id + '?$select=id') | Out-Null; return 'Live' }
    catch { if (-not (Test-NotFound $_)) { return 'Error' } }
    try { Invoke-Graph Get ('v1.0/directory/deletedItems/' + $Id + '?$select=id') | Out-Null; return 'Deleted' }
    catch { if (-not (Test-NotFound $_)) { return 'Error' } }
    return 'Gone'
}
function Test-AliasInUse([string] $A) {
    if ((Get-LiveSite (Get-SiteUrl $A)) -or (Get-DeletedSite (Get-SiteUrl $A))) { return $true }
    try { if ((Invoke-Graph Get ("v1.0/groups?`$filter=mailNickname eq '$A'&`$select=id")).value) { return $true } } catch { }
    try {
        $deleted = (Invoke-Graph Get 'v1.0/directory/deletedItems/microsoft.graph.group?$select=id,mailNickname&$top=999').value
        if ($deleted | Where-Object { $_.mailNickname -eq $A }) { return $true }
    } catch { }
    return $false
}
function Remove-GroupsPermanently([string[]] $Ids, [int] $TimeoutSeconds = 180) {
    # Slett og tøm fra Entra-papirkurven. Returnerer id-ene som ikke ble bekreftet borte.
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
    # Admin-API-et nekter å slette et område med GroupId, også når gruppen er slettet.
    # ClearGroupId krever at gruppen er slettet permanent.
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
    # Sletter gruppe og område for kandidatene. Returnerer feilmeldinger, tom liste ved suksess.
    $List = @($List | Where-Object GroupId)
    $errors = @()
    if (-not $List) { return , $errors }
    $notPurged = Remove-GroupsPermanently @($List | ForEach-Object GroupId)
    $pending = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $List) {
        if ($notPurged -contains $c.GroupId) { $errors += "$($c.Alias): gruppen ble ikke slettet permanent"; continue }
        $pending.Add($c)
    }
    # SharePoint kan se gruppen som myk-slettet en stund etter at Graph melder den borte, og
    # ClearGroupId feiler da («gruppen er i {0}-tilstand»). Områder som feiler, prøves igjen i opptil 2 min.
    $lastError = @{}
    for ($attempt = 1; $pending.Count -and $attempt -le 12; $attempt++) {
        if ($attempt -gt 1) {
            Show-Progress "Venter på at SharePoint registrerer slettingen av $($pending.Count) gruppe(r)"
            Start-Sleep -Seconds 10
        }
        foreach ($c in @($pending)) {
            try {
                if (Get-LiveSite $c.SiteUrl) { Remove-OrphanedGroupSite $c.SiteUrl }
                $script:sitesToPurge.Add($c.SiteUrl)
                $pending.Remove($c) | Out-Null
            }
            catch { $lastError[$c.Alias] = Get-ErrorText $_ }
        }
    }
    foreach ($c in $pending) { $errors += "$($c.Alias): $($lastError[$c.Alias])" }
    return , $errors
}
function Clear-CandidateRecycleBin([int] $TimeoutSeconds = 180) {
    # Tømmer områdene Remove-Candidates har slettet fra SharePoints papirkurv. RemoveSite flytter
    # området dit asynkront, så et område som fortsatt er aktivt ventes på. Alle polles samtidig.
    # Returnerer URL-ene som ikke ble bekreftet borte.
    $remaining = [System.Collections.Generic.List[string]]::new()
    $script:sitesToPurge | Select-Object -Unique | ForEach-Object { $remaining.Add($_) }
    $script:sitesToPurge.Clear()
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($remaining.Count -and (Get-Date) -lt $end) {
        Show-Progress "Tømmer papirkurven ($($remaining.Count) område(r) igjen)"
        Repair-AdminConnection
        foreach ($u in @($remaining)) {
            if (Get-LiveSite $u) { continue }
            if (Get-DeletedSite $u) {
                try { Remove-PnPTenantDeletedSite -Identity $u -Force -Connection $script:admin | Out-Null } catch { }
                if (Get-DeletedSite $u) { continue }
            }
            $remaining.Remove($u) | Out-Null
        }
        if ($remaining.Count) { Start-Sleep -Seconds 10 }
    }
    return , @($remaining)
}
function Resolve-UserIds([string[]] $Upns) {
    return @($Upns | Where-Object { $_ } | ForEach-Object {
            (Invoke-Graph Get ('v1.0/users/' + [uri]::EscapeDataString($_) + '?$select=id')).id
        })
}

# ---------------------------------------------------------------------------
# Forberedelser
# ---------------------------------------------------------------------------
$script:admin = New-AdminConnection
if (-not $Owners) {
    if ($useMi) { throw '-Owners er påkrevd med managed identity.' }
    $me = Get-PnPProperty -ClientObject (Get-PnPWeb -Connection $script:admin) -Property CurrentUser -Connection $script:admin
    $Owners = @(($me.LoginName -split '\|')[-1])
}
$ownerIds = Resolve-UserIds $Owners
$memberIds = Resolve-UserIds $Members

$rootLcid = $null
try { $rootLcid = Get-SiteLcid (Get-LiveSite $tenantRoot) } catch { }
if ($rootLcid -eq $Lcid -and $BatchSize -gt 1) {
    # Feilen gir området rotområdets språk. Er det likt det bestilte, treffer første forsøk.
    $BatchSize = 1
}

if (Test-AliasInUse $Alias) { throw "Aliaset '$Alias' eller $(Get-SiteUrl $Alias) er i bruk (aktivt eller i papirkurv)." }
Log ("{0}, språk {1}: opptil {2} runde(r) à {3}{4}. Eiere: {5}{6}" -f $Alias, $Lcid, $MaxRounds, $BatchSize,
    $(if ($rootLcid -eq $Lcid) { ' (rotområdet har samme språk)' }), ($Owners -join ', '),
    $(if ($Members) { ". Medlemmer: $($Members -join ', ')" }))

# ---------------------------------------------------------------------------
# Runder
# ---------------------------------------------------------------------------
$winner = $null
$attempts = 0
$hits = 0
$cleanupErrors = @()
$script:sitesToPurge = [System.Collections.Generic.List[string]]::new()

for ($round = 1; $round -le $MaxRounds -and -not $winner; $round++) {
    Repair-AdminConnection

    if ($RequireExactAlias -and $round -gt 1) {
        Log "Venter på at $(Get-SiteUrl $Alias) frigjøres (kan ta 10-30+ min)"
        $end = (Get-Date).AddMinutes($UrlReleaseTimeoutMinutes)
        # Bommen fra forrige runde holder på URL-en i papirkurven til den er tømt
        Clear-CandidateRecycleBin ([int] ($end - (Get-Date)).TotalSeconds) | Out-Null
        while ((Test-AliasInUse $Alias) -and (Get-Date) -lt $end) {
            Show-Progress "Venter på at $(Get-SiteUrl $Alias) frigjøres ($([int] ($end - (Get-Date)).TotalMinutes) min igjen)"
            Start-Sleep -Seconds 30
        }
        if (Test-AliasInUse $Alias) { Log "URL-en ble ikke frigjort innen $UrlReleaseTimeoutMinutes min." 'ERR'; break }
    }

    $batch = @()
    for ($i = 1; $i -le $BatchSize; $i++) {
        $a = if (($round -eq 1 -and $i -eq 1) -or $RequireExactAlias) { $Alias } else { New-SuffixAlias }
        while ($a -ne $Alias -and (Test-AliasInUse $a)) { $a = New-SuffixAlias }
        $batch += [pscustomobject]@{ Alias = $a; SiteUrl = (Get-SiteUrl $a); GroupId = $null; Created = $null; Lcid = $null; Outcome = 'Pending' }
    }

    Show-Progress "Runde $round/$($MaxRounds): oppretter $($batch.Count) kandidat(er)"
    $roundStart = Get-Date
    foreach ($c in $batch) {
        $body = @{
            description         = $Description
            displayName         = $Title
            groupTypes          = @('Unified')
            creationOptions     = @("SPSiteLanguage:$Lcid")
            mailEnabled         = $true
            mailNickname        = $c.Alias
            securityEnabled     = $false
            visibility          = $(if ($IsPublic) { 'Public' } else { 'Private' })
            'owners@odata.bind' = @($ownerIds | ForEach-Object { "https://graph.microsoft.com/v1.0/users/$_" })
        }
        try {
            $c.GroupId = (Invoke-Graph Post 'v1.0/groups' $body).id
            $c.Created = Get-Date
            $attempts++
        }
        catch { $c.Outcome = 'CreateFailed'; Log "Opprettelse av $($c.Alias) feilet: $(Get-ErrorText $_)" 'WARN' }
    }
    # Feiler alle opprettelsene, er feilen systematisk og nye runder hjelper ikke
    if (-not ($batch | Where-Object GroupId)) { Log "Ingen kandidater ble opprettet i runde $round. Avbryter." 'ERR'; break }

    $waitEnd = (Get-Date).AddMinutes($SiteReadyTimeoutMinutes)
    $created = @($batch | Where-Object GroupId).Count
    while ((Get-Date) -lt $waitEnd -and ($batch | Where-Object Outcome -eq 'Pending')) {
        $ready = @($batch | Where-Object { $_.Outcome -in 'Hit', 'Miss' }).Count
        Show-Progress "Runde $round/$($MaxRounds): venter på områdene ($ready av $created klare, $([int] ((Get-Date) - $roundStart).TotalSeconds) s)" ([int] (100 * $ready / $created))
        Start-Sleep -Seconds 10
        foreach ($c in ($batch | Where-Object Outcome -eq 'Pending')) {
            $s = Get-LiveSite $c.SiteUrl
            if (-not $s -or $s.Status -ne 'Active' -or $s.GroupId.Guid -ne $c.GroupId) { continue }
            $c.Lcid = Get-SiteLcid $s
            $c.Outcome = if ($c.Lcid -eq $Lcid) { 'Hit' } else { 'Miss' }
        }
    }
    foreach ($c in ($batch | Where-Object Outcome -eq 'Pending')) { $c.Outcome = 'NoSite' }

    $roundHits = @($batch | Where-Object Outcome -eq 'Hit')
    $hits += $roundHits.Count
    $winner = ($roundHits | Where-Object Alias -eq $Alias | Select-Object -First 1)
    if (-not $winner) { $winner = $roundHits | Select-Object -First 1 }

    $losers = @($batch | Where-Object { $_ -ne $winner -and $_.GroupId })
    $errs = @()
    if ($losers) {
        Show-Progress "Runde $round/$($MaxRounds): sletter $($losers.Count) kandidat(er)"
        $errs = Remove-Candidates $losers
        $cleanupErrors += $errs
    }
    # Én linje per runde, for eksempel «Runde 1/3: ingen treff, 5 bom (1044), slettet 5»
    $label = @{ Miss = 'bom'; NoSite = 'uten område'; CreateFailed = 'ikke opprettet' }
    $rest = @($batch | Where-Object Outcome -ne 'Hit' | Group-Object Outcome, Lcid | ForEach-Object {
            $o = $_.Group[0]; "$($_.Count) $($label[$o.Outcome])$(if ($o.Lcid) { " ($($o.Lcid))" })" })
    $line = "Runde $round/$($MaxRounds): " + $(if ($winner) { "treff $($winner.Alias)$(if ($roundHits.Count -gt 1) { " (+$($roundHits.Count - 1) treff slettet)" })" } else { 'ingen treff' })
    if ($rest) { $line += ', ' + ($rest -join ', ') }
    if ($losers) { $line += ", slettet $($losers.Count)$(if ($errs) { " ($($errs.Count) feil)" })" }
    Log $line $(if ($errs) { 'WARN' } elseif ($winner) { 'OK' } else { 'INFO' })
}

$purgeCount = @($script:sitesToPurge | Select-Object -Unique).Count
if ($purgeCount) {
    $notPurged = Clear-CandidateRecycleBin
    Log "Tømte $(if ($notPurged) { "$($purgeCount - $notPurged.Count) av " })$purgeCount område(r) fra papirkurven" $(if ($notPurged) { 'WARN' } else { 'INFO' })
    $cleanupErrors += @($notPurged | ForEach-Object { "$($_): ikke tømt fra papirkurven" })
}
Show-Progress
foreach ($e in $cleanupErrors) { Log "Ikke ryddet: $e" 'WARN' }
$elapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

if (-not $winner) {
    Log "Ingen kandidat fikk språk $Lcid etter $attempts forsøk ($elapsed min). Rotområdet har $rootLcid." 'ERR'
    if (-not $useMi) { exit 1 }
    throw "Ingen kandidat fikk språk $Lcid etter $attempts forsøk."
}

Log "Ferdig: $($winner.SiteUrl) ($attempts forsøk, $elapsed min)" 'OK'

# ---------------------------------------------------------------------------
# Etterarbeid: medlemmer, team og hub
# ---------------------------------------------------------------------------
$exitCode = 0
if ($memberIds) {
    Show-Progress "Legger til $($memberIds.Count) medlem(mer)"
    # Graph tar maks 20 per PATCH
    for ($i = 0; $i -lt $memberIds.Count; $i += 20) {
        $chunk = $memberIds[$i..([Math]::Min($i + 19, $memberIds.Count - 1))]
        try {
            Invoke-Graph Patch ('v1.0/groups/' + $winner.GroupId) @{ 'members@odata.bind' = @($chunk | ForEach-Object { "https://graph.microsoft.com/v1.0/directoryObjects/$_" }) } | Out-Null
        }
        catch { Log "Kunne ikke legge til medlemmer: $(Get-ErrorText $_)" 'WARN'; $exitCode = 2 }
    }
    Log "La til $($memberIds.Count) medlem(mer)"
}

$teamOk = $null
if ($CreateTeam) {
    $teamOk = $false
    Show-Progress 'Oppretter Teams-team'
    for ($i = 1; $i -le 4 -and -not $teamOk; $i++) {
        try { Invoke-Graph Put ('v1.0/groups/' + $winner.GroupId + '/team') @{} | Out-Null; $teamOk = $true }
        catch { Log "Teams-team, forsøk $i : $(Get-ErrorText $_)" 'WARN'; Start-Sleep -Seconds (15 * $i) }
    }
    if ($teamOk) { Log 'Teams-team opprettet' 'OK' } else { $exitCode = 2 }
}

$hubOk = $null
if ($HubUrl) {
    $hubOk = $false
    try {
        Repair-AdminConnection
        Add-PnPHubSiteAssociation -Site $winner.SiteUrl -HubSite $HubUrl.TrimEnd('/') -Connection $script:admin
        $hubOk = $true
        Log "Knyttet til hub $HubUrl" 'OK'
    }
    catch { Log "Hubtilknytning feilet: $(Get-ErrorText $_)" 'WARN'; $exitCode = 2 }
}

Show-Progress
[pscustomobject]@{
    SiteUrl       = $winner.SiteUrl
    Alias         = $winner.Alias
    GroupId       = $winner.GroupId
    Language      = $winner.Lcid
    Attempts      = $attempts
    Hits          = $hits
    TeamCreated   = $teamOk
    HubAssociated = $hubOk
    CleanupErrors = $cleanupErrors
    Minutes       = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
}
if (-not $useMi -and $exitCode) { exit $exitCode }
