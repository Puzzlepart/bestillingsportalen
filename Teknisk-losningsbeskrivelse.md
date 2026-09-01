# Teknisk løsningsbeskrivelse

Dette dokumentet gir en samlet teknisk beskrivelse av Bestillingsportalen: hvilke komponenter som settes opp og installeres, hvilke tilganger som kreves for å gjennomføre installasjonen, og hvilke tilganger løsningen bruker når den er i drift.

Dokumentet er ment som et supplement til [Installasjonsveiledningen](./Deployment-guide.md) og [Datatilgang og sikkerhet](./Data-access-security.md), og kan brukes som underlag for sikkerhetsvurdering og godkjenning hos kunde før installasjon.

> **Merk:** Beskrivelsen gjelder gjeldende versjon av løsningen, der Logic Apps autentiserer med **user-assigned managed identity**. Eldre installasjoner som bruker client secret/sertifikat må oppgraderes – se [Oppgraderingsveiledningen](./Upgrade.md).

## 1. Overordnet arkitektur

Bestillingsportalen er en Azure-basert løsning for styrt selvbetjening av samarbeidsområder i Microsoft 365 (Teams, Microsoft 365-grupper, SharePoint-områder og Viva Engage-fellesskap). Brukere bestiller områder via en SPFx-basert webdel/Teams-app. Bestillingene lagres i en SharePoint-liste, godkjennes via Power Automate, og provisjoneres automatisk av Azure Logic Apps, Microsoft Graph/SharePoint REST API og Azure Automation-runbooks.

I tillegg inneholder løsningen en frittstående **gjesteinvitasjonsflyt**: en egen SPFx-webdel (`InviteGuests`) lar brukere invitere eksterne gjester til et eksisterende område. Invitasjonene lagres i `Guest Requests`-listen og prosesseres av Logic Apps og en Automation-runbook.

``` mermaid
graph TD
    A(SPFx Webdel / Teams App) --> |Bestilling| B[(SharePoint-liste: Provisioning Requests)]
    B --> C(Power Automate: Provisioning Request Approval)
    C --> D(Logic App: ProcessProvisionRequest)
    D --> E(User-assigned Managed Identity)
    E --> |SharePoint Site| H[SharePoint REST API]
    E --> |Microsoft 365 Group / Team / Viva Engage| I(Microsoft Graph)
    D --> K(Azure Automation: ConfigureSpace)
    K --> |System-assigned MI + PnP PowerShell| M(Provisjonert område)
    N(InviteGuests SPFx-webdel) --> |Gjesteforespørsel| O[(SharePoint-liste: Guest Requests)]
    O --> P(Logic App: ProcessGuestRequest) --> Q(Logic App: ProcessGuests) --> I
    P --> R(Azure Automation: AddGuestToSite) --> M
```

Gjesteinvitasjonsflyten i detalj — hver invitasjon kan i tillegg til selve tenant-invitasjonen gi gjesten rollen **Gjest** (gjestemedlemskap i M365-gruppen, standardmodellen for eksterne i Microsoft 365 — gir tilgang til team, område, Planner osv.) og/eller medlemskap i en valgfri SharePoint-brukergruppe på selve siten. Eksterne kan aldri bli eiere — webdelen tilbyr ikke valget, og `AddGuestToSite`-runbooken avviser verdien. Er installasjonsparameteren `guestEntraGroup` konfigurert, legges hver gjest i tillegg inn i en felles Entra ID-gruppe for gjester — slik at organisasjonen kan gi alle gjester grunntilgang (f.eks. lesetilgang på hub-området og app-katalogen) ett sted. Uavhengig av dette registreres alltid **bestilleren som gjestens sponsor** i Entra ID, slik at det er dokumentert hvem i organisasjonen som står bak hver eksterne bruker:

