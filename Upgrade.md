# Oppgradere Bestillingsportalen

Denne veiledningen forklarer hvordan du oppgraderer en eksisterende Bestillingsportalen-installasjon for å få den nyeste funksjonaliteten og feilrettinger uten å bygge opp miljøet på nytt eller miste eksisterende data.

## Oversikt

Oppgraderingsprosessen lar deg:

- Anvende de nyeste PnP-mal-oppdateringene (feltdefinisjoner, content types, views osv.)
- Oppdatere Logic App-ene `ProcessProvisionRequest` og `ProcessGuestRequest` med de nyeste arbeidsflyt-forbedringene
- Bygge og publisere SPFx-løsninger (f.eks. `InviteGuests`-webdelen) til tenant app-katalog
- Registrere installasjonen i tenant-registeret `bp_ProvisionUrls` (storage entity) som webdelene og Teams-appen bruker til å finne området — eksisterende miljøer uten registeret får det opprettet ved første re-deploy; frem til da gjelder standard-URL-en `/sites/bestillingsportalen` som før
- Beholde alle eksisterende listedata (provisioning types, innstillinger, bestillinger osv.)
- Minimere nedetid og konfigurasjonsendringer

## Oppgradering til 2.1.0 i tenanter med Prosjektportalen 365 — rekkefølgen er obligatorisk

Fra og med 2.1.0 følger bestillings-webdelen (ProjectProvision, komponent-id `e88cea29-09a0-4ce4-a38c-e0d74b65f619`) med `bp-provision-web-parts.sppkg`. Til og med Prosjektportalen 365 1.14 fulgte samme komponent med PP365-pakken `pp-portfolio-web-parts`. Tenant app-katalogen tillater ikke to pakker som registrerer samme komponent-id, så i tenanter som også kjører Prosjektportalen 365 **må** oppgraderingen gjøres i denne rekkefølgen, helst i samme vedlikeholdsvindu:

