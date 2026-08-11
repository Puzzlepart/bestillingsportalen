# Diagnoserunbook: hva kjører runbookene egentlig på?
#
# Skriver ut PowerShell-versjon, modulversjoner og managed identity-status fra INNE i
# et Automation-jobb. Dette er grunnsannheten - portalen kan ikke stoles på her:
#
#   «Runbooks created in Runtime environment experience with Runtime version
#    PowerShell 7.2+ would show as PowerShell 5.1 runbooks in old experience.»
#   https://learn.microsoft.com/en-us/azure/automation/runtime-environment-overview#limitations
#
# Portalens standard Runbooks-blad ER «old experience», så alle runbookene våre vises
# som «PowerShell 5.1» selv når de kjører på 7.4. Bytt til Runtime environment-
# opplevelsen i portalen for å se den faktiske verdien - eller kjør denne.
#
# Bestillingsportalen krever PowerShell 7.4 og PnP.PowerShell 3.x. Kjører dette på 5.1
# vil produksjonsrunbookene feile med «Connect-PnPOnline is not recognized».
#
# Kjør: importer som PowerShell-runbook i runtime environmentet du vil teste
# ('bestillingsportalen-ps74'), publiser og start. Ingen parametre, endrer ingenting.

[CmdletBinding()]
Param(
    # Sett til false hvis du bare vil se versjoner uten å ta en tilkobling.
    [Parameter(Mandatory = $false)] [bool] $TestConnection = $true
)

$ErrorActionPreference = 'Continue'

Write-Output '=== PowerShell ==='
Write-Output "Versjon        : $($PSVersionTable.PSVersion)"
Write-Output "Edition        : $($PSVersionTable.PSEdition)"
Write-Output "OS             : $($PSVersionTable.OS)"

$isExpected = $PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -eq 4
if ($isExpected) {
    Write-Output 'STATUS         : OK - PowerShell 7.4 som forventet'
}
else {
    Write-Output "STATUS         : FEIL - forventet 7.4, fikk $($PSVersionTable.PSVersion)."
    Write-Output '                 Produksjonsrunbookene krever PnP.PowerShell 3.x, som krever 7.4.'
    Write-Output '                 Knytt runbooken til runtime environmentet bestillingsportalen-ps74.'
}

Write-Output ''
Write-Output '=== Moduler ==='
foreach ($moduleName in @('PnP.PowerShell', 'Az.Accounts', 'Az.KeyVault')) {
    $versions = (Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 3).Version
    if ($versions) {
        Write-Output ("{0,-16} : {1}" -f $moduleName, ($versions -join ', '))
    }
    else {
        Write-Output ("{0,-16} : IKKE TILGJENGELIG" -f $moduleName)
    }
}

$pnp = Get-Module -ListAvailable -Name PnP.PowerShell | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $pnp) {
    Write-Output 'STATUS         : FEIL - PnP.PowerShell mangler. Alle runbookene vil feile.'
}
elseif ($pnp.Version.Major -lt 3) {
    Write-Output "STATUS         : FEIL - PnP.PowerShell $($pnp.Version) er for gammel. Krever 3.x."
}
else {
    Write-Output "STATUS         : OK - PnP.PowerShell $($pnp.Version)"
}

if (-not $TestConnection) {
    Write-Output ''
    Write-Output 'Hopper over tilkoblingstest (TestConnection = false).'
    return
}

Write-Output ''
Write-Output '=== Managed identity ==='
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $ctx = Get-AzContext
    Write-Output "Konto          : $($ctx.Account.Id)"
    Write-Output "Tenant         : $($ctx.Tenant.Id)"
    Write-Output "Subscription   : $($ctx.Subscription.Name)"
    Write-Output 'STATUS         : OK - system-assigned managed identity fungerer'
}
catch {
    Write-Output "STATUS         : FEIL - Connect-AzAccount -Identity feilet: $($_.Exception.Message)"
}

Write-Output ''
Write-Output 'Merk: denne runbooken tester ikke SharePoint-tilkobling, siden den ikke vet'
Write-Output 'hvilken tenant du kjører i. Bruk Test-AppOnlySensitivityLabel.ps1 for det.'
