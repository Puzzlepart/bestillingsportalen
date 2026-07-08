# Teknisk løsningsbeskrivelse

Dette dokumentet gir en samlet teknisk beskrivelse av Bestillingsportalen: hvilke komponenter som settes opp og installeres, hvilke tilganger som kreves for å gjennomføre installasjonen, og hvilke tilganger løsningen bruker når den er i drift.

Dokumentet er ment som et supplement til [Installasjonsveiledningen](./Deployment-guide.md), [Arkitektur](./Architecture.md) og [Datatilgang og sikkerhet](./Data-access-security.md), og kan brukes som underlag for sikkerhetsvurdering og godkjenning hos kunde før installasjon.

## 1. Overordnet arkitektur

Bestillingsportalen er en Azure-basert løsning for styrt selvbetjening av samarbeidsområder i Microsoft 365 (Teams, Microsoft 365-grupper, SharePoint-områder og Viva Engage-fellesskap). Brukere bestiller områder via en SPFx-basert webdel/Teams-app. Bestillingene lagres i en SharePoint-liste, godkjennes via Power Automate, og provisjoneres automatisk av Azure Logic Apps, Microsoft Graph/SharePoint REST API og Azure Automation-runbooks.

I tillegg inneholder løsningen en frittstående **gjesteinvitasjonsflyt**: en egen SPFx-webdel (`InviteGuests`) lar brukere invitere eksterne gjester til et eksisterende område. Invitasjonene lagres i `Guest Requests`-listen og prosesseres av Logic Apps og en Automation-runbook.

``` mermaid
graph TD
    A(SPFx Webdel / Teams App) --> |Bestilling| B[(SharePoint-liste: Provisioning Requests)]
    B --> C(Power Automate: Provisioning Request Approval)
    C --> D(Logic App: ProcessProvisionRequest)
    D --> E(Entra ID App)
    E <--> |Secret i Key Vault| F(Azure Key Vault)
    E --> |SharePoint Site| H[SharePoint REST API]
    E --> |Microsoft 365 Group / Team / Viva Engage| I(Microsoft Graph)
    D --> K(Azure Automation: ConfigureSpace)
    K --> |Managed Identity + PnP PowerShell| M(Provisjonert område)
    N(InviteGuests SPFx-webdel) --> |Gjesteforespørsel| O[(SharePoint-liste: Guest Requests)]
    O --> P(Logic App: ProcessGuestRequest) --> Q(Logic App: ProcessGuests) --> I
    P --> R(Azure Automation: AddGuestToSite) --> M
```

Hovedprinsipper:

- Provisjoneringen kjører med **Application Permissions** via en dedikert Entra ID app registration. Eneste unntak er anvendelse av sensitivitetsmerker, som (grunnet en begrensning i Graph API) bruker delegert tilgang via en tjenestekonto.
- **Client ID** og **client secret** for Entra ID-appen lagres i en dedikert Azure Key Vault og hentes av Logic Apps ved kjøring (input/output skjules i kjørehistorikken). Et **sertifikat** brukes til klientsertifikat-autentisering fra Logic Apps mot Microsoft Graph og SharePoint REST API.
- Konfigurasjon som ikke kan gjøres via Graph API utføres av runbooks i Azure Automation (`ConfigureSpace`, `AddGuestToSite`, `GetSiteTemplates`), som autentiserer med Automation-kontoens **systemtildelte managed identity** og PnP PowerShell.
- E-post- og Teams-varsler sendes i konteksten til en **tjenestekonto** (standard lisensiert bruker, ikke admin) via autoriserte API-tilkoblinger.

## 2. Hva som settes opp og installeres

Installasjonen utføres av to PowerShell-skript fra en administrators arbeidsstasjon: `createentraidapp.ps1` (oppretter Entra ID-appen) og `deploy.ps1` (alt annet, inkludert bygg og publisering av SPFx-pakkene). Følgende komponenter etableres:

### 2.1 SharePoint Online

