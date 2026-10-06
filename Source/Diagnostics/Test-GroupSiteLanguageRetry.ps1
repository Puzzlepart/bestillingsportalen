# Testskript: opprett gruppeområde, sjekk språk, slett og prøv igjen.
#
# Bakgrunn: Graph ignorerer SPSiteLanguage i creationOptions ved POST /groups
# (sp-dev-docs #10875), så gruppeområdet kan få et annet språk enn bestilt. Groupify-
# workarounden (STS#3 + CreateGroupForSite) er forkastet: den krever en tjenestekonto med
# admin-rolle og er ustabil. Se Source/Scripts/provisioning-workaround/Bakgrunnsutredning-SPSiteLanguage.md.
#
# Dette skriptet tester alternativet: opprett gruppen akkurat som ProcessProvisionRequest gjør
# i dag (app-only POST /groups med creationOptions SPSiteLanguage), sjekk språket på området,
# og slett og prøv igjen hvis det er feil. Det svarer på to spørsmål før noe bygges inn i
# Bestillingsportalen:
#
#   1. Er feilen tilfeldig per opprettelse, eller fast i tenanten? Treffer ingen forsøk
#      riktig språk, hjelper ikke retry. Resultatet viser treff/bom for alle forsøk.
#   2. Hva koster det? Tid til området er klart, og hvor lenge URL-en er sperret etter sletting.
#
# Strategier (styres med parametre):
#   -BatchSize 1                  Ett forsøk om gangen. Første forsøk bruker aliaset, nye forsøk
#                                 bruker alias-xxxxx (5 tegn fra en GUID), så de slipper å vente
#                                 på at URL-en frigjøres.
#   -BatchSize 1 -RetrySameAlias  Ett forsøk om gangen på samme URL. Venter til URL-en er frigjort
#                                 etter sletting (observert 10-30+ min) og måler ventetiden.
#   -BatchSize N                  N forsøk samtidig per runde: aliaset + N-1 med suffiks. Første
#                                 treff beholdes (aliaset uten suffiks foretrekkes), resten slettes.
#
# Bom slettes med en gang, uten å vente: gruppen havner i Entra-papirkurven (30 dager) og området
# i SharePoint-papirkurven (93 dager). Med suffiks på aliaset sperrer de ingenting. Bare med
# -RetrySameAlias må gruppen slettes permanent og URL-en frigjøres før neste forsøk. Treffet slettes
# også til slutt, unntatt med -KeepWinner. -PurgeDeleted tømmer papirkurvene for det skriptet har
# slettet. Skriptet sletter aldri noe det ikke selv har opprettet.
#
# Kjøring:
#   Runbook (som i produksjon): importer som PowerShell 7.4-runbook i runtime environmentet
#     'bestillingsportalen-ps74'. Automation-kontoens managed identity har Graph
#     Group.ReadWrite.All og SharePoint Sites.FullControl.All (gis av deploy.ps1). Owner er påkrevd.
#   Lokalt: PowerShell 7.4 og PnP.PowerShell 3.2+. Logg inn som SharePoint-admin som også kan
#     slette grupper permanent (Groups-admin eller Global admin). Owner er deg hvis ikke oppgitt.
#     Merk at lokalt opprettes gruppen delegert, ikke app-only som i produksjon.
#
# Eksempler:
#   .\Test-GroupSiteLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com -BatchSize 3
#   .\Test-GroupSiteLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com -RetrySameAlias -MaxRounds 2
#   # Rydd rester etter tidligere kjøringer med aliaset LangTest01 (gruppe og område slettes permanent)
#   .\Test-GroupSiteLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com -Alias LangTest01 -CleanupOnly

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]  [string] $AdminUrl,
    # Gruppeeier (UPN). Påkrevd i runbook, standard innlogget bruker lokalt.
    [Parameter(Mandatory = $false)] [string] $Owner,
    [Parameter(Mandatory = $false)] [string] $Alias,
    [Parameter(Mandatory = $false)] [string] $Title,
    [Parameter(Mandatory = $false)] [int]    $Lcid = 1044,
    [Parameter(Mandatory = $false)] [string] $ManagedPath = 'sites',
    [Parameter(Mandatory = $false)] [int]    $BatchSize = 1,
    [Parameter(Mandatory = $false)] [int]    $MaxRounds = 3,
    [Parameter(Mandatory = $false)] [int]    $MaxMinutes = 60,
    [Parameter(Mandatory = $false)] [int]    $SiteReadyTimeoutMinutes = 15,
    [Parameter(Mandatory = $false)] [int]    $UrlReleaseTimeoutMinutes = 40,
    [Parameter(Mandatory = $false)] [int]    $CleanupTimeoutMinutes = 20,
    [Parameter(Mandatory = $false)] [switch] $RetrySameAlias,
    [Parameter(Mandatory = $false)] [switch] $KeepWinner,
    # Tøm slettede grupper og områder fra papirkurvene til slutt (venter ca. 10 min på områdene)
    [Parameter(Mandatory = $false)] [switch] $PurgeDeleted,
    # Opprett ingenting. Slett permanent grupper og områder fra tidligere kjøringer med -Alias:
    # bare URL-er som er nøyaktig <alias> eller <alias>-xxxxx, og grupper skriptet har merket.
    [Parameter(Mandatory = $false)] [switch] $CleanupOnly,
    # Tving managed identity. Ellers oppdages Azure Automation automatisk.
    [Parameter(Mandatory = $false)] [switch] $ManagedIdentity,
    [Parameter(Mandatory = $false)] [string] $ClientId = 'da6c31a6-b557-4ac3-9994-7315da06ea3a'
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
$deadline = $startTime.AddMinutes($MaxMinutes)

