az login

$currDate = Get-Date
$certEndDate = $currDate.AddDays(900) | Get-Date -Format 'yyyy/MM/dd'
$appId = "0c21e13e-b904-463a-b8a5-460b0e98ccaa"
$keyVaultName = "kv-12018-bp"
$certName = "cert-12018-bestillingsportalen"

az ad app credential reset --id $appId --create-cert --keyvault $keyVaultName --cert $certName --end-date $certEndDate --append