| Komponent | Beskrivelse |
|--|--|
| SharePoint-område | Et gruppetilknyttet Team Site (navn fra `requestsSiteName` i `parameters.json`) som utgjør backend for løsningen. Tjenestekontoen settes som eier og site collection-administrator. |
| Lister og biblioteker | PnP-provisjoneringsmal (`Bestillingsportalen.xml`) oppretter listene `Provisioning Requests`, `Guest Requests`, `Provisioning Request Settings`, `Provisioning Types`, `Site Templates`, `Teams Templates`, `Hub Sites`, `Business Units`, `IP Labels`, `Retention Labels`, `Time Zones`, `Locales` samt dokumentbiblioteket `PnP Templates`. Se [Datalagre](./Data-stores.md) for full beskrivelse. |
| Standardinnhold | Listeelementer (innstillinger, områdetyper, Teams-maler, tidssoner, språk) populeres fra `Source/Settings/SharePoint List items.xlsx`. Bilder og ikoner lastes opp til `SiteAssets`. |
| SPFx-pakke i app-katalogen | `deploy.ps1` bygger SPFx-løsningene under `Source/SharePointFramework/` (npm) og publiserer dem tenant-wide i tenantens App Catalog (`Add-PnPApp -Overwrite -Publish`). Per i dag gjelder dette `bp-provision-web-parts.sppkg` med `InviteGuests`-webdelen. Kan hoppes over med `-SkipSPFxDeploy`. |

### 2.2 Microsoft Entra ID

| Komponent | Beskrivelse |
|--|--|
| App registration | Entra ID-app (navn fra `appName`, f.eks. `Bestillingsportalen`) opprettes av `createentraidapp.ps1` med API-tillatelsene beskrevet i kapittel 4.1. Admin consent gis som del av skriptet. |
| Client secret | `deploy.ps1` genererer en client secret for appen. Standard gyldighet er **1 år** – se [Fornye App Secret](./Refreshing-app-secret.md) for fornyelsesprosessen. Brukes av Key Vault- og Azure Automation-tilkoblingene samt ROPC-flyten for sensitivitetsmerker. |
| Sertifikat | Et sertifikat (self-signed generert av skriptet, eller eget) legges på app-registreringen og i Key Vault. Brukes til klientsertifikat-autentisering mot Microsoft Graph og SharePoint REST API fra Logic Apps. Standard gyldighet 900 dager (`certValidityDays`). |
| SharePoint add-in-registrering | Entra ID-appen registreres i tillegg som SharePoint add-in med Full Control mot SharePoint-tenanten (kreves for å sjekke om områder finnes, inkludert i papirkurven). |

### 2.3 Azure (egen ressursgruppe)

Alle Azure-ressurser opprettes i en ny, dedikert ressursgruppe (navn fra `resourceGroupName`) i valgt region (f.eks. `norwayeast`):

| Ressurs | Beskrivelse |
|--|--|
| Azure Key Vault | Standard SKU. Lagrer secrets: `appid` (app-ID), `appSecret` (client secret), `sausername`/`sapassword` (tjenestekontoens påloggingsinfo – kun ved aktivert sensitivitetsmerke-funksjonalitet), samt app-sertifikatet ved self-signed generering. Vi anbefaler en dedikert Key Vault for løsningen. |
| Azure Automation-konto | `bestillingsportalen-auto` (Free SKU) med **systemtildelt managed identity**. Inneholder PowerShell 7.2-modulene `Az.Accounts` og `PnP.PowerShell`, runbookene `ConfigureSpace` (etterkonfigurasjon av provisjonerte områder), `AddGuestToSite` (legger gjester til M365-gruppe/SharePoint-grupper) og `GetSiteTemplates`, samt variablene `tenantId` og `logoUrl`. **Merk:** Inntil dette repoet er offentlig peker runbook-malene på upstream-repoet/plassholder-URI-er – innholdet i `ConfigureSpace` og `AddGuestToSite` må limes inn manuelt fra `Source/Runbooks/` etter første installasjon (se installasjonsveiledningen). |
| Logic Apps (9 stk.) | `ProcessProvisionRequest` (hovedmotor – provisjonerer godkjente bestillinger), `ProcessGuestRequest` (trigges av nye elementer i `Guest Requests`-listen, kaller `ProcessGuests` og `AddGuestToSite`-runbooken), `ProcessGuests` (inviterer gjestebrukere via Graph), `CheckSiteExists` (sjekker om område/URL finnes, inkl. papirkurv), `GetHubSites`, `GetSiteTemplates`, `GetTeamsTemplates`, `SyncGroupSettings` og `SyncLabels` (synkroniserer hhv. hub-områder, site-maler, Teams-maler, gruppeinnstillinger og sensitivitetsmerker fra tenanten til SharePoint-listene; kjører ukentlig som standard). |
| API-tilkoblinger (6 stk.) | `bestillingsportalen-spo` (SharePoint Online), `bestillingsportalen-o365` (Office 365 Outlook), `bestillingsportalen-o365users` (Office 365 Users) og `bestillingsportalen-teams` (Microsoft Teams) autoriseres manuelt med tjenestekontoen etter installasjon. `bestillingsportalen-kv` (Key Vault) og `bestillingsportalen-automation` (Azure Automation) autentiserer med Entra ID-appens client secret. |

