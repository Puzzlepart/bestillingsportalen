# Teams Templates

Bestillingsportalen støtter opprettelse av Teams basert på maler definert i Teams Admin Center. Admin Center-maler driver den innebygde «out of the box» Teams Templates-funksjonaliteten.

I tillegg til Admin Center-baserte maler støtter Bestillingsportalen «kloning» av Teams ved å definere disse som en mal.

Du kan også opprette egne navnekonvensjoner for Teams-maler – følg [Navnekonvensjoner](./Naming-conventions.md)-dokumentasjonen for hvordan du konfigurerer dette.

Les videre for mer informasjon om hvordan du kan konfigurere funksjonaliteten.

**_Maler opprettet i Admin Center kan ta opptil 24 timer før de er fullt tilgjengelige i Microsoft Graph. Vent derfor før du bruker dem._**

***

**VIKTIG – Graph API-endepunkter som brukes:**

Opprettelse av Teams fra Admin Center-maler bruker beta-endepunktet i Graph API. En gruppe opprettes først med v1.0-endepunktet, og deretter legges et team til fra den valgte malen. Se [Graph API Reference – Create team](https://learn.microsoft.com/en-us/graph/api/team-post?view=graph-rest-beta&tabs=http) (eksempel 4).

Kloning av Teams bruker v1.0-endepunktene.

***

**Teams Templates-listen**

`Teams Templates`-listen (som finnes i SharePoint-området bak Bestillingsportalen) definerer settet med maler brukere kan velge blant når de bestiller et Team fra en mal.

Listen skal inneholde Microsofts «out of the box»-maler når løsningen først installeres. Listen populeres av en Logic App – dette er forklart i [Installasjonsveiledningen](./Deployment-guide.md).

Du kan slette listeelementer for maler du ikke trenger. Logic App-en vil imidlertid legge dem til igjen ved neste kjøring, så du kan ønske å deaktivere Logic App-en når malene du trenger er i listen.

`Teams Templates`-listen inneholder følgende felt:

* **Title** – Tittel på malen
* **Description** – Beskrivelse av malen
* **Template id** – ID til malen
* **Team Id** – ID til et Team (Group ID) du ønsker å bruke som mal (for kloning)
* **Admin Center Template** – Identifiserer om malen er opprettet i Admin Center
* **Prefix Attribute** – Attributt brukt for prefiks på team opprettet fra denne malen
* **Suffix Attribute** – Attributt brukt for suffiks på team opprettet fra denne malen
* **Prefix Text** – Prefiks-tekst som legges til foran navnet på team opprettet fra denne malen
* **Suffix Text** – Suffiks-tekst som legges til etter navnet på team opprettet fra denne malen
* **Prefix Use Attribute** – Om attributt skal brukes som prefiks
* **Suffix Use Attribute** – Om attributt skal brukes som suffiks

Se stegene nedenfor for hvordan du definerer dine egne maler.

## Admin Center-maler

Som beskrevet i [Installasjonsveiledningen](./Deployment-guide.md) henter en Logic App kalt `GetTeamsTemplates` maler definert i Admin Center. Denne bruker Graph API – nærmere bestemt beta-endepunktet: https://learn.microsoft.com/en-us/graph/api/teamwork-list-teamtemplates?view=graph-rest-beta&tabs=http.

Dette API-et er foreløpig kun tilgjengelig på beta-endepunktet og er ennå ikke gjort tilgjengelig på v1.0. Sjekk [Graph API-referansen](https://learn.microsoft.com/en-us/graph/api/teamwork-list-teamtemplates?view=graph-rest-beta) for siste status.

**Kun en-US-lokale maler hentes for øyeblikket. Støtte for lokaliserte maler kan bli lagt til i en fremtidig utgivelse.**

### Steg 1: Definer malen i Admin Center

1. Gå til Teams Admin Center.
2. Velg `Team templates` fra venstre meny (under `Teams`).
3. Klikk `+Add` for å opprette en ny mal.
4. Velg om du vil lage en helt ny mal, bruke et eksisterende team eller starte med en eksisterende mal.
5. Fyll ut detaljene og klikk `Next` (**_Merk – kun engelsk (USA) støttes for øyeblikket i Bestillingsportalen_**)

![Creating a template in the Admin Center](https://github.com/OfficeDev/microsoft-teams-apps-requestateam/wiki/Images/template1.png)

6. Opprett kanaler og konfigurer apper for malen, og klikk `Submit`.

![Adding channels and apps to an Admin Center template](https://github.com/OfficeDev/microsoft-teams-apps-requestateam/wiki/Images/template2.png)

7. Når opprettet, klikk på malen og kopier `Template ID`-verdien.

![Copying the template id](https://github.com/OfficeDev/microsoft-teams-apps-requestateam/wiki/Images/template3.png)

### Steg 2: Kjør `GetTeamsTemplates` Logic App

Logic App-en er konfigurert til å kjøre ukentlig – dette kan endres etter behov. Merk at nye maler lagt til i Admin Center automatisk blir lagt til i SharePoint-listen `Teams Templates` når Logic App-en kjører.

Malene er dermed tilgjengelige i Bestillingsportalen webdel eller Teams app for valg. Hvis du har maler du ikke ønsker å vise, deaktiver Logic App-en etter at du har kjørt den.

**_Merk – Når stegene over er fullført, VENT 24 timer før du kjører Logic App-en. Det kan ta opptil 24 timer før malen kan hentes av Logic App-en._**

1. Gå til Azure Portal.
2. Finn ressursgruppen du opprettet for Bestillingsportalen.
3. Finn Logic App-en `GetTeamsTemplates`.
4. Klikk `Run Trigger > Run`.
5. Sjekk at statusen på Logic App-en viser `succeeded`.
6. Åpne listen `Teams Templates`.
7. Verifiser at malen er opprettet som et listeelement.

![GetTeamsTemplates logic app screenshot](./images/GetTeamsTemplatesLA.png)

Malen er nå klar til bruk – sørg for å oppfriske/laste inn Bestillingsportalen webdel eller Teams app på nytt hvis du har den åpen. Når en bruker bestiller et team fra den nye malen, vil det opprettes med det forhåndsdefinerte innholdet du konfigurerte i Admin Center.

**_Merk – Endringer i maler i Admin Center vil ikke endre Teams som tidligere er opprettet fra malen._**

## Kloning av Teams

I tillegg til opprettelse fra Admin Center-maler støtter Bestillingsportalen kloning av eksisterende Teams.

Kloning bruker v1.0 av Microsoft Graph – nærmere bestemt [Clone a team](https://learn.microsoft.com/en-us/graph/api/team-clone?view=graph-rest-1.0&tabs=http). Kloning kan være å foretrekke i et produksjonsmiljø.

Når et team klones, får det ny tittel, beskrivelse osv. som brukeren angir i bestillingen. Alle opprinnelige eiere og medlemmer av kildeteamet fjernes og erstattes med de brukeren har bestilt.

Dette alternativet gir ekstra funksjonalitet sammenlignet med Admin Center-maler, blant annet muligheten til å klone faner og kanaler.

For å bruke denne funksjonaliteten, følg stegene nedenfor.

### Steg 1: Opprett et team som skal brukes som mal

1. Opprett et team med den innebygde funksjonaliteten i Microsoft Teams.
2. Populer teamet slik du ønsker – kanaler, apper, faner osv. (Dette er innholdet som klones og settes opp som nytt team.)
2. Kopier Group Id for teamet. Du finner Group Id i URL-en som genereres når du klikker `Get link to team`.

### Steg 2: Legg malen til i Bestillingsportalen sin Teams Templates-liste

1. Gå til SharePoint-området bak Bestillingsportalen.
2. Åpne `Teams Templates`-listen.
3. Opprett et nytt listeelement med følgende verdier:

* Title – Tittel på malen (dette er det brukerne ser når de velger fra listen over maler)
* Description – Beskrivelse av malen
* Template Id – La stå tom
* Team Id – Lim inn Group Id du kopierte tidligere
* Admin Center Template – No

Nøkkelen er å populere `Team Id`-kolonnen i stedet for `Template Id`. Dette er hvordan provisjoneringen avgjør om vi kloner et team eller oppretter fra en Admin Center-mal.

![Creating template for cloning team screenshot](./images/CloneTeamsTemplate.png)

Malen er nå klar til bruk. Når en bruker sender inn en bestilling som godkjennes, vil teamet klones og settes opp som et nytt team.
