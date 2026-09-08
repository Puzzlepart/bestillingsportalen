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
8. **Store_expiration_date** - Lagring av utløpsdato
9. **Configure_space** - Konfigurering via Azure Automation runbook

Sensitivitetsmerking har ikke lenger et eget scope her – den gjøres i `ConfigureSpace`-runbooken og dekkes av `Handle_Error_Configure_space` (se [Sensitivitetsmerker](Sensitivity-labels.md)).

> **Merk:** `Run_CustomerSpecific_runbook` (organisasjonens eget utvidelsespunkt, som kjøres rett etter `Configure_space`) har ikke eget `Handle_Error`-scope — en feil *inne i* utvidelsesskriptet gir Failed-status på Automation-jobben uten å sette bestillingen til «Space Creation Failed». Sjekk jobbhistorikken på `CustomerSpecific`-runbooken ved feilsøking av lokale tilpasninger.

### Hvordan det fungerer

For hvert steg over finnes det en tilhørende `Handle_Error_[StepName]` scope som:

1. Aktiveres når hovedsteget får status `Failed` eller `TimedOut`
2. Henter den faktiske feilen fra steget med `result()` (`Filter_failed_actions_*` + `Compose_error_message_*`)
3. Oppdaterer Provisioning Request-listeelementet med:
   - Status: "Space Creation Failed"
   - StatusReason: hvilket steg som feilet **og** den underliggende feilmeldingen
4. Avslutter Logic App-kjøringen med Failed-status

> **Merk:** `Skipped` er *ikke* med i utløseren, i motsetning til hva denne dokumentasjonen tidligere hevdet. Et steg får `Skipped` først når en avhengighet feilet – og da har den avhengighetens eget `Handle_Error`-scope allerede kjørt `Terminate`. Å legge til `Skipped` ville gitt dobbel skriving til listeelementet.

### Eksempel på feilmelding

Hvis "Apply_Site_Template" feiler, settes StatusReason til steget pluss den faktiske feilen, for eksempel:

```
Failed to apply site template: Apply_site_template_to_site: The site design was not found.
```

`result()` rapporterer de **umiddelbare** barne-actionene i scopet. Ved dypt nestede feil navngir meldingen derfor grenen som feilet framfor det innerste kallet – bruk Logic App-kjørehistorikken for å komme helt ned.

For `Configure_space` brukes ikke `result()` (det er en connector-action, ikke et scope). Der leses Automation-jobbens `properties.exception`, som inneholder runbookens egen oppsummering:

```
Failed to configure space using runbook: An error occured: One or more configuration steps failed: ApplyTheme failed: ...
```

### Runbook-jobber som feiler med HTTP 200

Azure Automation-connectoren returnerer HTTP 200 selv når runbook-jobben internt har status `Failed`. Etter `Configure_space` ligger derfor en egen `Check_runbook_status`-If som leser `body('Configure_space')?['properties']?['status']` og setter bestillingen til "Space Creation Failed" hvis jobben feilet. `Update_status_to_Space_Created` er kjedet etter denne sjekken, ikke etter `Configure_space` – ellers kunne en bestilling bli stemplet "Space Created" før `Terminate` rakk å stoppe kjøringen.

## Feilhåndtering i ConfigureSpace Runbook

ConfigureSpace.ps1 runbook har også omfattende feilhåndtering for alle konfigurasjonsfunksjoner.

### `$ErrorActionPreference = 'Stop'`

Runbooken kjører med `Stop` på skriptnivå. Det er nødvendig for at feilhåndteringen skal fungere i det hele tatt: PnP-cmdleter produserer ofte **ikke-terminerende** feil, og uten `Stop` gikk disse rett forbi try/catch-blokkene. Kjøringen rapporterte da suksess selv om enkeltsteg ikke hadde utført noe.

Enkelte kall setter bevisst `-ErrorAction SilentlyContinue` fordi de *tester* om noe finnes (f.eks. `Get-PnPList -Identity "SiteAssets"` og `Get-PnPHubSite`). Det er tilsiktet og skal ikke fjernes.

### `Invoke-Step` og de tre statusene

Hvert konfigurasjonssteg kjøres via `Invoke-Step`, som erstatter de tidligere 22 identiske try/catch-blokkene. Hvert steg får én av tre statuser:

| Status | Betyr |
|--|--|
| `Succeeded` | Steget gjorde faktisk arbeid |
| `Skipped` | Steget gjaldt ikke denne bestillingen – **med årsak** |
| `Failed` | Steget feilet. Kjøringen fortsetter, feilen samles opp |

**Skillet mellom `Succeeded` og `Skipped` er hele poenget.** En typisk bestilling utløser under halvparten av stegene, så en tabell med bare `Succeeded` kan ikke svare på «hvorfor ble ikke temaet mitt satt?». Et steg som ikke gjelder kaller `Skip-Step` med en årsak før det returnerer, og årsaken havner både i loggen og i tabellen.

Ved feil kaller `Invoke-Step` også `Set-SpaceCreationFailed`, som setter `$script:hasErrors` og legger meldingen i `$script:errorMessages`. `Skipped` teller **ikke** som feil.

`Update-ProvisioningRequestStatus` er fjernet – den oppdaterte aldri noe, den logget bare, og navnet var misvisende. Listeoppdateringen tilhører Logic App-en.

### Steg som kjøres

