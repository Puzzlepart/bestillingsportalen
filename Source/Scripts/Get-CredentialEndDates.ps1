<#
.SYNOPSIS
    Henter siste utløpsdato (endDateTime) for sertifikat og klienthemmelighet på Entra ID-appen,
    i NØYAKTIG samme strengformat som deploy-pingbacken (SendDeployPingback i deploy.ps1) sender
    dem med i AddEntry. Skriver verdiene til en output-fil for manuell copy/paste inn i Entries-tabellen.

.DESCRIPTION
    Speiler GetLatestAppCredentialEndDate i deploy.ps1: spør app-registreringen via Azure CLI og
    rapporterer siste (lengst fram i tid) endDateTime for password- (klienthemmelighet) og
    certificate- (key) credentials. Krever at Azure CLI er installert og innlogget (az login).

    Uten -AppId/-AppName leses appName fra parameters.json i samme mappe (samme kilde som deploy.ps1).

.EXAMPLE
    ./Get-CredentialEndDates.ps1
    # Leser appName fra parameters.json

.EXAMPLE
    ./Get-CredentialEndDates.ps1 -AppName "Bestillingsportalen"

.EXAMPLE
    ./Get-CredentialEndDates.ps1 -AppId "00000000-0000-0000-0000-000000000000" -OutputPath "./bp.txt"
#>
param
(
    [Parameter(Mandatory = $false)]
    [string]$AppId,

    [Parameter(Mandatory = $false)]
    [string]$AppName,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "./credential-enddates.json"
)

# Identisk med GetLatestAppCredentialEndDate i deploy.ps1 — sikrer samme strengformat i output.
function GetLatestAppCredentialEndDate {
    param
    (
        [string]$AppId,
        [switch]$CertificateCredentials
    )

    if ([string]::IsNullOrEmpty($AppId)) {
        return $null
    }

    try {
        $credentials = if ($CertificateCredentials) {
            az ad app credential list --id $AppId --cert 2>$null | ConvertFrom-Json
        }
        else {
            az ad app credential list --id $AppId 2>$null | ConvertFrom-Json
        }

        $latest = $credentials |
        Where-Object { -not [string]::IsNullOrEmpty($_.endDateTime) } |
        Sort-Object { [datetime]$_.endDateTime } -Descending |
        Select-Object -First 1

        if ($null -ne $latest) {
            return $latest.endDateTime
        }
    }
    catch {}

    return $null
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Azure CLI (az) er ikke installert. Installer den og kjor 'az login' forst." -ForegroundColor Red
    exit 1
}

# Resolve app id: -AppId > -AppName > appName fra parameters.json
if ([string]::IsNullOrEmpty($AppId) -and [string]::IsNullOrEmpty($AppName)) {
    if (Test-Path './parameters.json') {
        try {
            $params = Get-Content './parameters.json' -Raw | ConvertFrom-Json
            $AppName = $params.appName.Value
            Write-Host "Bruker appName '$AppName' fra parameters.json" -ForegroundColor DarkGray
        }
        catch {}
    }
}

if ([string]::IsNullOrEmpty($AppId)) {
    if ([string]::IsNullOrEmpty($AppName)) {
        Write-Host "Oppgi enten -AppId eller -AppName (eller kjor fra mappen med parameters.json)." -ForegroundColor Red
        exit 1
    }

    $app = az ad app list --filter "displayName eq '$AppName'" 2>$null | ConvertFrom-Json
    $resolved = $app | Select-Object -First 1

    if ($null -eq $resolved -or [string]::IsNullOrEmpty($resolved.appId)) {
        Write-Host "Fant ingen Entra ID-app med displayName '$AppName'. Sjekk navnet og at du er innlogget (az login) med tilgang." -ForegroundColor Red
        exit 1
    }

    $AppId = $resolved.appId
}

Write-Host "Henter credential-datoer for app $AppId ..." -ForegroundColor Yellow

$clientSecretEndDate = GetLatestAppCredentialEndDate -AppId $AppId
$certificateEndDate = GetLatestAppCredentialEndDate -AppId $AppId -CertificateCredentials

if ([string]::IsNullOrEmpty($clientSecretEndDate)) {
    Write-Host "[WARN] Fant ingen klienthemmelighet (password credential) pa appen." -ForegroundColor Yellow
}
if ([string]::IsNullOrEmpty($certificateEndDate)) {
    Write-Host "[WARN] Fant ingen sertifikat (key credential) pa appen." -ForegroundColor Yellow
}

# Verdier til copy/paste (samme strengformat som i AddEntry-payloaden)
Write-Host ""
Write-Host "===== Verdier til Entries-tabellen =====" -ForegroundColor Cyan
Write-Host "AppId              : $AppId"
Write-Host "ClientSecretEndDate: $clientSecretEndDate"
Write-Host "CertificateEndDate : $certificateEndDate"
Write-Host ""

# Lagre til fil i samme JSON-strengformat som sendes med i AddEntry
$output = [ordered]@{
    ClientSecretEndDate = $clientSecretEndDate.ToString('o') 
    CertificateEndDate  = $certificateEndDate.ToString('o') 
}
$output | ConvertTo-Json | Out-File -FilePath $OutputPath -Encoding utf8
Write-Host "Lagret til $OutputPath" -ForegroundColor Green
