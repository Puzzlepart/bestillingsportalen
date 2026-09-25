# Brukerveiledning for Bestillingsportalen-appen

Denne veiledningen beskriver hvordan du bestiller et nytt samarbeidsområde og følger bestillingen i Bestillingsportalen. Den dekker også webdelen for invitasjon av eksterne gjester.

Veiledningen er skrevet for sluttbrukere. Administratorer og utviklere finner oppsett, dataflyt og tekniske detaljer i [teknisk referanse for appen](./App-teknisk-referanse.md).

![Bestillingsportalen](./Images/bp_app.png)

## Hva kan du gjøre i appen?

Bestillingsportalen gir en styrt inngang til å:

- bestille SharePoint-områder, Microsoft Teams-team, Microsoft 365-grupper og Viva Engage-fellesskap
- velge eiere, medlemmer, personvern, maler og andre egenskaper organisasjonen har gjort tilgjengelige
- følge status på egne bestillinger
- invitere eksterne gjester til et eksisterende SharePoint-område, når gjesteinvitasjonswebdelen er tilgjengelig

Hvilke områdetyper, felt og valg du ser, bestemmes av organisasjonens konfigurasjon. Skjermbildet kan derfor avvike noe fra eksemplene i denne veiledningen.

## Hvor finner du Bestillingsportalen?

Appen kan være tilgjengelig på to måter:

- som webdelen **Bestillingsportalen** på en SharePoint-side
- som den personlige appen **Bestillingsportalen** i Microsoft Teams

I Teams kan organisasjonen ha flere Bestillingsportalen-instanser. Har du tilgang til flere, velger du instans når appen åpnes. Valget huskes, og du kan senere bruke **Bytt bestillingsportal** i menyen. Har du bare tilgang til én instans, åpnes den direkte.

Får du melding om manglende tilgang eller at Bestillingsportalen ikke finnes, må du kontakte lokal administrator. Appen kan ikke gi deg tilgang på egen hånd.

## Bestille et samarbeidsområde

### 1. Åpne skjemaet

På en SharePoint-side velger du knappen for å opprette en ny bestilling. I Teams vises bestillingsskjemaet normalt direkte.

Skjemaet er delt i inntil tre trinn. Enkelte trinn eller felt kan være skjult for den valgte områdetypen.

### 2. Velg områdetype

Velg typen samarbeidsområde du trenger. Typiske valg er:

- **Prosjektområde**
- **Microsoft Teams Team**
- **Viva Engage Community**

Listen kan inneholde andre organisasjonsspesifikke typer. Bare typer du har tilgang til og som administrator har aktivert, vises.

Når du endrer områdetype, kan standardverdier, feltnavn og tilgjengelige valg endres. Kontroller derfor resten av skjemaet etter at du har valgt type.

### 3. Fyll inn grunninformasjon

| Felt                | Hva du skal fylle inn                                                                    |
| ------------------- | ---------------------------------------------------------------------------------------- |
| Navn                | Et tydelig navn for området eller teamet. Navnet brukes også til å beregne alias og URL. |
| Beskrivelse         | Formålet med samarbeidsområdet.                                                          |
| Begrunnelse         | Hvorfor området er nødvendig, dersom organisasjonen ber om dette.                        |
| Tilleggsinformasjon | Andre opplysninger godkjenner eller administrator trenger. Feltet kan være skjult.       |
| Eiere               | Personene som skal administrere området. Du blir normalt lagt til automatisk.            |
| Medlemmer           | Personene som skal delta fra starten. Medlemmer kan også legges til senere.              |

Organisasjonen kan bruke navnekonvensjoner som automatisk legger til prefiks eller suffiks. Alias og URL beregnes mens du skriver og kan være skrivebeskyttet.

En person kan ikke være både eier og medlem i samme bestilling. Organisasjonen kan også kreve et minimum antall eiere.

### 4. Velg egenskaper

Følgende valg kan vises avhengig av områdetype og konfigurasjon:

| Valg                    | Betydning                                                                                                   |
| ----------------------- | ----------------------------------------------------------------------------------------------------------- |
| Opprett Team            | Knytter et Microsoft Teams-team til området. For områdetypen Microsoft Teams Team er dette alltid aktivert. |
| Teams-mal               | Velger en Teams-mal som administrator har gjort tilgjengelig.                                               |
| Personvern              | Angir om området eller gruppen skal være privat eller offentlig.                                            |
| Konfidensielle data     | Markerer at området skal behandle konfidensielle data.                                                      |
| Ekstern deling          | Angir om eksterne brukere skal kunne få tilgang. Valget vises bare for typer som tillater ekstern deling.   |
| Gjester                 | Eksterne personer som skal knyttes til bestillingen. Feltet vises når ekstern deling er aktivert.           |
| Sensitivitetsmerke      | Velger et publisert merke for området eller gruppen.                                                        |
| Bibliotekmerke          | Velger et sensitivitetsmerke for dokumentbiblioteket.                                                       |
| Oppbevaringsmerke       | Velger et oppbevaringsmerke som skal brukes på innholdet.                                                   |
| Utløpsdato              | Angir dato eller antall måneder før området skal vurderes som utløpt.                                       |
| Hub-område              | Velger eller viser huben området skal knyttes til.                                                          |
| Områdemal eller PnP-mal | Bestemmer standard struktur og innhold.                                                                     |
| Bilde                   | Laster opp et bilde for området dersom typen støtter det.                                                   |
| Metadata                | Organisasjonsspesifikke egenskaper som kan overføres til prosjekt- eller hubdata.                           |

