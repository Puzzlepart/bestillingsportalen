# Oppgradere Bestillingsportalen

Denne veiledningen forklarer hvordan du oppgraderer en eksisterende Bestillingsportalen-installasjon for å få den nyeste funksjonaliteten og feilrettinger uten å bygge opp miljøet på nytt eller miste eksisterende data.

## Oversikt

Oppgraderingsprosessen lar deg:

- Anvende de nyeste PnP-mal-oppdateringene (feltdefinisjoner, content types, views osv.)
- Oppdatere Logic App-ene `ProcessProvisionRequest` og `ProcessGuestRequest` med de nyeste arbeidsflyt-forbedringene
- Bygge og publisere SPFx-løsninger (f.eks. `InviteGuests`-webdelen) til tenant app-katalog
- Beholde alle eksisterende listedata (provisioning types, innstillinger, bestillinger osv.)
- Minimere nedetid og konfigurasjonsendringer

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
- **Migrering til managed identity** – installasjoner fra før managed identity-migreringen må kjøre én full `deploy.ps1` (uten `-Upgrade`) først, slik at managed identityen, tilgangene og API-tilkoblingene opprettes. Se [Managed-identity-migration.md](Managed-identity-migration.md). Oppgraderingsmodus feiler med en tydelig melding hvis managed identityen ikke finnes.

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
   - Komplett erstatning av arbeidsflytene med nyeste versjon, oppdatert feilhåndtering

3. **Runbooks (lokale)** — `runbooks.bicep` deployes ALLTID, også med `-SkipBicepDeploy`
   - Nye runbook-RESSURSER opprettes (f.eks. `AddGuestToSite` i 1.11.0)
   - Eksisterende runbook-INNHOLD oppdateres bare hvis `publishContentLink.version` er bumpet i `runbooks.bicep`
   - **Manuell paste for `AddGuestToSite`**: Bicep-templaten har foreløpig en placeholder-URI (ConfigureSpace.ps1) inntil dette repoet blir public. Etter førstegangs deploy må du åpne Azure Portal → Automation Account → Runbooks → `AddGuestToSite` → Edit, lime inn innhold fra [Source/Runbooks/AddGuestToSite.ps1](Source/Runbooks/AddGuestToSite.ps1), og publisere. Senere upgrade-runs beholder den manuelt-limte koden så lenge `version` ikke bumpes.

4. **Upstream runbooks** (`ConfigureSpace`, `GetSiteTemplates`) — bare hvis `azureresources.bicep` deployes (IKKE med `-SkipBicepDeploy`)

5. **SPFx-løsninger** (med mindre `-SkipSPFxDeploy` brukes)
   - Alle løsninger under `Source/SharePointFramework/*/` med `config/package-solution.json`
   - `npm install` (kun ved første gang / hvis `node_modules` mangler) + `npm run build`
   - `.sppkg` lastes opp til tenant app-katalog via `Add-PnPApp -Overwrite -Publish`
   - Eksempel: `InviteGuests`-webdel for invitasjon av gjester

### ❌ Oppdateres IKKE i oppgraderingsmodus

1. **Listedata** – Alle eksisterende elementer beholdes:
   - Provisioning Request Settings
   - Provisioning Types (egne typer du har lagt til)
   - Site Templates
   - Hub Sites
   - Teams Templates
   - Time Zones
   - Locales
   - IP Labels
   - Eksisterende provisioning requests

2. **Ressurser (bilder/ikoner):**
   - Bilder for Provisioning Types
   - Ikoner for Provisioning Types
   - Andre opplastede filer

3. **Andre Azure-ressurser:**
   - Azure Automation Account
   - Innhold i eksisterende runbooks (Bicep `publishContentLink` re-importerer kun ved bumpet version i `azureresources.bicep`)
   - Key Vault
   - User-assigned managed identity (app-rollene synkroniseres likevel – `AssignUamiPermissions` kjøres også i oppgraderingsmodus)
   - Andre Logic Apps (`GetSiteTemplates`, `GetHubSites` osv.)
   - API Connections

4. **Entra ID-app:**
   - Application registration
   - App secrets
   - Tilganger

### Den interaktive `Site already exists`-prompten

Når scriptet oppdager at Bestillingsportalen-området allerede finnes, spørres du:

```text
Do you wish to re-apply the PnP provisioning template?
  y = re-apply template (updates lists, fields and settings on the existing site)
  n = skip template apply, but continue with Logic Apps / SPFx / other deploy steps
```

- **Svar `y`** når oppgraderingen inneholder skjema-endringer (nye lister, nye felter) — f.eks. ved å rulle ut `Guest Requests`-listen første gang. PnP-template applyes idempotent, og eksisterende listeelementer beholdes.
- **Svar `n`** når du kun vil oppdatere Logic Apps / SPFx uten å røre lister og felter — f.eks. ved hotfixes som kun endrer arbeidsflyt eller webdel-kode.

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
   - Bruk samme `parameters.json` som ved første installasjon
   - Verifiser at alle verdiene fortsatt er gyldige

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
   Invoke-PnPSiteTemplate -Path "../Templates/Bestillingsportalen.xml" -ClearNavigation
   ```

   I praksis er **Alternativ A anbefalt** – skriptet henter liste-ID-er og øvrige parametre automatisk.

### Steg 3: Hva som skjer under oppgraderingen

Skriptet vil:

1. **Validere parametere** – Sjekke `parameters.json`-konfigurasjonen
2. **Koble til tjenester** – Logge inn på Azure, Azure CLI og PnP PowerShell
3. **Prompt om PnP-mal** – Hvis området finnes, spør om template skal anvendes (se «Den interaktive prompten» over)
4. **Anvende PnP-mal** – (Hvis valgt) Oppdatere områdestrukturen UTEN å endre listedata
5. **Hente liste-ID-er** – Hente nødvendige liste-identifikatorer for Logic App-konfigurasjon (inkl. nye `Guest Requests`-listen)
6. **Oppdatere runbooks og runtime environment** – `runbooks.bicep` oppretter/oppdaterer PowerShell 7.4-runtime-miljøet (`bestillingsportalen-ps74` med PnP.PowerShell 3.2) og flytter runbookene dit. **Verifiser runbook-innholdet etterpå** — re-importeres runbookene fra plassholder-URI-ene, må innholdet i `ConfigureSpace` og `AddGuestToSite` limes inn på nytt fra `Source/Runbooks/`.
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
   - Sjekk Provisioning Request Settings – bekreft at innstillingene er beholdt
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
- [ ] Kjør `./deploy.ps1 -Upgrade` (og svar på «Site already exists»-prompten)
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
   - Versjon du oppgraderer fra/til
   - Feilmeldinger
   - Steg for å reprodusere
   - Skjermbilder hvis aktuelt

## Neste steg

Etter en vellykket oppgradering:

1. **Gjennomgå ny funksjonalitet** – Sjekk changelog for hva som er nytt
2. **Oppdater dokumentasjonen din** – Noter det nye versjonsnummeret
3. **Lær opp brukere** – Hvis det er endringer i UI eller arbeidsflyt
4. **Planlegg neste oppgradering** – Hold deg oppdatert på fremtidige releases
5. **Bidra tilbake** – Del tilbakemeldinger og forbedringer

---

**Relatert dokumentasjon:**

- [README.md](README.md) – Hoveddokumentasjon
- [Deployment-guide.md](Deployment-guide.md) – Full installasjonsprosess
- [CHANGELOG.md](CHANGELOG.md) – Versjonshistorikk
- [Error-handling.md](Error-handling.md) – Feilsøkingsveiledning
