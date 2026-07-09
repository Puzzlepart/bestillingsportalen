# ============================================================================
#  Fornye sertifikat for Bestillingsportalen (Entra ID app + Key Vault)
# ============================================================================
#
#  BAKGRUNN
#  --------
#  Logic Apps i Bestillingsportalen autentiserer mot Microsoft Graph med et
#  SERTIFIKAT (app-only). Sertifikatet ligger som en secret i Key Vault, og
#  thumbprint-en til sertifikatet må være registrert som en keyCredential på
#  app-registreringen i Entra ID.
#
#  Hver Logic App leser sertifikatet UTEN å låse til en bestemt versjon
#  (/secrets/<certName>/value), og får derfor ALLTID den NYESTE aktiverte
#  versjonen i Key Vault. For at autentiseringen skal lykkes må thumbprint-en
#  til den nyeste versjonen finnes blant credentials på app-registreringen.
#
#  TYPISK FEIL ("certificate thumbprint")
#  --------------------------------------
#  Feilen oppstår når Key Vault serverer en sertifikatversjon hvis thumbprint
#  IKKE er registrert på app-registreringen. Dette kan skje FØR utløpsdato,
#  for eksempel hvis:
#    * Key Vault auto-roterer sertifikatet (ny versjon med ny thumbprint som
#      aldri ble lagt til på app-registreringen), eller
#    * KV-sertifikatets fysiske gyldighet (policy, ofte 12 mnd) utløper før
#      app-credentialens --end-date (her 900 dager) -> utløpt pfx serveres.
#
#  Merk: CheckSiteExists bruker KUN sertifikat (app-only) og feiler derfor
#  først. ProcessProvisionRequest har også en client-secret/service-account-sti
#  og kan se ut til å "fungere" selv om sertifikatet er ødelagt.
#
#  Dette skriptet kjører BÅDE halvdelene samtidig: lager en ny KV-versjon OG
#  registrerer dens thumbprint på app-registreringen. Verifiseringen nederst
#  bekrefter at de er i synk etterpå.
#
#  CLIENT SECRET ER NOE ANNET
#  --------------------------
#  Client secret-en (appSecret) er en EGEN credential som ikke berøres av dette
#  skriptet. Den utløper separat (standard 1 år) og brukes av Key Vault API
#  Connection, Automation Account og service-account-flyten. Den er IKKE
#  årsaken til thumbprint-feilen, men bør fornyes samtidig hvis den nærmer seg
#  utløp. Se Refreshing-app-secret.md.
# ============================================================================

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

# --- 1) Logg inn -----------------------------------------------------------
az login

$currDate = Get-Date
$certEndDate = $currDate.AddDays($CertValidityDays).ToString("yyyy/MM/dd")

# --- 2) Finn appId fra app display name ------------------------------------
$apps = az ad app list --display-name $AppDisplayName | ConvertFrom-Json
$matchingApps = $apps | Where-Object { $_.displayName -eq $AppDisplayName }

if (-not $matchingApps -or $matchingApps.Count -eq 0) {
	throw "Fant ingen Entra-app med navn '$AppDisplayName'."
}

if ($matchingApps.Count -gt 1) {
	throw "Fant flere Entra-apper med navn '$AppDisplayName'. Oppgi unik app eller tilpass scriptet."
}

$appId = $matchingApps[0].appId

# --- 3) Finn Key Vault fra ressursgruppen (med mindre overstyrt) -----------
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

# --- 4) Finn sertifikatnavn: bruk angitt/standard navn hvis det finnes,
#        ellers fall tilbake til det eneste sertifikatet i vaulten. ----------
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

# --- 5) Forny sertifikatet -------------------------------------------------
# Lager en ny sertifikatversjon i Key Vault OG appender dens thumbprint som en
# keyCredential på app-registreringen. --append beholder eksisterende
# credentials (se note om opprydding under "MANUELLE STEG").
az ad app credential reset --id $appId --create-cert --keyvault $KeyVaultName --cert $CertName --end-date $certEndDate --append

