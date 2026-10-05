# Bakgrunnsutredning: SPSiteLanguage ignoreres ved M365-gruppeopprettelse

Sep 30, 2026 · @Tarjei E. Ormestøyl

## Sammendrag

Siden slutten av mai 2026 ignorerer Microsoft Graph verdien `SPSiteLanguage` i `creationOptions` ved opprettelse av Microsoft 365-grupper. Det gruppetilknyttede SharePoint-området opprettes da med rotsidens språk (typisk 1033, engelsk) i stedet for det bestilte (1044, norsk bokmål). Kallet returnerer `201 Created` uten feil eller advarsel.

Prosjektportalens provisjonering validerer at området har samme språk som malen. Når området kommer på engelsk, stopper provisjoneringen med «Ugyldig språk», og e-postvarsel og Teams-tilknytning uteblir fordi de kjøres etter valideringen.

Microsoft har bekreftet feilen i sp-dev-docs #10875 og i en supportsak SoftwareOne har eskalert til SharePoint Product Group. En rettelse ble merget 31. august 2026 med anslått tre ukers utrulling. Test i en kundetenant 29. september 2026 viste at rettelsen fortsatt ikke er aktiv; Microsoft kan ikke verifisere utrullingsstatus per tenant.

Anbefaling: ikke vent på Microsoft. Bruk et administratorkjørt hjelpeskript som oppretter området, verifiserer språk og retryer, med STS#3 + groupify som fallback. Behold rotsiden urørt. Berørte kunder bør i tillegg åpne egen Microsoft-sak fra sin tenant.

## Symptomer i Prosjektportalen og ROS-portalen

Alle symptomene som er rapportert har samme rotårsak: området opprettes med feil språk, og provisjoneringen stopper i språkvalideringen.

| Symptom | Årsak |
| --- | --- |
| «Ugyldig språk» når JSON-malen starter, selv om «Norsk» er valgt | Området fikk `Language = 1033` fra rotsiden. Malen krever 1044. |
| E-post sendes ikke alltid ved opprettelse | Varselet sendes etter fullført provisjonering. Feilet provisjonering gir ingen e-post. |
| Nyopprettede områder mangler Teams-tilknytning i Admin Center | Teamify kjøres som et senere steg i provisjoneringen og nås ikke. |
| Problemet virker tidsavhengig | Enkelte tenanter rapporterer periodevis riktig språk, trolig knyttet til gradvis utrulling av rettelsen. Ikke reproduserbart som ren timing-feil. |

Feilen er ikke spesifikk for Prosjektportalen. Den treffer alle løsninger som oppretter gruppetilknyttede områder via Graph med annet språk enn rotsidens: Bestillingsportalen, PnP Provisioning, Logic Apps, egne skript og tredjepartsløsninger.

## Teknisk bakgrunn

