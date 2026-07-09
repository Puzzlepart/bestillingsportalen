# Installasjonsveiledning

## Forutsetninger

For å komme i gang trenger du:

- Power Automate (seeded licenses) aktivert og utrullet i organisasjonen.
- Fakturerbart Azure-abonnement i samme tenant som du skal installere Bestillingsportalen i.
- Tjenestekonto (brukes av Logic Apps for å koble til SPO, Outlook og Teams) med en passende Microsoft 365-lisens (denne kontoen skal IKKE være admin). Denne kontoen KAN ha MFA.
- Tjenestekonto for sensitivitetsmerke-funksjonalitet (anvendelse av sensitivitetsmerker), hvis du vil bruke funksjonaliteten. Kan være samme konto som over, men kontoen kan være forhindret fra å bruke MFA grunnet begrensninger i Microsoft Graph. Verifiser mot gjeldende [Microsoft Graph-dokumentasjon](https://learn.microsoft.com/en-us/graph/api/resources/security-api-overview) da denne begrensningen kan ha blitt fjernet.
- Windows 10/11-maskin for å kjøre PowerShell-installasjonsskriptet.
- PowerShell 7 lastet ned og installert – <https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4>.
- Azure CLI (Command Line Interface) – <https://learn.microsoft.com/en-us/cli/azure/install-azure-cli>.
- **Node.js 22.14.0** eller nyere – <https://nodejs.org/> (kun nødvendig hvis SPFx-løsninger skal bygges; kan hoppes over med `-SkipSPFxDeploy`). Se [`.nvmrc`](Source/SharePointFramework/ProvisionWebParts/.nvmrc) for eksakt versjon.
- **Tenant app-katalog opprettet** i SharePoint Admin Center – kreves for å publisere SPFx-pakker (`.sppkg`). Se <https://learn.microsoft.com/en-us/sharepoint/use-app-catalog>.
- Brannmur/Proxy konfigurert til å tillate tilkobling via Azure CLI – test at `az login` fungerer før du fortsetter.
- Global Administrator (for å kjøre `createentraidapp.ps1`-skriptet og opprette/autorisere PnP app registration).
- Brukerkonto med **Owner**-rettigheter til Azure-abonnementet, som også er SharePoint, Power Platform og Teams Administrator.
- App Registration for PnP PowerShell (se nedenfor).

> **Managed identity:** Logic Apps autentiserer mot Microsoft Graph, SharePoint REST, Key Vault og Azure Automation med en user-assigned managed identity som opprettes av installasjonsskriptet. Det trengs derfor ikke noe sertifikat, og client secret opprettes kun hvis sensitivitetsmerke-funksjonaliteten aktiveres. Kontoen som kjører `deploy.ps1` må kunne tildele app-roller til managed identities (Global Administrator, ev. Privileged Role Administrator + Cloud Application Administrator). Se [Migrering til managed identity](Managed-identity-migration.md).

#### PnP PowerShell App Registration

PnP PowerShell støtter ikke lenger alternativet `multi-tenant app registration`. Dette opprettet tidligere en app registration automatisk for PnP PowerShell med alle nødvendige tilganger.

For å autentisere og bruke PnP PowerShell framover må du opprette din egen app registration med de nødvendige tillatelsene.

Før du kjører installasjonsskriptet for Bestillingsportalen, sørg for at du har opprettet denne app-en og har sertifikatet og passordet tilgjengelig.

Minimumskravene til PnP app registration for å kunne kjøre installasjonsskriptet er:

**Microsoft Graph**

- Group.Create
- Group.Read.All

**SharePoint**

- Sites.FullControl.All

Når installasjonen av Bestillingsportalen er fullført, kan du slette PnP PowerShell app registration eller fjerne tilgangene hvis du ikke trenger dem.

Mer informasjon om endringer i PnP PowerShell-autentisering finner du [her](https://pnp.github.io/blog/post/changes-pnp-management-shell-registration/).

Se [denne videoen](https://www.youtube.com/watch?v=ecRZrHOucz4&t=359s) for hvordan du oppretter og bruker app registration.

Hvis `Sites.FullControl.All` er et problem, kan du opprette SharePoint-området for Bestillingsportalen manuelt og sørge for at navnet i `parameters.json` matcher navnet på området du opprettet.

#### PowerShell 7.x

Installasjonsskriptet for Bestillingsportalen krever PowerShell 7 og støtter ikke lenger 5.1. Sørg for at PowerShell 7 er installert før du installerer PowerShell-modulene nedenfor.

#### PowerShell-moduler

Følgende PowerShell-moduler brukes av installasjonsskriptet og må installeres før skriptet kjøres:

- PnP.PowerShell (3.1)
- Az
- ImportExcel
- WriteAscii

## Steg 1: Konfigurere PowerShell

1. Last ned [nyeste utgave](https://github.com/Puzzlepart/bestillingsportalen/releases/latest) av Bestillingsportalen.
2. Start PowerShell 7 som administrator.
3. Sett PowerShell Execution Policy til `Unrestricted` ved å kjøre ```Set-ExecutionPolicy -ExecutionPolicy unrestricted```.

## Steg 2: Oppdatere parameters.json

Du finner en `parameters.json`-fil i Scripts-mappen. Oppdater alle parametre med korrekte verdier for tenanten din.

Erstatt `<<value>>` med passende verdier for alle påkrevde parametre.

Beskrivelse av hver parameter:

- `tenantId` – ID til tenanten du skal installere i. Finnes i Microsoft Entra ID-bladet.

- `spoTenantName` – Navnet på SharePoint-tenanten eksklusivt `.sharepoint.com`, f.eks. `puzzlepart`.

- `fullTenantName` – Fullt tenant-navn inklusive `.onmicrosoft.com`, f.eks. `puzzlepart.onmicrosoft.com`.

- `requestsSiteName` – Navn på SharePoint-området som skal lagre bestillinger (URL/alias genereres automatisk). Kan inneholde mellomrom. Hvis området finnes, spørres det om overskriving og PnP-provisjoneringsmal anvendes.

- `requestsSiteDesc` – Beskrivelse av området som opprettes.

- `managedPath` – Managed path konfigurert i tenanten, f.eks. `sites` eller `teams` (uten skråstrek).

- `subscriptionId` – Azure-abonnement som løsningen installeres i (MÅ være tilknyttet Entra ID-katalogen til Microsoft 365-tenanten du installerer i).

- `region` – Azure-region der ressursene opprettes. Bruk internt navn, f.eks. `norwayeast`. Plasseringen MÅ støtte Automation og Logic Apps. Se [Valid Azure locations](https://azure.microsoft.com/en-gb/explore/global-infrastructure/products-by-region/?products=logic-apps%2Cautomation&regions=all).

- `resourceGroupName` – Navn på ny ressursgruppe løsningen installeres i. Skriptet oppretter denne.

- `appName` – Navn på Entra ID-appen som opprettes, f.eks. `Bestillingsportalen`.

- `uamiName` (**valgfritt**) – Navn på user-assigned managed identity som opprettes og brukes av Logic Apps. Standard er `bestillingsportalen-uami`.

- `pnpAppId` – ID til PnP Entra-app registration du opprettet da du konfigurerte PnP PowerShell.

- `pnpCertPath` – Sti til PnP-sertifikatet på din lokale maskin som du opprettet da du konfigurerte PnP PowerShell.

- `siteLogoPath` (**valgfritt**) – Sti til en firmalogo (ideelt lagret i SharePoint) som alle brukere har tilgang til, brukes som logo for opprettede områder. Sørg for at stien peker til et bilde. Hvis du ikke har et bilde, la dette stå tomt.

- `serviceAccountUPN` – UPN til tjenestekontoen som brukes i løsningen – brukes til å koble Logic App API connections. Tjenestekontoen skal være en standard Microsoft 365-bruker med SPO/Exchange/Teams-lisenser. Se [Assign licenses to users](https://learn.microsoft.com/en-us/microsoft-365/admin/manage/assign-licenses-to-users?view=o365-worldwide).

- `isEdu` – Angir om tenanten er en Education-tenant. Hvis `true`, installeres Education Teams Templates. Disse hoppes over hvis `false` eller blank.

- `KeyVaultName` – Navn på Key Vault som installasjonsskriptet oppretter. Key Vault lagrer `app id` og `secret` for Entra ID-appen samt tjenestekonto-credentials (alle kun i bruk når sensitivitetsmerke-funksjonaliteten er aktivert). Navnet må være unikt på tvers av Azure-regionen du installerer i. Hvis en Key Vault med samme navn eksisterer ***i*** det aktuelle abonnementet, kan den brukes. **MERK – HVIS DU BRUKER EN EKSISTERENDE KEY VAULT, VIL DEN BLI OVERSKREVET OG KONFIGURASJON SOM ROLE ASSIGNMENTS GÅR TAPT. VI ANBEFALER EN DEDIKERT KEY VAULT FOR Bestillingsportalen.** Skriptet validerer at navnet er tilgjengelig, og hvis ikke må et annet navn oppgis.

- `enableSensitivity` – Aktiverer sensitivitetsmerke-funksjonaliteten. Merk – dette krever en tjenestekonto UTEN MFA. Kan være samme tjenestekonto som over.

- `skipApplySPOTemplate` – Hopper over anvendelse av PnP-mal på SharePoint-området. La stå som `false` med mindre du har en spesifikk grunn til å hoppe over dette.

## Steg 3: Kjør skriptene

### Opprettelse av Entra ID-app

Første steg er å kjøre det dedikerte skriptet som oppretter Entra ID-appen og gir admin consent for Microsoft Graph API-tillatelsene.

**Denne delen av installasjonen krever en brukerkonto med Global Administrator-tilgang.**

1. Åpne et PowerShell 7-vindu som administrator.
2. Gå til `Scripts`-mappen.
3. Kjør `createentraidapp`-skriptet i PowerShell-vinduet – ```.\createentraidapp.ps1```.
4. Oppgi et navn for Entra ID-appen når du blir spurt (**Dette må være samme navn som `appName`-parameteren i `parameters.json`**).
5. Vent til skriptet er ferdig.

### Installasjon av ressurser

Neste steg er å kjøre deploy-skriptet.

**Sørg for at kontoen du bruker på dette steget har owner-rettigheter til Azure-abonnementet, er SharePoint Administrator, og kan tildele app-roller til managed identities.**

**Hvis sensitivitetsmerke-funksjonaliteten aktiveres, genererer installasjonsskriptet en secret for Entra ID-appen opprettet over (standard utløpstid 1 år, brukes kun av ROPC-flyten for sensitivitetsmerker). For detaljer om hvordan du fornyer secret-en når den utløper, se [Fornye App Secret](./Refreshing-app-secret.md).**

Siden skriptet bruker flere PowerShell-moduler under installasjon, vil det be om autentisering flere ganger.

1. Åpne et PowerShell 7-vindu som administrator.
2. Gå til `Scripts`-mappen.
3. Kjør deploy-skriptet i PowerShell-vinduet – ```.\deploy.ps1```.

Du blir bedt om passordet for PnP app registration-sertifikatet underveis.

Hvis du aktiverer sensitivitetsmerke-funksjonaliteten, vises en dialog som ber om passordet for tjenestekontoen. Fullfør dialogen.

På slutten av kjøringen skriver skriptet ut en **DEPLOYMENT SUMMARY** — en statuslinje per delkomponent (SharePoint-område, Entra ID-app, Azure-ressurser, app-roller, runbooks, API-tilkoblinger, hver Logic App og SPFx-pakkene) med `OK`, `FAILED`, `WARNING` eller `SKIPPED`. Oppsummeringen vises også hvis skriptet stopper på en feil underveis, slik at du ser hvilke komponenter som rakk å fullføre.

- Vises **«DEPLOYMENT COMPLETED SUCCESSFULLY»**: gå videre til neste steg.
- Vises **«DEPLOYMENT COMPLETED WITH ERRORS»** (exit-kode 1): se hvilke komponenter som feilet i oppsummeringen, rett årsaken og kjør skriptet på nytt. Vær særlig oppmerksom på `App roles`-linjene — feiler disse vil Logic Apps få 401/403 ved kjøring selv om alt annet ser vellykket ut.

**Skriptet kan kjøres på nytt så mange ganger som nødvendig uten at ressurser må slettes — fullførte komponenter oppdateres idempotent.** Ved re-kjøring mot et eksisterende miljø:

- Eksisterende Entra ID-app, SharePoint-område og Key Vault gjenkjennes (du får spørsmål der det er relevant).
- På spørsmålet om PnP-malen: svar **`n`** for å beholde alt eksisterende listeinnhold urørt (skriptet henter da bare liste-ID-ene). Svar **`y`** kun hvis du vil nullstille konfigurasjonslistene (Settings, Provisioning Types, Teams Templates m.fl.) til pakkens standardverdier — bestillingsdata (Provisioning Requests / Guest Requests) røres aldri.
- App-roller sjekkes per rolle og tildeles kun det som mangler; Logic Apps og API-tilkoblinger oppdateres til malens definisjon.
- Med `enableSensitivity` aktivert roteres appens client secret ved hver kjøring (Key Vault oppdateres automatisk i samme kjøring).
- Sjekk at de delegerte API-tilkoblingene fortsatt står som `Connected` etterpå — en re-deploy kan i noen tilfeller kreve re-autorisering.

**For senere oppdateringer av et miljø i drift, bruk `./deploy.ps1 -Upgrade`** (se [Oppgraderingsveiledning](/Upgrade.md)) — den hopper over listeutfylling og områdeoppsett helt.

### Autorisere API-tilkoblinger

Skriptet oppretter flere API-tilkoblinger som må autoriseres manuelt.
I Microsoft Azure Portal, gå til ressursgruppen som ble opprettet av skriptet.

1. Klikk på API-tilkoblingen med navnet `bestillingsportalen-o365`.
2. Klikk `Edit API connection` i venstre meny.
3. Klikk `Authorize`. Bruk tjenestekontoen for å autentisere.
4. Gjenta handlingene for `bestillingsportalen-o365users`, `bestillingsportalen-spo` og `bestillingsportalen-teams` API-tilkoblinger.

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

Innstillingene for Bestillingsportalen finnes i `Provisioning Request Settings`-listen som nøkkel/verdi-par (Title/Value). Begge kolonnene er `Single line of text`.

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

## Steg 5: Aktivere `Provisioning Request Approval`-flyten

**`Provisioning Request Approval`** er avslått som standard og må aktiveres.

Følg stegene for å aktivere den:

1. Gå til Power Automate-portalen (make.powerautomate.com) som tjenestekontoen.
2. Finn flyten **`Provisioning Request Approval`**.
3. Klikk på flyten.
4. Klikk `Turn on` i toppmenyen.

## Steg 6: Dele flyter og SharePoint-område

Før Bestillingsportalen kan rulles ut, må flytene og SharePoint-området deles med alle brukerne som skal sende inn bestillinger.

### Steg 6a (midlertidig): Overskriv runbookene `ConfigureSpace` og `AddGuestToSite`

Under installasjonen hentes runbook-innholdet fra et offentlig repo (plassholder til dette repoet er offentlig), og **begge** disse runbookene MÅ erstattes med versjonene i dette repoet før løsningen tas i bruk:

- **`ConfigureSpace`** – [Source/Runbooks/ConfigureSpace.ps1](/Source/Runbooks/ConfigureSpace.ps1)
- **`AddGuestToSite`** – [Source/Runbooks/AddGuestToSite.ps1](/Source/Runbooks/AddGuestToSite.ps1). Merk: denne deployes med `ConfigureSpace`-innhold som plassholder – uten innliming vil hele gjesteinvitasjonsflyten kjøre feil skript.

For hver runbook: Azure Portal → Automation-kontoen `bestillingsportalen-auto` → `Runbooks` → velg runbooken → `Edit` → lim inn innholdet fra filen over → `Publish`.

(`GetSiteTemplates`-runbooken er identisk med upstream-versjonen og trenger ikke å erstattes.)

### Flyter

Del flytene som brukes av Bestillingsportalen med administratorer som ønsker å se flyt-kjøringer eller redigere flytene. Dette steget er valgfritt, men unngår at du må logge inn med tjenestekontoen når du ser på flyt-kjøringer. Gjenta stegene for hver flyt.

To flyter leveres med Bestillingsportalen:

- **Provisioning Request Approval** – Gir godkjenningsprosess for bestillinger. Se [Godkjenningsflyt](/Approval-flow.md) for detaljer.
- **Check Space Availability** – Sjekker om et område som matcher angitt tittel/URL allerede finnes. Bruker `Office 365 Groups`-connector for å sjekke om en gruppe med samme detaljer finnes, og sjekker også `Provisioning Requests`-listen for en matchende bestilling. Brukere kan kun fortsette hvis området ikke finnes og ingen bestilling med samme navn finnes. Hvis en bestilling finnes i listen og ble opprettet av SAMME bruker, blir brukeren bedt om å redigere den andre bestillingen i stedet.

1. Gå til Power Automate-portalen (make.powerautomate.com) som tjenestekontoen.
2. Finn flyten **`Provisioning Request Approval`** og klikk `Share` i toppmenyen.
3. Legg til brukere eller grupper du vil dele flyten med, og velg `OK` i `Before you share`-dialogen.
4. Gjenta stegene for `Check Space Availability`-flyten.
5. Brukerne har nå tilgang til flytene.

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