$stamp = Get-Date -Format 'yyyyMMddHHmm'
if (-not $Alias) { $Alias = "diag-lang-$stamp" }
if (-not $Title) { $Title = "Diagnose språk $stamp" }
$AdminUrl = $AdminUrl.TrimEnd('/')
$tenantRoot = $AdminUrl -replace '-admin\.sharepoint\.com', '.sharepoint.com'
if ($CleanupOnly -and -not $PSBoundParameters.ContainsKey('Alias')) { throw '-CleanupOnly krever -Alias.' }
$marker = 'Opprettet av Test-GroupSiteLanguageRetry.ps1'
if ($RetrySameAlias -and $BatchSize -ne 1) { throw '-RetrySameAlias kan bare brukes med -BatchSize 1.' }
if ($BatchSize -lt 1 -or $BatchSize -gt 10) { throw '-BatchSize må være mellom 1 og 10.' }

$inAutomation = [bool] ($env:AUTOMATION_ASSET_ACCOUNTID -or $PSPrivateMetadata.JobId)
$useMi = $ManagedIdentity -or $inAutomation

# Logging skjer kun på toppnivå. Hjelpefunksjoner som returnerer verdier skriver bare til
# warning-strømmen eller Write-Host, så Write-Output ikke blandes inn i returverdiene.
function Log([string] $Message, [string] $Level = 'INFO') {
    Write-Output ("[{0:HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message)
}
function Write-Section([string] $Text) {
    Write-Output ''
    Write-Output "=== $Text ==="
}
function Get-ErrorText($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    while ($ex.InnerException) { $ex = $ex.InnerException }
    return "$($ex.GetType().Name): $($ex.Message)"
}
function Wait-Until([scriptblock] $Condition, [int] $TimeoutSeconds, [int] $IntervalSeconds = 15, [string] $What) {
    $start = Get-Date
    $end = $start.AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $end) {
        try { if (& $Condition) { return $true } } catch { }
        if ($What) { Write-Host ("[{0:HH:mm:ss}] [WAIT]   {1} ({2}/{3} s)" -f (Get-Date), $What, [int] ((Get-Date) - $start).TotalSeconds, $TimeoutSeconds) }
        Start-Sleep -Seconds $IntervalSeconds
    }
    return $false
}
function Get-SiteUrl([string] $A) { return "$tenantRoot/$ManagedPath/$A" }
function New-SuffixAlias { return "$Alias-$(([guid]::NewGuid().ToString('N')).Substring(0, 5))" }

# ---------------------------------------------------------------------------
# Tilkobling
# ---------------------------------------------------------------------------
Write-Section "Tilkobling ($(if ($useMi) { 'managed identity' } else { 'interaktiv' }))"
if ($useMi) {
    if (-not $Owner) { throw '-Owner er påkrevd med managed identity.' }
    $admin = Connect-PnPOnline -Url $AdminUrl -ManagedIdentity -ReturnConnection
}
else {
    # Gjenbruk en tilkobling til samme admin-URL hvis sesjonen har en (fra Connect-PnPOnline eller
    # en tidligere kjøring). Ellers logg inn med -PersistLogin, så PnP husker innloggingen også
    # mellom sesjoner. Fjern den lagrede innloggingen med Disconnect-PnPOnline -ClearPersistedLogin.
    $admin = $null
    try { $admin = Get-PnPConnection -ErrorAction SilentlyContinue } catch { }
    if ($admin -and $admin.Url.TrimEnd('/') -ieq $AdminUrl) {
        Log 'Bruker eksisterende PnP-tilkobling'
    }
    else {
        Connect-PnPOnline -Url $AdminUrl -ClientId $ClientId -Interactive -PersistLogin
        $admin = Get-PnPConnection
    }
    $me =Get-PnPProperty -ClientObject (Get-PnPWeb -Connection $admin) -Property CurrentUser -Connection $admin
    $operatorUpn = ($me.LoginName -split '\|')[-1]
    Log "Innlogget som $operatorUpn"
    if (-not $Owner) { $Owner = $operatorUpn }
}