``` mermaid
graph TD
    A(InviteGuests SPFx-webdel) --> | Read M365 group status + SP groups | A2(Gjeldende SP-site)
    A --> | Write item per guest with M365GroupRole, SPGroupAction, SPGroupName, SPPermissionLevel | B[("Guest Requests SharePoint-liste")]
    B --> |"When an item is created (1 min poll)"| C(ProcessGuestRequest Logic App)
    C --> | Workflow action | D(ProcessGuests Logic App)
    D --> E(Microsoft Graph /invitations API) --> F(Guest user in Entra ID)
    D --> |"POST /users/{id}/sponsors/$ref (bestilleren som sponsor)"| F
    D --> | Status, GuestId, InviteRedeemUrl | B
    C --> | After successful invite, with guest + group params | G(AddGuestToSite runbook)
    G --> | Managed Identity | H(PnP PowerShell)
    H --> | Add-PnPMicrosoft365GroupMember | I2(M365-gruppen på siten)
    H --> | Add-PnPGroupMember / New-PnPGroup | J2(SP-brukergruppe på siten)
    H --> |"POST /groups/{id}/members/$ref (valgfritt, guestEntraGroup)"| K2(Felles Entra-gruppe for gjester)
    A --> | DataGrid view filtered by SiteUrl | B
```

Hovedprinsipper:

- Provisjoneringen kjører med **Application Permissions** via en delt **user-assigned managed identity** (`bestillingsportalen-uami`) som er koblet til alle Logic Apps og brukes mot Microsoft Graph, SharePoint REST og Azure Automation. Det finnes dermed **ingen client secret eller sertifikat å rotere**.
- **Det finnes ingen unntak:** løsningen har ingen client secret, ingen Key Vault og ingen egen Entra ID-app-registrering i drift. Også sensitivitetsmerker settes app-only – `ConfigureSpace` bruker `Set-PnPTenantSite -SensitivityLabel` med Automation-kontoens managed identity, som via SharePoints tenant-admin-API propagerer container-merket til gruppen. Runbooken leser tilbake `assignedLabels` for å bekrefte at merket landet. Se [Sensitivitetsmerker](./Sensitivity-labels.md).
- Konfigurasjon som ikke kan gjøres via Graph API utføres av runbooks i Azure Automation (`ConfigureSpace`, `AddGuestToSite`, `GetSiteTemplates` samt det kundeeide utvidelsespunktet `CustomerSpecific`), som autentiserer med Automation-kontoens **systemtildelte managed identity** og PnP PowerShell.
- E-post- og Teams-varsler sendes i konteksten til en **tjenestekonto** (standard lisensiert bruker, ikke admin) via autoriserte API-tilkoblinger – disse connectorene er delegated-only og støtter ikke managed identity.

## 2. Hva som settes opp og installeres

Installasjonen utføres i sin helhet fra en administrators arbeidsstasjon med `deploy.ps1` (inkludert bygg og publisering av SPFx-pakkene). Følgende komponenter etableres:

### 2.1 SharePoint Online

| Komponent | Beskrivelse |
|--|--|
| SharePoint-område | Et gruppetilknyttet Team Site (navn fra `requestsSiteName` i `parameters.json`) som utgjør backend for løsningen. Tjenestekontoen settes som eier og site collection-administrator. |
| Lister og biblioteker | PnP-provisjoneringsmal (`Bestillingsportalen.xml`) oppretter listene `Provisioning Requests`, `Guest Requests`, `Provisioning Request Settings`, `Provisioning Types`, `Site Templates`, `Teams Templates`, `Hub Sites`, `Business Units`, `IP Labels`, `Retention Labels`, `Time Zones`, `Locales` samt dokumentbiblioteket `PnP Templates`. Se [Datalagre](./Data-stores.md) for full beskrivelse. |
| Standardinnhold | Listeelementer (innstillinger, områdetyper, Teams-maler, tidssoner, språk) seedes av `<pnp:DataRows>`-blokker i PnP-malen (`Source/Templates/Objects/Lists/*.xml`) med `UpdateBehavior="Skip"`: eksisterende elementer røres aldri, manglende standardelementer legges til ved re-apply. Bilder og ikoner lastes opp til `SiteAssets`. |
| SPFx-pakke i app-katalogen | `deploy.ps1` bygger SPFx-løsningene under `Source/SharePointFramework/` (npm) og publiserer dem tenant-wide i tenantens App Catalog (`Add-PnPApp -Overwrite -Publish`). Per i dag gjelder dette `bp-provision-web-parts.sppkg` med `InviteGuests`-webdelen. Kan hoppes over med `-SkipSPFxDeploy`. |

### 2.2 Microsoft Entra ID

| Komponent | Beskrivelse |
|--|--|
| Service principals for managed identities | Den user-assigned managed identityen og Automation-kontoens systemtildelte identitet får app-roller tildelt i Entra ID (se kapittel 4). |

