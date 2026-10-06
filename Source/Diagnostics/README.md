# Diagnoseskript

Engangsskript for å måle eller verifisere oppførsel i en konkret tenant. De er
**ikke** en del av installasjonen: `deploy.ps1` laster kun opp runbookene som er
navngitt i `DeployLocalRunbooks` (`ConfigureSpace`, `GetSiteTemplates`,
`AddGuestToSite`, `CreateGroupWithLanguage`) pluss `CustomerSpecific`, så ingenting i denne mappen deployes
automatisk.

Importer dem manuelt i Automation-kontoen når du trenger dem, og slett dem etterpå.

| Skript | Formål |
|--|--|
| [`Test-RunbookRuntime.ps1`](Test-RunbookRuntime.ps1) | Skriver ut PowerShell-versjon, modulversjoner og managed identity-status fra inne i et Automation-jobb. Bruk denne når du er i tvil om hva runbookene faktisk kjører på — se advarselen under. |
| [`Test-AppOnlySensitivityLabel.ps1`](Test-AppOnlySensitivityLabel.ps1) | Avgjør om `Set-PnPTenantSite -SensitivityLabel` med managed identity faktisk setter container-merket på et gruppetilknyttet område, og om det propagerer til gruppens `assignedLabels`. Svaret avgjør om tjenestekontoen og Entra ID-appen kan fjernes — se [Sensitivitetsmerker](../../Sensitivity-labels.md). |
| [`Test-GroupifyOptions.ps1`](Test-GroupifyOptions.ps1) | Avgjør om et STS#3-område kan kobles til en ny M365-gruppe (groupify) app-only (`-Mode AppOnly`, som runbook), og ellers hva som skjer når tjenestekontoen gjør det (`-Mode Delegated`, lokalt): gruppepolicy, admin-roller og om gruppen henger igjen i kontoens `createdObjects`/`ownedObjects` (250-grensen). Grunnlag for workarounden når Graph ignorerer `SPSiteLanguage` — se [bakgrunnsutredningen](../Scripts/provisioning-workaround/Bakgrunnsutredning-SPSiteLanguage.md). `-Mode Delegated` kan ikke kjøres som runbook. Resultat (okt. 2026): groupify krever admin og er ustabil, så workarounden er forkastet. |
| [`Test-GroupSiteLanguageRetry.ps1`](Test-GroupSiteLanguageRetry.ps1) | Oppretter gruppeområder som `ProcessProvisionRequest` gjør i dag (app-only `POST /groups` med `SPSiteLanguage`), sjekker språket, sletter feil og prøver igjen, ett om gangen eller flere parallelt (`-BatchSize`). Viser treffraten (er feilen tilfeldig eller fast i tenanten?), tid til området er klart, og med `-RetrySameAlias` hvor lenge URL-en er sperret etter sletting. Kjøres som runbook (managed identity, som i produksjon) eller lokalt. Sletter alt den oppretter uten å vente; `-PurgeDeleted` tømmer også papirkurvene. |
| [`Invoke-DiagnosticRunbook.ps1`](Invoke-DiagnosticRunbook.ps1) | Hjelpeskript (kjøres lokalt med Az PowerShell): laster opp et diagnoseskript som runbook på `bestillingsportalen-ps74`, publiserer, starter jobben med parametre og skriver ut output. Bruker samme REST-kall som `deploy.ps1`, så runtime environmentet beholdes. |

## ⚠️ Portalen viser runbookene som «PowerShell 5.1» — det er normalt

Runbookene kjører på **PowerShell 7.4** via runtime environmentet `bestillingsportalen-ps74`, men portalens standard **Runbooks**-blad viser dem som «PowerShell 5.1». Det er en dokumentert begrensning i «old experience», som ikke kjenner runtime environments over 7.2:

> «Runbooks created in Runtime environment experience with Runtime version PowerShell 7.2+ would show as PowerShell 5.1 runbooks in old experience.»
> — [Runtime environment in Azure Automation § Limitations](https://learn.microsoft.com/en-us/azure/automation/runtime-environment-overview#limitations)

Tre måter å se den faktiske verdien:

1. **Bytt portalopplevelse** (enkleste, og den anbefalte): åpne Automation-kontoen og bytt til **Runtime environment-opplevelsen** — bryteren ligger i banneret på Automation-konto-oversikten. Da vises runtime environment og faktisk PowerShell-versjon korrekt for hver runbook, og `bestillingsportalen-ps74` blir synlig med pakkene sine. Innstillingen huskes, så dette er verdt å gjøre én gang per tenant du jobber i.
2. **REST API** — den autoritative kilden:

```bash
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Automation/automationAccounts/bestillingsportalen-auto/runbooks/ConfigureSpace?api-version=2024-10-23" --query "properties.runtimeEnvironment" --output tsv
```

3. **Kjør `Test-RunbookRuntime.ps1`** — grunnsannheten, siden den rapporterer `$PSVersionTable` fra inne i jobben.

`deploy.ps1` sjekker dette selv ved hver kjøring og rapporterer «Runbook runtime environment» i deployment summary, så du skal normalt ikke trenge å verifisere manuelt.

## Slik kjører du et diagnoseskript

1. Azure Portal > Automation-kontoen (`bestillingsportalen-auto`) > **Runbooks** > **Create a runbook**.
2. Type **PowerShell**, Runtime environment **`bestillingsportalen-ps74`** (samme som produksjonsrunbookene — skriptene forutsetter PnP.PowerShell 3.2).
3. Lim inn innholdet, **Save**, deretter **Publish**.
4. **Start**, og fyll inn parameterne.
5. Les output-fanen på jobben.
6. Slett runbooken når du er ferdig.