$siteConnections = @{}
function Connect-Site([string] $Url) {
    $key = $Url.TrimEnd('/').ToLowerInvariant()
    if (-not $siteConnections.ContainsKey($key)) {
        $siteConnections[$key] = if ($useMi) {
            Connect-PnPOnline -Url $Url -ManagedIdentity -ReturnConnection
        }
        else {
            Connect-PnPOnline -Url $Url -Interactive -Connection $admin -ReturnConnection
        }
    }
    return $siteConnections[$key]
}
function Get-LiveSite([string] $Url) {
    try { return Get-PnPTenantSite -Identity $Url -Connection $admin -ErrorAction SilentlyContinue } catch { return $null }
}
function Get-DeletedSite([string] $Url) {
    try { return Get-PnPTenantDeletedSite -Identity $Url -Connection $admin -ErrorAction SilentlyContinue } catch { return $null }
}
function Get-LiveGroup([string] $Id) {
    try { return Get-PnPMicrosoft365Group -Identity $Id -Connection $admin -ErrorAction SilentlyContinue } catch { return $null }
}
function Get-DeletedGroup([string] $Id) {
    try { return Get-PnPDeletedMicrosoft365Group -Identity $Id -Connection $admin -ErrorAction SilentlyContinue } catch { return $null }
}
function Test-AliasInUse([string] $A) {
    if ((Get-LiveSite (Get-SiteUrl $A)) -or (Get-DeletedSite (Get-SiteUrl $A))) { return $true }
    try {
        $hit = Invoke-PnPGraphMethod -Url ("v1.0/groups?`$filter=mailNickname eq '$A'&`$select=id") -Method Get -Connection $admin
        if ($hit.value) { return $true }
    } catch { }
    try {
        if (Get-PnPDeletedMicrosoft365Group -Connection $admin | Where-Object { $_.MailNickname -eq $A }) { return $true }
    } catch { }
    return $false
}
function Get-SiteLcid($Site) {
    # PnP-modellen (SPOSite) kaller SiteProperties.Lcid for LocaleId
    $v = if ($Site.PSObject.Properties["LocaleId"]) { $Site.LocaleId } else { $Site.Lcid }
    if ($null -eq $v) { return $null }
    return [int] $v
}
function Get-WebLanguage([string] $Url) {
    try { return [int] (Get-PnPWeb -Includes Language -Connection (Connect-Site $Url)).Language } catch { return $null }
}

function Remove-GroupPermanently([string] $Id, [int] $TimeoutSeconds = 300) {
    if (-not $Id) { return $true }
    return Wait-Until -TimeoutSeconds $TimeoutSeconds -What "gruppe $Id permanent slettet" -Condition {
        if (Get-LiveGroup $Id) {
            try { Remove-PnPMicrosoft365Group -Identity $Id -Connection $admin | Out-Null } catch { Write-Warning "Remove-PnPMicrosoft365Group: $(Get-ErrorText $_)" }
            return $false
        }
        if (Get-DeletedGroup $Id) {
            try { Remove-PnPDeletedMicrosoft365Group -Identity $Id -Connection $admin | Out-Null } catch { Write-Warning "Remove-PnPDeletedMicrosoft365Group: $(Get-ErrorText $_)" }
            return $false
        }
        Start-Sleep -Seconds 10
        return (-not (Get-LiveGroup $Id)) -and (-not (Get-DeletedGroup $Id))
    }
}

function Remove-GroupSoft([string] $Id) {
    # Myk sletting: ett kall, ingen venting. Området følger etter asynkront.
    try { Remove-PnPMicrosoft365Group -Identity $Id -Connection $admin | Out-Null; return $true }
    catch { Write-Warning "Remove-PnPMicrosoft365Group ($Id): $(Get-ErrorText $_)"; return $false }
}