Noen verdier er forhåndsvalgt fra områdetypen eller globale innstillinger. Et skjult felt betyr ikke nødvendigvis at funksjonen er avslått; administrator kan ha satt en fast standardverdi.

### 5. Kontroller og send inn

Knappen for innsending er utilgjengelig til alle krav er oppfylt. Appen kontrollerer blant annet:

- at obligatoriske felt er fylt ut
- at minimum antall eiere er valgt
- at samme person ikke er både eier og medlem
- at personene kan løses i SharePoint
- at URL-en eller aliaset ikke allerede er i bruk
- at det ikke finnes en aktiv bestilling med samme alias

Velg **Send inn** når opplysningene er riktige.

En vellykket innsending betyr at bestillingen er registrert. Området opprettes ikke nødvendigvis med én gang. Vanligvis må bestillingen først godkjennes, og deretter behandles den av de automatiske provisjoneringsprosessene. Automatisk godkjenning kan være aktivert i enkelte installasjoner.

## Følge en bestilling

Åpne **Status** fra menyen i Bestillingsportalen. Du ser bestillinger du selv har opprettet eller står oppført som bestiller for.

Du kan:

- søke i bestillingene
- sortere på navn, type, status eller dato
- åpne det ferdige området når URL-en er tilgjengelig
- slette bestillinger som ikke er sendt inn, er avvist, har feilet eller gjelder et område som allerede finnes

Statuslisten oppdateres ikke nødvendigvis umiddelbart. Bakgrunnsprosessene leser normalt SharePoint-listene med omtrent ett minutts intervall, men den totale behandlingstiden varierer med områdetype, godkjenning og belastning i Microsoft 365 og Azure.

### Statusforklaring

| Status                | Betydning                                                                                                                   |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Not Submitted         | Bestillingen er ikke sendt til godkjenning.                                                                                 |
| Submitted             | Bestillingen er sendt inn og venter på videre behandling.                                                                   |
| Pending Approval      | Bestillingen venter på en godkjenner.                                                                                       |
| Approved              | Bestillingen er godkjent og venter på provisjonering.                                                                       |
| Team Requested        | Opprettelse av team er forespurt.                                                                                           |
| Space Creation        | Området eller teamet opprettes og konfigureres.                                                                             |
| Space Created         | Området er ferdig opprettet.                                                                                                |
| Rejected              | Bestillingen ble avvist. Kommentar fra godkjenner kan være tilgjengelig.                                                    |
| Space Already Exists  | Aliaset eller URL-en var allerede i bruk.                                                                                   |
| Space Creation Failed | Ett eller flere opprettings- eller konfigurasjonssteg feilet. Kontakt administrator med navn og tidspunkt for bestillingen. |

Godkjenning utføres ikke inne i Bestillingsportalen-appen. Godkjenneren bruker Power Automate Approvals eller et godkjenningskort i Teams, avhengig av organisasjonens oppsett.

## Invitere eksterne gjester

Webdelen **Gjesteinvitasjon** kan plasseres på SharePoint-områder der organisasjonen tillater selvbetjent gjesteinvitasjon. Tilgang kan være begrenset til områdeeiere, til eiere og medlemmer, eller til alle med områdetilgang.

![Gjesteinvitasjon](./Images/Gjesteinvitasjonswebdel.png)

### 1. Legg til gjester

Velg **Inviter gjester**, og skriv inn én eller flere e-postadresser. I flergjestemodus kan adressene skilles med komma, semikolon eller linjeskift.

Appen forsøker å finne eksisterende brukere i organisasjonens Entra ID. For eksisterende brukere fylles navn ut automatisk. For nye gjester kan du bli bedt om å fylle inn fornavn, etternavn og firma.

### 2. Velg tilgang

Administratoren bestemmer hvilke valg som vises. Mulige valg er:

- **Gjest**: gjesten legges til som gjestemedlem i områdets Microsoft 365-gruppe. På et gruppetilknyttet område gir dette normalt tilgang til området og tilhørende tjenester som Teams.
- **Ingen rolle**: gjesten legges ikke til i Microsoft 365-gruppen. Gjesten kan likevel få SharePoint-tilgang dersom du velger en SharePoint-gruppe.
- **Ingen SharePoint-gruppe**: ingen ekstra SharePoint-gruppetilgang gis.
- **Eksisterende SharePoint-gruppe**: gjesten legges til i valgt gruppe.
- **Ny SharePoint-gruppe**: det opprettes en gruppe med valgt tillatelsesnivå.
- **Forhåndsvalgt gruppe**: administratorens faste gruppe brukes.

