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
    Eierne legges også inn som medlemmer, som i Bestillingsportalen.
    Med -CreateTeam opprettes Teams-team, og med -HubUrl knyttes området til en hub.

    Har huben en tilknyttet områdeutforming, venter skriptet inntil -SiteDesignQueueMinutes på at
    SharePoints kø kjører den. Står den fortsatt i kø, fjernes køoppgaven for området og
    utformingen kjøres direkte (køen kan henge i timevis, direkte kjøring tar sekunder). Er det
    Prosjektportalens «Prosjektområde», sjekkes det at oppsettveiviseren er lagt på området, og
    den legges på hvis den mangler. Til slutt får brukeren en oppsummering med neste steg.

    Kjøres lokalt (interaktiv innlogging) eller som runbook i Azure Automation (managed identity,
    oppdages automatisk). Skriptet sletter aldri noe det ikke selv har opprettet.

    Exit-koder lokalt: 0 suksess, 1 ingen treff/feil, 2 område OK men medlemmer, team, hub,
    områdeutforming eller oppsettveiviser feilet. Lokalt skrives en oppsummering, i runbook et
    resultatobjekt.

.PARAMETER AdminUrl          https://<tenant>-admin.sharepoint.com. Kan utelates når -HubUrl er oppgitt
.PARAMETER Title             Visningsnavn på gruppen
.PARAMETER Alias             Ønsket alias (mailNickname og /sites/<Alias>). Standard: laget fra tittelen,
                             små bokstaver, æøå til ae/o/a, bindestrek for mellomrom og maks 32 tegn
.PARAMETER Lcid              Ønsket språk. 1044 = norsk bokmål
.PARAMETER Owners            Eiere (UPN). Påkrevd med managed identity, ellers innlogget bruker
.PARAMETER Members           Medlemmer (UPN), legges til etter at treffet er valgt
.PARAMETER Description       Beskrivelse på gruppen. Standard: tittelen
.PARAMETER IsPublic          Offentlig gruppe. Standard: privat
.PARAMETER ManagedPath       Administrert bane for gruppeområder. Standard: sites
.PARAMETER BatchSize         Antall kandidater per runde. Standard 5
.PARAMETER MaxRounds         Maks antall runder. Standard 5
.PARAMETER RequireExactAlias Bruk bare aliaset uten suffiks, og vent på at URL-en frigjøres mellom forsøk
.PARAMETER CreateTeam        Opprett Teams-team på gruppen
.PARAMETER HubUrl            Knytt området til denne huben. Sjekkes før noe opprettes
.PARAMETER SiteDesignQueueMinutes Hvor lenge skriptet venter på at SharePoints kø kjører hubens områdeutforming,
                             før den kjøres direkte. Standard 2
.PARAMETER ManagedIdentity   Tving managed identity (oppdages ellers automatisk i Azure Automation)
.PARAMETER ClientId          App-registrering for interaktiv innlogging. Standard: Prosjektportalens PnP-app