### 2.4 Power Automate

To flyter leveres med løsningen og kjører i tjenestekontoens kontekst:

- **Provisioning Request Approval** – godkjenningsprosessen. Trigges når en bestilling i `Provisioning Requests`-listen får status `Submitted`. Støtter godkjenning via Power Automate Approvals eller adaptive cards i en Teams-kanal. Er avslått som standard og må aktiveres etter installasjon. Se [Godkjenningsflyt](./Approval-flow.md).
- **Check Space Availability** – sjekker om et område med samme navn/URL allerede finnes (mot Microsoft 365-grupper og `Provisioning Requests`-listen) før en bestilling kan sendes inn.

Flytene bruker seeded Power Automate-lisenser og krever ikke premium-lisensiering.

### 2.5 Klient (SPFx)

- **Bestillingsportalen webdel / Teams-app** – hovedgrensesnittet der brukere bestiller samarbeidsområder. Leser/skriver mot SharePoint-listene i brukerens egen sikkerhetskontekst. Distribueres separat og inngår ikke i dette repoet.
- **`InviteGuests`-webdel** (`ProvisionWebParts`-løsningen i dette repoet) – lar brukere invitere eksterne gjester til et eksisterende område. Bygges og publiseres tenant-wide av `deploy.ps1`, og kan deretter legges til på en hvilken som helst side. Webdelen skriver gjesteforespørsler til `Guest Requests`-listen i brukerens egen kontekst (konfigureres via `guestRequestSiteUrl` i property pane).

## 3. Tilganger som kreves for installasjon

### 3.1 Roller og kontoer

| Konto/rolle | Brukes til | Kommentar |
|--|--|--|
| **Global Administrator** | Kjøre `createentraidapp.ps1` (oppretter Entra ID-appen og gir admin consent for API-tillatelsene), samt opprette/godkjenne PnP PowerShell app registration. | Kun nødvendig under installasjon. |
| **Owner på Azure-abonnementet** | Kjøre `deploy.ps1`: opprette ressursgruppe, Key Vault, Automation-konto, Logic Apps og API-tilkoblinger, samt tildele Azure RBAC-roller (`Automation Job Operator`/`Automation Runbook Operator`) til appens service principal. | Abonnementet MÅ tilhøre samme Entra ID-tenant som Microsoft 365. |
| **SharePoint Administrator** | Opprette og konfigurere SharePoint-området og publisere SPFx-pakker til App Catalog under `deploy.ps1`. | Samme konto som over (kontoen som kjører `deploy.ps1` bør også være Power Platform- og Teams-administrator). |
| Rettighet til å opprette app secrets | `deploy.ps1` genererer secret for Entra ID-appen. | Rollen **Cloud Application Administrator** er tilstrekkelig dersom kontoen ikke er Global Administrator. |
| Rettighet til å tildele app-roller til managed identity | Tildele Graph- og SharePoint-app-roller til Automation-kontoens systemtildelte managed identity (gjøres av `deploy.ps1`, ev. `AssignPermissionsToManagedIdentity.ps1`). | Krever delegerte Graph-tilganger som `AppRoleAssignment.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`, `Application.ReadWrite.All`, `DelegatedPermissionGrant.ReadWrite.All` og `Directory.Read.All` – i praksis Global Administrator eller Privileged Role Administrator. |

### 3.2 PnP PowerShell app registration (midlertidig installasjonsidentitet)

Installasjonsskriptet bruker PnP PowerShell med en egen app registration (sertifikatbasert autentisering) for å opprette og konfigurere SharePoint-området og publisere SPFx-pakkene. Minimumstilganger:

| API | Tillatelse | Type |
|--|--|--|
| Microsoft Graph | `Group.Create` | Application |
| Microsoft Graph | `Group.Read.All` | Application |
| SharePoint | `Sites.FullControl.All` | Application |

