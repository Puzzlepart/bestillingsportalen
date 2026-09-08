# Konfigurasjonsveiledning

Denne veiledningen tar over der [Installasjonsveiledningen](./Deployment-guide.md) slutter: `deploy.ps1` har kjørt, API-tilkoblingene er autorisert med tjenestekontoen, og app-rollene er tildelt. Stegene her krever ingen Azure-tilganger — de gjøres i SharePoint, Power Automate og Teams, og kan utføres av den som skal konfigurere og forvalte løsningen.

Innstillingene for Bestillingsportalen finnes i `Provisioning Request Settings`-listen på Bestillingsportalen-området, som nøkkel/verdi-par (Title/Value). Standardverdiene seedes av PnP-malen ved installasjon (`<pnp:DataRows>` i `Source/Templates/Objects/Lists/Provisioning Request Settings.xml`) — eksisterende elementer røres aldri ved re-apply, og manglende standardelementer legges til.

## Steg 1: Konfigurere godkjenningsprosess

Godkjenning av bestillinger i løsningen kan skje på to måter:

- Power Automate Approval-handling (godkjennings-epost og Approvals-app i Teams).
- Microsoft Teams Adaptive Card-godkjenning (adaptivt kort postet i en Teams-kanal).

Godkjenninger av bestillinger bruker én Power Automate-flyt som kjører når status på en bestilling i **`Provisioning Requests`**-listen endres til **`Submitted`** (brukeren sender inn bestillingen i Bestillingsportalen webdel eller Teams app).

Følg stegene for å konfigurere Bestillingsportalen-innstillingene avhengig av hvilken godkjenningsmetode du vil bruke.

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

## Steg 2: Importere og aktivere flyten

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

## Steg 3: Dele flyt og SharePoint-område

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

## Steg 4: Kjøre/konfigurere støttende Logic Apps

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

## Steg 5 (valgfritt): Aktivere Site Templates og Hub Sites

Før Hub Sites og Site Templates er synlige for sluttbrukere i Bestillingsportalen webdel eller Teams app, må de aktiveres.

Det finnes en Yes/No-kolonne kalt `Enabled` i `Hub Sites`- og `Site Templates`-listene. Hvis du vil gjøre en mal synlig for sluttbrukere, rediger listeelementet og sett kolonneverdien til `true`.

Årsaken til denne kolonnen er å gi administratorer fleksibilitet til å vise/skjule Site Templates og Hub Sites.

![Enabled column in Site Templates list](/Images/SiteTemplatesListEnabled.png)

> **Bruker en provisioning-type `Join Hub`?** Sett også `Default Hub` på typen i `Provisioning Types`-listen — se merknaden om dette i [Provisioning Types](./Provisioning-types.md). Uten den kan bestillinger komme inn uten hub-ID, og området blir stående uten hub-tilknytning.

## Steg 6: Sette opp administratorgruppe

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

## Steg 7 (valgfritt): Aktivere automatisk godkjenning (deaktivere godkjenningsprosess)

Hvis du ikke ønsker å bruke den innebygde Power Automate-godkjenningsprosessen, kan du aktivere `Auto approval` via `Provisioning Request Settings`-listen.

For å aktivere, gå til innstillingslisten, rediger listeelementet `EnableAutoApproval` og sett `Value`-kolonnen til `true`.

Når brukere sender inn bestillinger via Bestillingsportalen webdel eller Teams app, settes statusen til `Approved`. Godkjenningsflyten kjører da ikke, og provisjoneringsprosessen starter umiddelbart.

## Steg 8: Verifiser med en testbestilling

Send en bestilling gjennom hele løpet før løsningen annonseres for brukerne — det er den eneste testen som dekker alle leddene samlet: tilganger, godkjenningsflyt, Logic Apps, runbook-konfigurasjon og varsling.

1. **Test som en vanlig bruker** — ikke som tjenestekontoen og ikke som administratoren som installerte. Det verifiserer tilgangene fra Steg 3 og den normale eier-flyten i provisjoneringen.
2. Send inn en testbestilling via webdelen eller Teams-appen — gjerne av en type med Teams-avhuking og hub-tilknytning, så testes mest mulig.
3. Godkjenn bestillingen (Approvals-oppgave eller Teams-kort, avhengig av Steg 1).
4. Følg statusfeltet i `Provisioning Requests`-listen: `Submitted` → `Approved` → `Space Creation` → `Space Created`. Logic App-en kjører på 1-minutts polling og gruppeprovisjonering har innebygde ventetider, så regn med 10–15 minutter totalt.
5. Verifiser resultatet: området/teamet finnes, riktige eiere og medlemmer, hub-tilknytning og regionale innstillinger (norsk språk/tidssone) er på plass, og bestilleren har fått e-post og adaptivt kort.
6. Ved **`Space Creation Failed`**: les `StatusReason`-feltet på bestillingen — det navngir steget som feilet og feilmeldingen. For runbook-feil: åpne `ConfigureSpace`-jobben i Automation-kontoen og les stegtabellen nederst i loggen (`Succeeded`/`Skipped`/`Failed` per konfigurasjonssteg). Se [Feilhåndtering](./Error-handling.md).