function Invoke-GroupSiteDelete([string] $Url) {
    # Det SharePoint selv bruker for «Slett område» på gruppeområder (også PnP Framework
    # SiteCollection.DeleteSiteAsync): sletter område og gruppe samlet.
    # Parameteren sendes i body: med siteUrl i spørrestrengen og tom body svarer SharePoint
    # «Kan ikke håndtere dataene med plasseringen 0».
    Invoke-PnPSPRestMethod -Method Post -Url "$Url/_api/GroupSiteManager/Delete" -Content @{ siteUrl = $Url } `
        -ContentType 'application/json;odata=nometadata' -Connection (Connect-Site $Url) | Out-Null
}

function Remove-OrphanedGroupSite([string] $Url) {
    # Admin-API-et nekter å slette et område med GroupId («Dette området tilhører en Microsoft
    # 365-gruppe»), også når gruppen er slettet. Fjern koblingen først, slett deretter området.
    # ClearGroupId krever at gruppen er slettet permanent, ikke bare ligger i papirkurven.
    $ctx = $admin.Context
    $tenant = [Microsoft.Online.SharePoint.TenantAdministration.Tenant]::new($ctx)
    $props = $tenant.GetSitePropertiesByUrl($Url, $false)
    $ctx.Load($props)
    $ctx.ExecuteQuery()
    if ($props.GroupId -ne [guid]::Empty) {
        $props.ClearGroupId = $true
        $props.Update() | Out-Null
        $ctx.ExecuteQuery()
    }
    Remove-PnPTenantSite -Url $Url -Force -Connection $admin | Out-Null
}

function Remove-Candidate($Candidate) {
    # Slett område og gruppe med en gang. Prøver i rekkefølge, og lagrer hva som virket:
    #   1. GroupSiteManager/Delete (område + gruppe samlet)
    #   2. Slett gruppen permanent via Graph (tar noen sekunder), fjern GroupId fra området og
    #      slett det via admin-API-et
    try {
        Invoke-GroupSiteDelete $Candidate.SiteUrl
        $Candidate.SiteDelete = 'GroupSiteManager'
        # Sikre at gruppen også er borte, i tilfelle SharePoint bare slettet området
        if (Get-LiveGroup $Candidate.GroupId) { return Remove-GroupSoft $Candidate.GroupId }
        return $true
    }
    catch { $gsmError = Get-ErrorText $_ }

    $groupOk = -not (Remove-GroupsPermanently @($Candidate.GroupId) 120).Count
    try {
        Remove-OrphanedGroupSite $Candidate.SiteUrl
        $Candidate.SiteDelete = "ClearGroupId (GroupSiteManager: $gsmError)"
    }
    catch { $Candidate.SiteDelete = "FEILET: GroupSiteManager: $gsmError | ClearGroupId: $(Get-ErrorText $_)" }
    return $groupOk
}

function Remove-GroupsPermanently([string[]] $Ids, [int] $TimeoutSeconds = 300) {
    # Myk-slett aktive grupper og tøm dem fra Entra-papirkurven. Alle polles samtidig.
    # Returnerer id-ene som ikke ble bekreftet borte.
    $remaining = [System.Collections.Generic.List[string]]::new()
    $Ids | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { $remaining.Add($_) }
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($remaining.Count -and (Get-Date) -lt $end) {
        foreach ($id in @($remaining)) {
            if (Get-LiveGroup $id) { Remove-GroupSoft $id | Out-Null; continue }
            if (Get-DeletedGroup $id) {
                try { Remove-PnPDeletedMicrosoft365Group -Identity $id -Connection $admin | Out-Null } catch { Write-Warning "Remove-PnPDeletedMicrosoft365Group ($id): $(Get-ErrorText $_)" }
                continue
            }
            $remaining.Remove($id) | Out-Null
            Write-Host ("[{0:HH:mm:ss}] [OK]     gruppe {1} er slettet permanent" -f (Get-Date), $id)
        }
        if ($remaining.Count) {
            Write-Host ("[{0:HH:mm:ss}] [WAIT]   venter på at {1} gruppe(r) forsvinner" -f (Get-Date), $remaining.Count)
            Start-Sleep -Seconds 10
        }
    }
    return , @($remaining)
}

function Remove-SitesPermanently([string[]] $Urls, [int] $TimeoutSeconds) {
    # Gruppeområder slettes ikke pålitelig av SharePoint når gruppen slettes like etter at den ble
    # opprettet: områdene ble stående aktive i 15+ min med GroupId til en gruppe som ikke finnes.
    # Er gruppen borte, slettes området derfor eksplisitt, og deretter tømmes papirkurven.
    # Alle URL-er polles samtidig. Returnerer URL-ene som ikke ble borte.
    $remaining = [System.Collections.Generic.List[string]]::new()
    $Urls | Select-Object -Unique | ForEach-Object { $remaining.Add($_) }
    $lastError = @{}
    $note = {
        param($u, $msg)
        if ($lastError[$u] -ne $msg) { Write-Warning "$u : $msg"; $lastError[$u] = $msg }
    }
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($remaining.Count -and (Get-Date) -lt $end) {
        foreach ($u in @($remaining)) {
            $live = Get-LiveSite $u
            if ($live) {
                $gid = if ($live.GroupId -and $live.GroupId.Guid -ne [guid]::Empty.Guid) { $live.GroupId.Guid } else { $null }
                if ($gid -and (Get-LiveGroup $gid)) {
                    try { Remove-PnPMicrosoft365Group -Identity $gid -Connection $admin | Out-Null } catch { & $note $u "Remove-PnPMicrosoft365Group: $(Get-ErrorText $_)" }
                }
                else {
                    # Uten gruppe, eller gruppen er slettet: slett området selv (til papirkurven)
                    try {
                        if ($gid) { Remove-OrphanedGroupSite $u } else { Remove-PnPTenantSite -Url $u -Force -Connection $admin | Out-Null }
                    } catch { & $note $u "Sletting av området: $(Get-ErrorText $_)" }
                }
                continue
            }
            if (Get-DeletedSite $u) {
                try { Remove-PnPTenantDeletedSite -Identity $u -Force -Connection $admin | Out-Null } catch { & $note $u "Remove-PnPTenantDeletedSite: $(Get-ErrorText $_)" }
                continue
            }
            $remaining.Remove($u) | Out-Null
            Write-Host ("[{0:HH:mm:ss}] [OK]     {1} er borte" -f (Get-Date), $u)
        }
        if ($remaining.Count) {
            Write-Host ("[{0:HH:mm:ss}] [WAIT]   venter på at {1} område(r) forsvinner" -f (Get-Date), $remaining.Count)
            Start-Sleep -Seconds 20
        }
    }
    return , @($remaining)
}

# ---------------------------------------------------------------------------
# Kun opprydding (-CleanupOnly)
# ---------------------------------------------------------------------------
if ($CleanupOnly) {
    Write-Section "Opprydding av rester for '$Alias'"
    $pattern = '^' + [regex]::Escape($Alias) + '(-[0-9a-f]{5})?$'
    $ids = [System.Collections.Generic.List[string]]::new()
    try {
        $q = "v1.0/groups?`$filter=startswith(mailNickname,'$Alias')&`$select=id,mailNickname,description&`$top=999"
        (Invoke-PnPGraphMethod -Url $q -Method Get -Connection $admin).value |
            Where-Object { $_.mailNickname -match $pattern -and $_.description -eq $marker } |
            ForEach-Object { $ids.Add($_.id); Log "Aktiv gruppe: $($_.mailNickname) ($($_.id))" }
    } catch { Log "Kunne ikke lese grupper: $(Get-ErrorText $_)" 'WARN' }
    try {
        Get-PnPDeletedMicrosoft365Group -Connection $admin |
            Where-Object { $_.MailNickname -match $pattern -and $_.Description -eq $marker } |
            ForEach-Object { if (-not $ids.Contains($_.Id)) { $ids.Add($_.Id) }; Log "Slettet gruppe: $($_.MailNickname) ($($_.Id))" }
    } catch { Log "Kunne ikke lese slettede grupper: $(Get-ErrorText $_)" 'WARN' }

    if ($ids.Count) {
        Log "Sletter $($ids.Count) gruppe(r) permanent"
        $leftGroups = Remove-GroupsPermanently $ids.ToArray()
        foreach ($id in $leftGroups) { Log "Gruppe $id ble ikke bekreftet slettet permanent" 'ERR' }
    }

    # Områder: bare nøyaktig <alias> eller <alias>-xxxxx, og aldri et område med en annens aktive gruppe
    $urls = [System.Collections.Generic.List[string]]::new()
    $matchUrl = { param($u) (($u.TrimEnd('/') -split '/')[-1]) -match $pattern }
    try {
        foreach ($site in (Get-PnPTenantSite -Filter "Url -like '$Alias'" -Connection $admin | Where-Object { & $matchUrl $_.Url })) {
            $gid = if ($site.GroupId -and $site.GroupId.Guid -ne [guid]::Empty.Guid) { $site.GroupId.Guid } else { $null }
            if ($gid -and -not $ids.Contains($gid) -and (Get-LiveGroup $gid)) { Log "Hopper over $($site.Url): tilhører en aktiv gruppe skriptet ikke har opprettet" 'WARN'; continue }
            $urls.Add($site.Url); Log "Aktivt område: $($site.Url)"
        }
    } catch { Log "Kunne ikke lese områder: $(Get-ErrorText $_)" 'WARN' }
    try {
        Get-PnPTenantDeletedSite -Connection $admin | Where-Object { & $matchUrl $_.Url } |
            ForEach-Object { if (-not $urls.Contains($_.Url)) { $urls.Add($_.Url) }; Log "Område i papirkurven: $($_.Url)" }
    } catch { Log "Kunne ikke lese papirkurven: $(Get-ErrorText $_)" 'WARN' }

    $left = @()
    if ($urls.Count) {
        Log "Sletter $($urls.Count) område(r) permanent (opptil $CleanupTimeoutMinutes min)"
        $left = Remove-SitesPermanently $urls.ToArray() ($CleanupTimeoutMinutes * 60)
    }
    foreach ($u in $left) { Log "Ikke ryddet ferdig: $u. Kjør -CleanupOnly på nytt senere." 'WARN' }
    Log "Ferdig: $($ids.Count) gruppe(r), $($urls.Count - $left.Count) av $($urls.Count) område(r) slettet permanent." $(if ($left.Count) { 'WARN' } else { 'OK' })
    return
}

