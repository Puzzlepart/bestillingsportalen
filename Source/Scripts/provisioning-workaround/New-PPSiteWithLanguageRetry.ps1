<#
.SYNOPSIS
    Oppretter et gruppetilknyttet teamområde med riktig språk, med retry og fallback.

.DESCRIPTION
    Workaround for at Microsoft Graph / CreateGroupEx ignorerer SPSiteLanguage ved
    gruppeopprettelse (sp-dev-docs #10875).

    Forhåndssjekk:
      Avbryter før noe opprettes hvis URL-en eller aliaset er i bruk (aktivt eller i papirkurv),
      eller hvis -HubUrl ikke er et registrert hubområde. Skriptet sletter aldri noe det ikke selv
      har opprettet.

    Standard: kun fase 2. Fase 1 kjøres bare med -TryDirect, f.eks. for å sjekke om Microsofts
    rettelse har nådd tenanten. Et mislykket direkte forsøk sperrer URL-en i 10–30+ min.

    Fase 1 – direkte opprettelse (retry, kun med -TryDirect):
      1. Oppretter teamområde (M365-gruppe) med ønsket LCID via New-PnPSite
      2. Venter til området svarer, leser Web.Language og kontrollerer URL
      3. Riktig språk og URL -> ferdig. Ellers slettes gruppe + område permanent og det prøves igjen
      4. Etter -FallbackAfterAttempts mislykkede forsøk (standard 1) går skriptet til fase 2

    Fase 2 – STS#3 + groupify (standard, og fallback etter fase 1):
      1. Oppretter teamområde UTEN gruppe (STS#3) med ønsket LCID. Dette respekterer språk.
      2. Venter til området er aktivt, gjør innlogget bruker til site admin via admin-API,
         og venter -GroupifyBufferSeconds
      3. Kobler området til ny M365-gruppe (CreateGroupForSite)
      4. Venter til Site.GroupId er satt. Kjent feil: SharePoint oppretter av og til et nytt
         område (nummerert URL) i stedet. Kun da slettes den feilopprettede gruppen permanent
         (frigjør aliaset), og groupify prøves igjen uten å vente på at duplikatområdet forsvinner.
         Duplikater som ikke er ryddet ferdig, listes til slutt. Er gruppen koblet til det
         opprinnelige området, men ennå ikke synlig på Site.GroupId, ventes det videre – ingenting slettes.
      5. -CreateTeam oppretter Teams-team etter vellykket groupify

    Hub (valgfritt):
      Med -HubUrl knyttes området til huben etter vellykket opprettelse (begge faser).
      Tilknytningen verifiseres via HubSiteId.

    Begge faser deler samme tidsramme (-MaxMinutes). Opprydding og hubtilknytning fullføres også
    etter at tidsrammen er brukt opp, så skriptet ikke etterlater halvslettede grupper/områder.

    Exit-koder: 0 suksess, 1 feilet/timeout/forhåndssjekk, 2 område OK men hubtilknytning feilet.

.PARAMETER AdminUrl               https://<tenant>-admin.sharepoint.com
.PARAMETER ClientId               App-registrering for PnP PowerShell (delegert). Standard: da6c31a6-b557-4ac3-9994-7315da06ea3a
.PARAMETER Title                  Tittel på området
.PARAMETER Alias                  Alias (blir /sites/<Alias> og gruppens mailNickname)
.PARAMETER Lcid                   Ønsket språk. 1044 = norsk bokmål
.PARAMETER Owners                 Eiere (UPN). Standard: innlogget bruker
.PARAMETER IsPublic               Offentlig gruppe. Standard: privat
.PARAMETER MaxMinutes             Tidsramme for opprettelse. Standard 30
.PARAMETER RetryDelaySeconds      Pause mellom forsøk. Standard 30
.PARAMETER FallbackAfterAttempts  Med -TryDirect: antall mislykkede direkte forsøk før fallback. 0 = aldri fallback. Standard 1
.PARAMETER GroupifyBufferSeconds  Ekstra ventetid etter at STS#3-området er aktivt, før groupify. Standard 120
.PARAMETER GroupifyWaitSeconds    Hvor lenge det ventes på Site.GroupId etter hvert groupify-kall. Standard 180
.PARAMETER CleanupTimeoutMinutes  Hvor lenge det ventes på at et slettet gruppeområde frigjør URL-en (fase 1). Standard 30
.PARAMETER TimeZone               Tidssone-ID for STS#3-området. 4 = Oslo (W. Europe)
.PARAMETER CreateTeam             Opprett Teams-team etter groupify (kun fase 2)
.PARAMETER TryDirect              Prøv ordinær opprettelse av gruppeområde (fase 1) før STS#3 + groupify
.PARAMETER SkipDirect             Utgått, har ingen effekt (fase 2 er nå standard). Beholdt for bakoverkompatibilitet
.PARAMETER HubUrl                 Valgfri URL til hubområde det nye området skal knyttes til

.EXAMPLE
    .\New-PPSiteWithLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com `
        -Title "Prosjekt X" -Alias "prosjekt-x" -Owners "ola@contoso.com"

.EXAMPLE
    .\New-PPSiteWithLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com `
        -Title "Prosjekt X" -Alias "prosjekt-x" -CreateTeam `
        -HubUrl https://contoso.sharepoint.com/sites/prosjekthub

.EXAMPLE
    # Sjekk om ordinær opprettelse gir riktig språk igjen, med fallback til STS#3 + groupify
    .\New-PPSiteWithLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com `
        -Title "Prosjekt X" -Alias "prosjekt-x" -TryDirect -CreateTeam

.NOTES
    Krever PowerShell 7.4+ (pwsh) og PnP.PowerShell 3.2 eller nyere. Kontoen trenger SharePoint-admin og rett til å
    opprette og permanent slette M365-grupper (Groups Administrator eller tilsvarende).

    Tidsbruk: et mislykket direkte forsøk holder URL-en opptatt til SharePoint har flyttet det
    slettede gruppeområdet til papirkurven. Observert 10 til over 15 min, uten øvre grense, og det
    finnes ikke API for å fremskynde det. Derfor er -TryDirect ikke standard.
#>
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'PnP.PowerShell'; ModuleVersion = '3.2.0' }
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $AdminUrl,
    [string] $ClientId = 'da6c31a6-b557-4ac3-9994-7315da06ea3a',
    [Parameter(Mandatory)] [string] $Title,
    [Parameter(Mandatory)] [string] $Alias,
    [int]      $Lcid = 1044,
    [string[]] $Owners,
    [switch]   $IsPublic,
    [int]      $MaxMinutes = 30,
    [int]      $RetryDelaySeconds = 30,
    [int]      $FallbackAfterAttempts = 1,
    [int]      $GroupifyBufferSeconds = 120,
    [int]      $GroupifyWaitSeconds = 180,
    [int]      $CleanupTimeoutMinutes = 30,
    [int]      $TimeZone = 4,
    [switch]   $CreateTeam,
    [switch]   $TryDirect,
    [switch]   $SkipDirect,
    [string]   $HubUrl
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
$deadline  = $startTime.AddMinutes($MaxMinutes)

function Log([string] $Message, [string] $Level = 'INFO') {
    $color = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERR' { 'Red' } 'STEP' { 'Cyan' } default { 'Gray' } }
    Write-Host ("[{0:HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message) -ForegroundColor $color
}
function Test-Deadline { return (Get-Date) -lt $deadline }
function Get-SecondsLeft { return [int] ($deadline - (Get-Date)).TotalSeconds }

function Wait-Until {
    # -IgnoreDeadline brukes for opprydding og hub: de skal fullføres selv om tidsrammen er brukt opp
    param([scriptblock] $Condition, [int] $TimeoutSeconds, [int] $IntervalSeconds = 10, [string] $What, [switch] $IgnoreDeadline)
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $end -and ($IgnoreDeadline -or (Test-Deadline))) {
        try { if (& $Condition) { return $true } } catch { }
        Start-Sleep -Seconds $IntervalSeconds
    }
    Log "Timeout: $What" 'WARN'
    return $false
}

function Test-SameUrl([string] $A, [string] $B) {
    # Normaliser: fjern avsluttende / og slå sammen doble / i stien
    $norm = { param($u) ($u.TrimEnd('/') -replace '(?<!:)/{2,}', '/') }
    return $A -and $B -and ((& $norm $A) -eq (& $norm $B))
}

# ---------------------------------------------------------------------------
# Tilkobling
# ---------------------------------------------------------------------------
$AdminUrl = $AdminUrl.TrimEnd('/')
Log "Kobler til $AdminUrl"
$admin = Connect-PnPOnline -Url $AdminUrl -ClientId $ClientId -Interactive -ReturnConnection
$tenantRoot  = $AdminUrl -replace '-admin\.sharepoint\.com', '.sharepoint.com'
$expectedUrl = "$tenantRoot/sites/$Alias"

$me = Get-PnPProperty -ClientObject (Get-PnPWeb -Connection $admin) -Property CurrentUser -Connection $admin
$myUpn = ($me.LoginName -split '\|')[-1]
if (-not $Owners) { $Owners = @($myUpn) }

# ---------------------------------------------------------------------------
# Hjelpefunksjoner
# ---------------------------------------------------------------------------
$siteConnections = @{}
function Connect-Site([string] $Url) {
    # -Connection $admin gjenbruker innloggingen fra admin-tilkoblingen, så brukeren ikke får nytt
    # innloggingsvindu for hvert område. Tilkoblingen mellomlagres per URL, siden ventesløyfene kaller dette ofte.
    $key = $Url.TrimEnd('/').ToLowerInvariant()
    if (-not $siteConnections.ContainsKey($key)) {
        $siteConnections[$key] = Connect-PnPOnline -Url $Url -Interactive -Connection $admin -ReturnConnection
    }
    return $siteConnections[$key]
}

function Get-LiveSite([string] $Url) {
    try { return Get-PnPTenantSite -Identity $Url -Connection $admin -ErrorAction SilentlyContinue } catch { return $null }
}

function Get-DeletedSite([string] $Url) {
    try { return Get-PnPTenantDeletedSite -Identity $Url -Connection $admin -ErrorAction SilentlyContinue } catch { return $null }
}

function Get-LiveGroup([string] $Identity) {
    try { return Get-PnPMicrosoft365Group -Identity $Identity -Connection $admin -ErrorAction SilentlyContinue } catch { return $null }
}

function Get-AliasGroup {
    # -Identity matcher også på visningsnavn. Filtrer på eksakt mailNickname så vi aldri treffer en annen gruppe.
    try {
        return Get-PnPMicrosoft365Group -Identity $Alias -Connection $admin -ErrorAction SilentlyContinue |
            Where-Object { $_.MailNickname -eq $Alias } | Select-Object -First 1
    } catch { return $null }
}

function Get-DeletedGroup([string] $GroupId) {
    try { return Get-PnPDeletedMicrosoft365Group -Identity $GroupId -Connection $admin -ErrorAction SilentlyContinue } catch { return $null }
}

function Get-SiteLanguage([string] $Url) {
    $c = Connect-Site $Url
    return [int] (Get-PnPWeb -Includes Language -Connection $c).Language
}

function Get-SiteGroupId([string] $Url) {
    $c = Connect-Site $Url
    $id = (Get-PnPSite -Includes GroupId -Connection $c).GroupId.Guid
    if ($id -eq [guid]::Empty.Guid) { return $null }
    return $id
}

function Wait-SiteActive([string] $Url, [int] $TimeoutSeconds = 240) {
    return Wait-Until -What "område aktivt ($Url)" -TimeoutSeconds $TimeoutSeconds -IntervalSeconds 15 -Condition {
        $s = Get-LiveSite $Url
        $s -and $s.Status -eq 'Active'
    }
}

function Remove-GroupPermanently([string] $GroupId, [int] $TimeoutSeconds = 300) {
    if (-not $GroupId -or $GroupId -eq [guid]::Empty.Guid) { return }
    Log "Sletter gruppe $GroupId permanent" 'WARN'
    # Løkke: slett aktiv gruppe, tøm fra Entra-papirkurv når den dukker opp, ferdig når den er borte begge steder
    $gone = Wait-Until -What "gruppe $GroupId permanent slettet" -TimeoutSeconds $TimeoutSeconds -IntervalSeconds 15 -IgnoreDeadline -Condition {
        if (Get-LiveGroup $GroupId) {
            try { Remove-PnPMicrosoft365Group -Identity $GroupId -Connection $admin | Out-Null } catch { Log "Remove-PnPMicrosoft365Group: $($_.Exception.Message)" 'WARN' }
            return $false
        }
        if (Get-DeletedGroup $GroupId) {
            try { Remove-PnPDeletedMicrosoft365Group -Identity $GroupId -Connection $admin | Out-Null } catch { Log "Remove-PnPDeletedMicrosoft365Group: $($_.Exception.Message)" 'WARN' }
            return $false
        }
        # Borte begge steder. Dobbeltsjekk etter en kort pause, siden sletting kan ha forsinket visning i papirkurven
        Start-Sleep -Seconds 15
        return (-not (Get-LiveGroup $GroupId)) -and (-not (Get-DeletedGroup $GroupId))
    }
    if (-not $gone) { Log "Gruppe $GroupId er ikke bekreftet permanent slettet. Sjekk Entra manuelt." 'ERR' }
    return $gone
}

function Remove-SitePermanently([string] $Url, [int] $TimeoutSeconds = $CleanupTimeoutMinutes * 60) {
    Log "Sletter område $Url permanent" 'WARN'
    # Løkke: ferdig når URL-en er fri. Tilstandsendringer logges.
    # Gruppeområder kan ikke slettes via admin-API ("Dette området tilhører en Microsoft 365-gruppe").
    # De slettes via gruppen (Remove-GroupPermanently, kjøres først), og SharePoint flytter deretter
    # området til papirkurven asynkront – observert ca. 10 min. Da venter vi bare.
    $script:siteState = $null
    $gone = Wait-Until -What "URL frigjort ($Url)" -TimeoutSeconds $TimeoutSeconds -IntervalSeconds 15 -IgnoreDeadline -Condition {
        $live = Get-LiveSite $Url
        if ($live) {
            $groupId = if ($live.GroupId -and $live.GroupId.Guid -ne [guid]::Empty.Guid) { $live.GroupId.Guid } else { $null }
            $state = "aktivt (Status=$($live.Status), GroupId=$($live.GroupId))"
            if ($state -ne $script:siteState) {
                Log "  $Url er $state"
                $script:siteState = $state
                if (-not $groupId) {
                    try { Remove-PnPTenantSite -Url $Url -Force -SkipRecycleBin -Connection $admin | Out-Null } catch { Log "Remove-PnPTenantSite: $($_.Exception.Message)" 'WARN' }
                }
                elseif (Get-LiveGroup $groupId) {
                    Log "  Gruppen $groupId finnes fortsatt, sletter den" 'WARN'
                    try { Remove-PnPMicrosoft365Group -Identity $groupId -Connection $admin | Out-Null } catch { Log "Remove-PnPMicrosoft365Group: $($_.Exception.Message)" 'WARN' }
                }
                else {
                    Log "  Gruppen er slettet. Venter på at SharePoint flytter området til papirkurven (kan ta ~10 min)."
                }
            }
            return $false
        }
        if (Get-DeletedSite $Url) {
            if ($script:siteState -ne 'papirkurv') { Log "  $Url ligger i papirkurven, sletter permanent"; $script:siteState = 'papirkurv' }
            try { Remove-PnPTenantDeletedSite -Identity $Url -Force -Connection $admin | Out-Null } catch { Log "Remove-PnPTenantDeletedSite: $($_.Exception.Message)" 'WARN' }
            return $false
        }
        Start-Sleep -Seconds 15
        return (-not (Get-LiveSite $Url)) -and (-not (Get-DeletedSite $Url))
    }
    if ($gone) { Log "URL frigjort: $Url" 'OK' }
    else       { Log "$Url er ikke bekreftet permanent slettet (siste tilstand: $script:siteState). Sjekk SharePoint Admin Center manuelt." 'ERR' }
    return $gone
}

function Test-UrlFree([string] $Url) {
    return (-not (Get-LiveSite $Url)) -and (-not (Get-DeletedSite $Url))
}

function Get-GroupSiteUrl([string] $GroupId) {
    try { return (Get-PnPMicrosoft365Group -Identity $GroupId -IncludeSiteUrl -Connection $admin).SiteUrl } catch { return $null }
}

function Join-HubSite([string] $Url, [int] $MaxAttempts = 5) {
    # Kjøres også etter deadline: området finnes allerede, og det er bedre å fullføre enn å etterlate det uten hub
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Log "Knytter $Url til hub $HubUrl (forsøk $i)"
        try { Add-PnPHubSiteAssociation -Site $Url -HubSite $HubUrl -Connection $admin }
        catch { Log "Add-PnPHubSiteAssociation: $($_.Exception.Message)" 'WARN' }

        $ok = Wait-Until -What 'hubtilknytning synlig' -TimeoutSeconds 60 -IntervalSeconds 10 -IgnoreDeadline -Condition {
            (Get-LiveSite $Url).HubSiteId.Guid -eq $hub.ID.Guid
        }
        if ($ok) { Log "Knyttet til hub $($hub.Title)" 'OK'; return $true }
        Start-Sleep -Seconds 15
    }
    return $false
}

