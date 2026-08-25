# Konfigurasjonsveiledning

Denne veiledningen tar over der [Installasjonsveiledningen](./Deployment-guide.md) slutter: `deploy.ps1` har kjørt, API-tilkoblingene er autorisert med tjenestekontoen, og app-rollene er tildelt. Stegene her krever ingen Azure-tilganger (utenom valgfri kikk på kjørehistorikk) — de gjøres i SharePoint og Teams, og kan utføres av den som skal konfigurere og forvalte løsningen.

Innstillingene for Bestillingsportalen finnes i `Provisioning Request Settings`-listen på Bestillingsportalen-området, som nøkkel/verdi-par (Title/Value). Standardverdiene seedes av PnP-malen ved installasjon (`<pnp:DataRows>` i `Source/Templates/Objects/Lists/Provisioning Request Settings.xml`) — eksisterende elementer røres aldri ved re-apply, og manglende standardelementer legges til.

## Steg 1: Konfigurere godkjenningsprosess

Godkjenning av bestillinger i løsningen kan skje på to måter:

- Godkjennings-epost (epost med Approve/Reject-valg sendt til godkjenner(ne)).
- Microsoft Teams Adaptive Card-godkjenning (adaptivt kort postet i en Teams-kanal).

Godkjenninger av bestillinger håndteres av Logic Appen **`ProcessApprovalRequest`** (deployet av `deploy.ps1`), som kjører når status på en bestilling i **`Provisioning Requests`**-listen endres til **`Submitted`** (brukeren sender inn bestillingen i Bestillingsportalen webdel eller Teams app). Se [Godkjenningsflyt](/Approval-flow.md) for hvordan prosessen fungerer.

Følg stegene for å konfigurere Bestillingsportalen-innstillingene avhengig av hvilken godkjenningsmetode du vil bruke.

### Godkjennings-epost

1. Gå til SharePoint-området opprettet som del av installasjonen.
2. Finn `Provisioning Request Settings`-listen og åpne den.
3. Rediger listeelementet `ApproverEmail` og sett `Value`-feltet til e-post/UPN for en **enkelt bruker** ELLER en **Microsoft 365-gruppe**. Flere godkjennere kan angis separert med semikolon — første svar avgjør utfallet.
4. Sørg for at verdien på listeelementet `PostToTeams` er satt til `false`.
5. Lagre endringene.

Godkjenninger er nå konfigurert til å bruke godkjennings-epost. Eposten sendes fra tjenestekontoen (via den autoriserte Outlook-API-tilkoblingen), og godkjenneren svarer med knappene direkte i eposten.

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

Godkjenninger bruker nå adaptive cards i Teams. Gå tilbake til denne seksjonen hvis du senere ønsker å bytte til godkjennings-epost.

### Verifisere godkjennings-Logic Appen (valgfritt)

Godkjenningsprosessen kjører i Logic Appen `ProcessApprovalRequest`, som deployes og aktiveres av `deploy.ps1` — det er ingen import- eller aktiveringssteg. Vil du kontrollere den:

1. Gå til Azure Portal (portal.azure.com) og finn Logic Appen `ProcessApprovalRequest` i ressursgruppen fra installasjonen.
2. Kontroller at status er `Enabled`, og at kjørehistorikken viser kjøringer etter at bestillinger er sendt inn. En kjøring står som `Running` mens den venter på svar fra godkjenner — det er normalt.

> Oppgraderer du fra en versjon som brukte Power Automate-flyten `Provisioning Request Approval`, må flyten skrus av og slettes — se [Upgrade.md](/Upgrade.md).

## Steg 2: Dele SharePoint-området

Før Bestillingsportalen kan rulles ut, må SharePoint-området deles med alle brukerne som skal sende inn bestillinger.

Stegene nedenfor deler SharePoint-området med sluttbrukere, slik at de får tilgang til å opprette/redigere bestillinger uten å endre backend-innstillinger i Bestillingsportalen.

