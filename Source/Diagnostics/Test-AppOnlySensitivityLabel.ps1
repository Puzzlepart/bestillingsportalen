# Diagnoserunbook: kan sensitivitetsmerker settes app-only?
#
# Formål: avgjøre om `Set-PnPTenantSite -SensitivityLabel` med Automation-kontoens
# system-assigned managed identity (app-only) faktisk anvender container-merket på et
# GRUPPETILKNYTTET SharePoint-område - og om merket propagerer til `assignedLabels` på
# den koblede Microsoft 365-gruppen.
#
# Svaret avgjør om tjenestekontoen (og hele Entra ID-app-registreringen med client
# secret) kan fjernes fra installasjonen. Se Sensitivity-labels.md.
#
# Bakgrunn:
#   - Graph støtter ikke application permissions for PATCH /groups/{id} med
#     assignedLabels (re-verifisert august 2026). Derfor ROPC-flyten i ConfigureSpace.
#   - PnP dokumenterer likevel `Set-PnPTenantSite -SensitivityLabel` som app-only-veien
#     for gruppetilknyttede områder.
#   - pnp/powershell#4917 rapporterer at kallet lykkes UTEN feil mens merket ikke
#     settes - nettopp med managed identity + Sites.FullControl.All. «Ingen exception»
#     er derfor ikke bevis, og dette skriptet leser alltid tilbake.
#
# Forutsetninger:
#   - Kjøres som PowerShell 7.4-runbook i runtime environmentet med PnP.PowerShell 3.2
#     (samme som produksjonsrunbookene - 'bestillingsportalen-ps74').
#   - Automation-kontoens managed identity har SharePoint Sites.FullControl.All og
#     Graph Group.ReadWrite.All (tildeles av deploy.ps1).
#   - $SiteUrl peker på et gruppetilknyttet TESTområde uten merke fra før.
#   - $LabelId er en publisert etikett med scope Site/UnifiedGroup - hent den fra
#     `IP Labels`-listen, kolonnen 'Label Id'.
#
# Kjør: Automation-konto > Runbooks > importer denne > Publiser > Start, og fyll inn
# SiteUrl og LabelId. Skriptet endrer bare merket på testområdet du peker på.

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]  [string] $SiteUrl,
    [Parameter(Mandatory = $true)]  [string] $LabelId,
    [Parameter(Mandatory = $false)] [int]    $MaxWaitSeconds = 300
)

$ErrorActionPreference = 'Stop'

function Write-Section($Text) {
    Write-Output ''
    Write-Output "=== $Text ==="
}

$tenantName = ([System.Uri]$SiteUrl).Host.Split('.')[0]
$adminUrl = "https://$tenantName-admin.sharepoint.com"

Write-Section 'Kobler til med managed identity'
Write-Output "Admin-URL : $adminUrl"
Write-Output "Målområde : $SiteUrl"
Write-Output "Etikett   : $LabelId"

Connect-PnPOnline -Url $adminUrl -ManagedIdentity
Write-Output 'Tilkoblet (app-only, system-assigned MI).'

# --- 1. Er området gruppetilknyttet? Uten en gruppe er testen meningsløs -------------
Write-Section '1. Kontrollerer at området er gruppetilknyttet'
$tenantSite = Get-PnPTenantSite -Identity $SiteUrl
$groupId = $tenantSite.GroupId

if (-not $groupId -or $groupId -eq [Guid]::Empty) {
    throw "Området har ingen tilknyttet M365-gruppe (GroupId er tomt). Velg et gruppetilknyttet område - det er hele poenget med testen."
}

Write-Output "GroupId              : $groupId"
Write-Output "Merke FØR (område)   : '$($tenantSite.SensitivityLabel)'"

# --- 2. Merke på gruppen før, via Graph ---------------------------------------------
# Invoke-PnPGraphMethod bruker samme managed identity-token som PnP-tilkoblingen.
Write-Section '2. Leser assignedLabels på gruppen FØR'
# Enkle fnutter + konkatenering for å slippe backtick-escaping av $select
$groupQuery = 'v1.0/groups/' + $groupId + '?$select=id,displayName,assignedLabels'
$groupBefore = Invoke-PnPGraphMethod -Url $groupQuery -Method Get
Write-Output "Gruppe               : $($groupBefore.displayName)"
Write-Output "assignedLabels FØR   : $($groupBefore.assignedLabels | ConvertTo-Json -Compress)"