Tilgangsforhåndsvisningen viser hva valgene normalt innebærer. Velger du både **Ingen rolle** og ingen SharePoint-gruppe, blir gjesten invitert til tenanten uten automatisk tilgang til det aktuelle området.

Ved flere gjester kan profil og tilgang enten være felles eller angis per gjest. Det avhenger av webdelens konfigurasjon.

### 3. Send forespørselen

Kontroller sammendraget og send inn. Appen oppretter én forespørsel per gjest med status `Pending`.

En bekreftelse betyr at forespørslene er registrert, ikke at gjestene allerede har mottatt invitasjonen. Bakgrunnsprosessen inviterer eller finner brukeren, registrerer deg som sponsor i Entra ID og tildeler den valgte tilgangen.

### 4. Følg status

| Status  | Betydning                                                               |
| ------- | ----------------------------------------------------------------------- |
| Pending | Forespørselen venter på behandling.                                     |
| Invited | Invitasjonen og de valgte tilgangsstegene er fullført.                  |
| Failed  | Behandlingen feilet. Hold pekeren over statusen for å se feilmeldingen. |

Avhengig av konfigurasjonen kan du:

- kopiere innløsningslenken for en fullført invitasjon
- prøve en mislykket forespørsel på nytt
- søke etter gjestens e-postadresse
- oppdatere statuslisten manuelt

Når du prøver på nytt, opprettes en ny forespørsel. Den gamle mislykkede forespørselen flyttes til papirkurven.

## Viktige avgrensninger

- Appen oppretter en forespørsel. Power Automate, Logic Apps og Azure Automation utfører godkjenning og provisjonering i bakgrunnen.
- Valg og hjelpetekster kan være tilpasset av organisasjonen. Lokal praksis går foran generelle eksempler i denne veiledningen.
- Innstillingsvisningen i appen er eksperimentell og i praksis skrivebeskyttet. Administratorer vedlikeholder normalt innstillinger i SharePoint-listene eller webdelens egenskaper.
- Feltet **Intern kanal** kan registrere et valg på bestillingen, men standardløsningen oppretter eller fjerner ikke en Teams-kanal basert på dette feltet. En organisasjonsspesifikk utvidelse må implementere selve kanalhandlingen.
- Gjesteinvitasjon gir bare den tilgangen som er valgt. En invitasjon uten gruppe- eller områdetilgang gjør ikke gjesten til deltaker på området.

## Vanlige problemer

| Problem                                       | Hva du kan gjøre                                                                                                    |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Bestillingsknappen er deaktivert              | Kontroller obligatoriske felt, eiere, duplikate eiere/medlemmer og eventuelle markerte valideringsfeil.             |
| Navnet eller URL-en er opptatt                | Velg et annet navn. Et nylig slettet område kan holde på aliaset en stund.                                          |
| En person kan ikke legges til                 | Kontroller skrivemåte og at personen finnes i organisasjonen. Kontakt administrator hvis oppslaget fortsatt feiler. |
| Jeg ser ikke ønsket områdetype eller felt     | Administrator har ikke aktivert typen, du mangler målgruppetilgang, eller feltet er skjult for typen.               |
| Status står lenge på Submitted eller Approved | Oppdater status. Ved langvarig venting må administrator kontrollere godkjenningsflyten og Logic App-kjøringene.     |
| Bestillingen har status Space Creation Failed | Hold musepekeren over statusen for å se årsaken. Oppgi bestillingens navn, tidspunkt og årsaken til administrator. |
| Gjesteinvitasjonen står på Pending            | Oppdater status etter noen minutter. Ved langvarig venting må administrator kontrollere `ProcessGuestRequest`.      |
| Gjesteinvitasjonen har status Failed          | Les feilmeldingen i statusvisningen og prøv på nytt dersom knappen er tilgjengelig.                                 |
| Jeg får ikke åpnet appen                      | Kontroller at du har tilgang til Bestillingsportalen-området og siden eller Teams-appen.                            |

## Personvern og ansvar

Bestillinger og gjesteforespørsler lagres i organisasjonens SharePoint-miljø. Appen bruker din innloggede Microsoft 365-identitet når den leser og skriver data. Bakgrunnsprosessene bruker organisasjonens administrerte identiteter og tjenestekonto.

Ved gjesteinvitasjon registreres bestilleren som sponsor for gjesten i Entra ID. Sponsoropplysningen dokumenterer hvem som står bak invitasjonen, men gir ikke sponsoren ekstra tilgang.

Kontakt organisasjonens Bestillingsportalen-administrator for spørsmål om lagringstid, godkjenningsregler, ekstern deling og lokal bruk av metadata.

## Mer dokumentasjon

- [Teknisk referanse for appen](./App-teknisk-referanse.md)
- [Godkjenningsflyt](./Approval-flow.md)
- [Provisioning Types](./Provisioning-types.md)
- [Navnekonvensjoner](./Naming-conventions.md)
- [Sensitivitetsmerker](./Sensitivity-labels.md)
- [Oppbevaringsmerker](./Retention-labels.md)
- [Feilhåndtering](./Error-handling.md)