.EXAMPLE
    .\New-PPSiteWithLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com `
        -Title "Prosjekt X" -Alias "prosjekt-x" -Owners "ola@contoso.com"

.EXAMPLE
    # Aliaset lages fra tittelen: prosjekt-ost-fase-2
    .\New-PPSiteWithLanguageRetry.ps1 -AdminUrl https://contoso-admin.sharepoint.com -Title "Prosjekt Øst – fase 2"

.EXAMPLE
    # -AdminUrl utledes fra -HubUrl
    .\New-PPSiteWithLanguageRetry.ps1 `
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
    [string]   $AdminUrl,
    [Parameter(Mandatory)] [string] $Title,
    [string]   $Alias,
    [int]      $Lcid = 1044,
    [string[]] $Owners,
    [string[]] $Members,
    [string]   $Description = '',
    [switch]   $IsPublic,
    [string]   $ManagedPath = 'sites',
    [int]      $BatchSize = 5,
    [int]      $MaxRounds = 5,
    [switch]   $RequireExactAlias,
    [switch]   $CreateTeam,
    [string]   $HubUrl,
    [switch]   $ManagedIdentity,
    [string]   $ClientId = 'da6c31a6-b557-4ac3-9994-7315da06ea3a',
    [int]      $SiteReadyTimeoutMinutes = 10,
    [int]      $UrlReleaseTimeoutMinutes = 40,
    [int]      $SiteDesignQueueMinutes = 2
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
if (-not $AdminUrl) {
    # https://contoso.sharepoint.com/sites/hub gir https://contoso-admin.sharepoint.com
    if (-not $HubUrl) { throw 'Oppgi -AdminUrl, eller -HubUrl så adminadressen kan utledes fra den.' }
    $hubHost = ([Uri] $HubUrl).Host
    if ($hubHost -notmatch '^([^.]+)\.sharepoint\.com$') { throw "Kan ikke utlede adminadressen fra $HubUrl. Oppgi -AdminUrl." }
    $AdminUrl = "https://$($Matches[1])-admin.sharepoint.com"
}
$AdminUrl = $AdminUrl.TrimEnd('/')
$tenantRoot = $AdminUrl -replace '-admin\.sharepoint\.com', '.sharepoint.com'
if ($RequireExactAlias) { $BatchSize = 1 }
if ($BatchSize -lt 1 -or $BatchSize -gt 10) { throw '-BatchSize må være mellom 1 og 10.' }
# Graph avviser tom description («Invalid value specified for property 'description'»), så tittelen brukes
if ([string]::IsNullOrWhiteSpace($Description)) { $Description = $Title }
if (-not $Alias) {
    # «Prosjekt Øst – fase 2» blir prosjekt-ost-fase-2
    $a = $Title.ToLowerInvariant().Replace('æ', 'ae').Replace('ø', 'o').Replace('å', 'a').Normalize([Text.NormalizationForm]::FormD)
    $a = ($a -replace '\p{Mn}', '' -replace '[^a-z0-9]+', '-').Trim('-')
    if ($a.Length -gt 32) { $a = $a.Substring(0, 32).TrimEnd('-') }
    if (-not $a) { throw "Kunne ikke lage alias fra tittelen '$Title'. Oppgi -Alias." }
    $Alias = $a
}
if ($Alias.Length -gt 58) { throw '-Alias kan være maks 58 tegn (plass til suffikset -xxxxx innenfor grensen på 64).' }
$useMi = $ManagedIdentity -or [bool] ($env:AUTOMATION_ASSET_ACCOUNTID -or $PSPrivateMetadata.JobId)
if ($HubUrl) { $HubUrl = $HubUrl.TrimEnd('/') }

# Prosjektportalens områdeutforming og oppsettveiviseren (Application Customizer) den skal legge på
$projectSiteDesignTitle = 'Prosjektområde'
$setupWizard = @{
    Title                         = 'Oppsettveiviser'
    Name                          = 'Oppsettveiviser'
    Location                      = 'ClientSideExtension.ApplicationCustomizer'
    ClientSideComponentId         = 'ce34553d-ab47-4107-8dd1-e980d953996d'
    ClientSideComponentProperties = '{"termSetIds":{"GtProjectPhase":"abcfc9d9-a263-4abb-8234-be973c46258a","GtResourceRole":"54da9f47-c64e-4a26-80f3-4d3c3fa1b7b2"}}'
    Scope                         = 'Web'
}