Et gruppetilknyttet teamområde (GROUP#0) opprettes ved at en Microsoft 365-gruppe opprettes først. SharePoint provisjonerer deretter området asynkront på bakgrunn av gruppen. Språk og URL på området har derfor aldri vært parametere på selve SharePoint-kallet, men er blitt sendt med gruppeopprettelsen.

To API-er har vært i bruk for dette:

| API | Autentisering | Språk/URL styres via | Status |
| --- | --- | --- | --- |
| `POST https://graph.microsoft.com/v1.0/groups` | App-only eller delegert | `creationOptions: ["SPSiteLanguage:1044", "SiteAlias:<alias>"]` | Ignoreres siden ca. uke 21 2026 (v1.0). Beta returnerer 400 Bad Request. |
| `POST <tenant>/_api/GroupSiteManager/CreateGroupEx` | Kun delegert | `optionalParams.CreationOptions` med samme verdier | Brukes av SharePoint-UI. Rapportert delvis brutt på enkelte tenanter ([#10875](https://github.com/SharePoint/sp-dev-docs/issues/10875)); avviser app-only token ([#10987](https://github.com/SharePoint/sp-dev-docs/issues/10987)). |

`creationOptions` har aldri vært dokumentert som en egenskap man setter selv. Microsoft Graph-dokumentasjonen for gruppeopprettelse lister ikke egenskapen, og for den beslektede `resourceProvisioningOptions` sier dokumentasjonen eksplisitt at systemet skal styre verdien ([Graph: group set options](https://learn.microsoft.com/en-us/graph/group-set-options)). Mønsteret har likevel vært det eneste tilgjengelige for app-only-provisjonering med annet språk enn rotsidens, og har vært i produksjonsbruk i PnP Framework (`UnifiedGroupsUtility`), PnP PowerShell (`New-PnPSite -Lcid`), Bestillingsportalen og Prosjektportalens provisjonering. SoftwareOnes egen implementasjon har provisjonert 200+ områder på denne måten siden juli 2024, sist bekreftet fungerende mai 2026.

Hva som skjer nå:

1. `POST /groups` med `SPSiteLanguage:1044` returnerer `201 Created`. Verdien lagres på gruppeobjektet og kan leses tilbake med `GET /groups/{id}`.
2. SharePoint provisjonerer området noen minutter senere uten å lese verdien. Området får rotsidens språk.
3. `GET <site>/_api/web?$select=Language` returnerer 1033.
4. Ingen feil, advarsel eller diagnostikk noe sted i kjeden.

Språket på et SharePoint-område kan ikke endres etter opprettelse. Det styrer URL-en til standardbiblioteket (`Shared Documents` vs. `Delte dokumenter`), standard lister og innholdstyper, varsler og e-postmaler. Et område med feil språk må slettes og opprettes på nytt.

## Rotårsak og Microsofts bekreftelse

Microsoft har reprodusert og bekreftet feilen på to kanaler. Rettelsen er merget, men utrullingen kan ikke verifiseres.

**sp-dev-docs #10875** ([lenke](https://github.com/SharePoint/sp-dev-docs/issues/10875)). Opprettet 4. juni 2026, merket `type:bug-confirmed`. Microsoft-representant reproduserte at gruppen opprettes, men at `SPSiteLanguage` og `SiteAlias` ikke anvendes ved områdeprovisjonering; området får `mailNickname` som URL og rotsidens språk. Saken er en repost av [pnpframework #1236](https://github.com/pnp/pnpframework/issues/1236). Over 20 leverandører og partnere rapporterer påvirkning på tvers av mange tenanter. Per slutten av september rapporterer én leverandør (NL) at rettelsen virker, mens norske tenanter fortsatt feiler.

**Microsoft-supportsak** (SoftwareOne, åpnet 1. juli 2026, eskalert til SharePoint Product Group). Hovedpunkter:

| Dato | Hendelse |
| --- | --- |
| 2. jul | Support bekrefter atferdsendringen fra slutten av mai. Anbefalt workaround: STS#3 med språk, deretter groupify, deretter teamify. |
| 3.–8. jul | SoftwareOne rapporterer at groupify-workarounden ikke er deterministisk (duplikatområde, se Workarounds). Ber om offisiell posisjon. |
| 10. jul | Eskalert til Product Group. |
| 27. jul | Fullstendig repro med HAR-trace levert. |
| 28. aug | Product Group har identifisert rettelse, PR under arbeid. |
| 31. aug | Rettelse merget. Anslått utrulling: ca. 3 uker. |
| 22. sep | Retest: fortsatt 1033. Microsoft har ingen metode for å verifisere om en tenant har fått rettelsen. |
| 29. sep | Retest 06:53 UTC: `creationOptions` lagret på gruppen, området fortsatt 1033. Tatt tilbake til Product Group. |

Microsoft har ikke gitt en offisiell kundevendt uttalelse, ingen dokumentert erstatningsmekanisme, og har ikke bekreftet om rettelsen gjenoppretter gammel atferd eller introduserer nytt mønster. Support kan ikke kommentere roadmap.

Relatert: **sp-dev-docs #10987** ([lenke](https://github.com/SharePoint/sp-dev-docs/issues/10987)) ber om at `CreateGroupEx` aksepterer app-only-token, siden det er det eneste SharePoint-API-et som lar `SiteAlias` og `SPSiteLanguage` settes uavhengig av gruppens e-postalias.

## Hvorfor Prosjektportalen feiler

Prosjektportalens provisjonering (JSON-mal via PnP) validerer at områdets språk stemmer med malens språk før malen anvendes. Valideringen finnes fordi en norsk mal på et engelsk område gir ødelagte resultater: feltnavn, listenavn, innholdstyper og URL-er i malen forutsetter norske standardnavn, og et engelsk område mangler dem. Feilmeldingen «Ugyldig språk» er dermed korrekt oppførsel; området er faktisk feil.

Å slå av eller myke opp valideringen løser ikke problemet, det flytter det:

- Standardbiblioteket heter `Shared Documents`, ikke `Delte dokumenter`. Lenker og konfigurasjon i malen som peker på norsk URL brekker.
- Områdets systemvarsler, e-poster og standardtekster kommer på engelsk.
- Blandet språk på tvers av prosjektområder i samme portefølje, uten mulighet til å rette i etterkant (språk kan ikke endres).
- Fremtidige oppgraderinger og skript som forutsetter norsk standardoppsett vil feile på disse områdene.

Konklusjon: språkvalideringen beholdes. Løsningen må sikre riktig språk før provisjoneringen starter, ikke tolerere feil språk.

## Workarounds som er vurdert

Ingen av workaroundene er rene. Tabellen oppsummerer; detaljer under.

| Workaround | Fungerer | Egnet for | Kjente svakheter |
| --- | --- | --- | --- |
| A. Siteswap av rotsiden til norsk | Ja, bekreftet i to tenanter | Tenanter med lite innhold/trafikk på rotsiden, kun ett målspråk | Inngrep i rotsiden. Feilet hos minst én kunde og skapte andre driftsproblemer. Løser ikke flere språk. |
| B. `CreateGroupEx` (SharePoint-UI-API) | Delvis, rapportert brutt på noen tenanter | Delegert kontekst | Udokumentert. Krever bruker/tjenestekonto med fast IP og Entra-rolle for å unngå 250-gruppers grense. Avviser app-only. |
| C. STS#3 + `CreateGroupForSite` (groupify) + teamify | Ja, med feilhåndtering | Delegert kontekst (Logic App, PowerShell med bruker) | Ikke-deterministisk: SharePoint oppretter av og til et duplikatområde. Feature-sett avviker fra GROUP#0. Enkelte gruppeinnstillinger kan bare settes ved opprettelse. |
| D. Retry: opprett, sjekk språk, slett permanent, prøv igjen | Kun hvis tenanten er delvis rettet | Admin-kjørt hjelpeskript | Kaster bort tid hvis LCID ignoreres deterministisk. Opprydding tar 3–5 min per forsøk. |
| E. Slå av språkvalidering i PP | Nei | – | Se forrige seksjon. |

**A. Siteswap.** Rotsiden byttes med et kommunikasjonsområde opprettet på norsk (`Invoke-PnPSiteSwap`). Nye gruppeområder arver da 1044. Dokumentert av SoftwareOne i [#10875](https://github.com/SharePoint/sp-dev-docs/issues/10875). Ikke anbefalt der rotsiden har innhold, tilpasninger eller trafikk. Hos én kunde måtte forsøket reverseres.

**B. CreateGroupEx.** Samme API som SharePoint-UI bruker. Én leverandør i #10875 kjører dette med tjenestekonto og betinget tilgang. Rapportert at også dette API-et ignorerer `SiteAlias` på enkelte tenanter (opprettet `/sites/SPTESTSITECREATION` i stedet for `/sites/WG-SPTESTSITECREATION`). Ikke aktuelt for app-only ([#10987](https://github.com/SharePoint/sp-dev-docs/issues/10987)).

**C. STS#3 + groupify.** Microsoft supports anbefalte workaround. `POST /_api/SPSiteManager/create` med `WebTemplate: STS#3` og `Lcid: 1044` respekterer språk. Deretter `POST <site>/_api/GroupSiteManager/CreateGroupForSite` ([Microsoft: Connect to a Microsoft 365 group](https://learn.microsoft.com/en-us/sharepoint/dev/transform/modernize-connect-to-office365-group)), som krever delegert tilgang. SoftwareOnes testing (juli 2026) viste at `CreateGroupForSite` av og til returnerer suksess og gyldig GroupId, men oppretter et nytt område med nummerert URL i stedet for å koble gruppen til det eksisterende. `SiteStatus = 2` er ikke tilstrekkelig beredskapssignal; Microsoft bekreftet at det ikke finnes noe dokumentert alternativ. En norsk leverandør har publisert en fungerende Logic App-flyt i #10875: buffer på noen minutter etter opprettelse, ensure + site admin for tjenestekontoen, groupify med `SharePointKeepOldHomepage`, verifisering av `Site.GroupId`, og ved duplikat: slett gruppe via Graph, tøm Entra-papirkurv, vent til 404, retry.

**D. Retry-skript.** SoftwareOnes hjelpeskript `New-PPSiteWithLanguageRetry.ps1` (PnP PowerShell) kombinerer D og C: N direkte forsøk med permanent opprydding, deretter fallback til STS#3 + groupify med duplikathåndtering, alt innenfor en tidsramme satt av administrator. Kjøres av administrator før PP-provisjoneringen. Testes i egen tenant før bruk hos kunde.

## Anbefaling og plan videre

Ikke vent på Microsoft. Rettelsen har vært «under utrulling» i fire uker uten verifiserbar effekt, og Microsoft har ingen måte å bekrefte status per tenant.

**For berørte kunder**

1. Ta i bruk hjelpeskriptet som midlertidig rutine: administrator kjører skriptet for hvert nytt område, deretter kjøres PP/ROS-provisjoneringen som normalt. Gjennomgang og første test sammen med SoftwareOne i arbeidsmøte.
2. Der siteswap er forsøkt: rydd opp, og kartlegg hva som ble endret på rotsiden og hvilke driftsproblemer som oppsto.
3. Åpne egen Microsoft-sak fra kundens tenant. Reproduser fra SharePoint Admin Center (nytt teamområde, norsk språk). SoftwareOne leverer reproduksjonssteg og saksreferanse som vedlegg.
4. Ikke rør språkvalideringen i Prosjektportalen.

**For SoftwareOne og andre kunder**

- Test hjelpeskriptet i egen tenant før det tas ut til kunder. Mål: tid per forsøk, andel som treffer i fase 1, og om fase 2 gir duplikater.
- Vurder om Prosjektportalens installasjonsskript skal få innebygd språkverifisering etter opprettelse, med tydelig feilmelding som peker på denne saken, uavhengig av Microsoft-rettelsen.
- Følg opp supportsaken. Be eksplisitt om: bekreftelse på at rettelsen gjenoppretter `SPSiteLanguage`-atferden, og en metode for å verifisere utrulling.
- Følg #10875 for meldinger om at rettelsen er aktiv i norske tenanter. Første tegn er at fase 1 i skriptet begynner å treffe konsekvent.
- Når rettelsen er bekreftet: legg bort hjelpeskriptet, behold det i repoet for neste gang.

**Åpne spørsmål**

- Gjenoppretter Microsofts rettelse eksakt gammel atferd, eller kommer det et nytt, dokumentert mønster? Ubesvart fra Product Group.
- Vil `CreateGroupEx` få app-only-støtte (#10987)? Ingen indikasjon.

## Tidslinje

| Dato | Hendelse |
| --- | --- |
| 5. okt 2026 | Test i egen tenant (`Source/Diagnostics/Test-GroupifyOptions.ps1`): groupify med managed identity avvises med 403 i alle varianter (`CreateGroupForSite` på området, `Add-PnPMicrosoft365GroupToSite` og `Tenant.CreateGroupForSite` i admin-CSOM). Workaround C krever delegert kall. Samme dag, delegert som tjenestekonto uten admin-rolle: `CreateGroupForSite` oppretter gruppen, men SharePoint lager et nytt område med nummerert URL i stedet for å koble gruppen til STS#3-området – 3 av 3 forsøk, 120 s buffer. Nytt forsøk med 15 min buffer (første kall 19 min etter opprettelse): duplikat. Som administrator via PnP (`New-PPSiteWithLanguageRetry.ps1`): duplikat, duplikat, deretter koblet på tredje forsøk (13 min etter opprettelse). Groupify i SharePoint-grensesnittet som administrator: koblet på første forsøk. Ventetid alene forklarer altså ikke duplikatene. Groupify i SharePoint-grensesnittet som tjenestekonto (site collection admin, ingen Entra-rolle): duplikat. Med samme fremgangsmåte koblet administrator riktig, så hvem som kaller ser ut til å avgjøre utfallet. |
| 30. sep 2026 | Hjelpeskript med retry og STS#3-fallback klart for test. Denne utredningen. |
| 29. sep 2026 | Retest i kundetenant: fortsatt 1033. Tilbake til Product Group. Siteswap-workaround har feilet hos en kunde. |
| 22. sep 2026 | Retest: fortsatt 1033. Microsoft kan ikke verifisere utrulling per tenant. |
| 9. sep 2026 | Siteswap foreslått som workaround for en kunde. |
| 7. sep 2026 | Kunde melder «Ugyldig språk» i Prosjektportalen og ROS-portalen. |
| 31. aug 2026 | Rettelse merget hos Microsoft. Anslått 3 ukers utrulling. |
| 28. aug 2026 | Product Group har identifisert rettelse. |
| 27. jul 2026 | SoftwareOne leverer full repro med HAR-trace. |
| 10. jul 2026 | Supportsak eskalert til SharePoint Product Group. |
| 3. jul 2026 | SoftwareOne rapporterer at STS#3 + groupify er ikke-deterministisk (duplikatområde). |
| 2. jul 2026 | Microsoft support bekrefter atferdsendringen. Anbefaler STS#3 + groupify. |
| 1. jul 2026 | SoftwareOne åpner supportsak hos Microsoft. |
| 4. jun 2026 | sp-dev-docs #10875 opprettet. |
| Uke 21 2026 | Graph slutter å respektere `creationOptions`. Ingen varsel, ingen deprecation notice. |
| Mai 2026 | Sist bekreftet fungerende i SoftwareOnes produksjon. |
| Jul 2024 | SoftwareOne tar mønsteret i bruk i Bestillingsportalen. |

## Referanser og kilder

**GitHub-saker**

- [sp-dev-docs #10875 – M365 GroupSite Creation: Ms silently remove option to set SiteAlias, SPLanguage in Graph-API](https://github.com/SharePoint/sp-dev-docs/issues/10875). Hovedsaken. Bug-confirmed. Inneholder repro, siteswap-test (SoftwareOne), Logic App-workaround med duplikathåndtering (norsk leverandør), og løpende status fra andre tenanter.
- [sp-dev-docs #10987 – CreateGroupEx rejects Entra app-only tokens when creating group-connected sites](https://github.com/SharePoint/sp-dev-docs/issues/10987). Ber om app-only-støtte for SharePoint-API-et.
- [pnpframework #1236](https://github.com/pnp/pnpframework/issues/1236). Opprinnelig rapport, videreført til #10875.

**Microsoft-dokumentasjon**

- [Microsoft Graph: Group set options](https://learn.microsoft.com/en-us/graph/group-set-options). Dokumenterer `resourceBehaviorOptions` og `resourceProvisioningOptions`; `creationOptions` er ikke dokumentert som brukerstyrt.
- [Connect to a Microsoft 365 group (modernize)](https://learn.microsoft.com/en-us/sharepoint/dev/transform/modernize-connect-to-office365-group). Groupify programmatisk.
- [Groupify overview](https://learn.microsoft.com/sharepoint/dev/features/groupify/groupify-overview). Begrensninger ved gruppetilkobling.

**Microsoft support**

- Microsoft 365 Developer Support (Graph-kø). Sak åpnet av SoftwareOne 1. juli 2026, eskalert til SharePoint Product Group. Saksnummer finnes internt.

**Interne artefakter**

- `New-PPSiteWithLanguageRetry.ps1` – hjelpeskript, SoftwareOne.
- HAR-trace og reproduksjonssteg levert Microsoft 27. juli 2026.