> **Det første døgnet etter installasjon kan gi falske feil.** App-rollene tildeles under deployen, men managed identity-tokens utstedes med rollene som gjaldt på utstedelsestidspunktet og caches i opptil ~24 timer i Azure-infrastrukturen. De første timene kan Logic Apps og runbooks derfor få sporadiske 401/403 eller Graph-feil av typen `Roles on the request ''` — også blandet, der noen kall lykkes og andre feiler i samme kjøring — selv om alt er riktig konfigurert. Dette leger seg selv senest 24 timer etter tildelingen. Feiler testbestillingen med slike symptomer på installasjonsdagen: ikke feilsøk konfigurasjonen — vent, og test på nytt neste dag.

Husk å rydde opp etterpå: slett testområdet/-teamet (slett Microsoft 365-gruppen, så følger området med). Merk at et permanent slettet område/gruppe holder på alias og URL en stund til slettingen har propagert — bruk et annet navn hvis du tester på nytt umiddelbart.

## Konfigurasjonen er nå fullført, og Bestillingsportalen webdel eller Teams app skal være tilgjengelig

## Merknad: Bestillings-webdelen følger denne løsningen

Selve bestillings-webdelen (grensesnittet der brukerne bestiller samarbeidsområder) inngår fra og med versjon 1.0.0 i **dette repoet**, som del av SPFx-pakken `bp-provision-web-parts.sppkg` — den distribueres automatisk av `deploy.ps1`. Prosjektportalen 365 er ikke lenger en forutsetning. Slik tas den i bruk:

1. Legg webdelen **Bestillingsportalen** inn på en SharePoint-side der brukerne skal bestille.
2. Sett eventuelt URL-egenskapen i webdelens property pane til den **absolutte URL-en** til Bestillingsportalen-området (f.eks. `https://<tenant>.sharepoint.com/sites/Bestillingsportalen`). Feltet kan stå tomt: da brukes standardinstansen fra tenant-registeret `bp_ProvisionUrls` (se [Tenant-registeret](#merknad-tenant-registeret-bp_provisionurls)), deretter `/sites/bestillingsportalen`.

Husk også at brukerne må ha tilgang til området og `Provisioning Requests`-listen (Steg 3) før de kan bestille.

### Tilgangsstyring med sikkerhetsgruppe (`requireProvisionAccess`)

Webdelen kan begrenses til medlemmer av en SharePoint-gruppe: slå på egenskapen **`requireProvisionAccess`** (av som standard) i property pane. Webdelen slår da opp en gruppe **på området der siden ligger**, med tittel lik egenskapen **`provisionAccessGroupTitle`** (standard `Bestillingsportalen`), og skjuler bestillingsflaten for brukere som ikke er medlem.

Gruppen opprettes **ikke** automatisk — verken av `deploy.ps1` eller av PnP-malen (den vet ikke hvor webdelen plasseres). Skal tilgangsstyring brukes, opprett gruppen manuelt på området (Områdeinnstillinger → Personer og grupper), gi den samme tittel som `provisionAccessGroupTitle`, og legg inn brukerne som skal kunne bestille.

> **Tenanter med Prosjektportalen 365:** Porteføljer provisjonert med PP365 ≤ 1.13 har allerede gruppen — `Bestillingsportalen` på norske installasjoner, **`Provision portal`** på engelske (sett i så fall `provisionAccessGroupTitle` til den engelske tittelen). Fra og med PP365 1.14 provisjonerer ikke PP365-malen gruppen lenger; eksisterende grupper består.

> **Oppgradering i tenanter med Prosjektportalen 365:** Til og med PP365 1.14 fulgte webdelen med PP365-pakken `pp-portfolio-web-parts`, med samme komponent-id. Appkatalogen tillater ikke to pakker som registrerer samme komponent — oppgrader derfor **først** Prosjektportalen 365 til en versjon uten webdelen, og distribuer **deretter** denne pakken, i samme vedlikeholdsvindu. Eksisterende Bestillingsportalen-sider viser «finner ikke komponenten» i mellomtiden og virker igjen så snart denne pakken er distribuert (komponent-id-en er beholdt). Oppdater til slutt Teams-appen fra denne pakken (se under).

## Merknad: Tenant-registeret `bp_ProvisionUrls`

Webdelene og Teams-appen finner Bestillingsportalen-området via en tenant-omfattende **storage entity** med nøkkel `bp_ProvisionUrls`, som `deploy.ps1` vedlikeholder automatisk ved hver installasjon og oppgradering (Teams-appen har ingen property pane, så uten registeret ville URL-en vært låst til standarden `/sites/bestillingsportalen`). Verdien er enten en ren URL eller et JSON-array av `{title, url}`-objekter der **første element er tenantens standardinstans**:

```json
[
  { "title": "Bestillingsportalen", "url": "/sites/bestillingsportalen" },
  { "title": "Bestillingsportalen Stab", "url": "/sites/bp-stab" }
]
```

Registeret kan også administreres manuelt mot **tenant app-katalogen** (krever SharePoint-administrator):

```powershell
Get-PnPStorageEntity -Key bp_ProvisionUrls
Set-PnPStorageEntity -Key bp_ProvisionUrls -Value '[{"title":"Bestillingsportalen","url":"/sites/bestillingsportalen"}]'
```

URL-oppløsningen er: på SharePoint-sider vinner property pane-verdien, med registerets standardinstans som fallback når feltet står tomt; i Teams vinner registeret. Verdien mellomlagres i `sessionStorage`, så endringer i registeret slår inn i en ny fane/økt. Gjeste-webdelen (`InviteGuests`) bruker samme register som fallback for `guestRequestSiteUrl`.

### Flere instanser i samme tenant

En tenant kan kjøre flere Bestillingsportalen-installasjoner (f.eks. per forretningsenhet) — hver installasjon registrerer seg i `bp_ProvisionUrls` med navnet fra parameteren `provisionInstanceTitle` (standard: `requestsSiteName`). På SharePoint-sider velges instans per webdel via URL-egenskapen. I Teams-appen filtreres registeret på **brukerens tilgang** (lesetilgang til instansens område):

- Tilgang til **ingen** instanser → feilmelding om manglende tilgang / at området ikke finnes
- Tilgang til **én** instans → appen åpner den direkte, ingen velger vises
- Tilgang til **flere** instanser → brukeren får en instansvelger; valget huskes per bruker (localStorage), og en `Bytt bestillingsportal`-meny øverst i appen lar brukeren bytte senere

## Merknad: Aktivere Teams-appen for Bestillingsportalen

Bestillingsportalen finnes også som Teams-app, slik at brukerne kan bestille samarbeidsområder direkte fra Teams. Teams-app-manifestet ligger i dette repoet (`ProvisionWebParts/teams/`), og `deploy.ps1` pakker og publiserer det til Teams-appkatalogen som del av SPFx-distribusjonen.

1. **Publiser appen til Teams.** `deploy.ps1` forsøker å publisere automatisk via Graph; mangler PnP-appen tillatelsen `AppCatalog.ReadWrite.All` (det vanlige), lastes zip-pakken opp manuelt i Teams admin center i stedet — se [Teams-appen](./Deployment-guide.md#teams-appen) i installasjonsveiledningen. Ikke bruk `Sync to Teams`-knappen i SharePoint-appkatalogen — den er upålitelig.

2. **Kontroller appen i Teams admin center.** Som Teams-administrator: gå til [Teams admin center](https://admin.teams.microsoft.com/policies/manage-apps) → `Teams apps` → `Manage apps` og søk etter **Bestillingsportalen**. Kontroller at `App status` står som `Unblocked` og at `Available to` dekker brukerne som skal ha appen (f.eks. `Everyone`). Hvordan du styrer tilgjengeligheten og eventuelt pinner appen automatisk for brukerne er beskrevet i underseksjonene nedenfor.

   ![Bestillingsportalen i Teams admin center](/Images/teamsapp-step2.png)

3. **Finn appen i Teams-klienten.** Gå til `Apper` → **`Bygget for organisasjonen din`** og finn **Bestillingsportalen**. Det kan ta litt tid (opptil noen timer) fra synkroniseringen til appen dukker opp her.

   ![Bestillingsportalen under Bygget for organisasjonen din i Teams](/Images/teamsapp-step3.png)

4. **Legg til appen.** Klikk på appen og velg **`Legg til`**.

   ![Legg til Bestillingsportalen i Teams](/Images/teamsapp-step4.png)

Bestillingsportalen åpnes nå som en egen app i Teams, med samme grensesnitt som webdelen — brukerne kan bestille områder direkte herfra:

![Bestillingsportalen åpnet som app i Teams](/Images/teamsapp-startpage.png)

Teams-appen bruker samme oppsett som webdelen: bestillinger sendt fra Teams skrives til de samme listene og behandles av den samme godkjenningsflyten (Steg 1–3 gjelder altså uendret). Husk at brukerne må ha tilgang til området og `Provisioning Requests`-listen (Steg 3) også når de bestiller fra Teams.

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

Merk at app-tilgjengelighet kun styrer hvem som ser appen i Teams — tilgang til selve bestillingsdataene styres fortsatt av SharePoint-tilgangene i Steg 3.

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
