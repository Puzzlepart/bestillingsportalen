# Diagnoseskript: kan et STS#3-område kobles til en ny M365-gruppe (groupify), og hvem
# må i så fall gjøre kallet?
#
# Bakgrunn: Graph ignorerer SPSiteLanguage ved POST /groups (sp-dev-docs #10875), så
# gruppetilknyttede områder kan få et annet språk enn bestilt. Workarounden er å opprette
# området som STS#3 med riktig LCID og deretter koble det til en gruppe. Se
# Source/Scripts/provisioning-workaround/Bakgrunnsutredning-SPSiteLanguage.md.
#
# Spørsmålene skriptet skal besvare før workarounden bygges inn i ProcessProvisionRequest:
#
#   -Mode AppOnly   (runbook, Automation-kontoens managed identity)
#       Godtar SharePoint groupify med app-only-token? Tre varianter prøves etter tur:
#         1. SiteRest:   POST <site>/_api/GroupSiteManager/CreateGroupForSite
#         2. PnPCmdlet:  Add-PnPMicrosoft365GroupToSite (samme endepunkt via PnP Framework)
#         3. TenantCsom: Tenant.CreateGroupForSite i admin-CSOM (det Set-SPOSiteOffice365Group bruker)
#       Virker én av dem, trengs ingen tjenestekonto for workarounden.
#
#   -Mode Delegated (lokalt, interaktiv innlogging)
#       Virker groupify når tjenestekontoen gjør kallet, og hva skjer med kontoens
#       objektkvote? Brukere uten admin-rolle kan opprette maks 250 Entra-objekter, og
#       gruppen opprettes i navnet til den som kaller. Skriptet:
#         - leser gruppeopprettelsespolicyen (Group.Unified) og kontoens admin-roller
#         - teller /me/createdObjects og /me/ownedObjects før groupify
#         - kjører groupify som tjenestekontoen
#         - fjerner tjenestekontoen som gruppeeier og teller på nytt
#       Om gruppen forsvinner fra createdObjects/ownedObjects når kontoen fjernes som eier,
#       sier noe om hvorvidt kvoten belastes varig. Microsoft dokumenterer ikke eksakt
#       hvilken relasjon kvoten teller, så tolk resultatet som en indikasjon, ikke et bevis.
#
# Begge moduser:
#   - avbryter før noe opprettes hvis URL eller alias er i bruk (aktivt eller i papirkurv)
#   - oppretter STS#3 med -Lcid og kontrollerer språket før og etter groupify
#   - oppdager kjent feil der groupify lager et duplikatområde i stedet for å koble gruppen
#   - rydder bort alt det har opprettet med -Cleanup (gruppe og område slettes permanent)
#
# Forutsetninger:
#   AppOnly:   Importeres som PowerShell 7.4-runbook i runtime environmentet
#              'bestillingsportalen-ps74' (PnP.PowerShell 3.2). Managed identity har
#              SharePoint Sites.FullControl.All og Graph Group.ReadWrite.All (gis av deploy.ps1).
#   Delegated: PowerShell 7.4 og PnP.PowerShell 3.2 lokalt. Du logger inn to ganger:
#              først som deg selv (SharePoint-admin, og Groups-admin hvis -Cleanup skal kunne
#              slette gruppen permanent), deretter som tjenestekontoen. Du kan bli bedt om å
#              logge inn som deg selv igjen senere i kjøringen.
#              Merk: i produksjon gjøres kallet via SharePoint-tilkoblingen i Logic App-en,
#              ikke via PnP-appen. Kvote og gruppepolicy er knyttet til brukeren, ikke appen,
#              så testen er representativ for det vi skal måle.
#
# Kjøres i en testtenant. Skriptet sletter aldri noe det ikke selv har opprettet.
#
# Eksempler:
#   Runbook: Start med Mode=AppOnly, AdminUrl, Owner (en testbruker), Cleanup=true.
#
#   Lokalt:
#   .\Test-GroupifyOptions.ps1 -Mode Delegated -AdminUrl https://contoso-admin.sharepoint.com `
#       -Owner ola@contoso.com -ServiceAccountUpn bestillingsportalen@contoso.com -Cleanup

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)] [ValidateSet('AppOnly', 'Delegated')] [string] $Mode,
    [Parameter(Mandatory = $true)] [string] $AdminUrl,
    # Eier av gruppen. Må være en annen enn tjenestekontoen, så den kan fjernes som eier.
    [Parameter(Mandatory = $true)] [string] $Owner,
    [Parameter(Mandatory = $false)] [string] $ServiceAccountUpn,
    [Parameter(Mandatory = $false)] [string] $ClientId = 'da6c31a6-b557-4ac3-9994-7315da06ea3a',
    [Parameter(Mandatory = $false)] [string] $Alias,
    [Parameter(Mandatory = $false)] [string] $Title,
    [Parameter(Mandatory = $false)] [int]    $Lcid = 1044,
    [Parameter(Mandatory = $false)] [int]    $TimeZone = 4,
    [Parameter(Mandatory = $false)] [int]    $GroupifyBufferSeconds = 120,
    [Parameter(Mandatory = $false)] [int]    $GroupifyWaitSeconds = 180,
    [Parameter(Mandatory = $false)] [int]    $MaxDuplicateRetries = 2,
    [Parameter(Mandatory = $false)] [int]    $CleanupTimeoutMinutes = 20,
    [Parameter(Mandatory = $false)] [switch] $Cleanup
)