Denne app-registreringen kan **slettes, eller tilgangene fjernes, etter fullført installasjon**. Hvis `Sites.FullControl.All` ikke er ønskelig, kan SharePoint-området opprettes manuelt på forhånd.

### 3.3 Tjenestekonto

- Standard Microsoft 365-brukerkonto med lisens for SharePoint Online, Exchange Online og Teams. Skal **ikke** være administrator. Kan ha MFA.
- Brukes under installasjon til å autorisere API-tilkoblingene `bestillingsportalen-o365`, `bestillingsportalen-o365users`, `bestillingsportalen-spo` og `bestillingsportalen-teams`.
- Ved bruk av sensitivitetsmerke-funksjonaliteten kreves en tjenestekonto **uten MFA** (kan være samme konto), siden Graph-endepunktet for merking kun støtter delegert tilgang. Kontoens brukernavn/passord lagres da kryptert i Key Vault. Verifiser mot gjeldende Graph-dokumentasjon om begrensningen fortsatt gjelder.

### 3.4 Arbeidsstasjon, tenant og nettverk

- Windows 10/11 med PowerShell 7 og Azure CLI installert.
- Node.js 22.14.0 eller nyere (kun nødvendig for SPFx-bygg; kan hoppes over med `-SkipSPFxDeploy`).
- PowerShell-moduler: `PnP.PowerShell` (3.1), `Az`, `ImportExcel`, `WriteAscii`.
- Tenant App Catalog må være opprettet i SharePoint Admin Center (for publisering av SPFx-pakker).
- Execution Policy satt til `Unrestricted` under installasjonen.
- Brannmur/proxy må tillate utgående tilkobling for Azure CLI (`az login`) og PowerShell-modulene mot Azure/Microsoft 365.

## 4. Tilganger for løsningen i drift

### 4.1 Entra ID-appen (Bestillingsportalen)

Appen brukes av Logic Apps (via secret/sertifikat hentet fra Key Vault) til provisjonering og synkronisering.

**Microsoft Graph:**

| API-tillatelse | Type | Brukes til |
|--|--|--|
| `Directory.Read.All` | Application | Lese brukere, grupper og team fra tenanten. |
| `Directory.ReadWrite.All` | Application | Opprette gjestebrukere i Entra ID (hvis forespurt). |
| `Group.ReadWrite.All` | Application | Opprette og oppdatere Microsoft 365-grupper og team. |
| `Group.ReadWrite.All` | Delegated | Anvende sensitivitetsmerker på grupper/team (via tjenestekontoen). |
| `InformationProtectionPolicy.Read.All` | Application | Synkronisere sensitivitetsmerker fra Purview til `IP Labels`-listen. |
| `Sites.FullControl.All` | Application | Oppdatere egenskaper på provisjonerte SharePoint-områder. |
| `TeamsTemplates.Read.All` | Application | Lese Teams-maler og synkronisere dem til `Teams Templates`-listen. |
| `Community.ReadWrite.All` | Application | Opprette Viva Engage-fellesskap. |
| `User.Invite.All` | Application | Invitere gjestebrukere til organisasjonen. |
| `User.ReadWrite.All` | Application | Oppdatere gjestebrukere i Entra ID. |

**SharePoint:**

| API-tillatelse | Type | Brukes til |
|--|--|--|
| `Sites.FullControl.All` | Application | Lese og skrive til opprettede SharePoint-områder via SharePoint REST API. |

I tillegg er appen registrert som **SharePoint add-in med Full Control** mot SharePoint-tenanten (for å kunne sjekke om områder finnes, inkludert i papirkurven).

**Azure RBAC og Key Vault:**

| Tilgang | Omfang | Brukes til |
|--|--|--|
| `Automation Job Operator` | Automation-kontoen `bestillingsportalen-auto` | Starte runbook-jobber fra Logic Apps. |
| `Automation Runbook Operator` | Automation-kontoen `bestillingsportalen-auto` | Lese/operere på runbooks. |
| Key Vault access policy: secrets `get`/`list`, keys `get` | Løsningens Key Vault | Hente app-ID, secret og sertifikat ved kjøring. |

### 4.2 Managed identity (Azure Automation)