# ---------------------------------------------------------------------------
# Forberedelser
# ---------------------------------------------------------------------------
Write-Section 'Forberedelser'
$ownerId = (Invoke-PnPGraphMethod -Url ('v1.0/users/' + [uri]::EscapeDataString($Owner) + '?$select=id') -Method Get -Connection $admin).id
if (-not $ownerId) { throw "Fant ikke brukeren $Owner." }
Log "Eier        : $Owner ($ownerId)"
Log "Bestilt LCID: $Lcid"
Log "Strategi    : BatchSize $BatchSize, MaxRounds $MaxRounds$(if ($RetrySameAlias) { ', samme alias' }), MaxMinutes $MaxMinutes"

$rootLcid = $null
# Områdets eget språk er fasit. Admin-API-ets verdi brukes bare hvis området ikke kan leses.
$rootLcid = Get-WebLanguage $tenantRoot
if (-not $rootLcid) { try { $rootLcid = Get-SiteLcid (Get-PnPTenantSite -Identity $tenantRoot -Connection $admin) } catch { } }
Log "Rotområdets språk: $rootLcid"
if ($rootLcid -eq $Lcid) {
    Log 'Rotområdet har samme språk som bestilt. Feilen gir da ikke utslag, så testen sier lite. Bruk en annen -Lcid.' 'WARN'
}