Løsningen oppretter **ingen egen app-registrering**. Den eneste som er involvert er PnP PowerShell-appen (`pnpAppId`), og den brukes bare under installasjon med interaktiv pålogging. Det brukes verken sertifikat eller client secret for Graph-/SharePoint-autentisering, og ingenting trenger registreres som SharePoint add-in (ACS).

### 2.3 Azure (egen ressursgruppe)

Alle Azure-ressurser opprettes i en ny, dedikert ressursgruppe (navn fra `resourceGroupName`) i valgt region (f.eks. `norwayeast`):

| Ressurs | Beskrivelse |
|--|--|
| User-assigned managed identity | `bestillingsportalen-uami` (navn konfigurerbart via `uamiName`). Koblet til alle Logic Apps og brukt til alle HTTP-kall mot Microsoft Graph og SharePoint REST samt Automation-API-tilkoblingen. |
| Azure Automation-konto | `bestillingsportalen-auto` (Free SKU) med **systemtildelt managed identity**. Runbookene `ConfigureSpace` (etterkonfigurasjon av provisjonerte områder), `AddGuestToSite` (legger gjester til M365-gruppen, SharePoint-brukergrupper og/eller en felles Entra-gjestegruppe) og `GetSiteTemplates` kjører i et **PowerShell 7.4 runtime environment** (`bestillingsportalen-ps74`) med `PnP.PowerShell` 3.2 og Az-pakken. **Merk at portalens standard Runbooks-blad viser disse som «PowerShell 5.1»** – en [dokumentert begrensning](https://learn.microsoft.com/en-us/azure/automation/runtime-environment-overview#limitations) i den gamle opplevelsen, som ikke kjenner runtime environments over 7.2. Faktisk versjon ses under **Runtime environments**, og `deploy.ps1` verifiserer og rapporterer den ved hver kjøring. Kontoen har i tillegg variablene `tenantId` og `logoUrl`. Runbook-innholdet lastes opp fra `Source/Runbooks/` og publiseres av installasjonsskriptet — endringer gjort direkte i Azure Portal overskrives ved deploy/oppgradering. Unntaket er `CustomerSpecific`: et utvidelsespunkt som kjøres rett etter `ConfigureSpace` ved provisjonering, opprettes med tomt innhold og **aldri** overskrives — kundespesifikke tilpasninger legges der. |
| Logic Apps (9 stk.) | `ProcessProvisionRequest` (hovedmotor – provisjonerer godkjente bestillinger), `ProcessGuestRequest` (trigges av nye elementer i `Guest Requests`-listen, kaller `ProcessGuests` og `AddGuestToSite`-runbooken), `ProcessGuests` (inviterer gjestebrukere via Graph), `CheckSiteExists` (sjekker om område/URL finnes, inkl. papirkurv), `GetHubSites`, `GetSiteTemplates`, `GetTeamsTemplates`, `SyncGroupSettings` og `SyncLabels` (synkroniserer hhv. hub-områder, site-maler, Teams-maler, gruppeinnstillinger og sensitivitetsmerker fra tenanten til SharePoint-listene; kjører ukentlig som standard). |
| API-tilkoblinger (5 stk.) | `bestillingsportalen-spo` (SharePoint Online), `bestillingsportalen-o365` (Office 365 Outlook), `bestillingsportalen-o365users` (Office 365 Users) og `bestillingsportalen-teams` (Microsoft Teams) er delegated-only og autoriseres manuelt med tjenestekontoen etter installasjon. `bestillingsportalen-automation` (Azure Automation) autentiserer med den user-assigned managed identityen og krever ingen manuell autorisering. |

**Navnekonvensjon for Azure-ressursene.** Alle ressurser i gruppa følger mønsteret `bestillingsportalen-<rolle>` — arbeidsbelastning først, rollen som **suffiks**: `-uami`, `-auto`, `-ps74`, `-spo`, `-o365`, `-o365users`, `-teams`, `-automation`. Poenget er at alt som hører til løsningen sorterer sammen alfabetisk i portalen og i `az resource list`. Ressursgruppa selv er det bevisste unntaket (`rg-bestillingsportalen`): den velges i en annen liste enn ressursene i den, og der er typeforkortelsen først mer lesbar.

Dette avviker fra [Microsofts CAF-abbreviasjonsliste](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations), som anbefaler typeforkortelse som *prefiks* og bruker `id-` for user-assigned managed identity. Valget er tatt for konsistens innenfor ressursgruppa, og fordi `bestillingsportalen-id` leser som «ID-en til bestillingsportalen» heller enn som en identitetsressurs. Følger du CAF for øvrig i kundens abonnement, er det ressursgruppenavnet (`resourceGroupName`) du vil tilpasse — det er en fri parameter.

> **Ressursnavnene er billige å velge, dyre å endre.** Bare `resourceGroupName` og `uamiName` er parametre; resten er hardkodet i bicep- og ARM-malene. Endrer du `uamiName` på et miljø i drift, oppretter deploy en **ny** identitet: den gamle beholder sine app-roller og RBAC-tildelinger på Automation-kontoen og må ryddes bort manuelt, og Logic Apps kan feile med `403 Authorization_RequestDenied` til de nye app-rollene har propagert (managed identity-tokens caches i opptil ~24 timer). Sett navnene ved førstegangs installasjon og la dem stå.

### 2.4 Power Automate

Én flyt leveres med løsningen (`Source/Flows/Bestillingsportalen-Flows_unmanaged.zip` — importeres manuelt som tjenestekontoen, se Steg 2 i [Konfigurasjonsveiledningen](./Configuration-guide.md)) og kjører i tjenestekontoens kontekst:

- **Provisioning Request Approval** – godkjenningsprosessen. Trigges når en bestilling i `Provisioning Requests`-listen får status `Submitted`. Støtter godkjenning via Power Automate Approvals eller adaptive cards i en Teams-kanal. Er avslått som standard og må aktiveres etter installasjon. Se [Godkjenningsflyt](./Approval-flow.md).

Flyten bruker seeded Power Automate-lisenser og krever ikke premium-lisensiering.

### 2.5 Klient (SPFx)

- **Bestillingsportalen webdel / Teams-app** – hovedgrensesnittet der brukere bestiller samarbeidsområder. Leser/skriver mot SharePoint-listene i brukerens egen sikkerhetskontekst. Distribueres separat og inngår ikke i dette repoet.
- **`InviteGuests`-webdel** (`ProvisionWebParts`-løsningen i dette repoet) – lar brukere invitere eksterne gjester til et eksisterende område. Bygges og publiseres tenant-wide av `deploy.ps1`, og kan deretter legges til på en hvilken som helst side. Webdelen skriver gjesteforespørsler til `Guest Requests`-listen i brukerens egen kontekst (konfigureres via `guestRequestSiteUrl` i property pane).

## 3. Tilganger som kreves for installasjon

### 3.1 Roller og kontoer

| Konto/rolle | Brukes til | Kommentar |
|--|--|--|
| **Global Administrator** | Opprette/godkjenne PnP PowerShell app registration. | Kun nødvendig under installasjon. |
| **Owner på Azure-abonnementet** | Kjøre `deploy.ps1`: opprette ressursgruppe, managed identity, Automation-konto, Logic Apps og API-tilkoblinger, inkl. RBAC-tildelinger i bicep-malen. | Abonnementet MÅ tilhøre samme Entra ID-tenant som Microsoft 365. |
| **SharePoint Administrator** | Opprette og konfigurere SharePoint-området og publisere SPFx-pakker til App Catalog under `deploy.ps1`. | Samme konto som over (kontoen som kjører `deploy.ps1` bør også være Power Platform- og Teams-administrator). |
| Rettighet til å tildele app-roller til managed identities | `deploy.ps1` tildeler Graph-/SharePoint-app-roller til både den user-assigned identityen (`AssignUamiPermissions`) og Automation-kontoens systemtildelte identitet. | Krever Global Administrator, ev. Privileged Role Administrator + Cloud Application Administrator. `Source/Scripts/AssignPermissionsToManagedIdentity.ps1` kan brukes til manuell reparasjon/tildeling. |

### 3.2 PnP PowerShell app registration (midlertidig installasjonsidentitet)

Installasjonsskriptet bruker PnP PowerShell med en egen app registration for å opprette og konfigurere SharePoint-området og publisere SPFx-pakkene. Autentiseringen er **interaktiv pålogging** (delegert — ingen sertifikater eller secrets; effektive rettigheter er snittet av installatørens rettigheter og appens delegerte tilganger). Minimumstilganger:

| API | Tillatelse | Type |
|--|--|--|
| Microsoft Graph | `Group.ReadWrite.All` | Delegated |
| SharePoint | `AllSites.FullControl` | Delegated |

Denne app-registreringen kan **slettes, eller tilgangene fjernes, etter fullført installasjon**. Hvis `AllSites.FullControl` ikke er ønskelig, kan SharePoint-området opprettes manuelt på forhånd.

### 3.3 Tjenestekonto

- Standard Microsoft 365-brukerkonto med lisens for SharePoint Online, Exchange Online og Teams. Skal **ikke** være administrator. Kan ha MFA.
- Brukes under installasjon til å autorisere API-tilkoblingene `bestillingsportalen-o365`, `bestillingsportalen-o365users`, `bestillingsportalen-spo` og `bestillingsportalen-teams`.

### 3.4 Arbeidsstasjon, tenant og nettverk

- Windows 10/11 med PowerShell 7.4 (eller nyere) og Azure CLI installert.
- Node.js 22.14.0 eller nyere (kun nødvendig for SPFx-bygg; kan hoppes over med `-SkipSPFxDeploy`).
- PowerShell-moduler: `PnP.PowerShell` (3.2 eller nyere), `Az`, `WriteAscii`.
- Tenant App Catalog må være opprettet i SharePoint Admin Center (for publisering av SPFx-pakker).
- Execution Policy satt til `Unrestricted` under installasjonen.
- Brannmur/proxy må tillate utgående tilkobling for Azure CLI (`az login`) og PowerShell-modulene mot Azure/Microsoft 365.

## 4. Tilganger for løsningen i drift

### 4.1 User-assigned managed identity (Logic Apps)

Den primære kjøretidsidentiteten. Brukes av alle Logic Apps til HTTP-kall mot Microsoft Graph og SharePoint REST, samt Automation-API-tilkoblingen. Ingen secret eller sertifikat – Entra ID utsteder tokens direkte til Azure-ressursen.

**Microsoft Graph (app-roller):**

| API-tillatelse | Type | Brukes til |
|--|--|--|
| `Directory.Read.All` | Application | Lese gruppe-lifecycle-policyer (`GET /groupLifecyclePolicies`) under provisjoneringen — dokumentert minste tillatelse for dette endepunktet. |
| `GroupSettings.ReadWrite.All` | Application | Deaktivere gjestedeling per gruppe (`Group.Unified.Guest`-innstillingen) og lese gruppeinnstillinger for synkronisering. |
| `Group.ReadWrite.All` | Application | Opprette Microsoft 365-grupper og team, legge til/fjerne eiere og medlemmer. |
| `InformationProtectionPolicy.Read.All` | Application | Synkronisere sensitivitetsmerker fra Purview til `IP Labels`-listen. |
| `Sites.Read.All` | Application | `CheckSiteExists` leser tenant-admin-områdets aggregerte områdeliste (sjekke om URL er i bruk, inkl. papirkurv). |
| `TeamTemplates.Read.All` | Application | Lese Teams-maler og synkronisere dem til `Teams Templates`-listen. |
| `Community.ReadWrite.All` | Application | Opprette Viva Engage-fellesskap. |
| `User.Invite.All` | Application | Invitere gjestebrukere til organisasjonen. |
| `User.ReadWrite.All` | Application | Oppdatere profilfelter (navn/selskap) på inviterte gjestebrukere, og registrere bestilleren som gjestens sponsor. |

**SharePoint:**

| API-tillatelse | Type | Brukes til |
|--|--|--|
| `Sites.FullControl.All` | Application | Opprette områdesamlinger (`POST /_api/SPSiteManager/create`), anvende site designs på nyopprettede områder og lese hub-områder. Kan ikke erstattes av `Sites.Selected`: målområdet finnes ikke før opprettelseskallet, så det er ingenting å gi en per-site-tillatelse på. |

**Azure RBAC (tildeles av `azureresources.bicep`):**

| Tilgang | Omfang | Brukes til |
|--|--|--|
| `Automation Job Operator` | Automation-kontoen `bestillingsportalen-auto` | Starte runbook-jobber fra Logic Apps. |
| `Automation Runbook Operator` | Automation-kontoen `bestillingsportalen-auto` | Lese/operere på runbooks. |

### 4.2 Systemtildelt managed identity (Azure Automation)

Runbookene `ConfigureSpace`, `AddGuestToSite`, `GetSiteTemplates` og `CustomerSpecific` (kundeeid utvidelsespunkt) autentiserer med Automation-kontoens systemtildelte managed identity (PnP PowerShell `-ManagedIdentity`) og utfører oppgaver Graph API ikke dekker (PnP-maler, temaer, hub-tilknytning, tilgangsgrupper, gjestemedlemskap m.m.):

| API | Tillatelse | Type |
|--|--|--|
| Microsoft Graph | `Group.ReadWrite.All` | Application |
| Microsoft Graph | `User.Read.All` (kreves av `AddGuestToSite` for å slå opp gjestebrukere) | Application |
| SharePoint (Office 365 SharePoint Online) | `Sites.FullControl.All` («Have full control of all site collections») | Application |

### 4.3 Tjenestekontoen

| Tilgang | Brukes til |
|--|--|
| Identitet bak de delegerte API-tilkoblingene (Outlook, Users, SharePoint, Teams) | Sende e-postvarsler, lese brukerprofiler, lese/skrive i SharePoint-listene og poste adaptive cards i Teams – i delegert kontekst fra Logic Apps og flytene. Connectorene støtter ikke managed identity. |
| Eier/site collection-administrator på Bestillingsportalen-området | Drift av backend-listene. |
| Eier av Power Automate-flyten | Flyten `Provisioning Request Approval` kjører i tjenestekontoens kontekst. |
| Medlem av godkjennings-teamet i Teams | Kreves kun ved bruk av adaptive card-godkjenning, for å kunne poste kort i kanalen. |

### 4.4 Sluttbrukere og administratorer

| Hvem | Tilgang | Kommentar |
|--|--|--|
| Sluttbrukere (bestillere) | Lesetilgang (`Visitors`) til Bestillingsportalen-området, samt `Edit` på `Provisioning Requests`-listen (brutt tilgangsarv). | Gir mulighet til å opprette og følge egne bestillinger via webdel/Teams-app. Ingen Azure-tilgang nødvendig. |
| Brukere av `InviteGuests`-webdelen | Skrivetilgang til `Guest Requests`-listen på Bestillingsportalen-området. | Webdelen oppretter og leser listeelementer i brukerens egen kontekst (PnPjs). |
| Godkjennere | Mottar godkjenningsoppgaver (Approvals) eller er medlem av godkjennings-teamet i Teams. | Konfigureres via `ApproverEmail`/`PostToTeams` i innstillingslisten. |
| Administratorer av løsningen | Medlemskap i administratorgruppen (`AdminGroupId` i innstillingslisten); flytene kan i tillegg deles med dem for innsyn i kjøringer. | Innstillingsskjermen i appen vises kun for medlemmer av denne gruppen. |

## 5. Hemmeligheter – livssyklus

**Løsningen har ingen hemmeligheter i drift.** Alt autentiserer med managed identity, som Entra ID utsteder tokens til direkte – ingenting å rotere, ingenting som kan utløpe eller lekke.

Det eneste som finnes er tjenestekontoens ordinære passord, som følger organisasjonens passordpolicy og brukes til å autorisere de fire delegerte API-tilkoblingene. Endres det, må tilkoblingene re-autoriseres (`Authorize-ApiConnections.ps1`).

> Tidligere versjoner hadde en client secret (1 års gyldighet) og tjenestekonto-credentials i en Key Vault, for ROPC-flyten som satte sensitivitetsmerker. Alt dette er fjernet – se [Oppgraderingsveiledningen](./Upgrade.md) for opprydding i eksisterende miljøer.

## 6. Referanser

- [Installasjonsveiledning](./Deployment-guide.md) – steg-for-steg-installasjon (den skriptede delen)
- [Konfigurasjonsveiledning](./Configuration-guide.md) – godkjenningsoppsett, flyt-import, deling og verifisering
- [Datatilgang og sikkerhet](./Data-access-security.md) – detaljert tilgangsbeskrivelse
- [Datalagre](./Data-stores.md) – alle SharePoint-lister og felter
- [Godkjenningsflyt](./Approval-flow.md) – godkjenningsprosessen
- [Oppgraderingsveiledning](./Upgrade.md) – oppgradering uten datatap