$ErrorActionPreference = 'Stop'

$stamp = Get-Date -Format 'yyyyMMddHHmm'
if (-not $Alias) { $Alias = "diag-groupify-$stamp" }
if (-not $Title) { $Title = "Diagnose groupify $stamp" }
$AdminUrl = $AdminUrl.TrimEnd('/')
$tenantRoot = $AdminUrl -replace '-admin\.sharepoint\.com', '.sharepoint.com'
$siteUrl = "$tenantRoot/sites/$Alias"

if ($Mode -eq 'Delegated' -and -not $ServiceAccountUpn) { throw '-ServiceAccountUpn er påkrevd med -Mode Delegated.' }
if ($ServiceAccountUpn -and $Owner -ieq $ServiceAccountUpn) { throw '-Owner må være en annen enn tjenestekontoen.' }

# Logging skjer kun på toppnivå. Hjelpefunksjoner som returnerer verdier skriver bare til
# warning-strømmen, så Write-Output ikke blandes inn i returverdiene i runbook-kjøring.
function Log([string] $Message, [string] $Level = 'INFO') {
    Write-Output ("[{0:HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message)
}
function Write-Section([string] $Text) {
    Write-Output ''
    Write-Output "=== $Text ==="
}

function Get-ErrorText($ErrorRecord) {
    # Pakk ut innerste exception (reflection og CSOM pakker inn den egentlige serverfeilen)
    $ex = $ErrorRecord.Exception
    while ($ex.InnerException) { $ex = $ex.InnerException }
    $code = if ($ex.PSObject.Properties['ServerErrorCode']) { " (ServerErrorCode $($ex.ServerErrorCode))" } else { '' }
    return "$($ex.GetType().Name): $($ex.Message)$code"
}

function Wait-Until([scriptblock] $Condition, [int] $TimeoutSeconds, [int] $IntervalSeconds = 15, [string] $What) {
    # Fremdrift skrives med Write-Host, som ikke havner i returverdien
    $start = Get-Date
    $end = $start.AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $end) {
        try { if (& $Condition) { return $true } } catch { }
        if ($What) { Write-Host ("[{0:HH:mm:ss}] [WAIT]   {1} ({2}/{3} s)" -f (Get-Date), $What, [int] ((Get-Date) - $start).TotalSeconds, $TimeoutSeconds) }
        Start-Sleep -Seconds $IntervalSeconds
    }
    return $false
}

function Test-SameUrl([string] $A, [string] $B) {
    $norm = { param($u) ($u.TrimEnd('/') -replace '(?<!:)/{2,}', '/') }
    return $A -and $B -and ((& $norm $A) -eq (& $norm $B))
}

# ---------------------------------------------------------------------------
# Tilkobling
# ---------------------------------------------------------------------------
Write-Section "Tilkobling ($Mode)"
Log "Admin-URL : $AdminUrl"
Log "Testområde: $siteUrl (LCID $Lcid)"
Log "Gruppeeier: $Owner"

if ($Mode -eq 'AppOnly') {
    $admin = Connect-PnPOnline -Url $AdminUrl -ManagedIdentity -ReturnConnection
    $operatorUpn = $null
    Log 'Tilkoblet med managed identity (app-only).'
}
else {
    Log 'Logg inn som deg selv (SharePoint-administrator).'
    $admin = Connect-PnPOnline -Url $AdminUrl -ClientId $ClientId -Interactive -ReturnConnection
    $me = Get-PnPProperty -ClientObject (Get-PnPWeb -Connection $admin) -Property CurrentUser -Connection $admin
    $operatorUpn = ($me.LoginName -split '\|')[-1]
    if ($operatorUpn -ieq $ServiceAccountUpn) { throw 'Første innlogging skal være deg selv, ikke tjenestekontoen.' }
    Log "Innlogget som $operatorUpn"
}

# Tilkoblingen for gruppeoppslag. I Delegated-modus byttes den til tjenestekontoen når den har
# logget inn: innloggingen med -ForceAuthentication tømmer PnPs tokencache, og videre bruk av
# $admin kan da kjøre som feil bruker eller vente på en ny innlogging.
$ops = $admin

