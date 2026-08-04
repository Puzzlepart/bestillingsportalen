# Diagnoseskript

Engangsskript for å måle eller verifisere oppførsel i en konkret tenant. De er
**ikke** en del av installasjonen: `deploy.ps1` laster kun opp runbookene som er
navngitt i `DeployLocalRunbooks` (`ConfigureSpace`, `GetSiteTemplates`,
`AddGuestToSite`) pluss `CustomerSpecific`, så ingenting i denne mappen deployes
automatisk.

Importer dem manuelt i Automation-kontoen når du trenger dem, og slett dem etterpå.

| Skript | Formål |
|--|--|
| [`Test-AppOnlySensitivityLabel.ps1`](Test-AppOnlySensitivityLabel.ps1) | Avgjør om `Set-PnPTenantSite -SensitivityLabel` med managed identity faktisk setter container-merket på et gruppetilknyttet område, og om det propagerer til gruppens `assignedLabels`. Svaret avgjør om tjenestekontoen og Entra ID-appen kan fjernes — se [Sensitivitetsmerker](../../Sensitivity-labels.md). |

## Slik kjører du et diagnoseskript

1. Azure Portal > Automation-kontoen (`bestillingsportalen-auto`) > **Runbooks** > **Create a runbook**.
2. Type **PowerShell**, Runtime environment **`bestillingsportalen-ps74`** (samme som produksjonsrunbookene — skriptene forutsetter PnP.PowerShell 3.2).
3. Lim inn innholdet, **Save**, deretter **Publish**.
4. **Start**, og fyll inn parameterne.
5. Les output-fanen på jobben.
6. Slett runbooken når du er ferdig.