1. **Oppgrader Prosjektportalen 365** til en versjon der webdelen er fjernet fra `pp-portfolio-web-parts`. Eksisterende `Bestillingsportalen.aspx`-sider viser nå «finner ikke komponenten» — det er forventet.
2. **Distribuer denne løsningen** (2.1.0 eller nyere) med `deploy.ps1`. Sidene og Teams-appen virker igjen umiddelbart — komponent-id-en er beholdt, og sidene refererer bare til id-en.
3. **Oppdater Teams-appen og verifiser at den åpner i Teams.** `deploy.ps1` produserer Teams-app-pakken (`sharepoint/solution/bestillingsportalen-teams-app.zip`) og forsøker å publisere den til Teams-appkatalogen via Graph — men det krever delegert `AppCatalog.ReadWrite.All` på PnP-appen, som de fleste tenanter ikke gir. **Regn med å laste opp zip-en manuelt** i Teams admin center (skriptet minner om det på slutten av kjøringen): fantes appen fra PP365-synkroniseringen, åpne den og bruk `Last opp fil`; ellers `Administrer apper` → `Last opp ny app`. Se [Teams-appen](Deployment-guide.md#teams-appen) i installasjonsveiledningen. Ikke bruk `Sync to Teams`-knappen i SharePoint-appkatalogen — den er upålitelig (deaktivert eller «failed to sync» i mange tenanter).

Omvendt rekkefølge er ikke mulig: distribusjon av `bp-provision-web-parts` 2.1.0 feiler i appkatalogen så lenge en PP365-pakke med komponenten fortsatt er distribuert. Tenanter **uten** Prosjektportalen 365 oppgraderer som normalt uten ekstra steg.

## Når du skal bruke oppgraderingsmodus

Bruk oppgraderingsmodus når du vil:

- Oppdatere en eksisterende Bestillingsportalen-installasjon til en nyere versjon
- Anvende mal-endringer uten å nullstille listedata
- Oppdatere den sentrale provisjonerings-Logic App-en
- Få ny funksjonalitet eller feilrettinger uten en full nyinstallasjon

**IKKE bruk oppgraderingsmodus for:**

- Førstegangs installasjon (bruk standard installasjonsprosess)
- Større breaking changes som krever datamigrering
- Komplette miljørebygginger
- **Migrering til managed identity** – installasjoner fra før managed identity-migreringen (2.0.0) må kjøre én full `deploy.ps1` (uten `-Upgrade`) først, slik at managed identityen, tilgangene og API-tilkoblingene opprettes. Oppgraderingsmodus feiler med en tydelig melding hvis managed identityen ikke finnes. Re-autoriser deretter de fire delegerte API-tilkoblingene med tjenestekontoen (`Authorize-ApiConnections.ps1`) — en redeploy av tilkoblingsressursene kan nullstille autoriseringen — og rydd bort restene fra den gamle modellen, se [Manuell opprydding](#manuell-opprydding-etter-oppgradering-key-vault-og-entra-id-appen) nedenfor. **Skal du oppgradere et slikt miljø, følg [Oppgradere fra versjoner før 2.0](Upgrade-from-pre-2.0.md)** — den dekker kartlegging, tilganger, parametermigrering, kjøreplan og opprydding for dette tilfellet spesielt.

## Hva som blir oppdatert

### ✅ Oppdateres i oppgraderingsmodus

1. **Anvendelse av PnP-mal** (valgfritt — se prompt-beskrivelsen lenger ned)
   - Site columns og content types
   - Liste-skjema og feltdefinisjoner (legger til nye lister som `Guest Requests`, nye felter osv.)
   - Views og forms
   - Web parts og side-layouts
   - **Navigasjon beholdes:** I oppgraderingsmodus brukes ikke `-ClearNavigation`, så egendefinerte nav-lenker bevares

2. **Logic Apps**
   - `ProcessProvisionRequest` — hovedflyten for områdeprovisjonering
   - `ProcessGuestRequest` — wrapper-flyten som lytter på `Guest Requests`-listen og kaller `ProcessGuests`
   - `ProcessGuests` — selve invitasjonsflyten mot Graph. Oppgraderes sammen med kalleren, siden de to utveksler felter (f.eks. bestilleren som skal registreres som gjestens sponsor)
   - Komplett erstatning av arbeidsflytene med nyeste versjon, oppdatert feilhåndtering

3. **Runbooks** — `runbooks.bicep` deployes ALLTID, også med `-SkipBicepDeploy`
   - De tre repo-eide runbookene (`ConfigureSpace`, `GetSiteTemplates`, `AddGuestToSite`) + PowerShell 7.4-runtime-miljøet opprettes/oppdateres
   - **Runbook-innholdet lastes opp direkte fra `Source/Runbooks/` og publiseres** — alltid i sync med repoet. Merk: endringer gjort direkte i Azure Portal overskrives ved hver deploy/upgrade; tilpasninger skal gjøres i repoet.
   - `CustomerSpecific` opprettes hvis den mangler, men **overskrives aldri** (kundeeid innhold — tilpasninger legges der)

4. **SPFx-løsninger** (med mindre `-SkipSPFxDeploy` brukes)
   - Alle løsninger under `Source/SharePointFramework/*/` med `config/package-solution.json`
   - `npm install` (kun ved første gang / hvis `node_modules` mangler) + `npm run build`
   - `.sppkg` lastes opp til tenant app-katalog via `Add-PnPApp -Overwrite -Publish`
   - Eksempel: `InviteGuests`-webdel for invitasjon av gjester

### ❌ Oppdateres IKKE i oppgraderingsmodus

1. **Listedata** – Alle eksisterende elementer beholdes uendret:
   - Provisioning Request Settings
   - Provisioning Types (egne typer du har lagt til)
   - Site Templates
   - Hub Sites
   - Teams Templates
   - Time Zones
   - Locales
   - IP Labels
   - Eksisterende provisioning requests

   **Merk:** PnP-malen seeder standardelementer via `<pnp:DataRows>` med `UpdateBehavior="Skip"`. Eksisterende elementer røres aldri, men **manglende standardelementer legges til** når malen anvendes — det er slik nye innstillinger i en release når oppgraderte miljøer. To konsekvenser: standardelementer som bevisst er slettet (f.eks. en fjernet områdetype) kommer tilbake ved oppgradering (sett heller `Allowed` til `false`), og standardelementer må ikke gis nytt navn — `Title` er nøkkelen som avgjør om elementet finnes (unntatt Time Zones, som bruker `TimeZoneId`), så et omdøpt element re-opprettes som duplikat.

2. **Ressurser (bilder/ikoner):**
   - Bilder for Provisioning Types
   - Ikoner for Provisioning Types
   - Andre opplastede filer

3. **Andre Azure-ressurser:**
   - Azure Automation Account
   - Innholdet i `CustomerSpecific`-runbooken (kundeeid utvidelsespunkt — overskrives aldri; de tre repo-eide runbookene oppdateres derimot alltid fra `Source/Runbooks/`)
   - User-assigned managed identity (app-rollene synkroniseres likevel – `AssignUamiPermissions` kjøres også i oppgraderingsmodus)
   - Andre Logic Apps (`GetSiteTemplates`, `GetHubSites` osv.)
   - API Connections

## Manuell opprydding etter oppgradering: Key Vault og Entra ID-appen

Fra denne versjonen har løsningen **ingen Key Vault, ingen client secret og ingen egen Entra ID-app-registrering**. Sensitivitetsmerker settes app-only med Automation-kontoens managed identity, så ROPC-flyten som krevde en tjenestekonto uten MFA er borte. Se [Sensitivitetsmerker](./Sensitivity-labels.md).

**ARM sletter ikke ressurser som fjernes fra en mal.** Disse blir derfor liggende igjen etter oppgradering og må ryddes manuelt:

| Rest | Handling |
|--|--|
| Key Vault (`kv-…`) med secrets `appid`, `appSecret`, `sausername`, `sapassword` | Slett Key Vault-en. Den brukes ikke av noe lenger. |
| API-tilkoblingen `bestillingsportalen-kv` | Slett tilkoblingen (ingen Logic App refererer til den). |
| Entra ID-app-registreringen (`Bestillingsportalen`) med client secret | Slett app-registreringen. Merk: **ikke** PnP-appen (`pnpAppId`), som er en annen app og brukes under installasjon. |
| `appName` og `keyVaultName` i `parameters.json` | Fjern nøklene – de leses ikke lenger. |

**Roter tjenestekontoens passord.** Har miljøet kjørt med `enableSensitivity = true` på en tidligere versjon, har passordet, client secret-en og et delegert Graph-token ligget lesbart i `ProcessProvisionRequest`s kjørehistorikk. Oppgraderingen fjerner kilden, men sletter ikke historikken. Roter passordet, og re-autoriser deretter de fire delegerte API-tilkoblingene (`Authorize-ApiConnections.ps1`).

MFA kan nå slås på for tjenestekontoen. Den brukes fortsatt som områdeeier, til de delegerte API-tilkoblingene og til å poste velkomstmeldingen i Teams – men ingen av disse krever at MFA er avslått.

### Den interaktive `Site already exists`-prompten

Når scriptet oppdager at Bestillingsportalen-området allerede finnes, spørres du:

```text
Do you wish to re-apply the PnP provisioning template?
  y = re-apply template (updates lists, fields and settings on the existing site)
  n = skip template apply, but continue with Logic Apps / SPFx / other deploy steps
```

- **Svar `y`** når oppgraderingen inneholder skjema-endringer (nye lister, nye felter) — f.eks. ved å rulle ut `Guest Requests`-listen første gang. PnP-template applyes idempotent, og eksisterende listeelementer beholdes.
- **Svar `n`** når du kun vil oppdatere Logic Apps / SPFx uten å røre lister og felter — f.eks. ved hotfixes som kun endrer arbeidsflyt eller webdel-kode.

## Hvilken versjon kjører miljøet?

`deploy.ps1` stempler versjonen inn i miljøet ved hver kjøring, så du ikke trenger å
gjette hva et miljø står på. Den kan leses av på to steder:

- **SharePoint:** listen «Provisioning Request Settings» på Bestillingsportalen-området
  har radene `InstalledVersion` og `InstalledDate`. Disse settes automatisk — ikke
  rediger dem manuelt.
- **Azure:** ressursgruppa har taggene `BestillingsportalenVersion` og
  `BestillingsportalenDeployed`.

Installatøren ser i tillegg versjonen i konsollen under kjøringen: pre-flight-sjekklista
har en `Solution version`-linje som også viser hva miljøet står på fra før, PRE-FLIGHT
SUMMARY viser `Version: <ny> (installed: <gammel>)` før du bekrefter, og DEPLOYMENT
SUMMARY bekrefter overgangen med en `Version stamp`-linje.

Er begge stedene tomme, er miljøet installert før versjonsstemplingen ble innført
(2.0.0). Merk at `InstalledVersion` **ikke** oppdateres hvis en kjøring hadde
komponenter som feilet — den gamle verdien beholdes med vilje, slik at en halvferdig
oppgradering ikke framstår som fullført.

## Forutsetninger

Før du starter oppgraderingen:

1. **Sikkerhetskopier miljøet ditt**
   - Eksporter kritiske listedata (spesielt egendefinerte Provisioning Types)
   - Dokumenter eventuelle tilpasninger du har gjort
   - Ta skjermbilder av viktige konfigurasjoner

2. **Gjennomgå release notes**
   - Sjekk hva som er nytt i versjonen du oppgraderer til
   - Gjennomgå breaking changes eller migreringssteg
   - Forstå ny funksjonalitet som legges til

3. **Verifiser tilganger**
   - Samme tilganger som ved første installasjon
   - Site Collection Administrator på Bestillingsportalen-området
   - Azure Owner-rolle på ressursgruppen/abonnementet (bicep-malen oppretter RBAC-tildelinger)
   - Rettighet til å tildele app-roller til managed identities – oppgraderingen kjører `AssignManagedIdentityPermissions` og `AssignUamiPermissions`, som krever Global Administrator, ev. Privileged Role Administrator + Cloud Application Administrator

4. **Ha parameterne klare**
   - Bruk samme parameterfil som ved første installasjon (`-ParametersPath` hvis den heter noe annet enn `parameters.json`)
   - Verifiser at alle verdiene fortsatt er gyldige
   - **Verifiser `requestsSiteAlias` mot områdets faktiske URL** hvis du regenererer parameterfila. Parameteren er ny i 2.0, og står den utfylt utledes ikke aliaset lenger fra `requestsSiteName`. Standardverdien `bestillingsportalen` treffer den vanlige URL-en (`/sites/bestillingsportalen`, som Teams-appen har hardkodet), men ligger området et annet sted, sett aliaset til det faktiske URL-segmentet — eller la parameteren stå tom, som gir gammel oppførsel. Feil verdi peker oppgraderingen på et annet område enn det du har i drift.

5. **Forutsetninger for SPFx-deploy** (kan hoppes over med `-SkipSPFxDeploy`)
   - Node.js installert (se `Source/SharePointFramework/ProvisionWebParts/.nvmrc` for versjon)
   - Tenant app-katalog må være opprettet i SharePoint Admin Center
   - PnP-appen må ha delegert `AllSites.FullControl` for å publisere til app-katalogen (interaktiv pålogging — kontoen som kjører skriptet må være SharePoint-administrator)

## Oppgraderingsprosess

### Steg 1: Forbered miljøet

1. Gå til `Source/Scripts`-mappen:

   ```bash
   cd Source/Scripts
   ```

2. Sørg for at `parameters.json` er oppdatert med gjeldende miljøinnstillinger.

3. Gjennomgå nyeste endringer i repositoriet for å forstå hva som vil bli oppdatert.

### Steg 2: Kjør oppgraderingen

#### Alternativ A: Automatisk oppgradering (anbefalt)

Kjør deploy-skriptet med `-Upgrade`-flagget:

```powershell
./deploy.ps1 -Upgrade
```

Du kan kombinere med andre skip-flagg ved behov:

```powershell
# Eksempel: Hopp over opprettelse av ressursgruppe
./deploy.ps1 -Upgrade -SkipCreateResourceGroup

# Eksempel: Hopp over SPFx-bygg/publisering (nyttig hvis du allerede har bygget manuelt
# eller kun vil oppdatere Logic Apps)
./deploy.ps1 -Upgrade -SkipSPFxDeploy
```

##### Uovervåket kjøring med `-Force`

Ved gjentatte kjøringer (typisk under utvikling og testing) blir promptene fort i veien:

```powershell
./deploy.ps1 -Upgrade -Force
```

`-Force` gjør tre ting:

| | |
|--|--|
| Gjenbruker cachede Az/Azure CLI-sesjoner | Uten å spørre (samme som `-SkipConfirmation`) |
| Hopper over pre-flight-bekreftelsen | Samme som `-SkipConfirmation` |
| Svarer **nei** på «apply PnP-template?» | Områdets skjema/views endres ikke |

Template-svaret er bevisst `nei`: en uovervåket kjøring skal ikke endre områdets skjema som bieffekt. Merk at `y` uansett aldri nullstiller listeinnhold — malens DataRows bruker `UpdateBehavior="Skip"`, så eksisterende elementer røres ikke og kun manglende standardrader legges til. Trenger du en skjemaendring anvendt, kjør interaktivt og svar `y`.

> **`-Force` betyr «ikke stopp og spør meg», ikke «svar ja på alt».** De tre destruktive promptene — tømme en slettet site fra papirkurven, tømme en slettet Microsoft 365-gruppe, eller permanent slette en **aktiv** gruppe med tilhørende site — blir *ikke* auto-godkjent. De avbryter med en melding i stedet, siden de er irreversible og kan slette et reelt område. Treffer du en av dem, kjør uten `-Force` og ta stilling.

#### Alternativ B: Manuell Logic App-oppdatering

Hvis du foretrekker å oppdatere Logic Apps manuelt (nyttig for å gjennomgå endringer før de anvendes), kan du deploye ARM-malene direkte med Azure CLI i stedet for å kjøre hele skriptet. Bruk `--what-if` først for å se endringene:

1. Finn parameterverdiene malen trenger (liste-ID-er m.m.) – se hvilke parametre `deploy.ps1` sender i `DeployARMTemplates`-funksjonen, eller les dem ut av eksisterende Logic App i Azure Portal.

2. Forhåndsvis endringene:

   ```powershell
   az deployment group what-if --resource-group <ressursgruppe> --template-file ../ARMTemplates/LogicApps/processprovisionrequest.json --parameters <parametre...>
   ```

3. Deploy når du er fornøyd (bytt `what-if` med `create`).

4. Hvis du brukte alternativ B, må du fortsatt anvende PnP-malen manuelt:

   ```powershell
   # Koble til med PnP-appen (interaktiv nettleserinnlogging)
   Connect-PnPOnline -Url "https://yourtenant.sharepoint.com/sites/bestillingsportalen" -ClientId <your-pnp-app-id> -Interactive
   Invoke-PnPSiteTemplate -Path "../Templates/Bestillingsportalen.xml" -ClearNavigation -Parameters @{ SPOManagedPath = "sites" }
   ```

   Malen seeder også standard listeelementer (eksisterende røres aldri, manglende legges til). `SPOManagedPath` styrer verdien på den tilsvarende innstillingen for *nye* elementer — sett den til `teams` hvis tenanten bruker den administrerte banen (utelates parameteren brukes `sites`).

   I praksis er **Alternativ A anbefalt** – skriptet henter liste-ID-er og øvrige parametre automatisk.

### Steg 3: Hva som skjer under oppgraderingen

Skriptet vil:

1. **Validere parametere** – Sjekke `parameters.json`-konfigurasjonen
2. **Koble til tjenester** – Logge inn på Azure, Azure CLI og PnP PowerShell
3. **Prompt om PnP-mal** – Hvis området finnes, spør om template skal anvendes (se «Den interaktive prompten» over)
4. **Anvende PnP-mal** – (Hvis valgt) Oppdatere områdestrukturen uten å endre eksisterende listeelementer (manglende standardelementer legges til)
5. **Hente liste-ID-er** – Hente nødvendige liste-identifikatorer for Logic App-konfigurasjon (inkl. nye `Guest Requests`-listen)
6. **Oppdatere runbooks og runtime environment** – `runbooks.bicep` oppretter/oppdaterer PowerShell 7.4-runtime-miljøet (`bestillingsportalen-ps74` med PnP.PowerShell 3.2), og runbook-innholdet lastes opp fra `Source/Runbooks/` og publiseres automatisk.
7. **Installere Logic Apps** – Erstatte `ProcessProvisionRequest` og `ProcessGuestRequest` med nyeste versjoner
8. **Bygge og publisere SPFx-pakker** – (Med mindre `-SkipSPFxDeploy`) Kjør `npm install`/`npm run build` og last opp `.sppkg` til tenant app-katalog
9. **Fullføre** – Vise deployment summary

### Steg 4: Verifisering etter oppgradering

Når oppgraderingen er fullført:

1. **Verifiser områdetilgang**
   - Gå til Bestillingsportalen-området ditt
   - Bekreft at området lastes korrekt

2. **Sjekk listedata**
   - Åpne Provisioning Types-listen – verifiser at alle egendefinerte typer fortsatt finnes
   - Sjekk Provisioning Request Settings – bekreft at innstillingene er beholdt (nye standardinnstillinger fra releasen kan ha kommet til)
   - Gjennomgå pågående eller fullførte provisioning requests

3. **Test arbeidsflyten**
   - Opprett en test-bestilling (bruk en enkel områdetype)
   - Overvåk Logic App-kjøringen i Azure Portal
   - Verifiser at området opprettes korrekt

4. **Gjennomgå Logic Apps**
   - Gå til Azure Portal → Ressursgruppe → `ProcessProvisionRequest` Logic App
   - Sjekk kjørehistorikken og verifiser at den bruker nyeste definisjon
   - Gjenta for `ProcessGuestRequest` Logic App
   - **Husk:** SharePoint-koblingen (`bestillingsportalen-spo`) må kanskje re-autoriseres i Azure Portal etter oppgradering

5. **Verifiser SPFx-løsninger** (hvis ikke `-SkipSPFxDeploy`)
   - Gå til tenant app-katalog (`https://<tenant>.sharepoint.com/sites/appcatalog`)
   - Bekreft at `bp-provision-web-parts.sppkg` står som «Deployed»
   - Legg `InviteGuests`-webdelen på en testside og test gjeste-flyten:
     1. Sett `guestRequestSiteUrl` til Bestillingsportalen-området i property pane
     2. Inviter en test-gjest
     3. Verifiser at raden vises i `DataGrid` med `Status=Pending`
     4. Etter at `ProcessGuestRequest` har kjørt, refresh og se at status oppdateres til `Invited`

6. **Sjekk ny funksjonalitet**
   - Gjennomgå hva som er nytt i denne versjonen
   - Test eventuell ny funksjonalitet
   - Oppdater dokumentasjonen din ved behov

## Vanlige oppgraderingsscenarier

### Anvende hotfixes

For mindre feilrettinger:

1. Hent siste endringer fra repositoriet
2. Kjør med `-Upgrade`
3. Verifiser at fiksen er anvendt

### Legge til ny funksjonalitet

Når ny funksjonalitet legges til i malen:

1. PnP-malen legger til nye felt/lister automatisk
2. Du må kanskje konfigurere nye provisioning types manuelt
3. Oppdater Bestillingsportalen webdel eller Teams app hvis grensesnitt-endringer er nødvendig

## Feilsøking

### Problem: «List not found»-feil

**Årsak:** Listestrukturen matcher ikke forventet skjema.

**Løsning:**

1. Verifiser at du kjører mot riktig område
2. Sjekk at første installasjon ble fullført korrekt
3. Du må kanskje anvende hele malen på nytt uten `-Upgrade`

### Problem: Logic App-installasjon feiler

**Årsak:** Manglende parametere eller endrede ressursnavn.

**Løsning:**

1. Verifiser at `parameters.json` har korrekte verdier
2. Sjekk at Automation Account-navnet matcher (standard: `bestillingsportalen-auto`)
3. Sørg for at liste-ID-er hentes korrekt

### Problem: Anvendelse av PnP-mal feiler

**Årsak:** Tilgangsproblemer eller konflikter med tilpasninger.

**Løsning:**

1. Bekreft at du er Site Collection Administrator
2. Sjekk om det finnes konfliktende tilpasninger
3. Gjennomgå PnP PowerShell-tilkobling og tilganger

### Problem: Eksisterende bestillinger slutter å fungere

**Årsak:** Oppdatering av Logic App kan ha introdusert breaking changes.

**Løsning:**

1. Sjekk Logic App-kjørehistorikken for spesifikke feil
2. Gjennomgå [CHANGELOG.md](CHANGELOG.md) for breaking changes
3. Du må kanskje oppdatere runbooks eller API connections
4. Sjekk at alle parametere er konfigurert korrekt

## Tilbakerullingsprosedyre

Hvis oppgraderingen skaper problemer:

### Tilbakerull Logic App-en

1. Gå til Azure Portal → Ressursgruppe → `ProcessProvisionRequest` Logic App
2. Klikk `Versions` i venstre meny
3. Velg forrige fungerende versjon
4. Klikk `Promote` for å gjøre den aktiv

### Tilbakerull PnP-malen

Dessverre kan PnP-mal-endringer ikke enkelt tilbakerulles. Alternativer:

1. **Manuell tilbakeføring:**
   - Identifiser hva som ble endret
   - Tilbakefør felt/views osv. manuelt

2. **Gjenopprett fra sikkerhetskopi:**
   - Hvis du har en sikkerhetskopi, gjenopprett den
   - Du vil miste eventuelle bestillinger opprettet siden sikkerhetskopien

3. **Anvend forrige versjon på nytt:**
   - Sjekk ut tidligere git commit
   - Kjør `./deploy.ps1 -Upgrade` med den eldre malen

## Beste praksis

1. **Test først**
   - Hvis mulig, test oppgraderingen i et dev/test-miljø
   - Verifiser at alt fungerer før du oppgraderer produksjon

2. **Planlegg vedlikeholdsvindu**
   - Varsle brukere om oppgraderingen
   - Utfør utenom arbeidstid hvis mulig
   - Planlegg for 30–60 minutters arbeid

3. **Hold parametere oppdatert**
   - Vedlikehold `parameters.json`-filen
   - Dokumenter eventuelle egendefinerte verdier

4. **Overvåk etter oppgradering**
   - Følg Logic App-kjøringer de første timene
   - Vær tilgjengelig for å adressere brukerspørsmål
   - Sjekk for eventuelle feilvarsler

5. **Dokumenter tilpasningene dine**
   - Hold oversikt over egendefinerte provisioning types
   - Noter mal-modifikasjoner
   - Spor manuelle konfigurasjonsendringer

## Sjekkliste for oppgradering

Bruk denne sjekklisten ved oppgradering:

- [ ] Sikkerhetskopier nåværende miljø
- [ ] Gjennomgå release notes og changelog
- [ ] Oppdater lokalt repository til nyeste versjon
- [ ] Verifiser at `parameters.json` er oppdatert
- [ ] Verifiser at tenant app-katalog finnes (hvis SPFx skal deployes)
- [ ] Verifiser at Node.js er installert (hvis SPFx skal deployes)
- [ ] Varsle brukere om vedlikeholdsvindu
- [ ] Kjør `./deploy.ps1 -Upgrade` (og svar på «Site already exists»-prompten — eller bruk `-Force`, som svarer nei)
- [ ] Verifiser at området lastes korrekt
- [ ] Sjekk at alle lister og data er intakte (inkl. ny `Guest Requests`-liste)
- [ ] Test `ProcessProvisionRequest` med en eksempel-bestilling
- [ ] Test `ProcessGuestRequest` ved å invitere en gjest via webdelen
- [ ] Gjennomgå Logic Apps-kjørehistorikk for begge
- [ ] Re-autoriser API Connections i Azure Portal hvis nødvendig
- [ ] Verifiser at SPFx-pakken vises som «Deployed» i app-katalog
- [ ] Test ny funksjonalitet (hvis aktuelt)
- [ ] Oppdater dokumentasjon
- [ ] Varsle brukere om at oppgraderingen er fullført

## Få hjelp

Hvis du møter problemer under oppgraderingen:

1. Sjekk [Error-handling.md](Error-handling.md)-dokumentasjonen
2. Gjennomgå Logic App-kjørehistorikken i Azure Portal
3. Sjekk [CHANGELOG.md](CHANGELOG.md) for kjente problemer
4. Konsulter [README.md](README.md) for generell veiledning
5. Opprett et issue i repositoriet med:
   - Versjon du oppgraderer fra/til (se [Hvilken versjon kjører miljøet?](#hvilken-versjon-kjører-miljøet))
   - Feilmeldinger
   - Steg for å reprodusere
   - Skjermbilder hvis aktuelt

## Neste steg

Etter en vellykket oppgradering:

1. **Gjennomgå ny funksjonalitet** – Sjekk changelog for hva som er nytt
2. **Oppdater dokumentasjonen din** – Noter det nye versjonsnummeret (`InstalledVersion` i innstillingslista bekrefter hva som faktisk ble installert)
3. **Lær opp brukere** – Hvis det er endringer i UI eller arbeidsflyt
4. **Planlegg neste oppgradering** – Hold deg oppdatert på fremtidige releases
5. **Bidra tilbake** – Del tilbakemeldinger og forbedringer

---

**Relatert dokumentasjon:**

- [README.md](README.md) – Hoveddokumentasjon
- [Upgrade-from-pre-2.0.md](Upgrade-from-pre-2.0.md) – Oppgradering av miljøer fra før managed identity-migreringen
- [Deployment-guide.md](Deployment-guide.md) – Full installasjonsprosess (den skriptede delen)
- [Configuration-guide.md](Configuration-guide.md) – Konfigurasjon og verifisering etter installasjon
- [CHANGELOG.md](CHANGELOG.md) – Versjonshistorikk
- [Error-handling.md](Error-handling.md) – Feilsøkingsveiledning