if (Test-AliasInUse $Alias) { throw "Aliaset '$Alias' eller $(Get-SiteUrl $Alias) er i bruk (aktivt eller i papirkurv). Velg et annet -Alias." }
Log "Alias '$Alias' er ledig." 'OK'

# ---------------------------------------------------------------------------
# Runder
# ---------------------------------------------------------------------------
$candidates = [System.Collections.Generic.List[object]]::new()
$sitesToPurge = [System.Collections.Generic.List[string]]::new()
$deletedGroups = [System.Collections.Generic.List[string]]::new()
$winner = $null
$urlReleaseSeconds = [System.Collections.Generic.List[int]]::new()

for ($round = 1; $round -le $MaxRounds -and -not $winner -and (Get-Date) -lt $deadline; $round++) {
    Write-Section "Runde $round av $MaxRounds"

    if ($RetrySameAlias -and $round -gt 1) {
        # Den slettede gruppens område holder URL-en til SharePoint har flyttet det til papirkurven
        $plainUrl = Get-SiteUrl $Alias
        Log "Venter på at $plainUrl og aliaset frigjøres"
        $releaseStart = Get-Date
        # En myk-slettet gruppe holder på aliaset, så den må tømmes fra Entra-papirkurven først
        $prev = $candidates | Where-Object { $_.Alias -eq $Alias -and $_.GroupId } | Select-Object -Last 1
        if ($prev -and -not (Remove-GroupPermanently $prev.GroupId)) { Log "Gruppen $($prev.GroupId) ble ikke slettet permanent. Avbryter." 'ERR'; break }
        $deletedGroups.Remove($prev.GroupId) | Out-Null
        $left = Remove-SitesPermanently @($plainUrl) ($UrlReleaseTimeoutMinutes * 60)
        if ($left.Count -or (Test-AliasInUse $Alias)) { Log "URL-en ble ikke frigjort innen $UrlReleaseTimeoutMinutes min. Avbryter." 'ERR'; break }
        $secs = [int] ((Get-Date) - $releaseStart).TotalSeconds
        $urlReleaseSeconds.Add($secs)
        $sitesToPurge.Remove($plainUrl) | Out-Null
        Log "URL frigjort etter $secs s" 'OK'
    }

    # Kandidater for runden
    $batch = @()
    for ($i = 1; $i -le $BatchSize; $i++) {
        $a = if (($round -eq 1 -and $i -eq 1) -or $RetrySameAlias) { $Alias } else { New-SuffixAlias }
        if ($a -ne $Alias -and (Test-AliasInUse $a)) { $a = New-SuffixAlias }
        $batch += [pscustomobject]@{
            Round = $round; Alias = $a; SiteUrl = (Get-SiteUrl $a); GroupId = $null; Created = $null
            ReadySeconds = $null; TenantLcid = $null; WebLanguage = $null; Outcome = 'Pending'; Error = $null; SiteDelete = $null
        }
    }

    # Opprett alle i runden. Samme body som ProcessProvisionRequest (Set_MembersRequestBody_variable).
    foreach ($c in $batch) {
        $body = @{
            description         = $marker
            displayName         = "$Title ($($c.Alias))"
            groupTypes          = @('Unified')
            creationOptions     = @("SPSiteLanguage:$Lcid")
            mailEnabled         = $true
            mailNickname        = $c.Alias
            securityEnabled     = $false
            visibility          = 'Private'
            'owners@odata.bind' = @("https://graph.microsoft.com/v1.0/users/$ownerId")
        }
        try {
            $g = Invoke-PnPGraphMethod -Url 'v1.0/groups' -Method Post -Content $body -Connection $admin
            $c.GroupId = $g.id
            $c.Created = Get-Date
            Log "Opprettet gruppe $($c.Alias) ($($g.id))"
        }
        catch {
            $c.Outcome = 'CreateFailed'
            $c.Error = Get-ErrorText $_
            Log "Opprettelse av $($c.Alias) feilet: $($c.Error)" 'ERR'
        }
        $candidates.Add($c)
    }

    # Vent til områdene finnes og les språket
    $waitEnd = (Get-Date).AddMinutes($SiteReadyTimeoutMinutes)
    while ((Get-Date) -lt $waitEnd -and ($batch | Where-Object Outcome -eq 'Pending')) {
        foreach ($c in ($batch | Where-Object Outcome -eq 'Pending')) {
            $s = Get-LiveSite $c.SiteUrl
            if (-not $s -or $s.Status -ne 'Active') { continue }
            if ($s.GroupId.Guid -ne $c.GroupId) {
                $c.Outcome = 'WrongSite'; $c.Error = "Området på $($c.SiteUrl) har GroupId $($s.GroupId)"
                continue
            }
            $c.ReadySeconds = [int] ((Get-Date) - $c.Created).TotalSeconds
            $c.TenantLcid = Get-SiteLcid $s
            $c.WebLanguage = Get-WebLanguage $c.SiteUrl
            $lang = if ($c.WebLanguage) { $c.WebLanguage } else { $c.TenantLcid }
            $c.Outcome = if ($lang -eq $Lcid) { 'Hit' } else { 'Miss' }
        }
        $pending = @($batch | Where-Object Outcome -eq 'Pending').Count
        if ($pending) {
            Write-Host ("[{0:HH:mm:ss}] [WAIT]   venter på {1} område(r)" -f (Get-Date), $pending)
            Start-Sleep -Seconds 15
        }
    }
    foreach ($c in ($batch | Where-Object Outcome -eq 'Pending')) {
        $c.Outcome = 'NoSite'; $c.Error = "Området dukket ikke opp innen $SiteReadyTimeoutMinutes min"
    }
    foreach ($c in $batch) {
        Log ("{0,-32} {1,-6} klart etter {2,4} s  admin-Lcid {3,-5} web-språk {4}" -f $c.Alias, $c.Outcome, $c.ReadySeconds, $c.TenantLcid, $c.WebLanguage) $(if ($c.Outcome -eq 'Hit') { 'OK' } else { 'WARN' })
        if ($c.WebLanguage -and $c.TenantLcid -and $c.WebLanguage -ne $c.TenantLcid) {
            Log "  Admin-API og området er uenige om språket ($($c.TenantLcid) / $($c.WebLanguage))." 'WARN'
        }
    }

    # Velg treff: aliaset uten suffiks foretrekkes
    $hits = @($batch | Where-Object Outcome -eq 'Hit')
    $winner = ($hits | Where-Object Alias -eq $Alias | Select-Object -First 1)
    if (-not $winner) { $winner = $hits | Select-Object -First 1 }
    if ($winner) { Log "Treff: $($winner.SiteUrl)" 'OK' }

    # Slett alt annet i runden, uten å vente
    foreach ($c in ($batch | Where-Object { $_ -ne $winner -and $_.GroupId })) {
        $ok = Remove-Candidate $c
        Log "Slettet $($c.Alias): gruppe $(if ($ok) { 'OK' } else { 'FEILET' }), område $($c.SiteDelete)" $(if ($ok -and $c.SiteDelete -eq 'OK') { 'INFO' } else { 'WARN' })
        $deletedGroups.Add($c.GroupId)
        $sitesToPurge.Add($c.SiteUrl)
    }
}

