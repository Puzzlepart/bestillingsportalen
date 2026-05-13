# Oppgradere Bestillingsportalen

Denne veiledningen forklarer hvordan du oppgraderer en eksisterende Bestillingsportalen-installasjon for å få den nyeste funksjonaliteten og feilrettinger uten å bygge opp miljøet på nytt eller miste eksisterende data.

## Oversikt

Oppgraderingsprosessen lar deg:

- Anvende de nyeste PnP-mal-oppdateringene (feltdefinisjoner, content types, views osv.)
- Oppdatere Logic App-en `ProcessProvisionRequest` med de nyeste arbeidsflyt-forbedringene
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

## Hva som blir oppdatert

### ✅ Oppdateres i oppgraderingsmodus

1. **Anvendelse av PnP-mal**
   - Site columns og content types
   - Liste-skjema og feltdefinisjoner
   - Views og forms
   - Navigasjonsstruktur
   - Web parts og side-layouts

2. **`ProcessProvisionRequest` Logic App**
   - Komplett erstatning av arbeidsflyten med nyeste versjon
   - Oppdatert feilhåndtering
   - Ny provisjoneringsfunksjonalitet
   - Feilrettinger og forbedringer

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
   - Runbooks
   - Key Vault
   - Sertifikater
   - Andre Logic Apps (`GetSiteTemplates`, `GetHubSites` osv.)
   - API Connections

4. **Entra ID-app:**
   - Application registration
   - App secrets
   - Tilganger

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
   - Azure Contributor-rolle på ressursgruppen
   - Application Administrator eller tilsvarende for Entra ID

4. **Ha parameterne klare**
   - Bruk samme `parameters.json` som ved første installasjon
   - Verifiser at alle verdiene fortsatt er gyldige

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
# Eksempel: Hopp over sertifikatgenerering hvis det allerede finnes
./deploy.ps1 -Upgrade -SkipGenerateCertificate

# Eksempel: Hopp over opprettelse av ressursgruppe
./deploy.ps1 -Upgrade -SkipCreateResourceGroup
```

#### Alternativ B: Manuell Logic App-oppdatering

Hvis du foretrekker å oppdatere Logic App-en manuelt (nyttig for å gjennomgå endringer før de anvendes):

1. Generer Logic App JSON-definisjonen:

   ```powershell
   ./generateProcessProvisionRequest.ps1
   ```

   Skriptet vil:
   - Koble til SharePoint via PnP-appen og sertifikatet i `parameters.json`
   - Hente liste-ID-ene automatisk fra Bestillingsportalen-området
   - Generere `ProcessProvisionRequest.json` med alle verdier ferdig populert
   - Be om passord for PnP-sertifikatet ved behov

2. (Valgfritt) Generer uten å koble til SharePoint:

   ```powershell
   ./generateProcessProvisionRequest.ps1 -SkipListIds
   ```

   Dette oppretter en fil med plassholderverdier som du må erstatte manuelt.

3. Åpne den genererte filen og gå gjennom endringene.

4. I Azure Portal:
   - Gå til `ProcessProvisionRequest` Logic App-en
   - Klikk `Logic app code view`
   - Kopier hele innholdet fra `ProcessProvisionRequest.json`
   - Lim det inn i Logic App code view (erstatt all eksisterende kode)
   - Klikk `Save`

5. Hvis du brukte alternativ B, må du fortsatt anvende PnP-malen manuelt:

   ```powershell
   # Koble til med PnP-app-legitimasjonen
   Connect-PnPOnline -Url "https://yourtenant.sharepoint.com/sites/bestillingsportalen" -ClientId <your-pnp-app-id> -CertificatePath <path-to-cert>
   Invoke-PnPSiteTemplate -Path "../Templates/Bestillingsportalen.xml" -ClearNavigation
   ```

### Steg 3: Hva som skjer under oppgraderingen

Skriptet vil:

1. **Validere parametere** – Sjekke `parameters.json`-konfigurasjonen
2. **Koble til tjenester** – Logge inn på Azure, Azure CLI og PnP PowerShell
3. **Anvende PnP-mal** – Oppdatere områdestrukturen UTEN å endre listedata
4. **Hente liste-ID-er** – Hente nødvendige liste-identifikatorer for Logic App-konfigurasjon
5. **Installere `ProcessProvisionRequest`** – Erstatte Logic App-en med nyeste versjon
6. **Fullføre** – Vise suksessmelding

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

4. **Gjennomgå Logic App**
   - Gå til Azure Portal → Ressursgruppe → `ProcessProvisionRequest` Logic App
   - Sjekk kjørehistorikken
   - Verifiser at den bruker nyeste definisjon

5. **Sjekk ny funksjonalitet**
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
- [ ] Varsle brukere om vedlikeholdsvindu
- [ ] Kjør `./deploy.ps1 -Upgrade`
- [ ] Verifiser at området lastes korrekt
- [ ] Sjekk at alle lister og data er intakte
- [ ] Test Logic App med en eksempel-bestilling
- [ ] Gjennomgå Logic App-kjørehistorikken
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