# ---------------------------------------------------------------------------
# Forhåndssjekk – ingenting opprettes eller slettes hvis noe allerede er i bruk
# ---------------------------------------------------------------------------
$preflight = @()
if (Get-LiveSite $expectedUrl)    { $preflight += "Området $expectedUrl finnes allerede." }
if (Get-DeletedSite $expectedUrl) { $preflight += "Området $expectedUrl ligger i SharePoint-papirkurven. Gjenopprett eller slett permanent (Remove-PnPTenantDeletedSite) først." }
$existingGroup = Get-AliasGroup
if ($existingGroup) { $preflight += "En M365-gruppe med alias '$Alias' finnes allerede ($($existingGroup.Id))." }
try {
    $deletedGroup = Get-PnPDeletedMicrosoft365Group -Connection $admin | Where-Object { $_.MailNickname -eq $Alias } | Select-Object -First 1
    if ($deletedGroup) { $preflight += "En slettet gruppe med alias '$Alias' ligger i Entra-papirkurven ($($deletedGroup.Id)). Slett permanent (Remove-PnPDeletedMicrosoft365Group) først." }
} catch { Log "Kunne ikke lese slettede grupper: $($_.Exception.Message)" 'WARN' }

$hub = $null
if ($HubUrl) {
    $HubUrl = $HubUrl.TrimEnd('/')
    try { $hub = Get-PnPHubSite -Identity $HubUrl -Connection $admin } catch { }
    if ($hub) { Log "Hub: $($hub.Title) ($HubUrl)" }
    else      { $preflight += "Fant ikke hubområde $HubUrl (er det registrert som hub?)." }
}

