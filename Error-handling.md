# Error Handling i Bestillingsportalen

Denne dokumentasjonen beskriver hvordan feilhåndtering fungerer i Bestillingsportalen-løsningen.

> 📊 **Flytdiagram**: Se [Error Handling Flow Diagram](Images/error-handling-flow.md) for en visuell oversikt over feilhåndteringsflyten.

## Oversikt

Bestillingsportalen har omfattende feilhåndtering for å sikre at feil under provisjoneringsprosessen blir fanget opp og dokumentert. Når en feil oppstår, blir status på forespørselen automatisk oppdatert til "Space Creation Failed" med detaljert informasjon om hva som gikk galt.

## Feilhåndtering i Logic App (processprovisionrequest)

Logic App-en har dedikerte feilhåndteringsscopes for hvert hovedsteg i provisjoneringsflyten. Disse aktiveres automatisk når et steg feiler, hoppes over, eller får timeout.

### Håndterte steg

Følgende steg har automatisk feilhåndtering:

1. **Check_if_space_exists** - Sjekk om området allerede eksisterer
2. **Check_space_type** - Validering og provisjonering basert på områdetype
3. **Process_Owners_and_Members** - Prosessering av eiere og medlemmer
4. **Process_Team** - Oppsett av Team-innstillinger
5. **Apply_Site_Template** - Anvendelse av nettstedmal
6. **Set_external_sharing** - Konfigurasjon av ekstern deling
7. **Invite_guests** - Invitasjon av gjestebrukere
8. **Apply_sensitivity_label** - Anvendelse av følsomhetsetikett
9. **Store_expiration_date** - Lagring av utløpsdato
10. **Configure_space** - Konfigurering via Azure Automation runbook

> **Merk:** `Run_CustomerSpecific_runbook` (det kundeeide utvidelsespunktet som kjøres rett etter `Configure_space`) har ikke eget `Handle_Error`-scope — en feil *inne i* kundeskriptet gir Failed-status på Automation-jobben uten å sette bestillingen til «Space Creation Failed». Sjekk jobbhistorikken på `CustomerSpecific`-runbooken ved feilsøking av kundetilpasninger.

### Hvordan det fungerer

For hvert steg over finnes det en tilhørende `Handle_Error_[StepName]` scope som:

1. Aktiveres når hovedsteget får status `Failed`, `Skipped`, eller `TimedOut`
2. Oppdaterer Provisioning Request-listeelementet med:
   - Status: "Space Creation Failed"
   - StatusReason: Beskrivende feilmelding som forteller hvilket steg som feilet
3. Avslutter Logic App-kjøringen med Failed-status

### Eksempel på feilmelding

Hvis steget "Apply_Site_Template" feiler, vil StatusReason-feltet settes til:
```
Failed to apply site template
```

## Feilhåndtering i ConfigureSpace Runbook

ConfigureSpace.ps1 runbook har også omfattende feilhåndtering for alle konfigurasjonsfunksjoner.

### Nye funksjoner

#### Set-SpaceCreationFailed

Denne funksjonen kalles fra try/catch-blokker i alle konfigurasjonsfunksjoner. Den:
- Registrerer at en feil har oppstått
- Lagrer feilmeldinger i en liste
- Logger feilen til output

```powershell
Set-SpaceCreationFailed -FunctionName "SetSiteLogo" -ErrorMessage "Failed to upload logo"
```

#### Update-ProvisioningRequestStatus

Denne funksjonen logger statusoppdateringer og akkumulerte feilmeldinger. Merk at den faktiske oppdateringen av SharePoint-listen håndteres av Logic App-en via error handling scopes.

### Håndterte funksjoner

Alle følgende funksjoner er wrappet med try/catch og kaller `Set-SpaceCreationFailed` ved feil:

- SetSiteLogo
- AddOwners
- AddMembers
- AddVisitors
- AddReadOnlyGroup
- AddSiteCollectionAdmins
- SetExternalSharing
- SetAccessRequestSettings
- SetSiteClassification
- JoinOrRegisterHubSite
- SetRegionalSettings
- SetStorageQuota
- DisableDocumentSync
- SetRetentionLabel
- SetSensitivityLabel
- SetSensitivityLabelLibrary
- ActivateFeatures
- ApplyPnPTemplate
- ApplyTheme
- ApplySiteDesign

### Feilhåndteringsflyt

1. En funksjon kjører og feiler
2. `Set-SpaceCreationFailed` kalles og logger feilen
3. Funksjonen returnerer uten å krasje scriptet
4. Hovedscriptet sjekker om det er akkumulerte feil
5. Hvis ja, kastes en exception med alle feilmeldinger
6. Logic App fanger opp feilen via `Handle_Error_Configure_space`
7. Provisioning Request oppdateres med "Space Creation Failed"

## Feilsøking

### Finne feilårsak

Når en forespørsel får status "Space Creation Failed":

1. Åpne forespørselen i Provisioning Requests-listen
2. Sjekk **StatusReason**-feltet for detaljert feilmelding
3. Gå til Azure Portal → Logic Apps → ProcessProvisionRequest
4. Åpne den feilede kjøringen
5. Ekspander de feilede stegene for å se detaljerte feilmeldinger

### Vanlige feilscenarier

#### "Failed to check if space exists"
- Problem med tilkobling til SharePoint
- Manglende app-roller på user-assigned managed identity (se [Managed-identity-migration.md](Managed-identity-migration.md))

#### "Failed during space type validation or provisioning"
- Ugyldig områdetype
- Manglende eller feil Teams-mal
- Graph API-feil ved oppretting av gruppe

#### "Failed to configure space using runbook"
- PnP PowerShell-modul ikke tilgjengelig
- Managed Identity mangler tillatelser
- Feil i konfigurasjonsfunksjoner (sjekk runbook logs)

#### "Failed to apply site template"
- Ugyldig Site Design ID
- Site Design eksisterer ikke
- Tillatelsesproblem

#### "Failed to apply sensitivity label"
- Følsomhetsetikett ikke publisert til grupper/sites
- Service account mangler tillatelser
- App secret (brukes kun av denne flyten) er utløpt – se [Refreshing-app-secret.md](Refreshing-app-secret.md)
- Ugyldig Label ID

#### 403 "Authorization_RequestDenied" rett etter installasjon/oppgradering
- Managed identity-tokens caches i opptil ~24 timer, og nytildelte app-roller kan bruke tid på å propagere
- Vent og prøv igjen før du feilsøker videre; verifiser deretter app-rollene på managed identityen

### Beste praksis

1. **Overvåk StatusReason-feltet** - Dette gir raskest innsikt i hva som gikk galt
2. **Sjekk Logic App run history** - For detaljerte logs og feilmeldinger
3. **Sjekk Automation Account job history** - For detaljerte runbook logs
4. **Test konfigurasjonen** - Bruk testforespørsler for å validere endringer
5. **Valider tillatelser** - Sørg for at både den user-assigned managed identityen (Logic Apps) og automation accountens system-assigned managed identity (runbooks) har nødvendige app-roller

## Gevinster med forbedret feilhåndtering

✅ **Bedre synlighet** - Alle feil reflekteres i Provisioning Requests-listen  
✅ **Enklere feilsøking** - Detaljerte feilmeldinger gjør det lettere å identifisere problemet  
✅ **Mer robust** - Provisjoneringsflyten håndterer feil på en kontrollert måte  
✅ **Konsistent** - Same feilhåndteringslogikk brukes på tvers av alle steg  
✅ **Brukervennlig** - Brukere får klar beskjed om at noe gikk galt og kan kontakte support

## Se også

- [Teknisk løsningsbeskrivelse](Teknisk-losningsbeskrivelse.md) - Løsningsarkitektur og komponenter
- [Data Stores](Data-stores.md) - Informasjon om Provisioning Requests-listen
- [Deployment Guide](Deployment-guide.md) - Deployment og konfigurasjon
