param(
	[Parameter(Mandatory = $false)]
	[string]$AppDisplayName = "Bestillingsportalen",

	[Parameter(Mandatory = $false)]
	[string]$ResourceGroupName = "Bestillingsportalen",

	[Parameter(Mandatory = $false)]
	[string]$KeyVaultName,

	[Parameter(Mandatory = $false)]
	[string]$CertName = "Bestillingsportalen-cert",

	[Parameter(Mandatory = $false)]
	[int]$CertValidityDays = 900
)

$ErrorActionPreference = "Stop"

az login

$currDate = Get-Date
$certEndDate = $currDate.AddDays($CertValidityDays).ToString("yyyy/MM/dd")

# Find appId from app display name
$apps = az ad app list --display-name $AppDisplayName | ConvertFrom-Json
$matchingApps = $apps | Where-Object { $_.displayName -eq $AppDisplayName }

if (-not $matchingApps -or $matchingApps.Count -eq 0) {
	throw "Fant ingen Entra-app med navn '$AppDisplayName'."
}

if ($matchingApps.Count -gt 1) {
	throw "Fant flere Entra-apper med navn '$AppDisplayName'. Oppgi unik app eller tilpass scriptet."
}

$appId = $matchingApps[0].appId

# Resolve Key Vault from resource group unless overridden
if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
	$keyVaults = az keyvault list --resource-group $ResourceGroupName | ConvertFrom-Json

	if (-not $keyVaults -or $keyVaults.Count -eq 0) {
		throw "Fant ingen Key Vault i ressursgruppen '$ResourceGroupName'. Bruk -KeyVaultName for overstyring."
	}

	if ($keyVaults.Count -gt 1) {
		throw "Fant flere Key Vaults i ressursgruppen '$ResourceGroupName'. Bruk -KeyVaultName for overstyring."
	}

	$KeyVaultName = $keyVaults[0].name
}

# Resolve certificate name: use provided/default name when it exists,
# otherwise fall back to the only certificate in the vault.
$certificates = az keyvault certificate list --vault-name $KeyVaultName | ConvertFrom-Json
if (-not $certificates -or $certificates.Count -eq 0) {
	throw "Fant ingen sertifikater i Key Vault '$KeyVaultName'."
}

$namedCertificate = $certificates | Where-Object { $_.name -eq $CertName }
if (-not $namedCertificate) {
	if ($certificates.Count -eq 1) {
		$CertName = $certificates[0].name
		Write-Host "Fant ikke sertifikat ved navn. Bruker eneste sertifikat i vault: '$CertName'."
	}
	else {
		throw "Fant ikke sertifikat '$CertName' i Key Vault '$KeyVaultName', og vaulten har flere sertifikater. Oppgi korrekt -CertName."
	}
}

$confirmation = Read-Host "Klar til aa fornye sertifikat. AppName='$AppDisplayName', AppId='$appId', KeyVault='$KeyVaultName', CertName='$CertName', EndDate='$certEndDate'. Fortsette? (J/N)"
if ($confirmation -notin @("J", "j", "Y", "y")) {
	Write-Host "Avbrutt av bruker."
	exit 0
}

az ad app credential reset --id $appId --create-cert --keyvault $KeyVaultName --cert $CertName --end-date $certEndDate --append