if ($preflight) {
    $preflight | ForEach-Object { Log $_ 'ERR' }
    Log 'Avbryter før opprettelse.' 'ERR'
    exit 1
}

# ---------------------------------------------------------------------------
# Fase 1 – direkte opprettelse med retry
# ---------------------------------------------------------------------------
$result  = $null
$attempt = 0
$directFailures = 0
$duplicatesCleaned = 0
$pendingCleanup = [System.Collections.Generic.List[string]]::new()

if ($SkipDirect) { Log '-SkipDirect er utgått og har ingen effekt: fase 2 er nå standard. Bruk -TryDirect for fase 1.' 'WARN' }
if ($SkipDirect -and $TryDirect) { Log '-SkipDirect og -TryDirect er begge oppgitt. -TryDirect gjelder.' 'WARN' }

if ($TryDirect) {
    Log "FASE 1: direkte opprettelse (fallback etter $FallbackAfterAttempts mislykkede forsøk)" 'STEP'

    while (-not $result -and (Test-Deadline)) {
        if ($FallbackAfterAttempts -gt 0 -and $directFailures -ge $FallbackAfterAttempts) {
            Log "$directFailures mislykkede forsøk, går til fallback" 'WARN'
            break
        }
        $attempt++
        Log "Forsøk $attempt (ca. $(Get-SecondsLeft) s igjen): New-PnPSite /sites/$Alias, LCID $Lcid"

        $siteUrl = $null; $groupId = $null
        try {
            $siteUrl = New-PnPSite -Type TeamSite -Title $Title -Alias $Alias -Lcid $Lcid `
                          -Owners $Owners -IsPublic:$IsPublic -Wait -Connection $admin
            if (-not $siteUrl) { $siteUrl = $expectedUrl }
            Log "Opprettet: $siteUrl"
        }
        catch {
            Log "New-PnPSite feilet: $($_.Exception.Message)" 'ERR'
            # Kallet kan ha feilet etter at gruppen ble opprettet. Rydd opp det som ble laget.
            $orphan = Get-AliasGroup
            if ($orphan) {
                $orphanUrl = Get-GroupSiteUrl $orphan.Id
                Remove-GroupPermanently $orphan.Id | Out-Null
                if ($orphanUrl) { Remove-SitePermanently $orphanUrl | Out-Null }
            }
            $directFailures++
            if (Test-Deadline) { Start-Sleep -Seconds $RetryDelaySeconds }
            continue
        }

        $ready = Wait-SiteActive $siteUrl
        $groupId = (Get-LiveSite $siteUrl).GroupId.Guid
        if (-not $groupId -or $groupId -eq [guid]::Empty.Guid) { $groupId = (Get-AliasGroup).Id }

        $lang = -1
        if ($ready) {
            try { $lang = Get-SiteLanguage $siteUrl } catch { Log "Kunne ikke lese språk: $($_.Exception.Message)" 'WARN' }
            Log "Språk: $lang (forventet $Lcid)"
        }

        $urlOk = Test-SameUrl $siteUrl $expectedUrl
        if (-not $urlOk) { Log "Området fikk URL $siteUrl, forventet $expectedUrl" 'WARN' }

        if ($lang -eq $Lcid -and $urlOk) {
            $result = [pscustomobject]@{ SiteUrl = $siteUrl; GroupId = $groupId; Language = $lang; Method = 'Direct'; Attempts = $attempt }
            break
        }

        $directFailures++
        # Gruppe først: gruppeområder kan bare slettes via gruppen. Deretter ventes det på at området frigjøres.
        Remove-GroupPermanently $groupId | Out-Null
        Remove-SitePermanently  $siteUrl | Out-Null
        if ((Test-Deadline) -and -not ($FallbackAfterAttempts -gt 0 -and $directFailures -ge $FallbackAfterAttempts)) {
            Log "Venter $RetryDelaySeconds s"
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

# ---------------------------------------------------------------------------
# Fase 2 – STS#3 + groupify
# ---------------------------------------------------------------------------
$runPhase2 = -not $result -and (Test-Deadline) -and (-not $TryDirect -or $FallbackAfterAttempts -gt 0)
if ($runPhase2 -and -not (Test-UrlFree $expectedUrl)) {
    # Fase 1-oppryddingen ble ikke ferdig. STS#3 på en opptatt URL feiler bare med en uklar SiteStatus.
    Log "Kan ikke starte fase 2: $expectedUrl er fortsatt i bruk (aktivt eller i papirkurv). Vent til den er frigjort, eller kjør på nytt med nytt alias." 'ERR'
    $runPhase2 = $false
}
if ($runPhase2) {
    Log "FASE 2: STS#3 med LCID $Lcid, deretter groupify" 'STEP'

    $siteUrl = $null
    try {
        $siteUrl = New-PnPSite -Type TeamSiteWithoutMicrosoft365Group -Title $Title -Url $expectedUrl `
                      -Lcid $Lcid -TimeZone $TimeZone -Owner $Owners[0] -Wait -Connection $admin
        if (-not $siteUrl) { $siteUrl = $expectedUrl }
        Log "STS#3 opprettet: $siteUrl"
    }
    catch {
        Log "Opprettelse av STS#3 feilet: $($_.Exception.Message)" 'ERR'
    }

    if ($siteUrl -and (Wait-SiteActive $siteUrl)) {
        $lang = -1
        try { $lang = Get-SiteLanguage $siteUrl } catch { Log "Kunne ikke lese språk: $($_.Exception.Message)" 'WARN' }
        Log "Språk på STS#3: $lang"
        if ($lang -ne $Lcid) {
            Log "STS#3 fikk også feil språk. Det er uventet – avbryter. Området $siteUrl er beholdt for feilsøking." 'ERR'
        }
        else {
            # Gjør innlogget bruker til site collection admin via admin-API. Via site-tilkoblingen
            # krever det at brukeren allerede har tilgang, noe den ikke har når $Owners[0] er en annen.
            try {
                Set-PnPTenantSite -Identity $siteUrl -Owners @($myUpn) -Connection $admin
                Log "$myUpn er site collection admin"
            } catch { Log "Kunne ikke sette site admin: $($_.Exception.Message)" 'WARN' }

            Log "Venter $GroupifyBufferSeconds s buffer før groupify"
            Start-Sleep -Seconds ([Math]::Min($GroupifyBufferSeconds, [Math]::Max(0, (Get-SecondsLeft) - 60)))

            $gAttempt = 0
            $pending = $false
            while (-not $result -and (Test-Deadline)) {
                if (-not $pending) {
                    $gAttempt++
                    Log "Groupify forsøk $gAttempt (ca. $(Get-SecondsLeft) s igjen)"
                    try {
                        $c = Connect-Site $siteUrl
                        Add-PnPMicrosoft365GroupToSite -Url $siteUrl -Alias $Alias -DisplayName $Title `
                            -IsPublic:$IsPublic -Owners $Owners -KeepOldHomePage -Connection $c
                    }
                    catch {
                        Log "Add-PnPMicrosoft365GroupToSite: $($_.Exception.Message)" 'WARN'
                    }
                }
                $pending = $false

                # Vent til det opprinnelige området viser gruppen
                $siteGroupId = $null
                Wait-Until -What 'Site.GroupId satt' -TimeoutSeconds $GroupifyWaitSeconds -IntervalSeconds 15 -Condition {
                    $script:siteGroupId = Get-SiteGroupId $siteUrl
                    [bool] $script:siteGroupId
                } | Out-Null
                $siteGroupId = $script:siteGroupId

                if ($siteGroupId) {
                    Log "Groupify OK: $siteUrl -> gruppe $siteGroupId" 'OK'
                    $result = [pscustomobject]@{ SiteUrl = $siteUrl; GroupId = $siteGroupId; Language = $lang; Method = 'STS3+Groupify'; Attempts = $attempt + $gAttempt }
                    break
                }

                # Ingen GroupId ennå. Finn ut om det ble opprettet en gruppe, og hvor den peker.
                $newGroup = Get-AliasGroup
                if ($newGroup) {
                    $groupSiteUrl = Get-GroupSiteUrl $newGroup.Id
                    if ($groupSiteUrl -and -not (Test-SameUrl $groupSiteUrl $siteUrl)) {
                        # Kjent feil: gruppen fikk et nytt duplikatområde. Trygt å slette, det er ikke vårt område.
                        Log "Groupify traff ikke opprinnelig område. Gruppe $($newGroup.Id) ligger på '$groupSiteUrl'. Rydder opp." 'WARN'
                        # Kun aliaset må være fritt før neste forsøk. Duplikatområdet har egen URL og
                        # kan bruke lang tid på å forsvinne, så det sjekkes kort og ellers ryddes til slutt.
                        Remove-GroupPermanently $newGroup.Id | Out-Null
                        if (-not (Remove-SitePermanently $groupSiteUrl -TimeoutSeconds 60)) {
                            Log "Duplikatområdet $groupSiteUrl er ikke borte ennå. Fortsetter groupify; det ryddes til slutt." 'WARN'
                            $pendingCleanup.Add($groupSiteUrl)
                        }
                        $duplicatesCleaned++
                    }
                    else {
                        # Gruppen peker på vårt område (eller har ingen URL ennå). Å slette gruppen nå ville
                        # også slette STS#3-området. Vent videre uten nytt groupify-kall.
                        Log "Gruppe $($newGroup.Id) finnes, men koblingen er ikke ferdig ('$groupSiteUrl'). Venter videre." 'WARN'
                        $pending = $true
                        continue
                    }
                }

                if (Test-Deadline) {
                    Log "Venter $RetryDelaySeconds s før nytt groupify-forsøk"
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
            }

            if (-not $result) {
                Log "Groupify ble ikke fullført innen tidsrammen. STS#3-området $siteUrl er beholdt; sjekk om gruppen $Alias kobles til etter hvert." 'ERR'
            }

            if ($result -and $CreateTeam) {
                Log "Oppretter Teams-team"
                try { New-PnPTeamsTeam -GroupId $result.GroupId -Connection $admin | Out-Null; Log "Team opprettet" 'OK' }
                catch { Log "New-PnPTeamsTeam: $($_.Exception.Message)" 'WARN' }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Resultat
# ---------------------------------------------------------------------------
# Siste forsøk på duplikater som ikke var borte da groupify gikk videre. Gruppen er allerede
# permanent slettet, så det gjenstår bare å tømme området fra papirkurven når det dukker opp.
$leftovers = @()
foreach ($u in $pendingCleanup) {
    if (-not (Remove-SitePermanently $u -TimeoutSeconds 120)) { $leftovers += $u }
}
foreach ($u in $leftovers) {
    Log "Ikke ryddet ferdig: $u. Når det ligger i papirkurven: Remove-PnPTenantDeletedSite -Identity $u -Force" 'WARN'
}

$elapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

if ($result) {
    Log "Suksess ($($result.Method), $($result.Attempts) forsøk, $elapsed min): $($result.SiteUrl) språk $($result.Language)" 'OK'

    $exitCode = 0
    $hubOk = $null
    if ($HubUrl) {
        $hubOk = Join-HubSite $result.SiteUrl
        if (-not $hubOk) {
            Log "Området er opprettet, men kunne ikke knyttes til hub $HubUrl. Knytt manuelt: Add-PnPHubSiteAssociation -Site $($result.SiteUrl) -HubSite $HubUrl" 'ERR'
            $exitCode = 2
        }
    }
    $result | Add-Member -NotePropertyName HubUrl -NotePropertyValue $(if ($HubUrl) { $HubUrl } else { $null })
    $result | Add-Member -NotePropertyName HubAssociated -NotePropertyValue $hubOk
    $result | Add-Member -NotePropertyName DirectFailures -NotePropertyValue $directFailures
    $result | Add-Member -NotePropertyName DuplicatesCleaned -NotePropertyValue $duplicatesCleaned
    $result | Add-Member -NotePropertyName PendingCleanup -NotePropertyValue $leftovers
    $result | Add-Member -NotePropertyName DurationMinutes -NotePropertyValue ([Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1))

    Log "Neste steg: kjør Prosjektportalen-provisjoneringen mot dette området."
    $result
    exit $exitCode
}
else {
    Log "Ga opp etter $elapsed min uten område med språk $Lcid (direkte feil: $directFailures, duplikater ryddet: $duplicatesCleaned)." 'ERR'
    exit 1
}