# ---------------------------------------------------------------------------
# Opprydding
# ---------------------------------------------------------------------------
Write-Section 'Opprydding'
if ($winner -and -not $KeepWinner) {
    Log "Sletter treffet $($winner.SiteUrl) også (bruk -KeepWinner for å beholde det)"
    $ok = Remove-Candidate $winner
    Log "  Gruppe $(if ($ok) { 'OK' } else { 'FEILET' }), område $($winner.SiteDelete)"
    $deletedGroups.Add($winner.GroupId)
    $sitesToPurge.Add($winner.SiteUrl)
}
$leftovers = @()
if (-not $PurgeDeleted) {
    Log "$($deletedGroups.Count) gruppe(r) er slettet og ligger i papirkurvene (grupper 30 dager, områder 93 dager). Bruk -PurgeDeleted for å tømme dem."
}
else {
    $leftGroups = Remove-GroupsPermanently $deletedGroups.ToArray()
    foreach ($id in $leftGroups) { Log "Gruppen $id ble ikke bekreftet slettet permanent." 'ERR' }
}
if ($PurgeDeleted -and $sitesToPurge.Count) {
    Log "Venter på at $($sitesToPurge.Count) område(r) forsvinner og tømmer dem fra papirkurven (opptil $CleanupTimeoutMinutes min)"
    $leftovers = Remove-SitesPermanently $sitesToPurge.ToArray() ($CleanupTimeoutMinutes * 60)
}
foreach ($u in $leftovers) {
    Log "Ikke ryddet ferdig: $u. Når det ligger i papirkurven: Remove-PnPTenantDeletedSite -Identity $u -Force" 'WARN'
}