Runbookene `ConfigureSpace`, `AddGuestToSite` og `GetSiteTemplates` autentiserer med Automation-kontoens systemtildelte managed identity (PnP PowerShell `-ManagedIdentity`) og utfører oppgaver Graph API ikke dekker (PnP-maler, temaer, hub-tilknytning, tilgangsgrupper, gjestemedlemskap m.m.):

| API | Tillatelse | Type |
|--|--|--|
| Microsoft Graph | `Group.ReadWrite.All` | Application |
| SharePoint (Office 365 SharePoint Online) | `Sites.FullControl.All` («Have full control of all site collections») | Application |

### 4.3 Tjenestekontoen

| Tilgang | Brukes til |
|--|--|
| Identitet bak API-tilkoblingene (Outlook, Users, SharePoint, Teams) | Sende e-postvarsler, lese brukerprofiler, lese/skrive i SharePoint-listene og poste adaptive cards i Teams – i delegert kontekst fra Logic Apps og flytene. |
| Eier/site collection-administrator på Bestillingsportalen-området | Drift av backend-listene. |
| Eier av Power Automate-flytene | Flytene `Provisioning Request Approval` og `Check Space Availability` kjører i tjenestekontoens kontekst. |
| Medlem av godkjennings-teamet i Teams | Kreves kun ved bruk av adaptive card-godkjenning, for å kunne poste kort i kanalen. |
| Delegert Graph-tilgang via Entra ID-appen (uten MFA) | Kun ved aktivert sensitivitetsmerke-funksjonalitet. |

### 4.4 Sluttbrukere og administratorer

| Hvem | Tilgang | Kommentar |
|--|--|--|
| Sluttbrukere (bestillere) | Lesetilgang (`Visitors`) til Bestillingsportalen-området, samt `Edit` på `Provisioning Requests`-listen (brutt tilgangsarv). | Gir mulighet til å opprette og følge egne bestillinger via webdel/Teams-app. Ingen Azure-tilgang nødvendig. |
| Brukere av `InviteGuests`-webdelen | Skrivetilgang til `Guest Requests`-listen på Bestillingsportalen-området. | Webdelen oppretter og leser listeelementer i brukerens egen kontekst (PnPjs). |
| Godkjennere | Mottar godkjenningsoppgaver (Approvals) eller er medlem av godkjennings-teamet i Teams. | Konfigureres via `ApproverEmail`/`PostToTeams` i innstillingslisten. |
| Administratorer av løsningen | Medlemskap i administratorgruppen (`AdminGroupId` i innstillingslisten); flytene kan i tillegg deles med dem for innsyn i kjøringer. | Innstillingsskjermen i appen vises kun for medlemmer av denne gruppen. |

## 5. Hemmeligheter og sertifikater – livssyklus

| Element | Lagres i | Standard gyldighet | Fornyelse |
|--|--|--|--|
| Client secret (Entra ID-app) | Key Vault (`appSecret`), Key Vault API-tilkoblingen og kryptert Automation-variabel | 1 år | Se [Fornye App Secret](./Refreshing-app-secret.md) – Logic Apps og runbooks feiler når secret er utløpt. |
| App-sertifikat (Graph/SPO REST-autentisering) | Key Vault og app-registreringen | 900 dager (`certValidityDays`) | Generer/last opp nytt sertifikat, se `Source/Scripts/renew-certificate.ps1`. |
| Tjenestekonto-påloggingsinfo | Key Vault (`sausername`/`sapassword`) | Følger organisasjonens passordpolicy | Kun ved aktivert sensitivitetsmerke-funksjonalitet. |
| PnP-installasjonssertifikat | Lokalt hos den som installerer | – | Brukes kun under installasjon/oppgradering; app-registreringen kan fjernes etterpå. |

## 6. Referanser

- [Installasjonsveiledning](./Deployment-guide.md) – steg-for-steg-installasjon
- [Arkitektur](./Architecture.md) – arkitekturdiagrammer (provisjonering og gjesteinvitasjon)
- [Datatilgang og sikkerhet](./Data-access-security.md) – detaljert tilgangsbeskrivelse
- [Datalagre](./Data-stores.md) – alle SharePoint-lister og felter
- [Godkjenningsflyt](./Approval-flow.md) – godkjenningsprosessen
- [Oppgraderingsveiledning](./Upgrade.md) – oppgradering uten datatap
- [Kostnadsestimater](./Cost-estimates.md) – estimert Azure-kostnad
- [Fornye App Secret](./Refreshing-app-secret.md) – fornyelse av secret