function Log([string] $Message, [string] $Level = 'INFO') {
    # I runbook går loggen til jobbutdataene. Interaktivt får nivåene farge, så det er lett å se hva som gikk.
    if ($useMi) { Write-Output ("[{0:HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message); return }
    $color = @{ OK = 'Green'; WARN = 'Yellow'; ERR = 'Red' }[$Level]
    $text = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
    if ($color) { Write-Host $text -ForegroundColor $color } else { Write-Host $text }
}
function Get-LanguageName([int] $Id) {
    # 1044 blir «norsk bokmål (1044)»
    if (-not $Id) { return 'ukjent' }
    try { return "$(([Globalization.CultureInfo]::GetCultureInfo($Id)).NativeName -replace '\s*\(.*\)$', '') ($Id)" }
    catch { return "$Id" }
}
function Get-ErrorText($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    while ($ex.InnerException) { $ex = $ex.InnerException }
    return "$($ex.GetType().Name): $($ex.Message)"
}
function Show-Progress([string] $Status, [int] $Percent = -1) {
    # Fremdriftslinje mens skriptet venter. Bare interaktivt: i Azure Automation blir det støy i jobbloggen.
    # PowerShell 7 viser aktivitet og status på én linje og kutter resten, så begge holdes korte.
    if ($useMi) { return }
    if ($Status) { Write-Progress -Activity 'Status' -Status $Status -PercentComplete $Percent }
    else { Write-Progress -Activity 'Status' -Completed }
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
$script:siteConnections = @{}
function Connect-Site([string] $Url) {
    # Gjenbrukes, så språksjekken hvert 10. sekund ikke kobler til på nytt hver gang
    $key = $Url.TrimEnd('/').ToLowerInvariant()
    if (-not $script:siteConnections.ContainsKey($key)) {
        $script:siteConnections[$key] = if ($useMi) { Connect-PnPOnline -Url $Url -ManagedIdentity -ReturnConnection }
        else { Connect-PnPOnline -Url $Url -Interactive -Connection $script:admin -ReturnConnection }
    }
    return $script:siteConnections[$key]
}
function Get-WebLanguage([string] $Url) {
    # Områdets språk (Web.Language). LocaleId fra admin-API-et er de regionale innstillingene, og de
    # kan avvike fra språket (rotområde med engelsk språk og norske regionale innstillinger ga 1044).
    try { return [int] (Get-PnPWeb -Includes Language -Connection (Connect-Site $Url)).Language }
    catch { return $null }
}
function Test-ActionFailed($Result) {
    # SiteScriptActionOutcome: Success 0, Failure 1, NoOp 2, Exception 3
    return "$($Result.OutcomeCode)" -in 'Failure', 'Exception', '1', '3'
}
function Complete-SiteDesign([string] $Url, $Design) {
    # Hubtilknytningen legger områdeutformingen i SharePoints kø. Køen kan bli hengende i timevis
    # (observert hos kunde), mens den samme utformingen kjørt direkte er ferdig på sekunder. Derfor
    # ventes det kort på køen, og står den fortsatt der, fjernes køoppgaven for dette området og
    # utformingen kjøres direkte, med nye forsøk.
    # Returnerer feilede handlinger (tom liste ved suksess). Kaster når alle forsøk feilet.
    $end = (Get-Date).AddMinutes($SiteDesignQueueMinutes)
    while ((Get-Date) -lt $end) {
        Show-Progress "Områdeutforming: venter på køen ($([int] ($end - (Get-Date)).TotalSeconds) s)"
        Start-Sleep -Seconds 15
        try {
            Repair-AdminConnection
            $run = Get-PnPSiteDesignRun -WebUrl $Url -Connection $script:admin | Where-Object { "$($_.SiteDesignID)" -eq "$($Design.Id)" } | Select-Object -First 1
            $queued = Get-PnPSiteDesignTask -WebUrl $Url -Connection $script:admin | Where-Object { "$($_.SiteDesignID)" -eq "$($Design.Id)" }
        }
        catch { continue }
        if ($run -and -not $queued) {
            Log 'Områdeutformingen ble kjørt fra køen'
            return , @(Get-PnPSiteDesignRunStatus -Run $run -Connection $script:admin | Where-Object { Test-ActionFailed $_ })
        }
    }

    Log "Områdeutformingen ble ikke kjørt fra køen innen $SiteDesignQueueMinutes min. Kjører den direkte."
    $c = Connect-Site $Url
    $siteId = "$((Get-PnPSite -Includes Id -Connection $c).Id)"
    $lastError = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Show-Progress "Områdeutforming: forsøk $attempt av 3"
        try {
            # Fjern køoppgaven først, ellers kan den kjøre i tillegg senere. Bare oppgaver for dette området.
            Repair-AdminConnection
            Get-PnPSiteDesignTask -WebUrl $Url -Connection $script:admin |
                Where-Object { "$($_.SiteID)" -eq $siteId -and "$($_.SiteDesignID)" -eq "$($Design.Id)" } |
                ForEach-Object { Remove-PnPSiteDesignTask -Identity $_.ID -Force -Connection $script:admin }
            $results = Invoke-PnPSiteDesign -Identity $Design.Id -WebUrl $Url -Connection $c
            return , @($results | Where-Object { Test-ActionFailed $_ })
        }
        catch {
            $lastError = Get-ErrorText $_
            if ($attempt -lt 3) { Log "Direkte kjøring feilet (forsøk $attempt av 3): $lastError. Prøver igjen om $(15 * $attempt) s."; Start-Sleep -Seconds (15 * $attempt) }
        }
    }
    throw "Direkte kjøring feilet 3 ganger. Siste feil: $lastError"
}
function Add-SetupWizardIfMissing([string] $Url) {
    # Returnerer 'Exists' eller 'Added'. Kaster ved feil.
    $c = Connect-Site $Url
    $existing = Get-PnPCustomAction -Scope All -Connection $c | Where-Object { "$($_.ClientSideComponentId)" -eq $setupWizard.ClientSideComponentId }
    if ($existing) { return 'Exists' }
    Add-PnPCustomAction @setupWizard -Connection $c | Out-Null
    return 'Added'
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
            Show-Progress "Venter på SharePoint ($($pending.Count) slettet)"
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
        Show-Progress "Papirkurv: $($remaining.Count) igjen"
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
if ($useMi -and -not $Owners) { throw '-Owners er påkrevd med managed identity.' }
Log "Kobler til $AdminUrl$(if (-not $useMi) { '. Logg inn i nettleservinduet hvis det åpnes.' })"
$script:admin = New-AdminConnection
if (-not $Owners) {
    $me = Get-PnPProperty -ClientObject (Get-PnPWeb -Connection $script:admin) -Property CurrentUser -Connection $script:admin
    $Owners = @(($me.LoginName -split '\|')[-1])
}
Log "Sjekker eiere, medlemmer og adresse"
$ownerIds = Resolve-UserIds $Owners
# Eierne legges også inn som medlemmer, som i Bestillingsportalen: en eier som ikke er medlem,
# mangler i medlemslisten i Teams og i SharePoint-gruppen for medlemmer
$memberIds = @(@($ownerIds) + @(Resolve-UserIds $Members) | Select-Object -Unique)

# Sjekk huben før noe opprettes, så en feil adresse ikke oppdages først til slutt
$hubDesign = $null
$isProjectHub = $false
if ($HubUrl) {
    $hub = $null
    try { $hub = Get-PnPHubSite -Identity $HubUrl -Connection $script:admin } catch { }
    if (-not $hub) { throw "$HubUrl er ikke en hub (eller finnes ikke). Sjekk adressen." }
    if ($hub.SiteDesignId -and "$($hub.SiteDesignId)" -ne "$([guid]::Empty)") {
        try { $hubDesign = Get-PnPSiteDesign -Identity $hub.SiteDesignId -Connection $script:admin } catch { }
    }
    $isProjectHub = [bool] ($hubDesign -and $hubDesign.Title -eq $projectSiteDesignTitle)
    Log $(if ($isProjectHub) { "Huben $HubUrl er en Prosjektportalen-hub. Området får områdeutformingen «Prosjektområde» og oppsettveiviseren." }
        elseif ($hubDesign) { "Huben $HubUrl legger områdeutformingen «$($hubDesign.Title)» på området." }
        else { "Huben $HubUrl har ingen områdeutforming." })
}

$rootLcid = Get-WebLanguage $tenantRoot
if ($rootLcid -eq $Lcid -and $BatchSize -gt 1) {
    # Feilen gir området rotområdets språk. Er det likt det bestilte, treffer første forsøk.
    $BatchSize = 1
}

if (Test-AliasInUse $Alias) { throw "Adressen $(Get-SiteUrl $Alias) (alias '$Alias') er i bruk eller ligger i papirkurven. Velg et annet -Alias eller en annen tittel." }
Log "Oppretter «$Title» på $(Get-SiteUrl $Alias) med språk $(Get-LanguageName $Lcid)"
Log "Eiere: $($Owners -join ', ')$(if ($Members) { ". Medlemmer: $($Members -join ', ')" })"
Log ("Microsoft gir ofte nye områder feil språk. Skriptet oppretter derfor {0} om gangen, beholder ett med riktig språk og sletter resten (opptil {1} runder)." -f
    $(if ($BatchSize -gt 1) { "$BatchSize områder" } else { 'ett område' }), $MaxRounds)

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
            Show-Progress "Venter på adressen ($([int] ($end - (Get-Date)).TotalMinutes) min igjen)"
            Start-Sleep -Seconds 30
        }
        if (Test-AliasInUse $Alias) { Log "URL-en ble ikke frigjort innen $UrlReleaseTimeoutMinutes min." 'ERR'; break }
    }

    $batch = @()
    for ($i = 1; $i -le $BatchSize; $i++) {
        $a = if (($round -eq 1 -and $i -eq 1) -or $RequireExactAlias) { $Alias } else { New-SuffixAlias }
        while ($a -ne $Alias -and (Test-AliasInUse $a)) { $a = New-SuffixAlias }
        $batch += [pscustomobject]@{ Alias = $a; SiteUrl = (Get-SiteUrl $a); GroupId = $null; Created = $null; Lcid = $null; Outcome = 'Pending'; Waiting = 'området finnes ikke ennå' }
    }

    Log "Runde $round av $($MaxRounds): oppretter $(if ($batch.Count -gt 1) { "$($batch.Count) områder" } else { 'området' }) og sjekker språket (tar vanligvis 1-2 min)"
    Show-Progress "Runde $round/$($MaxRounds): oppretter"
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
    $nextNotice = (Get-Date).AddSeconds(90)
    # Har ett område fått riktig språk, er det ingen grunn til å vente på resten
    while ((Get-Date) -lt $waitEnd -and ($batch | Where-Object Outcome -eq 'Pending') -and -not ($batch | Where-Object Outcome -eq 'Hit')) {
        $ready = @($batch | Where-Object { $_.Outcome -in 'Hit', 'Miss' }).Count
        Show-Progress "Runde $round/$($MaxRounds): $ready av $created klare ($([int] ((Get-Date) - $roundStart).TotalSeconds) s)" ([int] (100 * $ready / $created))
        if ((Get-Date) -ge $nextNotice) {
            # Si hva som holder igjen, så det ikke ser ut som skriptet har hengt seg opp
            $waiting = @($batch | Where-Object Outcome -eq 'Pending' | ForEach-Object { "$($_.Alias): $($_.Waiting)" })
            Log "Venter fortsatt på $($waiting.Count) av $($created) (maks $SiteReadyTimeoutMinutes min): $($waiting -join '; ')"
            $nextNotice = (Get-Date).AddMinutes(2)
        }
        Start-Sleep -Seconds 10
        foreach ($c in ($batch | Where-Object Outcome -eq 'Pending')) {
            $s = Get-LiveSite $c.SiteUrl
            if (-not $s) { $c.Waiting = 'området finnes ikke ennå'; continue }
            if ($s.Status -ne 'Active') { $c.Waiting = "området opprettes (status $($s.Status))"; continue }
            if ($s.GroupId.Guid -ne $c.GroupId) { $c.Waiting = 'området er ikke koblet til gruppen ennå'; continue }
            # Er weben ikke klar ennå, prøves kandidaten igjen ved neste runde i løkken
            try { $c.Lcid = [int] (Get-PnPWeb -Includes Language -Connection (Connect-Site $c.SiteUrl)).Language }
            catch { $c.Waiting = "språket kan ikke leses ennå ($(Get-ErrorText $_))"; continue }
            $c.Outcome = if ($c.Lcid -eq $Lcid) { 'Hit' } else { 'Miss' }
        }
    }
    foreach ($c in ($batch | Where-Object Outcome -eq 'Pending')) {
        # Etter et treff er ventende kandidater bare overflødige, ellers ble de ikke klare i tide
        $c.Outcome = if ($batch | Where-Object Outcome -eq 'Hit') { 'Skipped' } else { 'NoSite' }
    }

    $roundHits = @($batch | Where-Object Outcome -eq 'Hit')
    $hits += $roundHits.Count
    $winner = ($roundHits | Where-Object Alias -eq $Alias | Select-Object -First 1)
    if (-not $winner) { $winner = $roundHits | Select-Object -First 1 }

    $losers = @($batch | Where-Object { $_ -ne $winner -and $_.GroupId })
    $errs = @()
    if ($losers) {
        Show-Progress "Runde $round/$($MaxRounds): sletter $($losers.Count)"
        $errs = Remove-Candidates $losers
        $cleanupErrors += $errs
    }
    # Én linje per runde, for eksempel «Runde 1 av 3: ingen fikk riktig språk. 5 fikk English (1033). Slettet 5.»
    $rest = @($batch | Where-Object Outcome -ne 'Hit' | Group-Object Outcome, Lcid | ForEach-Object {
            # $_ er switch-verdien inne i switch, så antallet hentes før
            $o = $_.Group[0]; $n = $_.Count
            switch ($o.Outcome) {
                'Miss' { "$n fikk $(Get-LanguageName $o.Lcid)" }
                'NoSite' { "$n ble ikke klare i tide" }
                'CreateFailed' { "$n ble ikke opprettet" }
                'Skipped' { "$n var ikke klare ennå" }
            } })
    $line = "Runde $round av $($MaxRounds): " + $(if ($winner) { "riktig språk på $($winner.SiteUrl)." } else { 'ingen fikk riktig språk.' })
    if ($rest) { $line += ' ' + ($rest -join ', ') + '.' }
    if ($losers) { $line += " Slettet $($losers.Count)$(if ($errs) { ", $($errs.Count) kunne ikke slettes" })." }
    Log $line $(if ($errs) { 'WARN' } elseif ($winner) { 'OK' } else { 'INFO' })
}