# ---------------------------------------------------------------------------
# Resultat
# ---------------------------------------------------------------------------
Write-Section 'RESULTAT'
$candidates | Format-Table Round, Alias, Outcome, ReadySeconds, TenantLcid, WebLanguage, SiteDelete, GroupId, Error -AutoSize -Wrap | Out-String -Width 250 | Write-Output

$measured = @($candidates | Where-Object { $_.Outcome -in @('Hit', 'Miss') })
$hitCount = @($measured | Where-Object Outcome -eq 'Hit').Count
$readyTimes = @($measured | ForEach-Object ReadySeconds)
$elapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

Write-Output "Treff: $hitCount av $($measured.Count) målte forsøk. Bestilt $Lcid, rotområdet har $rootLcid."
if ($readyTimes.Count) {
    Write-Output ("Tid til området var klart: min {0} s, maks {1} s, snitt {2} s." -f ($readyTimes | Measure-Object -Minimum).Minimum, ($readyTimes | Measure-Object -Maximum).Maximum, [int] ($readyTimes | Measure-Object -Average).Average)
}
if ($urlReleaseSeconds.Count) {
    Write-Output "URL sperret etter sletting: $(($urlReleaseSeconds | ForEach-Object { "$_ s" }) -join ', ')."
}
Write-Output "Total tid: $elapsed min.$(if ($PurgeDeleted) { " Ikke ryddet: $($leftovers.Count)." })"
Write-Output ''
if ($measured.Count -eq 0) {
    Write-Output 'UAVKLART - ingen områder ble klare til å måles. Se feilene over.'
}
elseif ($hitCount -eq $measured.Count) {
    Write-Output 'INGEN FEIL - alle forsøk fikk riktig språk. Feilen er ikke (lenger) til stede i tenanten.'
}
elseif ($hitCount -eq 0) {
    Write-Output "FAST FEIL - ingen av $($measured.Count) forsøk fikk riktig språk. Retry hjelper trolig ikke i denne"
    Write-Output '           tenanten. Kjør gjerne flere forsøk (-BatchSize/-MaxRounds) for å være sikker.'
}
else {
    Write-Output "TILFELDIG - $hitCount av $($measured.Count) forsøk fikk riktig språk. Retry/parallell opprettelse kan fungere."
    Write-Output '           Treffraten avgjør hvor mange forsøk per bestilling som trengs.'
}