$siteConnections = @{}
function Connect-Site([string] $Url) {
    $key = $Url.TrimEnd('/').ToLowerInvariant()
    if (-not $siteConnections.ContainsKey($key)) {
        $siteConnections[$key] = if ($Mode -eq 'AppOnly') {
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
function Get-LiveGroup([string] $Identity) {
    try { return Get-PnPMicrosoft365Group -Identity $Identity -Connection $ops -ErrorAction SilentlyContinue } catch { return $null }
}
function Get-DeletedGroup([string] $GroupId) {
    try { return Get-PnPDeletedMicrosoft365Group -Identity $GroupId -Connection $ops -ErrorAction SilentlyContinue } catch { return $null }
}
function Get-AliasGroup {
    # -Identity matcher også visningsnavn. Filtrer på eksakt mailNickname.
    try {
        return Get-PnPMicrosoft365Group -Identity $Alias -Connection $ops -ErrorAction SilentlyContinue |
            Where-Object { $_.MailNickname -eq $Alias } | Select-Object -First 1
    } catch { return $null }
}
function Get-SiteLanguage([string] $Url) {
    return [int] (Get-PnPWeb -Includes Language -Connection (Connect-Site $Url)).Language
}
function Get-SiteGroupId([string] $Url) {
    $id = (Get-PnPSite -Includes GroupId -Connection (Connect-Site $Url)).GroupId.Guid
    if ($id -eq [guid]::Empty.Guid) { return $null }
    return $id
}
function Get-GroupSiteUrl([string] $GroupId) {
    # Graph /groups/{id}/sites/root krever Sites.Read.All, som runbookens MI ikke har.
    # Fallback: søk etter områder med aliaset i URL-en og samme GroupId via admin-API.
    try {
        $url = (Get-PnPMicrosoft365Group -Identity $GroupId -IncludeSiteUrl -Connection $ops).SiteUrl
        if ($url) { return $url }
    } catch { }
    if ($ops -ne $admin) { return $null }
    try {
        $match = Get-PnPTenantSite -Filter "Url -like '$Alias'" -Connection $admin |
            Where-Object { $_.GroupId.Guid -eq $GroupId } | Select-Object -First 1
        if ($match) { return $match.Url }
    } catch { }
    return $null
}

function Get-GraphAll([string] $Url, $Connection) {
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Url
    while ($next) {
        $r = Invoke-PnPGraphMethod -Url $next -Method Get -Connection $Connection
        if ($r.value) { $items.AddRange([object[]] $r.value) }
        $next = $r.'@odata.nextLink'
    }
    return , $items
}

function Remove-GroupPermanently([string] $GroupId, [int] $TimeoutSeconds = 300) {
    if (-not $GroupId) { return $true }
    return Wait-Until -TimeoutSeconds $TimeoutSeconds -What "gruppe $GroupId permanent slettet" -Condition {
        if (Get-LiveGroup $GroupId) {
            try { Remove-PnPMicrosoft365Group -Identity $GroupId -Connection $ops | Out-Null } catch { Write-Warning "Remove-PnPMicrosoft365Group: $(Get-ErrorText $_)" }
            return $false
        }
        if (Get-DeletedGroup $GroupId) {
            try { Remove-PnPDeletedMicrosoft365Group -Identity $GroupId -Connection $ops | Out-Null } catch { Write-Warning "Remove-PnPDeletedMicrosoft365Group: $(Get-ErrorText $_)" }
            return $false
        }
        Start-Sleep -Seconds 15
        return (-not (Get-LiveGroup $GroupId)) -and (-not (Get-DeletedGroup $GroupId))
    }
}

function Remove-SitePermanently([string] $Url, [int] $TimeoutSeconds = $CleanupTimeoutMinutes * 60) {
    # Gruppeområder kan ikke slettes via admin-API. De forsvinner asynkront etter at gruppen er
    # slettet (observert ca. 10 min), og tømmes da fra papirkurven.
    return Wait-Until -TimeoutSeconds $TimeoutSeconds -What "$Url permanent slettet" -Condition {
        $live = Get-LiveSite $Url
        if ($live) {
            $gid = if ($live.GroupId -and $live.GroupId.Guid -ne [guid]::Empty.Guid) { $live.GroupId.Guid } else { $null }
            if (-not $gid) {
                try { Remove-PnPTenantSite -Url $Url -Force -SkipRecycleBin -Connection $admin | Out-Null } catch { Write-Warning "Remove-PnPTenantSite: $(Get-ErrorText $_)" }
            }
            elseif (Get-LiveGroup $gid) {
                try { Remove-PnPMicrosoft365Group -Identity $gid -Connection $admin | Out-Null } catch { Write-Warning "Remove-PnPMicrosoft365Group: $(Get-ErrorText $_)" }
            }
            return $false
        }
        if (Get-DeletedSite $Url) {
            try { Remove-PnPTenantDeletedSite -Identity $Url -Force -Connection $admin | Out-Null } catch { Write-Warning "Remove-PnPTenantDeletedSite: $(Get-ErrorText $_)" }
            return $false
        }
        Start-Sleep -Seconds 15
        return (-not (Get-LiveSite $Url)) -and (-not (Get-DeletedSite $Url))
    }
}

# ---------------------------------------------------------------------------
# Groupify-varianter. Hver returnerer $null ved suksess (kallet kastet ikke) eller feilteksten.
# ---------------------------------------------------------------------------
function Invoke-GroupifySiteRest($Connection) {
    # Samme kall som Logic App-en vil sende via "Send an HTTP request to SharePoint"
    $body = @{
        displayName    = $Title
        alias          = $Alias
        isPublic       = $false
        optionalParams = @{
            Description     = 'Opprettet av Test-GroupifyOptions.ps1'
            Owners          = @($Owner)
            CreationOptions = @('SharePointKeepOldHomepage')
        }
    }
    $resp = Invoke-PnPSPRestMethod -Method Post -Url "$siteUrl/_api/GroupSiteManager/CreateGroupForSite" `
        -Content $body -ContentType 'application/json;odata=nometadata' -Connection $Connection
    Write-Warning "CreateGroupForSite svarte: GroupId=$($resp.GroupId) SiteStatus=$($resp.SiteStatus)"
}

function Invoke-GroupifyPnPCmdlet($Connection) {
    Add-PnPMicrosoft365GroupToSite -Url $siteUrl -Alias $Alias -DisplayName $Title `
        -Owners @($Owner) -KeepOldHomePage -Connection $Connection
}

function Invoke-GroupifyTenantCsom {
    # Tenant.CreateGroupForSite finnes i admin-CSOM, men signatur og parametertype varierer
    # mellom CSOM-versjoner. Slå opp metoden med reflection i stedet for å anta signaturen.
    $ctx = $admin.Context
    $tenant = [Microsoft.Online.SharePoint.TenantAdministration.Tenant]::new($ctx)
    $method = $tenant.GetType().GetMethods() | Where-Object { $_.Name -eq 'CreateGroupForSite' } | Select-Object -First 1
    if (-not $method) { throw 'Tenant.CreateGroupForSite finnes ikke i CSOM-versjonen PnP.PowerShell leverer.' }

    $values = foreach ($p in $method.GetParameters()) {
        switch ($p.Name) {
            'siteUrl'     { $siteUrl }
            'displayName' { $Title }
            'alias'       { $Alias }
            'isPublic'    { $false }
            default {
                $t = $p.ParameterType
                $ctor = $t.GetConstructor([type[]] @([Microsoft.SharePoint.Client.ClientRuntimeContext]))
                $o = if ($ctor) { $ctor.Invoke(@($ctx)) } else { [Activator]::CreateInstance($t) }
                if ($t.GetProperty('Owners')) { $o.Owners = [string[]] @($Owner) }
                if ($t.GetProperty('CreationOptions')) { $o.CreationOptions = [string[]] @('SharePointKeepOldHomepage') }
                if ($t.GetProperty('Description')) { $o.Description = 'Opprettet av Test-GroupifyOptions.ps1' }
                $o
            }
        }
    }
    $ret = $method.Invoke($tenant, [object[]] $values)
    if ($ret -is [Microsoft.SharePoint.Client.ClientObject]) { $ctx.Load($ret) }
    $ctx.ExecuteQuery()
}

function Wait-GroupifyResult([bool] $CallThrew) {
    # Kastet kallet og ingen gruppe dukker opp, er det ingen vits i å vente hele perioden
    if ($CallThrew) {
        Start-Sleep -Seconds 30
        $siteGroup = try { Get-SiteGroupId $siteUrl } catch { $null }
        if (-not (Get-AliasGroup) -and -not $siteGroup) { return @{ Outcome = 'NoGroup' } }
    }
    $linked = Wait-Until -TimeoutSeconds $GroupifyWaitSeconds -What 'Site.GroupId satt' -Condition { [bool] (Get-SiteGroupId $siteUrl) }
    if ($linked) { return @{ Outcome = 'Linked'; GroupId = (Get-SiteGroupId $siteUrl) } }

    $g = Get-AliasGroup
    if (-not $g) { return @{ Outcome = 'NoGroup' } }
    $gUrl = Get-GroupSiteUrl $g.Id
    if ($gUrl -and -not (Test-SameUrl $gUrl $siteUrl)) { return @{ Outcome = 'Duplicate'; GroupId = $g.Id; GroupSiteUrl = $gUrl } }
    return @{ Outcome = 'Pending'; GroupId = $g.Id; GroupSiteUrl = $gUrl }
}

function Get-ObjectSnapshot($Connection) {
    $snap = [ordered]@{ Created = $null; CreatedGroups = $null; Owned = $null; OwnedGroups = $null; CreatedIds = @(); OwnedIds = @(); Error = $null }
    try {
        $created = Get-GraphAll 'v1.0/me/createdObjects?$select=id&$top=999' $Connection
        $snap.Created = $created.Count
        $snap.CreatedGroups = @($created | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }).Count
        $snap.CreatedIds = @($created | ForEach-Object { $_.id })
    } catch { $snap.Error = "createdObjects: $(Get-ErrorText $_)" }
    try {
        $owned = Get-GraphAll 'v1.0/me/ownedObjects?$select=id&$top=999' $Connection
        $snap.Owned = $owned.Count
        $snap.OwnedGroups = @($owned | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }).Count
        $snap.OwnedIds = @($owned | ForEach-Object { $_.id })
    } catch { $snap.Error = "$($snap.Error) ownedObjects: $(Get-ErrorText $_)".Trim() }
    return $snap
}

# ---------------------------------------------------------------------------
# Forhåndssjekk
# ---------------------------------------------------------------------------
Write-Section 'Forhåndssjekk'
# Get-LiveSite svelger feil, så kontroller admin-tilgangen eksplisitt først. Ellers ser
# manglende rettighet ut som «URL ledig», og feilen kommer først ved opprettelsen.
try { Get-PnPTenantSite -Identity $tenantRoot -Connection $admin | Out-Null }
catch {
    throw "Ingen tilgang til SharePoint admin-API: $(Get-ErrorText $_). Kontoen må ha rollen SharePoint-administrator (aktivert, hvis dere bruker PIM)."
}
$preflight = @()
if (Get-LiveSite $siteUrl)    { $preflight += "Området $siteUrl finnes allerede." }
if (Get-DeletedSite $siteUrl) { $preflight += "Området $siteUrl ligger i SharePoint-papirkurven." }
$existing = Get-AliasGroup
if ($existing) { $preflight += "En M365-gruppe med alias '$Alias' finnes allerede ($($existing.Id))." }
try {
    $deleted = Get-PnPDeletedMicrosoft365Group -Connection $admin | Where-Object { $_.MailNickname -eq $Alias } | Select-Object -First 1
    if ($deleted) { $preflight += "En slettet gruppe med alias '$Alias' ligger i Entra-papirkurven ($($deleted.Id))." }
} catch { Log "Kunne ikke lese slettede grupper: $(Get-ErrorText $_)" 'WARN' }
if ($preflight) {
    $preflight | ForEach-Object { Log $_ 'ERR' }
    throw 'Avbryter før noe er opprettet. Velg et annet -Alias.'
}
Log 'URL og alias er ledige.' 'OK'

$createdGroupIds = [System.Collections.Generic.List[string]]::new()
$createdSiteUrls = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# 1. STS#3 med riktig språk
# ---------------------------------------------------------------------------
Write-Section '1. Oppretter STS#3-område'
# Delegert oppretting med en annen eier enn innlogget bruker kan avvises, så i Delegated-modus
# blir du eier, og tjenestekontoen legges til som site collection admin etterpå. Det tilsvarer
# produksjon, der managed identity oppretter området og gir tjenestekontoen tilgang.
if ($Mode -eq 'Delegated') {
    New-PnPSite -Type TeamSiteWithoutMicrosoft365Group -Title $Title -Url $siteUrl -Lcid $Lcid `
        -TimeZone $TimeZone -Wait -Connection $admin | Out-Null
}
else {
    New-PnPSite -Type TeamSiteWithoutMicrosoft365Group -Title $Title -Url $siteUrl -Lcid $Lcid `
        -TimeZone $TimeZone -Owner $Owner -Wait -Connection $admin | Out-Null
}
$createdSiteUrls.Add($siteUrl)
Log 'Opprettet'

$active = Wait-Until -TimeoutSeconds 300 -What 'området aktivt' -Condition { (Get-LiveSite $siteUrl).Status -eq 'Active' }
if (-not $active) { throw "Området ble ikke aktivt innen 5 min. Rydd manuelt: $siteUrl" }

if ($Mode -eq 'Delegated') {
    # Tjenestekontoen må ha tilgang til området for å kunne gjøre groupify-kallet
    Set-PnPTenantSite -Identity $siteUrl -Owners @($ServiceAccountUpn) -Connection $admin
    Log "$ServiceAccountUpn lagt til som site collection admin"
}

$langBefore = Get-SiteLanguage $siteUrl
Log "Språk på STS#3: $langBefore (forventet $Lcid)" $(if ($langBefore -eq $Lcid) { 'OK' } else { 'ERR' })
if ($langBefore -ne $Lcid) { Log 'STS#3 fikk feil språk. Det er uventet - resultatet under er da lite verdt.' 'WARN' }

# ---------------------------------------------------------------------------
# 2. Tjenestekonto: innlogging, policy og kvote før groupify (kun Delegated)
# ---------------------------------------------------------------------------
$sa = $null
$snapBefore = $null
$policy = [ordered]@{}
if ($Mode -eq 'Delegated') {
    Write-Section '2. Tjenestekontoen før groupify'
    # Policy og roller leses med din tilkobling før tjenestekontoen logger inn (se $ops over)
    $saPath = 'v1.0/users/' + [uri]::EscapeDataString($ServiceAccountUpn)
    try {
        $roles = Get-GraphAll ($saPath + '/memberOf/microsoft.graph.directoryRole?$select=displayName') $admin
        $policy.AdminRoles = if ($roles.Count) { ($roles | ForEach-Object { $_.displayName }) -join ', ' } else { '(ingen)' }
    } catch { $policy.AdminRoles = "kunne ikke lese: $(Get-ErrorText $_)" }
    Log "Admin-roller på tjenestekontoen: $($policy.AdminRoles)"
    if ($policy.AdminRoles -notmatch '^\(ingen\)$|^kunne ikke') {
        Log 'Kontoen har admin-rolle. 250-grensen gjelder da ikke, så kvotemålingen sier lite om kunder uten rolle.' 'WARN'
    }

    try {
        $settings = Invoke-PnPGraphMethod -Url 'v1.0/groupSettings' -Method Get -Connection $admin
        $unified = $settings.value | Where-Object { $_.displayName -eq 'Group.Unified' } | Select-Object -First 1
        if ($unified) {
            $policy.EnableGroupCreation = ($unified.values | Where-Object name -eq 'EnableGroupCreation').value
            $policy.AllowedGroupId = ($unified.values | Where-Object name -eq 'GroupCreationAllowedGroupId').value
        }
        else { $policy.EnableGroupCreation = 'true (ingen Group.Unified-innstilling, standard)' }
    } catch { $policy.EnableGroupCreation = "kunne ikke lese: $(Get-ErrorText $_)" }
    Log "Gruppeopprettelse for alle brukere: $($policy.EnableGroupCreation)"
    if ($policy.AllowedGroupId) {
        try {
            $hit = Invoke-PnPGraphMethod -Url ($saPath + '/checkMemberGroups') -Method Post -Content @{ groupIds = @($policy.AllowedGroupId) } -Connection $admin
            $policy.MemberOfAllowedGroup = [bool] ($hit.value -contains $policy.AllowedGroupId)
        } catch { $policy.MemberOfAllowedGroup = "kunne ikke lese: $(Get-ErrorText $_)" }
        Log "Begrenset til gruppe $($policy.AllowedGroupId). Tjenestekontoen er medlem: $($policy.MemberOfAllowedGroup)"
    }

    Log "Logg inn som tjenestekontoen ($ServiceAccountUpn). Velg kontoen i innloggingsvinduet."
    $sa = Connect-PnPOnline -Url $siteUrl -ClientId $ClientId -Interactive -ForceAuthentication -ReturnConnection
    $saMe = Get-PnPProperty -ClientObject (Get-PnPWeb -Connection $sa) -Property CurrentUser -Connection $sa
    $saLogin = ($saMe.LoginName -split '\|')[-1]
    if ($saLogin -ine $ServiceAccountUpn) { throw "Innlogget som $saLogin, forventet $ServiceAccountUpn. Kjør på nytt (området $siteUrl må ryddes manuelt)." }
    Log "Innlogget som $saLogin" 'OK'

    # Herfra brukes bare tjenestekontoens tilkobling, frem til oppryddingen. Kontoen er site
    # collection admin, så den kan også lese språk og GroupId på området.
    $ops = $sa
    $siteConnections[$siteUrl.TrimEnd('/').ToLowerInvariant()] = $sa

    $snapBefore = Get-ObjectSnapshot $sa
    Log "createdObjects: $($snapBefore.Created) (grupper: $($snapBefore.CreatedGroups))   ownedObjects: $($snapBefore.Owned) (grupper: $($snapBefore.OwnedGroups))"
    if ($snapBefore.Error) { Log $snapBefore.Error 'WARN' }
}
Log "Venter $GroupifyBufferSeconds s buffer før groupify"
Start-Sleep -Seconds $GroupifyBufferSeconds

# ---------------------------------------------------------------------------
# 3. Groupify
# ---------------------------------------------------------------------------
Write-Section '3. Groupify'
$variants = if ($Mode -eq 'AppOnly') { @('SiteRest', 'PnPCmdlet', 'TenantCsom') } else { @('SiteRest', 'PnPCmdlet') }
$callConn = if ($Mode -eq 'AppOnly') { Connect-Site $siteUrl } else { $sa }
$attempts = [System.Collections.Generic.List[object]]::new()
$result = $null

foreach ($variant in $variants) {
    $retries = 0
    while ($true) {
        Log "Variant $variant$(if ($retries) { " (nytt forsøk $retries etter duplikat)" })"
        $err = $null
        try {
            switch ($variant) {
                'SiteRest'   { Invoke-GroupifySiteRest $callConn }
                'PnPCmdlet'  { Invoke-GroupifyPnPCmdlet $callConn }
                'TenantCsom' { Invoke-GroupifyTenantCsom }
            }
            Log '  Kallet returnerte uten feil.'
        }
        catch {
            $err = Get-ErrorText $_
            Log "  Kallet feilet: $err" 'WARN'
        }

        $r = Wait-GroupifyResult ([bool] $err)
        if ($r.GroupId -and -not $createdGroupIds.Contains($r.GroupId)) { $createdGroupIds.Add($r.GroupId) }
        $attempts.Add([pscustomobject]@{ Variant = $variant; Error = $err; Outcome = $r.Outcome; GroupId = $r.GroupId; GroupSiteUrl = $r.GroupSiteUrl })
        Log "  Utfall: $($r.Outcome)$(if ($r.GroupId) { ", gruppe $($r.GroupId)" })$(if ($r.GroupSiteUrl) { ", gruppens område $($r.GroupSiteUrl)" })" $(if ($r.Outcome -eq 'Linked') { 'OK' } else { 'WARN' })

        if ($r.Outcome -eq 'Duplicate') {
            # Kjent feil: gruppen fikk et nytt område. Slett gruppen så aliaset blir ledig og prøv igjen.
            $createdSiteUrls.Add($r.GroupSiteUrl)
            Log "  Sletter gruppen permanent for å frigjøre aliaset" 'WARN'
            if (-not (Remove-GroupPermanently $r.GroupId)) { Log '  Gruppen ble ikke bekreftet slettet. Avbryter groupify.' 'ERR'; break }
            if ($retries++ -lt $MaxDuplicateRetries) { continue }
        }
        break
    }
    if ($attempts[-1].Outcome -in @('Linked', 'Pending')) { $result = $attempts[-1]; break }
}

# ---------------------------------------------------------------------------
# 4. Etter groupify
# ---------------------------------------------------------------------------
$langAfter = $null
$saWasOwner = $null
$snapAfterLink = $null
$snapAfterRemoval = $null
$ownerRemoved = $null

if ($result -and $result.Outcome -eq 'Linked') {
    Write-Section '4. Etter groupify'
    try { $langAfter = Get-SiteLanguage $siteUrl } catch { Log "Kunne ikke lese språk: $(Get-ErrorText $_)" 'WARN' }
    Log "Språk etter groupify: $langAfter" $(if ($langAfter -eq $Lcid) { 'OK' } else { 'ERR' })

    $owners = @()
    try { $owners = @(Get-PnPMicrosoft365GroupOwner -Identity $result.GroupId -Connection $ops | ForEach-Object { $_.UserPrincipalName }) }
    catch { Log "Kunne ikke lese eiere: $(Get-ErrorText $_)" 'WARN' }
    Log "Gruppeeiere: $($owners -join ', ')"

    if ($Mode -eq 'Delegated') {
        $saWasOwner = [bool] ($owners | Where-Object { $_ -ieq $ServiceAccountUpn })
        $snapAfterLink = Get-ObjectSnapshot $sa
        Log "createdObjects: $($snapAfterLink.Created) (grupper: $($snapAfterLink.CreatedGroups))   ownedObjects: $($snapAfterLink.Owned) (grupper: $($snapAfterLink.OwnedGroups))"
        Log "Gruppen i createdObjects: $($snapAfterLink.CreatedIds -contains $result.GroupId)   i ownedObjects: $($snapAfterLink.OwnedIds -contains $result.GroupId)"

        if ($saWasOwner) {
            Log "Fjerner $ServiceAccountUpn som gruppeeier"
            try {
                Remove-PnPMicrosoft365GroupOwner -Identity $result.GroupId -Users $ServiceAccountUpn -Connection $ops
                $ownerRemoved = Wait-Until -TimeoutSeconds 120 -What 'tjenestekontoen fjernet som eier' -Condition {
                    -not (Get-PnPMicrosoft365GroupOwner -Identity $result.GroupId -Connection $ops | Where-Object { $_.UserPrincipalName -ieq $ServiceAccountUpn })
                }
            } catch { Log "Kunne ikke fjerne eier: $(Get-ErrorText $_)" 'WARN'; $ownerRemoved = $false }
            Log "Fjernet som eier: $ownerRemoved" $(if ($ownerRemoved) { 'OK' } else { 'WARN' })
            # Gi katalogen litt tid før relasjonene leses på nytt
            Start-Sleep -Seconds 30
            $snapAfterRemoval = Get-ObjectSnapshot $sa
            Log "createdObjects: $($snapAfterRemoval.Created) (grupper: $($snapAfterRemoval.CreatedGroups))   ownedObjects: $($snapAfterRemoval.Owned) (grupper: $($snapAfterRemoval.OwnedGroups))"
            Log "Gruppen i createdObjects: $($snapAfterRemoval.CreatedIds -contains $result.GroupId)   i ownedObjects: $($snapAfterRemoval.OwnedIds -contains $result.GroupId)"
        }
        else {
            Log 'Tjenestekontoen ble ikke lagt til som gruppeeier av groupify.'
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Resultat
# ---------------------------------------------------------------------------
Write-Section '5. RESULTAT'
$attempts | Format-Table Variant, Outcome, GroupId, GroupSiteUrl, Error -AutoSize -Wrap | Out-String -Width 250 | Write-Output
$duplicates = @($attempts | Where-Object Outcome -eq 'Duplicate').Count

if ($Mode -eq 'AppOnly') {
    if ($result -and $result.Outcome -eq 'Linked') {
        Write-Output "UTFALL A - groupify virker app-only via $($result.Variant)."
        Write-Output '           Workarounden kan kjøres av managed identity. Ingen tjenestekonto trengs.'
        Write-Output "           Språk før/etter: $langBefore / $langAfter. Duplikater underveis: $duplicates."
    }
    elseif ($result) {
        Write-Output "UAVKLART  - $($result.Variant) opprettet gruppe $($result.GroupId), men området viste ikke GroupId"
        Write-Output "           innen $GroupifyWaitSeconds s. Sjekk området manuelt, og kjør gjerne med høyere -GroupifyWaitSeconds."
    }
    else {
        Write-Output 'UTFALL B - groupify avvises app-only i alle varianter (se feilene over).'
        Write-Output '           Workarounden krever et delegert kall. Kjør -Mode Delegated for å teste tjenestekontoen.'
    }
}
else {
    if ($result -and $result.Outcome -eq 'Linked') {
        Write-Output "Groupify som tjenestekonto virker ($($result.Variant)). Språk før/etter: $langBefore / $langAfter. Duplikater underveis: $duplicates."
        Write-Output "Admin-roller: $($policy.AdminRoles)"
        Write-Output "Gruppeopprettelse for alle: $($policy.EnableGroupCreation)$(if ($policy.AllowedGroupId) { ", begrenset til $($policy.AllowedGroupId), medlem: $($policy.MemberOfAllowedGroup)" })"
        Write-Output "Tjenestekontoen ble gruppeeier: $saWasOwner. Fjernet som eier: $ownerRemoved."
        if ($snapBefore -and $snapAfterRemoval) {
            $inCreated = $snapAfterRemoval.CreatedIds -contains $result.GroupId
            $inOwned = $snapAfterRemoval.OwnedIds -contains $result.GroupId
            Write-Output "createdObjects før/etter: $($snapBefore.Created) -> $($snapAfterRemoval.Created). Gruppen står der fortsatt: $inCreated"
            Write-Output "ownedObjects   før/etter: $($snapBefore.Owned) -> $($snapAfterRemoval.Owned). Gruppen står der fortsatt: $inOwned"
            if (-not $inCreated -and -not $inOwned) {
                Write-Output 'Tolkning: gruppen henger ikke igjen på tjenestekontoen etter at den er fjernet som eier.'
                Write-Output '          Det tyder på at 250-grensen ikke belastes varig, men bekreft med Microsoft før det bygges på.'
            }
            elseif ($inCreated) {
                Write-Output 'Tolkning: gruppen står fortsatt i createdObjects. Hvis kvoten telles derfra, belastes den varig'
                Write-Output '          (også slettede grupper i 30 dager). Da trenger tjenestekontoen en rolle, eller annen løsning.'
            }
            else {
                Write-Output 'Tolkning: gruppen står fortsatt i ownedObjects selv om kontoen er fjernet som eier. Undersøk manuelt.'
            }
        }
    }
    else {
        Write-Output 'Groupify som tjenestekonto virket ikke (se feilene over). Sjekk gruppepolicyen og site admin-tilgangen.'
    }
}

# ---------------------------------------------------------------------------
# Opprydding
# ---------------------------------------------------------------------------
Write-Section 'Opprydding'
if ($Cleanup -and $ops -ne $admin) {
    # Sletting krever admin. Logg inn som deg selv igjen, siden $admin ikke kan brukes etter
    # at tjenestekontoen har logget inn.
    Log 'Logg inn som deg selv igjen for oppryddingen.'
    $admin = Connect-PnPOnline -Url $AdminUrl -ClientId $ClientId -Interactive -ForceAuthentication -ReturnConnection
    $me = Get-PnPProperty -ClientObject (Get-PnPWeb -Connection $admin) -Property CurrentUser -Connection $admin
    $who = ($me.LoginName -split '\|')[-1]
    if ($who -ine $operatorUpn) { Log "Innlogget som $who, forventet $operatorUpn. Oppryddingen kan feile." 'WARN' }
    $ops = $admin
}
foreach ($gid in ($createdGroupIds | Select-Object -Unique)) {
    if ($Cleanup) {
        Log "Sletter gruppe $gid permanent"
        if (Remove-GroupPermanently $gid) { Log '  Slettet' 'OK' } else { Log "  Ikke bekreftet slettet. Sjekk Entra manuelt." 'ERR' }
    }
    else { Log "Opprettet gruppe: $gid" }
}
foreach ($u in ($createdSiteUrls | Select-Object -Unique)) {
    if ($Cleanup) {
        Log "Sletter område $u permanent (gruppeområder kan bruke ~10 min)"
        if (Remove-SitePermanently $u) { Log '  Slettet' 'OK' }
        else { Log "  Ikke bekreftet slettet. Når det ligger i papirkurven: Remove-PnPTenantDeletedSite -Identity $u -Force" 'ERR' }
    }
    else { Log "Opprettet område: $u" }
}
if (-not $Cleanup) { Log 'Kjørt uten -Cleanup. Slett gruppe og område manuelt når du har sett på dem.' 'WARN' }
