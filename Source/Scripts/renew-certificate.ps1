az login --tenant "xxx" # 

$currDate = Get-Date

$certEndDate = $currDate.AddDays(900) | Get-Date -Format 'yyyy/MM/dd'

$appId = "22c8506d-f3f2-4d91-af6f-64acd647d730"

$keyVaultName = "kv-bestillingsportalen"

$certName = "cert-bestillingsportalen"



az ad app credential reset --id $appId --create-cert --keyvault $keyVaultName --cert $certName --end-date $certEndDate --append