1. Gå til SharePoint-området opprettet under installasjonen.
2. Klikk `Settings` _(tannhjulet)_ oppe til høyre.
3. Klikk `Site permissions`.
4. Klikk `Advanced Permissions settings`.
5. Klikk `Grant Permission` i toppmenyen og søk etter brukernavnet eller e-postadressen du vil dele området med, ELLER velg en gruppe med brukerne.
6. Klikk `Show Options` og velg `Visitors`-gruppen under `Permission level` (dette gir brukerne lesetilgang til området i første omgang).
7. Gå til `Provisioning Requests`-listen og [følg disse stegene](https://support.office.com/en-gb/article/customize-permissions-for-a-sharepoint-list-or-library-02d770f3-59eb-4910-a608-5f84cc297782) for å bryte arv av tilganger. Gi `Visitors`-gruppen `Edit`-rettigheter (dette sikrer at brukerne kan opprette bestillinger).

## Steg 3: Kjøre/konfigurere støttende Logic Apps

Det finnes noen støttende Logic Apps som bør kjøres manuelt etter første installasjon.

Disse er konfigurert med tilbakevendende triggere og kjører ukentlig som standard. Du kan endre kjørefrekvensen til en plan som passer organisasjonen din.

Detaljer om disse:

- **GetHubSites** – Henter alle Hub Sites i tenanten og oppretter dem som listeelementer i `Hub Sites`-listen.
- **GetSiteTemplates** – Henter alle SharePoint Site Templates installert i tenanten og oppretter dem som listeelementer i `Site Templates`-listen.
- **GetTeamsTemplates** – Henter Teams-maler konfigurert i Teams Admin Center og oppretter referanser til disse som listeelementer i `Teams Templates`-listen.
- **SyncGroupSettings** – Henter gruppe-innstillinger (blokkerte ord og klassifiseringer) fra Entra ID og oppdaterer listeelementer i `Provisioning Request Settings`-listen.
- **SyncLabels** – Henter alle sensitivitetsmerker fra Purview i tenanten og legger dem til i `IP Labels`-listen.

> **MERK:** Logic Appene `ProcessProvisionRequest`, `ProcessApprovalRequest` og `ProcessGuestRequest` trigges automatisk av endringer i listene (1-min polling) og skal **ikke** kjøres manuelt. De deployes som del av `deploy.ps1`.

Slik kjører du dem «on demand»:

1. Gå til Azure Portal (portal.azure.com).
2. Finn ønsket Logic App, f.eks. `GetHubSites`. Du kan enten søke i søkefeltet eller finne ressursgruppen fra installasjonen og finne Logic App-en der.
3. Velg Logic App-en.
4. Klikk `Run Trigger > Run`.
5. Når Logic App-en har kjørt, skal statusen i kjørehistorikken være `Succeeded`.
6. Gjenta stegene for hver Logic App.

## Steg 4 (valgfritt): Aktivere Site Templates og Hub Sites

Før Hub Sites og Site Templates er synlige for sluttbrukere i Bestillingsportalen webdel eller Teams app, må de aktiveres.

Det finnes en Yes/No-kolonne kalt `Enabled` i `Hub Sites`- og `Site Templates`-listene. Hvis du vil gjøre en mal synlig for sluttbrukere, rediger listeelementet og sett kolonneverdien til `true`.

Årsaken til denne kolonnen er å gi administratorer fleksibilitet til å vise/skjule Site Templates og Hub Sites.

![Enabled column in Site Templates list](/Images/SiteTemplatesListEnabled.png)

> **Bruker en provisioning-type `Join Hub`?** Sett også `Default Hub` på typen i `Provisioning Types`-listen — se merknaden om dette i [Provisioning Types](./Provisioning-types.md). Uten den kan bestillinger komme inn uten hub-ID, og området blir stående uten hub-tilknytning.

## Steg 5: Sette opp administratorgruppe

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

## Steg 6 (valgfritt): Aktivere automatisk godkjenning (deaktivere godkjenningsprosess)

Hvis du ikke ønsker å bruke den innebygde godkjenningsprosessen, kan du aktivere `Auto approval` via `Provisioning Request Settings`-listen.

For å aktivere, gå til innstillingslisten, rediger listeelementet `EnableAutoApproval` og sett `Value`-kolonnen til `true`.

Når brukere sender inn bestillinger via Bestillingsportalen webdel eller Teams app, settes statusen til `Approved`. Godkjennings-Logic Appen kjører da ikke, og provisjoneringsprosessen starter umiddelbart.

## Steg 7: Verifiser med en testbestilling

Send en bestilling gjennom hele løpet før løsningen annonseres for brukerne — det er den eneste testen som dekker alle leddene samlet: tilganger, godkjenningsflyt, Logic Apps, runbook-konfigurasjon og varsling.

1. **Test som en vanlig bruker** — ikke som tjenestekontoen og ikke som administratoren som installerte. Det verifiserer tilgangene fra Steg 2 og den normale eier-flyten i provisjoneringen.
2. Send inn en testbestilling via webdelen eller Teams-appen — gjerne av en type med Teams-avhuking og hub-tilknytning, så testes mest mulig.
3. Godkjenn bestillingen (godkjennings-epost eller Teams-kort, avhengig av Steg 1).
4. Følg statusfeltet i `Provisioning Requests`-listen: `Submitted` → `Approved` → `Space Creation` → `Space Created`. Logic App-en kjører på 1-minutts polling og gruppeprovisjonering har innebygde ventetider, så regn med 10–15 minutter totalt.
5. Verifiser resultatet: området/teamet finnes, riktige eiere og medlemmer, hub-tilknytning og regionale innstillinger (norsk språk/tidssone) er på plass, og bestilleren har fått e-post og adaptivt kort.
6. Ved **`Space Creation Failed`**: les `StatusReason`-feltet på bestillingen — det navngir steget som feilet og feilmeldingen. For runbook-feil: åpne `ConfigureSpace`-jobben i Automation-kontoen og les stegtabellen nederst i loggen (`Succeeded`/`Skipped`/`Failed` per konfigurasjonssteg). Se [Feilhåndtering](./Error-handling.md).

> **Det første døgnet etter installasjon kan gi falske feil.** App-rollene tildeles under deployen, men managed identity-tokens utstedes med rollene som gjaldt på utstedelsestidspunktet og caches i opptil ~24 timer i Azure-infrastrukturen. De første timene kan Logic Apps og runbooks derfor få sporadiske 401/403 eller Graph-feil av typen `Roles on the request ''` — også blandet, der noen kall lykkes og andre feiler i samme kjøring — selv om alt er riktig konfigurert. Dette leger seg selv senest 24 timer etter tildelingen. Feiler testbestillingen med slike symptomer på installasjonsdagen: ikke feilsøk konfigurasjonen — vent, og test på nytt neste dag.

Husk å rydde opp etterpå: slett testområdet/-teamet (slett Microsoft 365-gruppen, så følger området med). Merk at et permanent slettet område/gruppe holder på alias og URL en stund til slettingen har propagert — bruk et annet navn hvis du tester på nytt umiddelbart.

## Konfigurasjonen er nå fullført, og Bestillingsportalen webdel eller Teams app skal være tilgjengelig

## Merknad: Bestillings-webdelen distribueres separat

Selve bestillings-webdelen (grensesnittet der brukerne bestiller samarbeidsområder) inngår ikke i dette repoet — per i dag følger den **Prosjektportalen**-leveransen. Etter at den er tilgjengelig i tenanten:

1. Legg webdelen inn manuelt på en SharePoint-side der brukerne skal bestille.
2. Sett URL-egenskapen i webdelens property pane til den **absolutte URL-en** til Bestillingsportalen-området (f.eks. `https://<tenant>.sharepoint.com/sites/Bestillingsportalen`) slik at bestillingene skrives til riktige lister.

Husk også at brukerne må ha tilgang til området og `Provisioning Requests`-listen (Steg 2) før de kan bestille.

## Merknad: Aktivere Teams-appen for Bestillingsportalen (krever Prosjektportalen)

Bestillingsportalen finnes også som Teams-app, slik at brukerne kan bestille samarbeidsområder direkte fra Teams. Teams-app-manifestet følger med SPFx-pakken **Prosjektportalen 365 - Portfolio Web Parts** (`pp-portfolio-web-parts`) — akkurat som webdelen i merknaden over krever dette derfor at [Prosjektportalen 365](https://github.com/Puzzlepart/prosjektportalen365) er installert i tenanten, slik at pakken ligger i tenant app-katalogen.

> **Teams-appen har områdets URL hardkodet til `/<managedPath>/bestillingsportalen`.** Webdelen har URL-en som en property i property pane og kan peke hvor som helst — Teams-appen kan ikke. Området må derfor ligge på den URL-en for at Teams-appen skal finne listene. Det er også grunnen til at standardverdien for `requestsSiteAlias` er `bestillingsportalen`; er aliaset opptatt i tenanten, se framgangsmåten i [Installasjonsveiledningen](./Deployment-guide.md#steg-2-oppdatere-parametersjson).

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

Teams-appen bruker samme oppsett som webdelen: bestillinger sendt fra Teams skrives til de samme listene og behandles av den samme godkjenningsprosessen (Steg 1–2 gjelder altså uendret). Husk at brukerne må ha tilgang til området og `Provisioning Requests`-listen (Steg 2) også når de bestiller fra Teams.

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

Merk at app-tilgjengelighet kun styrer hvem som ser appen i Teams — tilgang til selve bestillingsdataene styres fortsatt av SharePoint-tilgangene i Steg 2.

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
