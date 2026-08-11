# Migrering til managed identity

Dette dokumentet beskriver hvorfor og hvordan Bestillingsportalen er migrert fra client secret- og sertifikatbasert autentisering til **user-assigned managed identity** for Logic Apps, hva som bevisst *ikke* er endret, og hvordan eksisterende installasjoner oppgraderes.

> **Oppdatering:** dette dokumentet beskriver migreringen i 1.11.0, der ett unntak sto igjen – ROPC-flyten for sensitivitetsmerker, med tjenestekonto uten MFA, client secret og Key Vault. **Det unntaket er senere fjernet:** merker settes nå app-only med Automation-kontoens managed identity, og løsningen har ingen Key Vault, ingen client secret og ingen egen Entra ID-app-registrering i drift. Der dette dokumentet omtaler Key Vault, ROPC eller client secret, gjelder det historikken – ikke dagens løsning. Se [Sensitivitetsmerker](Sensitivity-labels.md) for dagens mekanisme og [Oppgraderingsveiledningen](Upgrade.md) for opprydding i eksisterende miljøer.

## Bakgrunn og motivasjon

Før migreringen var kjøretidsautentiseringen i løsningen avhengig av to roterende credentials på Entra ID-appen:

- **Client secret** (standard utløp 1 år) – brukt av Key Vault- og Azure Automation-API-tilkoblingene, og i ROPC-kallet for sensitivitetsmerker.
- **Sertifikat** (PFX i Key Vault, standard 365 dagers gyldighet) – brukt av samtlige HTTP-handlinger i Logic Apps mot Microsoft Graph og SharePoint REST (hentet ved kjøretid via `Get_Client_ID`-/`Get_Certificate`-handlingene).

Utløp av en av disse stoppet hele løsningen til credentialen var fornyet og oppdatert i Key Vault, API-tilkoblinger m.m. (se de tidligere dokumentene «Fornye App Secret» og «Renewing certificate»). I tillegg var både secret og PFX lesbare ved kjøretid for alle med tilgang til Logic App-kjørehistorikk eller Key Vault.

Med managed identity utsteder Entra ID tokens direkte til Azure-ressursen. Det finnes **ingen credential å rotere, lagre eller lekke**.

## Hva som er undersøkt (konklusjoner)