$purgeCount = @($script:sitesToPurge | Select-Object -Unique).Count
if ($purgeCount) {
    Log "Tømmer de slettede områdene fra papirkurven, så adressene blir ledige igjen"
    $notPurged = Clear-CandidateRecycleBin
    Log "Tømte $(if ($notPurged) { "$($purgeCount - $notPurged.Count) av " })$purgeCount område(r) fra papirkurven" $(if ($notPurged) { 'WARN' } else { 'INFO' })
    $cleanupErrors += @($notPurged | ForEach-Object { "$($_): ikke tømt fra papirkurven" })
}
Show-Progress
foreach ($e in $cleanupErrors) { Log "Ikke ryddet: $e" 'WARN' }
$elapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

if (-not $winner) {
    Log "Ingen av de $attempts områdene fikk språk $(Get-LanguageName $Lcid) ($elapsed min). Rotområdet har $(Get-LanguageName $rootLcid)." 'ERR'
    if (-not $useMi) {
        Write-Host 'Ingenting er beholdt. Prøv igjen litt senere, eventuelt med flere runder (-MaxRounds 8).' -ForegroundColor Yellow
        exit 1
    }
    throw "Ingen kandidat fikk språk $Lcid etter $attempts forsøk."
}

Log "Området har riktig språk etter $attempts forsøk ($elapsed min). Gjør ferdig oppsettet." 'OK'

