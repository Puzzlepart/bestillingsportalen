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
- [ ] SharePoint Administrator (Teams- og Power Platform-administrator trengs også, for stegene etter selve skriptet)
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
- Tjenestekonto (brukes av Logic Apps for å koble til SPO, Outlook og Teams, og eier godkjenningsflyten) med en passende Microsoft 365-lisens (denne kontoen skal IKKE være admin). Denne kontoen KAN ha MFA. Lisensen må inkludere SPO, Exchange Online, Teams **og seeded Power Automate** — både E-lisenser (E1/E3/E5) og frontline-lisenser (F1/F3) har alt dette ([Microsofts lisens-FAQ](https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs#office-365-license-questions)), og en F3-lisensiert tjenestekonto er verifisert i praksis gjennom hele løpet inkludert flyt-import og -aktivering (kundetenant, august 2026). Uprovisjonerte prøvelisenser («viral» `FLOW_P2_VIRAL`) teller ikke. Skulle aktiveringen i Steg 5 mot formodning feile med `FlowNotOriginalAuthor` (sett én gang i et utviklingsmiljø), se feilsøkingsboksen der — bytte av lisens er siste utvei, ikke førstevalg.
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
    -GraphDelegatePermissions "Group.ReadWrite.All" `
    -SharePointDelegatePermissions "AllSites.FullControl"
```

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

- `requestsSiteAlias` – Aliaset til området, som bestemmer **URL-en** (`/<managedPath>/<alias>`) og **e-postadressen til Microsoft 365-gruppen** (`<alias>@<maildomene>`). Standard er `BP`, altså `/sites/BP` og `BP@kunde.no`. Et kort alias er raskt å skrive, men er lettere opptatt av noe annet i tenanten enn et langt — sjekk feilmeldingen fra pre-flight hvis det skjer, og velg noe annet.

  > **Aliaset deler navnerom med alle brukere og grupper i tenanten.** Har kunden en tjenestekonto som `bestillingsportalen@kunde.no`, er aliaset `bestillingsportalen` opptatt — og SharePoint **feiler ikke** på det, det oppretter gruppen som `bestillingsportalen1` i stedet. Da peker alle URL-ene skriptet har regnet ut på et område som ikke finnes, og kjøringen stopper lenger ned med `Object reference not set to an instance of an object`. Derfor er standardaliaset `BP` og ikke `bestillingsportalen`, og derfor validerer `deploy.ps1` aliaset mot tjenestekontoen og mot brukere i tenanten før noe opprettes.
  >
  > **Ved oppgradering av et eksisterende miljø: la denne stå tom.** Da utledes aliaset fra `requestsSiteName` som før, slik at kjøringen peker på området som allerede er installert. Setter du den, flytter du deg til en ny URL.

- `requestsSiteDesc` – Beskrivelse av området som opprettes.

- `managedPath` – Managed path konfigurert i tenanten, f.eks. `sites` eller `teams` (uten skråstrek). Dette er innstillingen **`Opprett gruppeområder under`** i SharePoint Admin Center → `Innstillinger` → `Områdeoppretting`. Verdien må stemme med tenanten: `deploy.ps1` bygger område-URL-er fra den og skriver den til innstillingslisten, så en tenant satt opp med `/teams/` får feil URL-er hvis den står som `sites`. `GenerateParameters.ps1` tilbyr å lese den fra tenanten (se under).

- `subscriptionId` – Azure-abonnement som løsningen installeres i (MÅ være tilknyttet Entra ID-katalogen til Microsoft 365-tenanten du installerer i).

- `region` – Azure-region der ressursene opprettes. Bruk internt navn, f.eks. `norwayeast`. Plasseringen MÅ støtte Automation og Logic Apps. Se [Valid Azure locations](https://azure.microsoft.com/en-gb/explore/global-infrastructure/products-by-region/?products=logic-apps%2Cautomation&regions=all).

- `resourceGroupName` – Navn på ny ressursgruppe løsningen installeres i. Skriptet oppretter denne.

- `uamiName` (**valgfritt**) – Navn på user-assigned managed identity som opprettes og brukes av Logic Apps. Standard er `bestillingsportalen-uami`.

- `pnpAppId` – ID til PnP Entra-app registration du opprettet da du konfigurerte PnP PowerShell.

- `siteLogoPath` (**valgfritt**) – Sti til en firmalogo (ideelt lagret i SharePoint) som alle brukere har tilgang til, brukes som logo for opprettede områder. Sørg for at stien peker til et bilde. Hvis du ikke har et bilde, la dette stå tomt.

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

Etter at alle innloggingene er fullført — men **før noe opprettes eller endres** — kjører skriptet alle forhåndssjekkene og viser en **PRE-DEPLOYMENT CHECKLIST**: én linje per sjekk (maler, tjenestekonto med lisens, område-alias, RBAC, resource providers, app-rolle-rettigheter, app-katalog, Node.js) med status `OK`, `MISSING`, `WARNING` eller `SKIPPED`, og en `Fix:`-linje med konkret løsning for hver mangel. Finnes `MISSING`-punkter stopper skriptet der — med **hele** mangellisten synlig, ikke bare første funn. Vil du bare ha statusoversikten uten å installere, kjør `./deploy.ps1 -Preflight`. Deretter viser skriptet en **PRE-FLIGHT SUMMARY**: hvilken parameterfil verdiene kom fra, hvilken Entra ID-tenant, Azure-subscription og SharePoint-tenant du faktisk er koblet til, hvilken konto du er logget inn med, **språket (LCID) på tenantens rot-område**, og hva som vil bli satt opp (ressursgruppe, SharePoint-område, Automation/managed identity, app-roller, runbooks, API-tilkoblinger, Logic Apps, SPFx). **Kontroller at du er koblet til riktig miljø** og bekreft med `y` — svarer du `n` avsluttes skriptet uten at noe er endret.

> **Om rot-områdets språk:** linja `Root site language` viser LCID og språknavn for tenantens rot-område (`https://<tenant>.sharepoint.com`). Vi har sett problemer ved provisjonering av områder med et annet språk enn rot-området, så verdien vises for at du skal kunne vurdere det før du kjører. Den påvirker ingenting i seg selv, og skriptet stopper ikke på den — men vurder å sette `DefaultLCID` i `Provisioning Request Settings` til samme språk, og å begrense `Locales`-listen (se [Regionale innstillinger](./Regional-settings.md)) hvis kunden ikke har behov for å bestille områder på flere språk. Kan verdien ikke leses, står det `could not be read (...)`; det er kun en visningsverdi og blokkerer ikke installasjonen.

For gjentatte eller uovervåkede kjøringer: `-SkipConfirmation` hopper over denne prompten og gjenbruker cachede sesjoner, og `-Force` gjør i tillegg at «re-anvend PnP-template?»-prompten svares **nei**. `-Force` auto-godkjenner bevisst **ikke** de destruktive promptene (tømme slettet site/gruppe fra papirkurv, slette en aktiv gruppe) — de avbryter i stedet. Se [Oppgraderingsveiledningen](/Upgrade.md#uovervåket-kjøring-med--force).

På slutten av kjøringen skriver skriptet ut en **DEPLOYMENT SUMMARY** — en statuslinje per delkomponent (tjenestekonto, SharePoint-område, ressursgruppe, Azure-ressurser, app-roller på begge managed identities, runbook-innhold og runbook-runtime, API-tilkoblinger, Logic Apps og SPFx-pakkene) med `OK`, `FAILED`, `WARNING` eller `SKIPPED`, etterfulgt av en henvisning til de gjenstående manuelle stegene i denne veiledningen (fra [Autorisere API-tilkoblinger](#autorisere-api-tilkoblinger) og utover). Oppsummeringen vises også hvis skriptet stopper på en feil underveis, slik at du ser hvilke komponenter som rakk å fullføre.

![Deployment summary etter vellykket kjøring](/Images/InstallationSuccess.png)

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

## Steg 4: Konfigurere godkjenningsprosess

Godkjenning av bestillinger i løsningen kan skje på to måter:

- Power Automate Approval-handling (godkjennings-epost og Approvals-app i Teams).
- Microsoft Teams Adaptive Card-godkjenning (adaptivt kort postet i en Teams-kanal).

Godkjenninger av bestillinger bruker én Power Automate-flyt som kjører når status på en bestilling i **`Provisioning Requests`**-listen endres til **`Submitted`** (brukeren sender inn bestillingen i Bestillingsportalen webdel eller Teams app).

Følg stegene for å konfigurere Bestillingsportalen-innstillingene avhengig av hvilken godkjenningsmetode du vil bruke.

Innstillingene for Bestillingsportalen finnes i `Provisioning Request Settings`-listen som nøkkel/verdi-par (Title/Value). Standardverdiene seedes av PnP-malen ved installasjon (`<pnp:DataRows>` i `Source/Templates/Objects/Lists/Provisioning Request Settings.xml`) — eksisterende elementer røres aldri ved re-apply, og manglende standardelementer legges til.

### Power Automate Approvals

1. Gå til SharePoint-området opprettet som del av installasjonen.
2. Finn `Provisioning Request Settings`-listen og åpne den.
3. Rediger listeelementet `ApproverEmail` og sett `Value`-feltet til e-post/UPN for en **enkelt bruker** ELLER en **Microsoft 365-gruppe**.
4. Sørg for at verdien på listeelementet `PostToTeams` er satt til `false`.
5. Lagre endringene.

Godkjenninger er nå konfigurert til å bruke Power Automate Approvals-oppgaver.

### Teams

1. Opprett (ELLER bruk et eksisterende) Microsoft Teams-team for godkjennings-adaptive cards. Du kan koble **Bestillingsportalen**-SharePoint-området (-gruppen) til et nytt Teams-team.
2. Opprett (ELLER bruk en eksisterende) kanal i samme team for godkjenningskortene. Det er her de vil postes.
3. Legg til brukerne som skal godkjenne bestillinger i teamet.
4. I Teams-klienten, klikk på ellipsisen og velg `Get link to channel`.

![Microsoft Teams get link to channel screenshot](/Images/LinkToChannel.png)

5. Klikk `Copy` for å kopiere lenken til utklippstavlen.

![Get link to channel screenshot](/Images/LinkToChannelCopy.png)

6. Trekk ut Group Id og Channel Id fra lenkestrengen som vist nedenfor:

https://teams.microsoft.com/l/channel/<span style="color:red">19%3af221b1abbb214c4b8b5fe3d7e4074194%40thread.tacv2</span>/Request%2520Approvals?groupId=<span style="color:green">320312d1-e925-433f-80bc-4422f5395edf</span>&tenantId=32292181-0169-456b-b0a4-95fa4c5773a4

Teksten i <span style="color:red">rødt</span> er Channel Id. Teksten i <span style="color:green">grønt</span> er Group Id.

7. Gå til SharePoint-området opprettet som del av installasjonen.
8. Finn `Provisioning Request Settings`-listen og åpne den.
9. Rediger listeelementet `PostToTeams` og sett `Value`-feltet til `true`.
10. Rediger listeelementet `TeamsChannelID` og sett `Value`-feltet til Channel Id du trakk ut.
11. Rediger listeelementet `TeamsTeamID` og sett `Value`-feltet til Group Id du trakk ut.
12. Legg til tjenestekontoen som medlem i teamet – dette er påkrevd, ellers vil ikke kortene postes.

Godkjenninger bruker nå adaptive cards i Teams. Gå tilbake til denne seksjonen hvis du senere ønsker å bytte til Power Automate Approvals.

## Steg 5: Importere og aktivere flyten

Flyten `Provisioning Request Approval` er ikke en del av Azure-deployen — den lever i Power Automate i **tjenestekontoens** miljø. I miljøer som har hatt Bestillingsportalen tidligere finnes den gjerne allerede (hopp da til aktiveringen nedenfor); i en ny installasjon importeres den først.

### Importere flyten

Flyten distribueres som Power Platform-løsningspakken `Source/Flows/Bestillingsportalen-Flows_unmanaged.zip` (se [Source/Flows/README.md](/Source/Flows/README.md) for bakgrunn og vedlikehold av pakken).

> **Før import: gi tjenestekontoen rollen System Customizer i standardmiljøet.** Solution-flyter er Dataverse-poster, og Environment Maker-rollen alle brukere har automatisk i standardmiljøet dekker kun flyter *utenfor* solutions ([rolletabellen](https://learn.microsoft.com/power-platform/admin/database-security#summary-of-resources-available-to-predefined-security-roles)) — import og eierskap av solution-flyter krever **System Customizer**. Tildelingen krever Power Platform Administrator eller Global Administrator: Power Platform admin center → `Environments` → standardmiljøet → `Settings` → `Users + permissions` → `Users` → tjenestekontoen → **System Customizer**. Uten rollen feiler import eller aktivering med tilgangsfeil/`FlowNotOriginalAuthor` (se feilsøkingsboksen under «Aktivere flyten»).

1. Gå til Power Automate-portalen (make.powerautomate.com) logget inn som **tjenestekontoen** (flyten skal eies av og kjøre som den), i standardmiljøet (løsningsimport krever Dataverse, som standardmiljøet har).
2. Velg `Solutions` i venstremenyen → `Import solution` → last opp `Bestillingsportalen-Flows_unmanaged.zip`.

   ![Import solution - velg fil](/Images/FlowImportSelectFile.png)

3. På detaljsiden: verifiser at løsningen er **BestillingsportalenFlows**, og la avkrysningen under `Avanserte innstillinger` stå som den er. Flyten er pakket i Draft-tilstand og aktiveres uansett manuelt etter importen (siste seksjon i dette steget).

   ![Import solution - detaljer](/Images/FlowImportDetails.png)

4. Koble til/opprett de fem tilkoblingene (Teams, Approvals, Outlook, SharePoint, pluss en ekstra SharePoint-tilkobling som kreves for miljøvariablene) **som tjenestekontoen**. Grønn hake betyr klar.

   ![Import solution - tilkoblinger](/Images/FlowImportConnections.png)

5. Fyll inn de fire **environment variables**:
   - `ProvisionAssistSPOSite` — URL-en til Bestillingsportalen-området (f.eks. `https://<tenant>.sharepoint.com/sites/Bestillingsportalen`)
   - `ProvisioningRequestsList`, `ProvisioningRequestSettingslist`, `BusinessUnitsList` — listenavnene (standardverdiene matcher listene PnP-malen oppretter)

   ![Import solution - miljøvariabler](/Images/FlowImportEnvironmentVariables.png)

   > Veiviseren kan vise advarselen *«Du har ikke tilgang til områdeverdien for den valgte tilkoblingen»* på site-URL-en. Dette er et kjent falskt positiv når siten er nyopprettet (den ligger ikke i connectorens fulgte/indekserte site-liste ennå) — at liste-dropdownene populeres beviser at tilkoblingen leser siten. Ignorer advarselen og fortsett.
6. Etter import: åpne løsningen **«Bestillingsportalen Flows»** og verifiser at flyten `Provisioning Request Approval` finnes.

### Aktivere flyten

Flyten importeres i avslått tilstand (Draft) og må slås på manuelt som tjenestekontoen:

1. Gå til Power Automate-portalen (make.powerautomate.com) som tjenestekontoen og åpne løsningen **«Bestillingsportalen Flows»**.
2. Klikk på **`Provisioning Request Approval`** → `Turn on` i toppmenyen.

(Import-loggen kan vise `0x80048026` om språketiketter for språk 1033 — ren kosmetikk, ignorer.)

> **Feilsøking — «Du har ikke tilgang» / gul advarsel om tillatelser i miljøet (fwlink 2098112) / `FlowNotOriginalAuthor` ved aktivering:** Sjekk først at tjenestekontoen faktisk fikk rollen **System Customizer** i standardmiljøet (se «Før import»-noten i starten av dette steget, og skjermbilde under). Prøv deretter `Turn on` igjen; hjelper det ikke, åpne flyten i editoren (`Edit`), lagre uendret (re-provisjonerer flyten under kontoen) og slå på.
>
> ![Sikkerhetsroller for tjenestekontoen](/Images/FlowSecurityRoles.png)
>
> Vedvarer feilen med rollen på plass — typisk også med `Kan ikke bruke tilkoblingen … til shared_logicflows`-feil hvis du prøver `Edit` — kan årsaken være **lisensen**: flow-tjenesten nekter kontoer uten brukbar Power Automate-plan å eie/aktivere flyter — en konto uten gyldig lisens får dessuten access mode «Administrative» i Dataverse og kan da heller ikke importere ([kjent årsak](https://learn.microsoft.com/troubleshoot/power-platform/dataverse/working-with-solutions/install-failure-priviledge-not-assigned)). Merk at seeded Power Automate fra F-lisenser normalt er tilstrekkelig (verifisert i kundetenant) — feilen er kun sett én gang, i et utviklingsmiljø. Test ved å opprette en triviell flyt under `My flows` som tjenestekontoen. Merk at lisensendringer kan bruke litt tid på å propagere til flow-tjenesten — logg ut/inn og prøv igjen etter en stund før du feilsøker videre.

## Steg 6: Dele flyt og SharePoint-område

Før Bestillingsportalen kan rulles ut, må SharePoint-området deles med alle brukerne som skal sende inn bestillinger, og flyten eventuelt med administratorer.

### Flyt

Del flyten `Provisioning Request Approval` (godkjenningsprosessen for bestillinger, se [Godkjenningsflyt](/Approval-flow.md)) med administratorer som ønsker å se flyt-kjøringer eller redigere flyten. Dette steget er valgfritt, men unngår at du må logge inn med tjenestekontoen når du ser på flyt-kjøringer.

1. Gå til Power Automate-portalen (make.powerautomate.com) som tjenestekontoen.
2. Finn flyten **`Provisioning Request Approval`** og klikk `Share` i toppmenyen.
3. Legg til brukere eller grupper du vil dele flyten med, og velg `OK` i `Before you share`-dialogen.
4. Brukerne har nå tilgang til flyten.

### SharePoint-område

Stegene nedenfor deler SharePoint-området med sluttbrukere, slik at de får tilgang til å opprette/redigere bestillinger uten å endre backend-innstillinger i Bestillingsportalen.

1. Gå til SharePoint-området opprettet under installasjonen.
2. Klikk `Settings` _(tannhjulet)_ oppe til høyre.
3. Klikk `Site permissions`.
4. Klikk `Advanced Permissions settings`.
5. Klikk `Grant Permission` i toppmenyen og søk etter brukernavnet eller e-postadressen du vil dele området med, ELLER velg en gruppe med brukerne.
6. Klikk `Show Options` og velg `Visitors`-gruppen under `Permission level` (dette gir brukerne lesetilgang til området i første omgang).
7. Gå til `Provisioning Requests`-listen og [følg disse stegene](https://support.office.com/en-gb/article/customize-permissions-for-a-sharepoint-list-or-library-02d770f3-59eb-4910-a608-5f84cc297782) for å bryte arv av tilganger. Gi `Visitors`-gruppen `Edit`-rettigheter (dette sikrer at brukerne kan opprette bestillinger).

## Steg 7: Kjøre/konfigurere støttende Logic Apps

Det finnes noen støttende Logic Apps som bør kjøres manuelt etter første installasjon.

Disse er konfigurert med tilbakevendende triggere og kjører ukentlig som standard. Du kan endre kjørefrekvensen til en plan som passer organisasjonen din.

Detaljer om disse:

- **GetHubSites** – Henter alle Hub Sites i tenanten og oppretter dem som listeelementer i `Hub Sites`-listen.
- **GetSiteTemplates** – Henter alle SharePoint Site Templates installert i tenanten og oppretter dem som listeelementer i `Site Templates`-listen.
- **GetTeamsTemplates** – Henter Teams-maler konfigurert i Teams Admin Center og oppretter referanser til disse som listeelementer i `Teams Templates`-listen.
- **SyncGroupSettings** – Henter gruppe-innstillinger (blokkerte ord og klassifiseringer) fra Entra ID og oppdaterer listeelementer i `Provisioning Request Settings`-listen.
- **SyncLabels** – Henter alle sensitivitetsmerker fra Purview i tenanten og legger dem til i `IP Labels`-listen.

> **MERK:** `ProcessGuestRequest` Logic App trigges automatisk når et nytt element legges til i `Guest Requests`-listen (1-min polling) og skal **ikke** kjøres manuelt. Den deployes som del av `deploy.ps1`.

Slik kjører du dem «on demand»:

1. Gå til Azure Portal (portal.azure.com).
2. Finn ønsket Logic App, f.eks. `GetHubSites`. Du kan enten søke i søkefeltet eller finne ressursgruppen fra installasjonen og finne Logic App-en der.
3. Velg Logic App-en.
4. Klikk `Run Trigger > Run`.
5. Når Logic App-en har kjørt, skal statusen i kjørehistorikken være `Succeeded`.
6. Gjenta stegene for hver Logic App.

## Steg 8 (valgfritt): Aktivere Site Templates og Hub Sites

Før Hub Sites og Site Templates er synlige for sluttbrukere i Bestillingsportalen webdel eller Teams app, må de aktiveres.

Det finnes en Yes/No-kolonne kalt `Enabled` i `Hub Sites`- og `Site Templates`-listene. Hvis du vil gjøre en mal synlig for sluttbrukere, rediger listeelementet og sett kolonneverdien til `true`.

Årsaken til denne kolonnen er å gi administratorer fleksibilitet til å vise/skjule Site Templates og Hub Sites.

![Enabled column in Site Templates list](/Images/SiteTemplatesListEnabled.png)

## Steg 9: Sette opp administratorgruppe

Bestillingsportalen webdel eller Teams app bruker en innstilling i `Provisioning Request Settings`-listen for å avgjøre om «innstillinger»-skjermen skal vises for en bruker i webdel/Teams app. Innstillingene for løsningen kan konfigureres via denne skjermen som et alternativ til å bruke innstillingslisten i SharePoint-området. *Denne skjermen er eksperimentell og anses som under arbeid.* Innstillingene skal kun være synlige for administratorer av Bestillingsportalen. Før du følger stegene, opprett en av følgende (eller bruk en eksisterende) som inneholder administratorene for Bestillingsportalen:

- Microsoft 365-gruppe (kan være samme som Bestillingsportalen SPO-området bruker) ELLER
- Microsoft Teams-team ELLER
- Entra ID Security Group

Hent ID-en til ressursen du opprettet eller en eksisterende du gjenbruker, og følg stegene nedenfor:

1. Gå til SharePoint-området opprettet som del av installasjonen.
2. Finn `Provisioning Request Settings`-listen og åpne den.
3. Rediger listeelementet `AdminGroupId` og sett `Value`-feltet til ID-en fra over.
4. Lagre listeelementet.

Administratorgruppen er nå satt opp og konfigurert.

## Installasjonen av løsningen er nå fullført, og Bestillingsportalen webdel eller Teams app skal være tilgjengelig

## Steg 10 (valgfritt): Aktivere automatisk godkjenning (deaktivere godkjenningsprosess)

Hvis du ikke ønsker å bruke den innebygde Power Automate-godkjenningsprosessen, kan du aktivere `Auto approval` via `Provisioning Request Settings`-listen.

For å aktivere, gå til innstillingslisten, rediger listeelementet `EnableAutoApproval` og sett `Value`-kolonnen til `true`.

Når brukere sender inn bestillinger via Bestillingsportalen webdel eller Teams app, settes statusen til `Approved`. Godkjenningsflyten kjører da ikke, og provisjoneringsprosessen starter umiddelbart.

## Merknad: Bestillings-webdelen distribueres separat

Selve bestillings-webdelen (grensesnittet der brukerne bestiller samarbeidsområder) inngår ikke i dette repoet — per i dag følger den **Prosjektportalen**-leveransen. Etter at den er tilgjengelig i tenanten:

1. Legg webdelen inn manuelt på en SharePoint-side der brukerne skal bestille.
2. Sett URL-egenskapen i webdelens property pane til den **absolutte URL-en** til Bestillingsportalen-området (f.eks. `https://<tenant>.sharepoint.com/sites/Bestillingsportalen`) slik at bestillingene skrives til riktige lister.

Husk også at brukerne må ha tilgang til området og `Provisioning Requests`-listen (Steg 6) før de kan bestille.

## Merknad: Aktivere Teams-appen for Bestillingsportalen (krever Prosjektportalen)

Bestillingsportalen finnes også som Teams-app, slik at brukerne kan bestille samarbeidsområder direkte fra Teams. Teams-app-manifestet følger med SPFx-pakken **Prosjektportalen 365 - Portfolio Web Parts** (`pp-portfolio-web-parts`) — akkurat som webdelen i merknaden over krever dette derfor at [Prosjektportalen 365](https://github.com/Puzzlepart/prosjektportalen365) er installert i tenanten, slik at pakken ligger i tenant app-katalogen.

1. **Synkroniser pakken til Teams.** Som Teams og SharePoint-administrator: gå til tenant app-katalogen og åpne `Apps for SharePoint`-biblioteket. Merk pakken **Prosjektportalen 365 - Portfolio Web Parts** (`pp-portfolio-web-parts`) og klikk **`Sync to Teams`** i `FILES`-båndet.

   ![Sync to Teams fra tenant app-katalogen](/Images/teamsapp-step1.png)

2. **Kontroller appen i Teams admin center.** Som Teams-administrator: gå til [Teams admin center](https://admin.teams.microsoft.com/policies/manage-apps) → `Teams apps` → `Manage apps` og søk etter **Bestillingsportalen**. Kontroller at `App status` står som `Unblocked` og at `Available to` dekker brukerne som skal ha appen (f.eks. `Everyone`). Hvordan du styrer tilgjengeligheten og eventuelt pinner appen automatisk for brukerne er beskrevet i underseksjonene nedenfor.

   ![Bestillingsportalen i Teams admin center](/Images/teamsapp-step2.png)

3. **Finn appen i Teams-klienten.** Gå til `Apper` → **`Bygget for organisasjonen din`** og finn **Bestillingsportalen**. Det kan ta litt tid (opptil noen timer) fra synkroniseringen til appen dukker opp her.

   ![Bestillingsportalen under Bygget for organisasjonen din i Teams](/Images/teamsapp-step3.png)

4. **Legg til appen.** Klikk på appen og velg **`Legg til`**.

   ![Legg til Bestillingsportalen i Teams](/Images/teamsapp-step4.png)

Bestillingsportalen åpnes nå som en egen app i Teams, med samme grensesnitt som webdelen — brukerne kan bestille områder direkte herfra:

![Bestillingsportalen åpnet som app i Teams](/Images/teamsapp-startpage.png)

Teams-appen bruker samme oppsett som webdelen: bestillinger sendt fra Teams skrives til de samme listene og behandles av den samme godkjenningsflyten (Steg 4–6 gjelder altså uendret). Husk at brukerne må ha tilgang til området og `Provisioning Requests`-listen (Steg 6) også når de bestiller fra Teams.

### Tilgjengeliggjøre appen for flere brukere

Hvem som ser og kan legge til appen styres per app via **app centric management** ([Microsoft Learn: App centric management](https://learn.microsoft.com/en-us/microsoftteams/app-centric-management)) — dette har erstattet de gamle app permission policies i de fleste tenanter (alle tenanter migreres automatisk fra april 2025):

1. Gå til [Teams admin center](https://admin.teams.microsoft.com/policies/manage-apps) → `Teams apps` → `Manage apps` og åpne **Bestillingsportalen**.
2. Velg fanen **`Users and groups`** → **`Availability`** → **`Edit availability`**.
3. Velg under `Available to`:
   - **`Everyone`** — alle brukere i organisasjonen (anbefalt hvis alle skal kunne bestille).
   - **`Specific users or groups`** — kun valgte brukere/grupper (sikkerhetsgrupper, Microsoft 365-grupper, dynamiske grupper og distribusjonslister støttes; maks 99 om gangen).
   - **`No one`** — appen skjules for alle (tilsvarer gammel «blocked»).
4. Klikk `Apply`.

> Endringer i tilgjengelighet kan ta **opptil 24 timer** å slå gjennom for alle brukere. Bruker tenanten fortsatt gamle [app permission policies](https://learn.microsoft.com/en-us/microsoftteams/teams-app-permission-policies) (synlig under `Teams apps` → `Permission policies`), styres tilgangen der i stedet, med samme prinsipp: appen må være `Allowed` i policyen som er tildelt brukerne.

Merk at app-tilgjengelighet kun styrer hvem som ser appen i Teams — tilgang til selve bestillingsdataene styres fortsatt av SharePoint-tilgangene i Steg 6.

### Pinne appen automatisk for brukerne (valgfritt)

Vil du at Bestillingsportalen skal ligge ferdig i app-linjen i Teams (venstre side på desktop, nederst på mobil) uten at brukerne selv må legge den til, bruk en **app setup policy** ([Microsoft Learn: App setup policies](https://learn.microsoft.com/en-us/microsoftteams/teams-app-setup-policies)):

1. Gå til [Teams admin center](https://admin.teams.microsoft.com/policies/app-setup) → `Teams apps` → `Setup policies`.
2. Skal appen pinnes for **alle**: rediger **`Global (Org-wide default)`**. Skal den pinnes for **utvalgte brukere**: klikk `Add` og opprett en egen policy (en tilpasset policy overstyrer den globale for brukerne den tildeles).
3. Under **`Pinned apps`**, klikk **`Add apps`**, søk etter **Bestillingsportalen** og velg `Add`.
4. Dra appen til ønsket plassering i rekkefølgen under `App bar`, og klikk `Save`.
5. Opprettet du en egen policy: tildel den til brukere eller grupper — se [Assign policies to users and groups](https://learn.microsoft.com/en-us/microsoftteams/assign-policies-users-and-groups).

Nyttig å vite:

- **`User pinning`**-innstillingen i policyen avgjør om brukerne selv kan pinne/flytte apper. Er den på, vises brukernes egne pins under admin-pinnede apper; er den av, mister brukerne sine egne pins og ser kun de admin-pinnede.
- Pinning respekterer tilgjengeligheten over: appen pinnes bare for brukere den faktisk er tilgjengelig for.
- Policyendringer kan ta **noen timer** å slå gjennom i klientene.