if ($groupBefore.assignedLabels.Count -gt 0) {
    Write-Warning 'Gruppen har allerede et merke. Testen blir tvetydig - bruk et område uten merke.'
}

# --- 3. Selve kallet vi tester -------------------------------------------------------
Write-Section '3. Kjører Set-PnPTenantSite -SensitivityLabel (app-only)'
$callThrew = $false
try {
    Set-PnPTenantSite -Identity $SiteUrl -SensitivityLabel $LabelId
    Write-Output 'Kallet returnerte UTEN exception.'
}
catch {
    $callThrew = $true
    Write-Output "Kallet KASTET: $($_.Exception.Message)"
}

# --- 4. Les tilbake til merket har propagert, eller vi gir opp -----------------------
Write-Section "4. Poller inntil $MaxWaitSeconds sekunder på propagering"
$deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
$siteLabelSet = $false
$groupLabelSet = $false
$lastSiteLabel = ''
$lastGroupLabels = ''
$attempt = 0

while ((Get-Date) -lt $deadline -and -not ($siteLabelSet -and $groupLabelSet)) {
    $attempt++
    Start-Sleep -Seconds 15

    $siteNow = Get-PnPTenantSite -Identity $SiteUrl
    $lastSiteLabel = "$($siteNow.SensitivityLabel)"
    $siteLabelSet = ($lastSiteLabel -replace '[{}]', '') -ieq ($LabelId -replace '[{}]', '')

    $groupNow = Invoke-PnPGraphMethod -Url ('v1.0/groups/' + $groupId + '?$select=assignedLabels') -Method Get
    $lastGroupLabels = ($groupNow.assignedLabels | ForEach-Object { $_.labelId }) -join ','
    $groupLabelSet = $groupNow.assignedLabels.labelId -contains $LabelId

    Write-Output ("Forsøk {0,2} ({1,3}s): område='{2}' (match={3})  gruppe='{4}' (match={5})" -f `
            $attempt, ($attempt * 15), $lastSiteLabel, $siteLabelSet, $lastGroupLabels, $groupLabelSet)
}

# --- 5. Dom ---------------------------------------------------------------------------
Write-Section '5. RESULTAT'
Write-Output "Kallet kastet exception : $callThrew"
Write-Output "Merke satt på OMRÅDET   : $siteLabelSet  (leste '$lastSiteLabel')"
Write-Output "Merke satt på GRUPPEN   : $groupLabelSet  (leste '$lastGroupLabels')"
Write-Output ''

if ($siteLabelSet -and $groupLabelSet) {
    Write-Output 'UTFALL A - app-only-merking virker, og merket propagerer til gruppen.'
    Write-Output '           ROPC-apparatet er redundant og kan fjernes i sin helhet:'
    Write-Output '           Entra ID-appen, client secret, sausername/sapassword,'
    Write-Output '           createentraidapp.ps1 og kravet om tjenestekonto uten MFA.'
}
elseif ($siteLabelSet -and -not $groupLabelSet) {
    Write-Output 'DELVIS   - merket ligger på området, men IKKE på gruppen.'
    Write-Output '           Behandle som UTFALL B: ROPC beholdes som fallback. Dette er'
    Write-Output '           det viktigste enkeltfunnet - container-merket styrer'
    Write-Output '           gruppens privacy/gjestedeling, så område alene er ikke nok.'
}
else {
    Write-Output 'UTFALL B - app-only-merking virker ikke (stille no-op eller feil).'
    Write-Output '           Bekrefter pnp/powershell#4917. ROPC beholdes som fallback.'
}

Write-Output ''
Write-Output 'Verifiser til slutt manuelt i SharePoint Admin Center (Sites > Active sites,'
Write-Output 'kolonnen Sensitivity) og i Graph Explorer:'
Write-Output ('  GET https://graph.microsoft.com/v1.0/groups/' + $groupId + '?$select=assignedLabels')
Write-Output ''
Write-Output 'Dokumentér resultatet i Sensitivity-labels.md, og slett runbooken fra'
Write-Output 'Automation-kontoen når du er ferdig.'