# ============================================================================
#  VERIFISERING – kjør dette etter fornyelse for å bekrefte synk
# ============================================================================
# Hjelpefunksjon: normaliser en thumbprint til store HEX-tegn uavhengig av om
# verdien kommer som hex (Key Vault) eller base64 (customKeyIdentifier).
function ConvertTo-HexThumb([string]$value) {
	if ([string]::IsNullOrWhiteSpace($value)) { return $null }
	$v = $value.Trim()
	if ($v -match '^[0-9A-Fa-f]{40}$') { return $v.ToUpper() }
	try {
		$bytes = [Convert]::FromBase64String($v)
		return (($bytes | ForEach-Object { $_.ToString('X2') }) -join '')
	} catch {
		return $v.ToUpper()
	}
}

Write-Host "`n=== Nyeste sertifikatversjon i Key Vault ===" -ForegroundColor Cyan
$kvCert     = az keyvault certificate show --vault-name $KeyVaultName --name $CertName -o json | ConvertFrom-Json
$kvThumbHex = ConvertTo-HexThumb $kvCert.x509ThumbprintHex
Write-Host ("Thumbprint : {0}" -f $kvThumbHex)
Write-Host ("Utløper    : {0}" -f $kvCert.attributes.expires)

Write-Host "`n=== Sertifikat-credentials registrert på app-registreringen ===" -ForegroundColor Cyan
$appCreds = az ad app credential list --id $appId --cert -o json | ConvertFrom-Json
$appCreds |
	Select-Object displayName, endDateTime, @{ n = 'thumbprint'; e = { ConvertTo-HexThumb $_.customKeyIdentifier } } |
	Sort-Object endDateTime |
	Format-Table -AutoSize

$registered = $appCreds | ForEach-Object { ConvertTo-HexThumb $_.customKeyIdentifier }
if ($registered -contains $kvThumbHex) {
	Write-Host "OK: Nyeste Key Vault-thumbprint er registrert på app-registreringen. Logic Apps bør autentisere." -ForegroundColor Green
} else {
	Write-Warning "MISMATCH: Nyeste Key Vault-thumbprint finnes IKKE blant credentials pa app-registreringen."
	Write-Warning "Logic Apps vil feile med thumbprint-feil. Kjor fornyelsen pa nytt, eller registrer thumbprint-en manuelt."
}

Write-Host "`n=== Rotation-/utstedelsespolicy for sertifikatet i Key Vault ===" -ForegroundColor Cyan
# Hvis lifetimeActions inneholder en auto-renew-handling, lager Key Vault nye
# versjoner automatisk – og disse blir IKKE registrert på app-registreringen.
# Det er den vanligste årsaken til at thumbprint-feilen kommer tilbake gjentatte
# ganger før utløpsdato. Vurder å fjerne auto-rotation, eller sørg for at dette
# skriptet kjøres hver gang Key Vault lager en ny versjon.
az keyvault certificate get-policy --vault-name $KeyVaultName --name $CertName `
	--query "{validityMonths: x509CertificateProperties.validityInMonths, lifetimeActions: lifetimeActions}" -o json

# ============================================================================
#  MANUELLE STEG / TING Å SJEKKE
# ============================================================================
#  1) Hent den FAKTISKE feilmeldingen fra den feilende Logic App-kjøringen
#     (f.eks. CheckSiteExists) for å bekrefte at det er en thumbprint-feil og
#     ikke en annen årsak (Key Vault-tilgang, utløpt client secret, osv.).
#
#  2) Rotation-policy: Sjekk utskriften over. Hvis Key Vault auto-roterer
#     sertifikatet, fjern auto-rotation ELLER planlegg at dette skriptet kjøres
#     hver gang en ny versjon lages, slik at thumbprint-en alltid registreres
#     på app-registreringen.
#
#  3) Validitet: Hvis "validityMonths" er kortere enn de 900 dagene som settes
#     på app-credentialen, vil pfx-en i Key Vault utløpe før app-credentialen.
#     Juster KV-policyen slik at de samsvarer.
#
#  4) Opprydding: --append akkumulerer credentials på app-registreringen for
#     hver kjøring. Slett utløpte/gamle keyCredentials (alle unntatt den
#     gjeldende) manuelt i Entra ID -> App registrations -> Certificates &
#     secrets, eller med:
#       az ad app credential delete --id <appId> --key-id <keyId> --cert
#
#  5) Client secret (appSecret): Egen credential, ikke berørt av dette skriptet.
#     Fornyes separat (standard 1 års utløp) og brukes av Key Vault API
#     Connection, Automation Account og service-account-flyten. Forny samtidig
#     hvis den nærmer seg utløp. Se Refreshing-app-secret.md.