# ---------------------------------------------------------------------------
# Etterarbeid: medlemmer, team, hub, områdeutforming og oppsettveiviser
# ---------------------------------------------------------------------------
$exitCode = 0
# Det som ikke gikk, i klartekst til oppsummeringen
$problems = [System.Collections.Generic.List[string]]::new()
if ($memberIds) {
    Show-Progress 'Medlemmer'
    # Én og én, så en bruker som allerede er medlem ikke stopper resten
    $memberFailures = 0
    foreach ($id in $memberIds) {
        try { Invoke-Graph Post ('v1.0/groups/' + $winner.GroupId + '/members/$ref') @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$id" } | Out-Null }
        catch {
            if ((Get-ErrorText $_) -match 'already exist') { continue }
            Log "Kunne ikke legge til medlem $id : $(Get-ErrorText $_)" 'WARN'; $memberFailures++
        }
    }
    if ($memberFailures) {
        $exitCode = 2
        $problems.Add("$memberFailures medlem(mer) ble ikke lagt til. Legg dem til selv under Medlemmer på området eller i Teams.")
    }
    else { Log "Eiere og medlemmer er lagt inn som medlemmer av gruppen ($($memberIds.Count))" 'OK' }
}

$teamOk = $null
if ($CreateTeam) {
    $teamOk = $false
    Log 'Oppretter Teams-team'
    Show-Progress 'Teams-team'
    for ($i = 1; $i -le 4 -and -not $teamOk; $i++) {
        try { Invoke-Graph Put ('v1.0/groups/' + $winner.GroupId + '/team') @{} | Out-Null; $teamOk = $true }
        catch {
            # Gruppen er ofte ikke klar for Teams de første minuttene, så de første feilene er forventet
            if ($i -lt 4) { Log "Teams er ikke klar for gruppen ennå (forsøk $i av 4). Prøver igjen om $(15 * $i) s."; Start-Sleep -Seconds (15 * $i) }
            else { Log "Teams-teamet kunne ikke opprettes: $(Get-ErrorText $_)" 'WARN' }
        }
    }
    if ($teamOk) { Log 'Teams-team opprettet' 'OK' }
    else { $exitCode = 2; $problems.Add('Teams-teamet ble ikke opprettet. Det kan opprettes fra området eller fra Teams.') }
}

$hubOk = $null
if ($HubUrl) {
    $hubOk = $false
    try {
        Repair-AdminConnection
        Add-PnPHubSiteAssociation -Site $winner.SiteUrl -HubSite $HubUrl -Connection $script:admin
        $hubOk = $true
        Log "Området er knyttet til huben" 'OK'
    }
    catch {
        Log "Hubtilknytning feilet: $(Get-ErrorText $_)" 'WARN'; $exitCode = 2
        $problems.Add("Området ble ikke knyttet til huben $HubUrl.")
    }
}

$designOk = $null
if ($hubOk -and $hubDesign) {
    $designOk = $false
    Log "Legger på områdeutformingen «$($hubDesign.Title)» (tar vanligvis 1-3 min)"
    try {
        $failed = Complete-SiteDesign $winner.SiteUrl $hubDesign
        if ($failed.Count) {
            foreach ($f in $failed) { Log "Områdeutforming, handling feilet: $($f.ActionTitle): $($f.OutcomeText)" 'WARN' }
            $problems.Add("Områdeutformingen «$($hubDesign.Title)» ble kjørt, men $($failed.Count) handling(er) feilet.")
        }
        else { $designOk = $true; Log "Områdeutformingen «$($hubDesign.Title)» er ferdig" 'OK' }
    }
    catch {
        Log "Områdeutformingen ble ikke lagt på: $(Get-ErrorText $_)" 'WARN'
        $problems.Add("Områdeutformingen «$($hubDesign.Title)» ble ikke lagt på. Kjør skriptet på nytt eller be en administrator legge den på.")
    }
    if (-not $designOk) { $exitCode = 2 }
}

$wizardOk = $null
if ($isProjectHub -and $hubOk) {
    # Oppsettveiviseren skal komme med områdeutformingen. Sjekkes også når den ikke ble bekreftet ferdig.
    $wizardOk = $false
    Show-Progress 'Oppsettveiviser'
    try {
        $r = Add-SetupWizardIfMissing $winner.SiteUrl
        $wizardOk = $true
        Log $(if ($r -eq 'Added') { 'Oppsettveiviseren manglet og er lagt på' } else { 'Oppsettveiviseren er på plass' }) 'OK'
    }
    catch {
        Log "Kunne ikke sjekke eller legge på oppsettveiviseren: $(Get-ErrorText $_)" 'WARN'; $exitCode = 2
        $problems.Add('Oppsettveiviseren er ikke lagt på området. Be en administrator legge den på.')
    }
}

Show-Progress
$result = [pscustomobject]@{
    SiteUrl            = $winner.SiteUrl
    Alias              = $winner.Alias
    GroupId            = $winner.GroupId
    Language           = $winner.Lcid
    Attempts           = $attempts
    Hits               = $hits
    TeamCreated        = $teamOk
    HubAssociated      = $hubOk
    SiteDesignApplied  = $designOk
    SetupWizardPresent = $wizardOk
    CleanupErrors      = $cleanupErrors
    Minutes            = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
}
if ($useMi) { $result; return }

# Oppsummering for den som kjører skriptet
$line = '=' * 72
$ready = $isProjectHub -and $designOk -and $wizardOk
Write-Host ''
Write-Host $line -ForegroundColor Cyan
Write-Host "  Området er opprettet: $($winner.SiteUrl)" -ForegroundColor Green
Write-Host "  Språk: $(Get-LanguageName $winner.Lcid)$(if ($teamOk) { '   Teams-team: ja' })$(if ($hubOk) { "   Hub: $HubUrl" })"
if ($problems.Count) {
    Write-Host ''
    Write-Host '  Dette gikk ikke:' -ForegroundColor Yellow
    foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Yellow }
}
Write-Host ''
if ($ready) {
    Write-Host '  Området er klart til å legge på prosjektmal.' -ForegroundColor Green
    Write-Host '  Åpne adressen over i nettleseren, så starter oppsettveiviseren der du velger mal.'
}
elseif ($isProjectHub) {
    Write-Host '  Området er ikke klart for prosjektmal ennå. Se punktene over.' -ForegroundColor Yellow
}
else {
    Write-Host '  Området er klart til bruk.' -ForegroundColor Green
}
Write-Host $line -ForegroundColor Cyan
if ($exitCode) { exit $exitCode }