Container-nivå først (merket overstyrer områdets privacy og delingsinnstillinger, så det må settes før dem):

- SetSensitivityLabel
- SetExternalSharing
- DisableNoScript

Deretter, med `EnableNoScript` garantert i `finally`:

- AddOwners, AddMembers, AddVisitors, AddReadOnlyGroup, AddSiteCollectionAdmins
- SetAccessRequestSettings, SetSiteLogo, SetRegionalSettings
- ActivateFeatures, ApplyPnPTemplate, ApplyTheme
- DisableDocumentSync, SetRetentionLabel, SetSensitivityLabelLibrary, SetSiteClassification
- SetMetadata, JoinOrRegisterHubSite, SetStorageQuota, ApplySiteDesign, UpdateParentSite

### Feilhåndteringsflyt

1. Et steg feiler (terminerende eller ikke-terminerende)
2. `Invoke-Step` fanger feilen, registrerer den og går videre
3. `EnableNoScript` kjøres uansett i `finally`
4. `Write-StepSummary` skriver en per-steg-tabell til jobbloggen – **dette er det første du leser ved feilsøking**
5. Hvis noen steg feilet, kastes en exception som navngir dem
6. Automation-jobben får status `Failed` med exception-teksten
7. Logic App-en fanger det via `Check_runbook_status` (jobb-status) eller `Handle_Error_Configure_space` (connector-feil)
8. Provisioning Request oppdateres med "Space Creation Failed" og exception-teksten som StatusReason

Eksempel på steg-tabellen:

```
===================== Step summary =====================
  Succeeded SetSensitivityLabel
  Skipped   SetExternalSharing           External sharing not requested (ExternalSharingRequired = 'false')
  Succeeded DisableNoScript
  Skipped   AddOwners                    Space type 'Office 365 Group' takes owners from the M365 group, not the SP owners group
  Failed    ApplyTheme                   Theme 'Foo' does not exist
  Skipped   SetRetentionLabel            No retention label on the request
--------------------------------------------------------
  2 applied, 3 not applicable, 1 failed
========================================================
```

Tellelinja nederst er en rask helsesjekk: får du `0 applied` på en bestilling som skulle konfigurert noe, er det sannsynligvis parameterne fra Logic App-en som er tomme – ikke stegene som er ødelagte.

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
- Manglende app-roller på user-assigned managed identity (se [Datatilgang og sikkerhet](Data-access-security.md) for hele rollelista, og `AssignPermissionsToManagedIdentity.ps1` for reparasjon)

#### "Failed during space type validation or provisioning"
- Ugyldig områdetype
- Manglende eller feil Teams-mal
- Graph API-feil ved oppretting av gruppe

#### "Failed to configure space using runbook"
StatusReason inneholder runbookens egen oppsummering med navn på de feilende stegene. Åpne jobben i Automation-kontoen og les steg-tabellen nederst i loggen. Vanlige årsaker:
- Managed Identity mangler tillatelser
- Feil i et enkelt konfigurasjonssteg (temanavn, tidssone, hub-ID som ikke finnes)
- Merk: etter at `$ErrorActionPreference = 'Stop'` ble innført vil steg som tidligere feilet *stille* nå rapporteres. En bestilling som «alltid har fungert» kan derfor begynne å feile – det er reelle feil som ble skjult før, ikke en regresjon.

#### "Failed to apply site template"
- Ugyldig Site Design ID
- Site Design eksisterer ikke
- Tillatelsesproblem

#### Sensitivitetsmerke ble ikke satt
Har ikke lenger eget scope – dukker opp under "Failed to configure space using runbook" med `SetSensitivityLabel` i steg-tabellen. Vanlige årsaker:
- Merket er ikke publisert til grupper/sites i Purview (vent 24 timer etter publisering)
- Ugyldig Label ID i bestillingen eller i `DefaultSensitivityLabel`
- Automation-kontoens managed identity mangler SharePoint `Sites.FullControl.All` (tenant-admin-kallet feiler) eller Graph `Group.ReadWrite.All` (tilbakelesingen av `assignedLabels` feiler)

Feilmeldingen navngir de vanligste årsakene direkte. Merket verifiseres alltid mot **gruppen** etter at det er satt – står det på området men ikke på gruppen, er merket sannsynligvis ikke publisert til grupper og områder. Se [Sensitivitetsmerker](Sensitivity-labels.md).

#### Runbookene vises som «PowerShell 5.1» i Automation-kontoen
**Ikke en feil.** Portalens standard Runbooks-blad kjenner ikke runtime environments over 7.2 og viser derfor alt som 5.1 — [dokumentert begrensning](https://learn.microsoft.com/en-us/azure/automation/runtime-environment-overview#limitations). Bytt til **Runtime environment-opplevelsen** i Automation-kontoen, så vises riktig versjon. `deploy.ps1` verifiserer dette og rapporterer `Runbook runtime environment` i DEPLOYMENT SUMMARY.

Er runbooken *faktisk* på klassisk 5.1-runtime, ser du det på et helt annet symptom: `Connect-PnPOnline is not recognized` ved hver kjøring, siden `PnP.PowerShell` 3.x krever 7.4. Kjør [`Source/Diagnostics/Test-RunbookRuntime.ps1`](Source/Diagnostics/Test-RunbookRuntime.ps1) for å se `$PSVersionTable` fra inne i jobben.

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