| Spørsmål | Konklusjon |
|--|--|
| Kan HTTP-handlingene i Logic Apps (Graph + SharePoint REST) bruke managed identity? | **Ja.** Consumption Logic Apps støtter `ManagedServiceIdentity`-autentisering på HTTP-handlinger, med samme `audience` som før. SharePoint godtar app-only-tokens fra managed identity (kravet om sertifikat gjelder bare client credentials-flyten med secret). |
| Kan Key Vault- og Azure Automation-API-tilkoblingene bruke managed identity? | **Ja.** Begge managed connectors støtter managed identity (`parameterValueType: Alternative` på tilkoblingen + `connectionProperties.authentication` på referansen i workflowen). |
| Kan de delegerte connectorene (SharePoint Online, Outlook, O365 Users, Teams) bruke managed identity? | **Nei.** Disse er delegated-only og krever fortsatt interaktiv autorisering med **tjenestekontoen**. |
| Kan sensitivitetsmerker settes med application permissions / managed identity? | **Nei** (verifisert mot Microsoft Graph-dokumentasjonen). `assignedLabels` på grupper kan kun oppdateres med **delegated permissions**. ROPC-flyten med tjenestekonto (og dermed client secret-en, siden appen er en confidential client) beholdes — men kun for denne ene operasjonen, og kun når `enableSensitivity` er aktivert. Sjekk jevnlig om begrensningen er fjernet: [Update group – Microsoft Graph](https://learn.microsoft.com/en-us/graph/api/group-update). |

## Målbilde

Én delt **user-assigned managed identity** (`bestillingsportalen-uami`, konfigurerbar via `uamiName` i `parameters.json`) er koblet til alle ni Logic Apps og brukes til:

- Alle HTTP-handlinger mot Microsoft Graph og SharePoint REST.
- `bestillingsportalen-kv`-API-tilkoblingen (Key Vault).
- `bestillingsportalen-automation`-API-tilkoblingen (Azure Automation).

### Hva som bevisst IKKE er endret

- **Tjenestekontoen** beholdes for (a) interaktiv autorisering av de delegerte API-tilkoblingene (SPO, Outlook, O365 Users, Teams) og (b) ROPC-flyten for sensitivitetsmerker.
- **Client secret-en** beholdes *kun* for ROPC-flyten og opprettes nå bare når `enableSensitivity` er `true`.
- **Automation Account-ens system-assigned managed identity** (brukt av runbookene `ConfigureSpace`, `GetSiteTemplates`, `AddGuestToSite` og `CustomerSpecific` via `Connect-PnPOnline -ManagedIdentity`) er uendret.
- **PnP-appen** for selve installasjonen (deploy-tid, ikke kjøretid) er uendret.
- Key Vault beholdes for `appid`, `appSecret`, `sausername` og `sapassword` (alle kun relevante for sensitivitetsmerke-funksjonaliteten).

## Tillatelser

App-rollene på den user-assigned managed identityen (9 Graph + 1 SharePoint) og Automation-kontoens system-assigned identity tildeles av `deploy.ps1` (`AssignUamiPermissions`/`AssignManagedIdentityPermissions`) og er dokumentert **kall-for-kall i [Datatilgang og sikkerhet](Data-access-security.md)** — den er kanonisk kilde for tillatelseslistene. Settet er minimert mot faktiske runtime-kall (bl.a. `GroupSettings.ReadWrite.All` i stedet for `Directory.ReadWrite.All`, og `Sites.Read.All` i stedet for Graph `Sites.FullControl.All`).

### Azure-tilganger (tildeles av `azureresources.bicep`)

| Omfang | Tilgang |
|--|--|
| Key Vault | Access policy: `get`/`list` på secrets (for ROPC-secretene) |
| Automation Account | RBAC: Automation Job Operator + Automation Runbook Operator |

### Entra ID-appen (fase 2)

Etter 1.11.0 trengte Entra ID-appen («Bestillingsportalen») i praksis bare den delegerte `Group.ReadWrite.All`-tillatelsen for ROPC-flyten.

**Dette er senere gjort irrelevant:** ROPC-flyten er fjernet, og løsningen oppretter ikke lenger noen egen app-registrering. Har du en installasjon fra 1.11.0 eller tidligere, kan **hele app-registreringen slettes** – ikke bare application-tillatelsene. Se [Oppgraderingsveiledningen](Upgrade.md) for den fulle oppryddingslista (app-registrering, Key Vault og KV-tilkoblingen).

## Endringsoversikt

| Fil | Endring |
|--|--|
| `Source/ARMTemplates/azureresources.bicep` | Ny UAMI-ressurs, Key Vault access policy for UAMI (erstatter app-SP/bruker-policyene), RBAC-tildelinger på Automation Account, outputs. |
| `Source/ARMTemplates/LogicApps/apiconnections.json` | KV- og Automation-tilkoblingene bruker managed identity (`Alternative`) i stedet for client secret. `appId`/`appSecret`-parametrene fjernet. |
| Alle 9 Logic App-maler | `identity`-blokk + `uamiName`-parameter; alle `ActiveDirectoryOAuth`/PFX-autentiseringsblokker erstattet med `ManagedServiceIdentity`; `Get_Client_ID`-/`Get_Certificate`-handlingene fjernet (unntatt ROPC-kjeden i `processprovisionrequest.json`); ubrukte Key Vault-tilkoblingsreferanser fjernet. |
| `Source/Scripts/deploy.ps1` | Sertifikatgenerering fjernet; secret opprettes kun ved `enableSensitivity`; ny `AssignUamiPermissions`; `CreateAutomationRoleAssignments` flyttet til bicep; `uamiName` sendes til alle maler. |
| `Source/Scripts/parameters.template.json` | `createSelfSignedCert`, `certName`, `certValidityDays` fjernet; `uamiName` lagt til. |
| `Source/Scripts/renew-certificate.ps1`, `Renewing-certificate.md` | Slettet (ingen sertifikater å fornye lenger). |
| `Source/Scripts/AssignPermissionsToManagedIdentity.ps1` | Utvidet med `-Scopes` og `-IncludeSharePointSitesFullControl` for manuell reparasjon/tildeling. |

## Oppgradering av eksisterende installasjoner

Migreringen krever **én full kjøring av `deploy.ps1`** (vanlig upgrade-modus `-Upgrade` er ikke nok, siden den hopper over bicep og API-tilkoblinger). Utføres av en konto med Owner på ressursgruppen, SharePoint Administrator, og rettigheter til å tildele app-roller (Global Administrator, ev. Privileged Role Administrator + Cloud Application Administrator).

1. Oppdater `parameters.json`: fjern `createSelfSignedCert`, `certName` og `certValidityDays`; legg ev. til `uamiName`.
2. Kjør `./deploy.ps1` (ev. med `-SkipSharepointSite -SkipSPFxDeploy` hvis bare Azure-ressursene skal migreres). Dette:
   - oppretter managed identityen og skriver om Key Vault access policies (**merk:** manuelt tildelte policies på Key Vault-en overskrives — kjent oppførsel, se installasjonsveiledningen),
   - tildeler RBAC- og app-roller til managed identityen,
   - redeployer API-tilkoblingene (KV/Automation går over til managed identity) og alle Logic Apps.
3. **Re-autoriser** de delegerte API-tilkoblingene `bestillingsportalen-spo`, `-o365`, `-o365users` og `-teams` med tjenestekontoen (redeploy av tilkoblingsressursene kan nullstille eksisterende autorisering).
4. Verifiser (se sjekklisten nedenfor). Får du `403 Authorization_RequestDenied` rett etter migreringen: managed identity-tokens caches i opptil ~24 timer, og nye app-roller kan bruke litt tid på å propagere — vent og prøv igjen før du feilsøker videre.
5. Opprydding etter en periode med stabil drift:
   - Fjern rolletildelingene «Automation Job Operator»/«Automation Runbook Operator» for den *gamle* app-service-principalen på `bestillingsportalen-auto`.
   - Slett sertifikatet fra Key Vault og fra app registration.
   - (Fase 2) Fjern application-tillatelsene fra app registration, behold kun delegert `Group.ReadWrite.All` hvis sensitivitetsmerker brukes. Brukes ikke sensitivitetsmerker kan hele app registration slettes.
   - Ble miljøet migrert med et eldre rollesett på UAMI-en: fjern `Directory.ReadWrite.All` og Graph `Sites.FullControl.All` fra UAMI-en manuelt i Entra-portalen (erstattet av `GroupSettings.ReadWrite.All` og `Sites.Read.All`; `deploy.ps1` tildeler kun manglende roller og fjerner aldri gamle).

> **Merk:** Hvis `enableSensitivity` er aktivert kjører `az ad app credential reset` (uten `--append`) under deploy — den fjerner appens eksisterende credentials, inkludert det gamle sertifikatet. Det er ønsket her, men vær oppmerksom hvis app registration deles med andre løsninger.

### Rollback

Alle malene er deklarative: redeploy forrige git-revisjon med den gamle `deploy.ps1` (som gjenoppretter secret + sertifikat) for å gå tilbake.

## Verifikasjonssjekkliste

1. UAMI finnes i ressursgruppen, har Key Vault-policy, to RBAC-roller på Automation Account, 9 Graph-app-roller + 1 SharePoint-app-rolle (sjekk under *Enterprise applications* eller via `Get-MgServicePrincipalAppRoleAssignment`).
2. Kjør de tilbakevendende Logic Apps manuelt: `GetHubSites` (SharePoint REST), `SyncLabels`/`SyncGroupSettings`/`GetTeamsTemplates` (Graph), `GetSiteTemplates` (Automation-connector + runbook).
3. Send en testbestilling ende-til-ende via webdelen (dekker `ProcessProvisionRequest` inkl. Automation- og KV-tilkoblingene).
4. Test gjesteinvitasjon (dekker `ProcessGuestRequest`/`ProcessGuests` + `AddGuestToSite`-runbooken).
5. Hvis sensitivitetsmerker er aktivert: verifiser at merket faktisk settes på en ny gruppe. Merkingen gjøres nå i `ConfigureSpace`-runbooken — sjekk jobbloggen for `Label confirmed on group ...`.

## Restrisiko og åpne punkter

- **Designer-roundtrip:** Åpnes en Logic App i designeren og eksporteres tilbake til ARM-malene, blir `[variables('uamiId')]` til en hardkodet ressurs-ID. Behold ARM-uttrykkene ved manuell redigering av malene.
- **Token-caching:** Managed identity-tokens caches (opptil ~24 t). Nye/endrede app-roller slår ikke inn umiddelbart.
- **Graph-begrensningen for sensitivitetsmerker:** Sjekk jevnlig om `assignedLabels` har fått støtte for application permissions — da kan ROPC-flyten, tjenestekonto-secretene og client secret-en fjernes helt. **Sist verifisert august 2026: begrensningen står fortsatt**, også med `Group.ManageProtection.All` (finnes som app-rolle, men er delegated-only for denne egenskapen). ROPC-flyten er flyttet fra Logic App-en til `ConfigureSpace`-runbooken, som først forsøker en app-only-vei — se [Sensitivitetsmerker](Sensitivity-labels.md) for hvordan du avgjør om tjenestekontoen kan fjernes i din tenant.
