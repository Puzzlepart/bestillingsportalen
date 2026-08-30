# Installasjonsveiledning

## Forutsetninger

### Sjekkliste

Alt under er utdypet i [detaljene nedenfor](#detaljer). Punktene i siste gruppe må ofte bestilles hos kundens administratorer — gjør det tidlig, de har ledetid.

**Maskinen som kjører installasjonen:**

- [ ] Windows 10/11 med PowerShell **7.4+**
- [ ] Azure CLI installert, og `az login` fungerer gjennom brannmur/proxy
- [ ] PowerShell-moduler: PnP.PowerShell 3.2+, Az, WriteAscii
- [ ] Node.js 22.14+ (kun hvis SPFx skal bygges — ellers `-SkipSPFxDeploy`)

**Kontoen som kjører installasjonen:**

- [ ] **Owner på Azure-abonnementet** — eller minimum Contributor + User Access Administrator på ressursgruppen
- [ ] SharePoint Administrator (Teams- og Power Platform-administrator trengs også, for stegene i [Konfigurasjonsveiledningen](./Configuration-guide.md))
- [ ] Kan tildele app-roller til managed identities: Global Administrator, ev. Privileged Role Administrator + Cloud Application Administrator — **mangler du dette, bruk `-SkipAppRoles`** (se noten under detaljene)

**Tenanten og abonnementet (bestilles hos kundens admin ved behov):**

- [ ] Fakturerbart Azure-abonnement i **samme tenant** som Microsoft 365
- [ ] **Resource providers registrert i abonnementet**: `Microsoft.Automation`, `Microsoft.ManagedIdentity`, `Microsoft.Logic`, `Microsoft.Web` — registrering krever rettigheter på *abonnementsnivå*, se detaljene. ([Om resource providers – Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-providers-and-types))
- [ ] Power Automate (seeded licenses) aktivert og utrullet i organisasjonen
- [ ] Tenant app-katalog opprettet i SharePoint Admin Center
- [ ] Tjenestekonto opprettet, med lisens som inkluderer SPO, Exchange Online, Teams og seeded Power Automate (E- og F-lisenser fungerer begge — se detaljene)
- [ ] PnP app registration i tenanten (Prosjektportalen sin kan gjenbrukes — se «PnP PowerShell App Registration»)

Det meste av denne sjekklisten kan verifiseres automatisk: **kjør `./deploy.ps1 -Preflight`** (etter Steg 2), så kjøres alle sjekkene — tjenestekonto med lisens, område-alias, RBAC-rettigheter, resource providers, GA-rettigheter for app-roller, app-katalog og Node.js — og resultatet vises som en **PRE-DEPLOYMENT CHECKLIST** med `OK`/`MISSING`/`WARNING` per punkt og konkret løsning for hver mangel, uten at noe deployes. Alle sjekkene kjøres uansett i starten av en vanlig kjøring, og **alle** resultater vises samlet før noe opprettes — du får hele mangellisten i én kjøring, ikke én vegg per forsøk.

### Detaljer

- Power Automate (seeded licenses) aktivert og utrullet i organisasjonen.
- Fakturerbart Azure-abonnement i samme tenant som du skal installere Bestillingsportalen i.
- Tjenestekonto (brukes av Logic Apps for å koble til SPO, Outlook og Teams, og eier godkjenningsflyten) med en passende Microsoft 365-lisens (denne kontoen skal IKKE være admin). Denne kontoen KAN ha MFA. Lisensen må inkludere SPO, Exchange Online, Teams **og seeded Power Automate** — både E-lisenser (E1/E3/E5) og frontline-lisenser (F1/F3) har alt dette ([Microsofts lisens-FAQ](https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs#office-365-license-questions)), og en F3-lisensiert tjenestekonto er verifisert i praksis gjennom hele løpet inkludert flyt-import og -aktivering (kundetenant, august 2026). Uprovisjonerte prøvelisenser («viral» `FLOW_P2_VIRAL`) teller ikke. Skulle flyt-aktiveringen mot formodning feile med `FlowNotOriginalAuthor` (sett én gang i et utviklingsmiljø), se feilsøkingsboksen i [Konfigurasjonsveiledningen, Steg 2](./Configuration-guide.md) — bytte av lisens er siste utvei, ikke førstevalg.
- Sensitivitetsmerker krever **ingen egen tjenestekonto og ingen app-registrering**. Merker settes app-only med Automation-kontoens managed identity. Kravet om en tjenestekonto uten MFA gjaldt en tidligere ROPC-flyt som er fjernet — se [Sensitivitetsmerker](./Sensitivity-labels.md).
- Windows 10/11-maskin for å kjøre PowerShell-installasjonsskriptet.
- PowerShell **7.4 eller nyere** lastet ned og installert (kreves av PnP.PowerShell 3.x; versjonen sjekkes av installasjonsskriptet) – <https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4>.
- Azure CLI (Command Line Interface) – <https://learn.microsoft.com/en-us/cli/azure/install-azure-cli>.
- **Node.js 22.14.0** eller nyere – <https://nodejs.org/> (kun nødvendig hvis SPFx-løsninger skal bygges; kan hoppes over med `-SkipSPFxDeploy`). Se [`.nvmrc`](Source/SharePointFramework/ProvisionWebParts/.nvmrc) for eksakt versjon.
- **Tenant app-katalog opprettet** i SharePoint Admin Center – kreves for å publisere SPFx-pakker (`.sppkg`). Se <https://learn.microsoft.com/en-us/sharepoint/use-app-catalog>.
- Brannmur/Proxy konfigurert til å tillate tilkobling via Azure CLI – test at `az login` fungerer før du fortsetter.
- Global Administrator (for å opprette/autorisere PnP app registration).
- Brukerkonto med **Owner**-rettigheter til Azure-abonnementet, som også er SharePoint, Power Platform og Teams Administrator.
- **Resource providers registrert i abonnementet**: `Microsoft.Automation`, `Microsoft.ManagedIdentity`, `Microsoft.Logic` og `Microsoft.Web` ([hva resource providers er – Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-providers-and-types)). I et ferskt abonnement er de typisk *ikke* registrert, og deployen feiler da med `MissingSubscriptionRegistration`. Pre-flight sjekker dette og registrerer dem automatisk hvis kontoen har rettigheter på **abonnementsnivå** — men registrering er en abonnementsoperasjon, så med Owner kun på ressursgruppen stopper skriptet med de nøyaktige `az provider register`-kommandoene en abonnementsadministrator må kjøre (engangsjobb, tar et par minutter; det aktiverer kun ressurstypene og oppretter ingenting). Sjekk status selv med `az provider show --namespace Microsoft.Automation --query registrationState`.
- App Registration for PnP PowerShell (se nedenfor).

> **Managed identity:** Logic Apps autentiserer mot Microsoft Graph, SharePoint REST og Azure Automation med en user-assigned managed identity som opprettes av installasjonsskriptet. Det trengs derfor verken sertifikat eller client secret. Kontoen som kjører `deploy.ps1` må kunne tildele app-roller til managed identities (Global Administrator, ev. Privileged Role Administrator + Cloud Application Administrator). Se [Datatilgang og sikkerhet](Data-access-security.md) for hvilke app-roller som tildeles.
>
> **Har du ikke Global Administrator?** Kjør `./deploy.ps1 -SkipAppRoles`. Alt annet installeres, og skriptet skriver ut en ferdig kommando (med object-ID-ene fylt inn) som en Global Administrator kjører etterpå — send vedkommende den ene filen `Source/Scripts/AssignPermissionsToManagedIdentity.ps1` og kommandoen. Rollelistene er innbakt i skriptet, så GA-en trenger ingenting annet fra installasjonen (kun PowerShell 7+ og Microsoft.Graph-modulen). Merk at Logic Apps får 401/403 ved kjøring frem til kommandoen er kjørt, så bestillinger kan ikke behandles før da. Kommandoen er trygg å kjøre flere ganger — eksisterende roller hoppes over.

#### PnP PowerShell App Registration

PnP PowerShell støtter ikke lenger alternativet `multi-tenant app registration`. Dette opprettet tidligere en app registration automatisk for PnP PowerShell med alle nødvendige tilganger. For å autentisere med PnP PowerShell trenger du derfor en app registration i kundens tenant.

Installasjonen kjøres manuelt og overvåket (skriptet har flere interaktive prompts), og bruker **interaktiv pålogging**: du logger inn i nettleseren som kontoen som kjører skriptet — ingen sertifikater å opprette eller forvalte. Dette samsvarer med [PnP sin egen veiledning](https://pnp.github.io/powershell/articles/registerapplication.html), der app-only med sertifikat kun anbefales for skript som kjører *uten* brukerinteraksjon.

**Alternativ A: Gjenbruk Prosjektportalen sin PnP-app.** Har tenanten allerede [Prosjektportalen 365](https://github.com/Puzzlepart/prosjektportalen365) installert, finnes det normalt en PnP-app-registrering fra før — standardverdien for `pnpAppId` i `parameters.json` (`da6c31a6-b557-4ac3-9994-7315da06ea3a`) peker på denne. Ingen ny registrering nødvendig.

**Alternativ B: Registrer en ny app for interaktiv pålogging.** Kjør følgende som Global Administrator (PnP.PowerShell-modulen må være installert). Kommandoen oppretter app-registreringen med delegerte tilganger og ber om admin consent i nettleseren:

```powershell
Register-PnPEntraIDAppForInteractiveLogin `
    -ApplicationName "Bestillingsportalen PnP" `
    -Tenant "<kunde>.onmicrosoft.com" `
    -GraphDelegatePermissions "Group.ReadWrite.All", "AppCatalog.ReadWrite.All" `
    -SharePointDelegatePermissions "AllSites.FullControl"
```

`AppCatalog.ReadWrite.All` er **valgfri** og brukes kun til å publisere Bestillingsportalen-appen til Teams-appkatalogen automatisk som del av SPFx-distribusjonen. De fleste tenanter gir ikke denne tillatelsen (og PP365-appen i alternativ A har den ikke) — da fullfører `deploy.ps1` likevel, og Teams-appen lastes i stedet opp manuelt, se [Teams-appen](#teams-appen). Vil du ha automatisk publisering på en eksisterende PnP-app, kan en Global Administrator legge tillatelsen til under `API permissions` på app-registreringen i Entra ID (Microsoft Graph → Delegated → `AppCatalog.ReadWrite.All` → Grant admin consent).

**App-ID-en (Client ID)** fra outputen settes som `pnpAppId` i `parameters.json`. Under installasjonen åpner `deploy.ps1` nettleseren for pålogging (kun ved første tilkobling — tokens caches). De effektive rettighetene er snittet av dine rettigheter og appens delegerte tilganger; kontoen som kjører skriptet er uansett SharePoint-administrator.

Når installasjonen av Bestillingsportalen er fullført, kan du slette PnP PowerShell app registration eller fjerne tilgangene hvis du ikke trenger dem.

Mer informasjon om endringer i PnP PowerShell-autentisering finner du [her](https://pnp.github.io/blog/post/changes-pnp-management-shell-registration/).

Hvis `AllSites.FullControl` er et problem, kan du opprette SharePoint-området for Bestillingsportalen manuelt og sørge for at navnet i `parameters.json` matcher navnet på området du opprettet.

#### PowerShell 7.4+

Installasjonsskriptet for Bestillingsportalen krever PowerShell 7.4 eller nyere (PnP.PowerShell 3.x støtter ikke eldre versjoner) og støtter ikke 5.1. Sørg for at PowerShell 7.4+ er installert før du installerer PowerShell-modulene nedenfor.

> **Kjente konflikter mellom Az og PnP.PowerShell:** Modulene leverer ulike versjoner av `Microsoft.Extensions.*`-assemblies. Skriptet laster derfor PnP.PowerShell *før* Az. Får du likevel feilen `Method 'get_Services' in type '...LoggingBuilder' ... does not have an implementation`, start et **nytt** PowerShell-vindu og kjør skriptet på nytt — en økt der Az allerede er lastet kan ikke repareres.

#### PowerShell-moduler

Følgende PowerShell-moduler brukes av installasjonsskriptet og må installeres før skriptet kjøres:

- PnP.PowerShell (3.2 eller nyere — versjonen sjekkes av installasjonsskriptet)
- Az
- WriteAscii

## Steg 1: Konfigurere PowerShell

1. Last ned [nyeste utgave](https://github.com/Puzzlepart/bestillingsportalen/releases/latest) av Bestillingsportalen.
2. Start PowerShell 7 som administrator.
3. Sett PowerShell Execution Policy til `Unrestricted` ved å kjøre ```Set-ExecutionPolicy -ExecutionPolicy unrestricted```.

## Steg 2: Oppdatere parameters.json

**Tips: generer filen automatisk.** Kjør hjelpeskriptet `GenerateParameters.ps1` fra `Scripts`-mappen. Det spør først **hvilken tenant (kunde) du skal installere i** (initial-domene eller tenant-ID) og logger Azure CLI inn i akkurat den tenanten — jobber du mot flere kunder, kan du dermed ikke generere parametre mot feil miljø ved et uhell. Subscription-velgeren viser kun abonnementer i mål-tenanten, sammen med hvem du er logget inn som. Deretter fylles alt som kan utledes fra miljøet (`tenantId`, `subscriptionId`, `fullTenantName`, `spoTenantName`) pluss fornuftige standardverdier. Du blir bare spurt om det som ikke kan utledes (tjenestekonto-UPN — kan også angis som parameter for kjøring uten prompts). Skriptet verifiserer samtidig at tjenestekontoen faktisk finnes i tenanten (re-prompter hvis ikke), og at PnP-appen `pnpAppId` er registrert der — mangler den, sier skriptet det i «Next steps»:

```powershell
./GenerateParameters.ps1
# eller uten prompts:
./GenerateParameters.ps1 -Tenant contoso.onmicrosoft.com -ServiceAccountUPN svc-bp@contoso.com -Force
```

> **Managed path leses fra tenanten.** Mot slutten spør skriptet om det skal hente `Opprett gruppeområder under` fra SharePoint Admin Center (`Innstillinger` → `Områdeoppretting`). Dette er det ene som ikke kan leses med Azure CLI — SharePoint krever eget token — så steget bruker PnP.PowerShell og åpner én nettleser-pålogging som SharePoint-administrator. Svarer du `n`, mangler PnP.PowerShell, eller kjører du med `-Force`, beholdes standardverdien `sites`. Kan verdien ikke leses ut av tenanten, spør skriptet deg om den i stedet, med henvisning til innstillingen — **kontroller den**, for `sites` mot en `/teams/`-tenant gir feil område-URL-er.

> **Jobber du mot flere kunder?** Bruk én fil per miljø i stedet for å kopiere den riktige over `parameters.json` før hver kjøring: `./GenerateParameters.ps1 -OutputPath .\parameters-contoso.json`, og kjør deretter `./deploy.ps1 -ParametersPath .\parameters-contoso.json`. `parameters-*.json` er git-ignorert, og deploy-skriptets PRE-FLIGHT SUMMARY viser hvilken fil verdiene kom fra.

Skriptet endrer ingenting i miljøet (kun lesekall) og skriver ut en oversikt over alle genererte verdier til slutt. **Gå gjennom filen etterpå** — særlig standardnavnene (`resourceGroupName`, `appName`, `requestsSiteName`) og at `spoTenantName` stemmer med den faktiske SharePoint-URL-en (tenants som har byttet navn kan avvike fra initial-domenet).

Alternativt kan du fylle ut manuelt: du finner en `parameters.json`-fil i Scripts-mappen. Oppdater alle parametre med korrekte verdier for tenanten din.

Erstatt `<<value>>` med passende verdier for alle påkrevde parametre.

Beskrivelse av hver parameter:

- `tenantId` – ID til tenanten du skal installere i. Finnes i Microsoft Entra ID-bladet.

- `spoTenantName` – Navnet på SharePoint-tenanten eksklusivt `.sharepoint.com`, f.eks. `puzzlepart`.

- `fullTenantName` – Fullt tenant-navn inklusive `.onmicrosoft.com`, f.eks. `contoso.onmicrosoft.com`.

- `requestsSiteName` – Visningsnavnet på SharePoint-området som skal lagre bestillinger, f.eks. `Bestillingsportalen`. Kan inneholde mellomrom. Hvis området finnes, spørres det om overskriving og PnP-provisjoneringsmal anvendes.

- `requestsSiteAlias` – Aliaset til området, som bestemmer **URL-en** (`/<managedPath>/<alias>`) og **e-postadressen til Microsoft 365-gruppen** (`<alias>@<maildomene>`). Standard er `bestillingsportalen`, altså `/sites/bestillingsportalen` og `bestillingsportalen@kunde.no`.

  > **Ethvert alias fungerer.** Webdelene og Teams-appen finner området via tenant-registeret (storage entity `bp_ProvisionUrls`), som `deploy.ps1` vedlikeholder automatisk — se [Tenant-registeret](./Configuration-guide.md#merknad-tenant-registeret-bp_provisionurls). Standardverdien beholdes for gjenkjennelighet, ikke av teknisk nødvendighet.
  >
  > **Aliaset deler navnerom med alle brukere og grupper i tenanten.** Har kunden en tjenestekonto som `bestillingsportalen@kunde.no`, er aliaset opptatt — og SharePoint **feiler ikke** på det, det oppretter gruppen som `bestillingsportalen1` i stedet. Da peker alle URL-ene skriptet har regnet ut på et område som ikke finnes, og kjøringen stopper lenger ned med `Object reference not set to an instance of an object`. Derfor validerer `deploy.ps1` aliaset mot tjenestekontoen og mot brukere i tenanten **før** noe opprettes, og stopper i pre-flight med `MISSING` på `Site alias` hvis det er opptatt. Fiksen er å sette et ledig alias (f.eks. `BP`) og kjøre på nytt.
  >
  > **Ved oppgradering av et eksisterende miljø: verifiser mot områdets faktiske URL.** Ligger området på `/sites/bestillingsportalen`, gjør standardverdien jobben. Ligger det et annet sted, sett aliaset til det faktiske URL-segmentet — eller la parameteren stå tom, da utledes aliaset fra `requestsSiteName` som før 2.0. Setter du feil verdi, peker kjøringen på et annet område enn det du har i drift.

- `provisionInstanceTitle` (**valgfritt**) – Visningsnavnet for **denne** installasjonen i tenant-registeret `bp_ProvisionUrls`, som vises i Teams-appens instansvelger når tenanten har flere Bestillingsportalen-installasjoner. La stå tomt for å bruke `requestsSiteName`. Kan ikke settes registeret? `deploy.ps1` fullfører likevel med en `WARNING` og skriver ut `Set-PnPStorageEntity`-kommandoen for manuell registrering.

- `requestsSiteDesc` – Beskrivelse av området som opprettes.

- `managedPath` – Managed path konfigurert i tenanten, f.eks. `sites` eller `teams` (uten skråstrek). Dette er innstillingen **`Opprett gruppeområder under`** i SharePoint Admin Center → `Innstillinger` → `Områdeoppretting`. Verdien må stemme med tenanten: `deploy.ps1` bygger område-URL-er fra den og skriver den til innstillingslisten, så en tenant satt opp med `/teams/` får feil URL-er hvis den står som `sites`. `GenerateParameters.ps1` tilbyr å lese den fra tenanten (se under).

- `subscriptionId` – Azure-abonnement som løsningen installeres i (MÅ være tilknyttet Entra ID-katalogen til Microsoft 365-tenanten du installerer i).

- `region` – Azure-region der ressursene opprettes. Bruk internt navn, f.eks. `norwayeast`. Plasseringen MÅ støtte Automation og Logic Apps. Se [Valid Azure locations](https://azure.microsoft.com/en-gb/explore/global-infrastructure/products-by-region/?products=logic-apps%2Cautomation&regions=all).

- `resourceGroupName` – Navn på ny ressursgruppe løsningen installeres i. Skriptet oppretter denne.

- `uamiName` (**valgfritt**) – Navn på user-assigned managed identity som opprettes og brukes av Logic Apps. Standard er `bestillingsportalen-uami`.

- `pnpAppId` – ID til PnP Entra-app registration du opprettet da du konfigurerte PnP PowerShell.

- `siteLogoPath` (**valgfritt**) – Sti til en firmalogo (ideelt lagret i SharePoint) som alle brukere har tilgang til, brukes som logo for opprettede områder. Sørg for at stien peker til et bilde. Hvis du ikke har et bilde, la dette stå tomt.

- `guestEntraGroup` (**valgfritt**) – Objekt-ID (anbefalt) eller visningsnavn på en Entra ID-gruppe som alle gjester invitert via `InviteGuests`-webdelen legges inn i, i tillegg til området de inviteres til. Lar organisasjonen gi alle gjester en felles grunntilgang ett sted — f.eks. lesetilgang på hub-området og app-katalogen ved å gi gruppen tilgang der. Gjelder hele installasjonen (alle webdel-instanser), og en gjest som allerede er medlem hoppes stille over. Sikkerhetsgrupper og M365-grupper støttes; rolletildelbare og on-premises-synkroniserte grupper kan ikke skrives via Graph. Angis et visningsnavn må det matche nøyaktig én gruppe i tenanten — ellers feiler invitasjonen med en tydelig melding. La stå tomt for å skru av funksjonen.

- `serviceAccountUPN` – UPN til tjenestekontoen som brukes i løsningen – brukes til å koble Logic App API connections. Tjenestekontoen skal være en standard Microsoft 365-bruker med SPO/Exchange/Teams-lisenser og seeded Power Automate (E- og F-lisenser fungerer begge, se forutsetningene). Se [Assign licenses to users](https://learn.microsoft.com/en-us/microsoft-365/admin/manage/assign-licenses-to-users?view=o365-worldwide).

- `isEdu` – Angir om tenanten er en Education-tenant. Hvis `true`, installeres Education Teams Templates. Disse hoppes over hvis `false` eller blank.

> **Sensitivitetsmerker har ingen installasjonsparameter.** Alt som trengs settes opp uansett (`SyncLabels`, `IP Labels`-listen og app-tillatelsen), og merkingen bruker Automation-kontoens managed identity. Funksjonaliteten skrus på ved å sette `EnableSensitivityLabels` til `true` i `Provisioning Request Settings`-listen etter installasjon – se [Sensitivitetsmerker](./Sensitivity-labels.md).

- `skipApplySPOTemplate` – Hopper over anvendelse av PnP-mal på SharePoint-området. La stå som `false` med mindre du har en spesifikk grunn til å hoppe over dette.

## Steg 3: Kjør skriptet

> Løsningen krever **ingen egen Entra ID-app-registrering**. Alt i drift autentiserer med managed identity, også sensitivitetsmerking. Den eneste app-registreringen som er involvert er PnP PowerShell-appen fra forutsetningene, som bare brukes under installasjonen.

### Installasjon av ressurser

Neste steg er å kjøre deploy-skriptet.

**Sørg for at kontoen du bruker på dette steget har owner-rettigheter til Azure-abonnementet, er SharePoint Administrator, og kan tildele app-roller til managed identities.**

Skriptet bruker tre verktøy som hver har sin pålogging (Az PowerShell, Azure CLI og PnP PowerShell), men **eksisterende sesjoner gjenbrukes**: finner skriptet en cachet sesjon som matcher tenant/subscription i `parameters.json`, blir du spurt om å gjenbruke den (`y`) i stedet for å logge inn på nytt — ved gjentatte kjøringer slipper du dermed MFA-rundene. Svar `n` for å tvinge frisk innlogging (f.eks. med en annen konto).

1. Åpne et PowerShell 7-vindu som administrator.
2. Gå til `Scripts`-mappen.
3. Kjør deploy-skriptet i PowerShell-vinduet – ```.\deploy.ps1```. Ligger parametrene i en annen fil enn `parameters.json`, angi den med `-ParametersPath`: ```.\deploy.ps1 -ParametersPath .\parameters-contoso.json```. Skriptet må uansett kjøres fra `Scripts`-mappen, og stopper umiddelbart med forslag til hvilke parameterfiler som finnes hvis stien er feil.

PnP PowerShell logger inn interaktivt — et nettleservindu åpnes ved første tilkobling i kjøringen; logg inn med kontoen du kjører skriptet med. Tokenet gjenbrukes for resten av kjøringen (innloggingen persisteres bevisst *ikke* på tvers av økter, så det ikke blir liggende tokens for kundetenants på maskinen).

Etter at alle innloggingene er fullført — men **før noe opprettes eller endres** — kjører skriptet alle forhåndssjekkene og viser en **PRE-DEPLOYMENT CHECKLIST**: én linje per sjekk (løsningsversjon, maler, tjenestekonto med lisens, område-alias, RBAC, resource providers, app-rolle-rettigheter, app-katalog, Node.js) med status `OK`, `MISSING`, `WARNING` eller `SKIPPED`, og en `Fix:`-linje med konkret løsning for hver mangel. Finnes `MISSING`-punkter stopper skriptet der — med **hele** mangellisten synlig, ikke bare første funn. Vil du bare ha statusoversikten uten å installere, kjør `./deploy.ps1 -Preflight`. Deretter viser skriptet en **PRE-FLIGHT SUMMARY**: hvilken versjon som installeres (og hvilken miljøet står på fra før), hvilken parameterfil verdiene kom fra, hvilken Entra ID-tenant, Azure-subscription og SharePoint-tenant du faktisk er koblet til, hvilken konto du er logget inn med, **språket (LCID) på tenantens rot-område**, og hva som vil bli satt opp (ressursgruppe, SharePoint-område, Automation/managed identity, app-roller, runbooks, API-tilkoblinger, Logic Apps, SPFx). **Kontroller at du er koblet til riktig miljø** og bekreft med `y` — svarer du `n` avsluttes skriptet uten at noe er endret.

> **Om rot-områdets språk:** linja `Root site language` viser LCID og språknavn for tenantens rot-område (`https://<tenant>.sharepoint.com`). Vi har sett problemer ved provisjonering av områder med et annet språk enn rot-området, så verdien vises for at du skal kunne vurdere det før du kjører. Den påvirker ingenting i seg selv, og skriptet stopper ikke på den — men vurder å sette `DefaultLCID` i `Provisioning Request Settings` til samme språk, og å begrense `Locales`-listen (se [Regionale innstillinger](./Regional-settings.md)) hvis kunden ikke har behov for å bestille områder på flere språk. Kan verdien ikke leses, står det `could not be read (...)`; det er kun en visningsverdi og blokkerer ikke installasjonen.

For gjentatte eller uovervåkede kjøringer: `-SkipConfirmation` hopper over denne prompten og gjenbruker cachede sesjoner, og `-Force` gjør i tillegg at «re-anvend PnP-template?»-prompten svares **nei**. `-Force` auto-godkjenner bevisst **ikke** de destruktive promptene (tømme slettet site/gruppe fra papirkurv, slette en aktiv gruppe) — de avbryter i stedet. Se [Oppgraderingsveiledningen](/Upgrade.md#uovervåket-kjøring-med--force).

På slutten av kjøringen skriver skriptet ut en **DEPLOYMENT SUMMARY** — en statuslinje per delkomponent (tjenestekonto, SharePoint-område, ressursgruppe, Azure-ressurser, app-roller på begge managed identities, runbook-innhold og runbook-runtime, API-tilkoblinger, Logic Apps, SPFx-pakkene og versjonsstemplet) med `OK`, `FAILED`, `WARNING` eller `SKIPPED`, etterfulgt av en henvisning til de gjenstående manuelle stegene ([Autorisere API-tilkoblinger](#autorisere-api-tilkoblinger) her, deretter [Konfigurasjonsveiledningen](./Configuration-guide.md)). Oppsummeringen vises også hvis skriptet stopper på en feil underveis, slik at du ser hvilke komponenter som rakk å fullføre.

![Deployment summary etter vellykket kjøring](/Images/InstallationSuccess.png)

> **Om versjonsstemplet:** `Version stamp`-linja bekrefter at versjonen er skrevet inn i
> miljøet — som radene `InstalledVersion` og `InstalledDate` i «Provisioning Request
> Settings», og som taggene `BestillingsportalenVersion`/`BestillingsportalenDeployed` på
> ressursgruppa. Det gjør at den som senere supporterer installasjonen kan lese av hvilken
> versjon den kjører, uten å gjette. Feilet noen komponenter, stemples ingenting: den gamle
> verdien beholdes med vilje, slik at en halvferdig kjøring ikke framstår som fullført. Se
> [Hvilken versjon kjører miljøet?](./Upgrade.md#hvilken-versjon-kjører-miljøet).

- Vises **«DEPLOYMENT COMPLETED SUCCESSFULLY»**: gå videre til neste steg.
- Vises **«DEPLOYMENT COMPLETED WITH ERRORS»** (exit-kode 1): se hvilke komponenter som feilet i oppsummeringen, rett årsaken og kjør skriptet på nytt. Vær særlig oppmerksom på `App roles`-linjene — feiler disse vil Logic Apps få 401/403 ved kjøring selv om alt annet ser vellykket ut.

### Kjøre uten Global Administrator (`-SkipAppRoles`)

App-rolletildelingen er det eneste steget i `deploy.ps1` som krever Global Administrator. Har ikke kontoen din den rollen i kundens tenant:

1. Kjør `./deploy.ps1 -SkipAppRoles`. Alt annet installeres som normalt, og `App roles`-linjene i DEPLOYMENT SUMMARY står som `SKIPPED` med en ferdig kommando i detaljene.
2. Send **én fil** til kundens Global Administrator: `Source/Scripts/AssignPermissionsToManagedIdentity.ps1`, sammen med kommandoen skriptet skrev ut — den har tenant-ID og begge identitetenes object-ID-er ferdig utfylt:

   ```powershell
   ./AssignPermissionsToManagedIdentity.ps1 -TenantId <tenantId> -AutomationIdentityId <objectId> -UamiId <objectId>
   ```

3. GA-en trenger PowerShell 7+ og Microsoft.Graph-modulen (`Install-Module Microsoft.Graph.Applications`), logger inn interaktivt, og godkjenner scopene `AppRoleAssignment.ReadWrite.All` + `Application.Read.All`. Rollelistene er innbakt i skriptet og dokumentert i [Datatilgang og sikkerhet](Data-access-security.md).
4. **Frem til kommandoen er kjørt får Logic Apps 401/403** — bestillinger kan ikke behandles. Nye app-roller kan bruke noen minutter på å propagere, og managed identity-tokens caches i opptil ~24 timer.

Kommandoen er idempotent — eksisterende roller hoppes over, så den kan trygt kjøres på nytt, også etter en oppgradering som legger til nye roller.

**Skriptet kan kjøres på nytt så mange ganger som nødvendig uten at ressurser må slettes — fullførte komponenter oppdateres idempotent.** Ved re-kjøring mot et eksisterende miljø:

- Eksisterende SharePoint-område gjenkjennes (du får spørsmål der det er relevant).
- På spørsmålet om PnP-malen: **`y` nullstiller ingenting** — malens DataRows bruker `UpdateBehavior="Skip"`, så eksisterende listeelementer røres aldri; `y` oppdaterer skjema/views og legger til manglende standardrader. Svar **`n`** for å hoppe over malen helt (skriptet henter da bare liste-ID-ene). Skal du kun oppdatere Logic Apps/runbooks, hopper `-SkipSharepointSite` over hele områdesteget inkludert denne prompten.
- App-roller sjekkes per rolle og tildeles kun det som mangler; Logic Apps og API-tilkoblinger oppdateres til malens definisjon.
- Sjekk at de delegerte API-tilkoblingene fortsatt står som `Connected` etterpå — en re-deploy kan i noen tilfeller kreve re-autorisering.

**For senere oppdateringer av et miljø i drift, bruk `./deploy.ps1 -Upgrade`** (se [Oppgraderingsveiledning](/Upgrade.md)) — den hopper over listeutfylling og områdeoppsett helt.

#### Runbookene vises som «PowerShell 5.1» i portalen — det er normalt

Runbookene kjører på **PowerShell 7.4** i runtime environmentet `bestillingsportalen-ps74` (kreves av `PnP.PowerShell` 3.x), men Automation-kontoens **standard Runbooks-blad viser dem som «PowerShell 5.1»**. Det er en [dokumentert begrensning](https://learn.microsoft.com/en-us/azure/automation/runtime-environment-overview#limitations) i den gamle portalopplevelsen, som ikke kjenner runtime environments over 7.2:

> «Runbooks created in Runtime environment experience with Runtime version PowerShell 7.2+ would show as PowerShell 5.1 runbooks in old experience.»

**Slik ser du de riktige verdiene:** åpne Automation-kontoen i Azure Portal og bytt til **Runtime environment-opplevelsen** (bryteren ligger i banneret øverst på Automation-konto-oversikten / under `Process Automation`). Da vises både runtime environment og faktisk PowerShell-versjon korrekt for hver runbook, og `bestillingsportalen-ps74` blir synlig med sine pakker.

Du trenger normalt ikke sjekke dette manuelt: `deploy.ps1` leser `properties.runtimeEnvironment` via REST for hver runbook og rapporterer **`Runbook runtime environment`** i DEPLOYMENT SUMMARY. Står den `OK`, kjører runbookene på 7.4 uansett hva Runbooks-bladet viser. Står den `FAILED`, er det et reelt problem — da ville produksjonsrunbookene feilet med `Connect-PnPOnline is not recognized`.

Trenger du grunnsannheten fra inne i en jobb, kjør [`Source/Diagnostics/Test-RunbookRuntime.ps1`](/Source/Diagnostics/Test-RunbookRuntime.ps1) — den skriver ut `$PSVersionTable` og modulversjonene som faktisk er lastet.

### Autorisere API-tilkoblinger

De fire delegerte API-tilkoblingene må autoriseres interaktivt med **tjenestekontoen**. Selve innloggingen kan ikke automatiseres (delegert OAuth krever at kontoen selv logger inn), men alt rundt er skriptet:

**Anbefalt: kjør hjelpeskriptet** fra `Scripts`-mappen (bruker az CLI-sesjonen fra deploy):

```powershell
./Authorize-ApiConnections.ps1
```

Skriptet sjekker status på alle fire tilkoblingene (hopper over de som allerede er `Connected`), åpner en samtykkelenke i nettleseren per tilkobling — **logg inn som tjenestekontoen**, ikke admin-kontoen din — fanger opp samtykket og verifiserer at statusen blir `Connected` til slutt. Kan kjøres på nytt når som helst, f.eks. etter en oppgradering hvis en tilkobling står som `Error`.

> Underveis viser Microsoft en advarsel om at «this connection was created from a different organization» med phishing-varsel. Det er forventet: samtykkelenken genereres av admin-sesjonen din, mens tjenestekontoen er den som samtykker. Huk av `I have verified this request and trust the source` og velg `Allow access`.

**Alternativt manuelt i Azure Portal:** gå til ressursgruppen → klikk på tilkoblingen (`bestillingsportalen-o365`, `-o365users`, `-spo`, `-teams`) → `Edit API connection` → `Authorize` (logg inn som tjenestekontoen) → `Save`.

### SPFx-løsninger (`InviteGuests`-webdel)

Deploy-scriptet bygger og publiserer automatisk alle SPFx-løsninger under `Source/SharePointFramework/*/` til tenant app-katalogen via `Add-PnPApp -Overwrite -Publish`. Konkret betyr det at `bp-provision-web-parts.sppkg` (som inneholder `InviteGuests`-webdelen) blir lastet opp og publisert tenant-wide når deploy fullføres.

Når webdelen er publisert kan den legges til på en hvilken som helst SharePoint-side. Husk å konfigurere `guestRequestSiteUrl` i property pane til URL-en til Bestillingsportalen-admin-området slik at gjesteforespørsler skrives til riktig liste.

**Hopp over SPFx-bygg/publisering** hvis du allerede har bygget manuelt eller kun vil deploye Azure-ressurser:

```powershell
./deploy.ps1 -SkipSPFxDeploy
```

### Teams-appen

Bestillingsportalen skal også være tilgjengelig som personlig app i Teams. Som del av SPFx-distribusjonen pakker `deploy.ps1` Teams-app-manifestet (`ProvisionWebParts/teams/`, versjon synkronisert fra `package-solution.json`) til `bestillingsportalen-teams-app.zip` og forsøker å publisere den til Teams-appkatalogen via Graph. Automatisk publisering krever delegert `AppCatalog.ReadWrite.All` på PnP-appen (se [PnP PowerShell App Registration](#pnp-powershell-app-registration)) — en tillatelse de fleste tenanter ikke gir. **Regn derfor med å laste opp appen manuelt** (skriptet minner om det på slutten av kjøringen):

1. Åpne **Teams admin center** → `Teams-apper` → `Administrer apper`
2. `Handlinger` → `Last opp ny app`, og velg `Source/SharePointFramework/ProvisionWebParts/sharepoint/solution/bestillingsportalen-teams-app.zip` (produseres av deploy-skriptet, som også skriver ut stien)
3. Finnes appen **Bestillingsportalen** i katalogen fra før (f.eks. synkronisert fra Prosjektportalen 365 tidligere), åpne den eksisterende appen og bruk `Last opp fil` for å oppdatere den i stedet
4. Verifiser at appen åpner i Teams

Steget trengs ved førstegangsinstallasjon og ved oppgraderinger som gir ny appversjon. Ikke bruk `Sync to Teams`-knappen i SharePoint-appkatalogen — den er upålitelig (deaktivert eller «Failed to sync» i mange tenanter), og zip-opplastingen gjør nøyaktig det samme.

## Videre: Konfigurasjonsveiledningen

Den skriptede delen av installasjonen er nå ferdig. Resten — godkjenningsoppsett, import og aktivering av flyten, deling med brukerne, støtte-Logic Apps, aktivering av maler/huber, administratorgruppe og en verifiserende testbestilling — gjøres uten Azure-tilganger og er beskrevet i **[Konfigurasjonsveiledningen](./Configuration-guide.md)**.

> **Tidsforsinkelse på app-rollene:** rollene tildeles under deployen (eller av en Global Administrator ved `-SkipAppRoles`), men managed identity-tokens utstedes med rollene som gjaldt på utstedelsestidspunktet og caches i opptil **~24 timer** i Azure-infrastrukturen. De første timene etter en fersk installasjon kan Logic Apps og runbooks derfor få sporadiske 401/403 eller Graph-feil av typen `Roles on the request ''` — også blandet, der noen kall lykkes og andre feiler i samme kjøring — selv om alt er riktig konfigurert. Dette leger seg selv og krever ingen handling. Verifiseringssteget i konfigurasjonsveiledningen tar høyde for det.
