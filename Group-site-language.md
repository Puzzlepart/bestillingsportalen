# Språk på gruppeområder

Siden mai 2026 ignorerer Microsoft Graph det bestilte språket (`SPSiteLanguage` i `creationOptions`) når en Microsoft 365-gruppe opprettes. Gruppeområdet får da ofte rotområdets språk i stedet for det bestilte. Kallet lykkes uten feil eller advarsel. Feilen er bekreftet av Microsoft ([sp-dev-docs #10875](https://github.com/SharePoint/sp-dev-docs/issues/10875)), men rettelsen har ikke nådd alle tenanter. Bakgrunn og vurderte alternativer: [Bakgrunnsutredning](./Source/Scripts/provisioning-workaround/Bakgrunnsutredning-SPSiteLanguage.md).

Feilen er tilfeldig per opprettelse. I test fikk ca. 28 % av gruppene riktig språk (12 av 43), både med managed identity og delegert. Bestillingsportalen har derfor en valgfri workaround: opprett flere kandidater samtidig, behold den som fikk riktig språk, og slett resten.

## Når er dette aktuelt?

Bare når både:

- tenanten har feilen, og
- brukerne bestiller et annet språk enn rotområdets.

Har rotområdet samme språk som bestillingen, gir feilen riktig språk uansett. Runbooken oppdager det og oppretter da bare én kandidat.

Workaround-en gjelder områdetyper som oppretter en Microsoft 365-gruppe: **Prosjektområde**, **Microsoft 365-gruppe** og **Microsoft Teams Team** (også med Teams-mal fra Admin Center). Den gjelder ikke kloning av et eksisterende team (`TeamsTemplate` som ikke er `standard`), som oppretter sin egen gruppe.

## Slik slår du den på

Rediger radene i listen **Provisioning Request Settings** på bestillingsområdet:

| Innstilling | Standard | Betydning |
|--|--|--|
| `EnableGroupLanguageRetry` | `false` | `true` slår på workaround-en |
| `GroupLanguageRetryParallel` | `3` | Antall kandidater som opprettes samtidig per runde (1–10) |
| `GroupLanguageRetryMaxRounds` | `3` | Maks antall runder før bestillingen feiler |

Med ca. 28 % treff gir 3 kandidater per runde minst ett treff i omtrent 3 av 4 runder, og 3 runder gir treff i over 95 % av bestillingene. Hver runde tar under ett minutt. Øk `GroupLanguageRetryParallel` hvis bestillinger feiler fordi ingen kandidat traff.

Radene opprettes av installasjonen. Mangler de i en eksisterende installasjon, kjør `deploy.ps1 -Upgrade` og svar ja på malspørsmålet, eller opprett radene manuelt.

## Hva skjer når den er på

`ProcessProvisionRequest` kaller runbooken `CreateGroupWithLanguage` i stedet for sin egen `POST /groups`. Runbooken får nøyaktig den samme gruppe-bodyen, base64-kodet. Azure Automation tolker parameterverdier som er gyldig JSON før runbooken starter, og runbooken fikk da `@{description=...}` i stedet for JSON. Per runde:

1. Oppretter kandidatene: den første med bestilt alias, resten med `alias-xxxxx` (5 tegn fra en GUID). Kandidatene opprettes uten medlemmer.
2. Venter til områdene finnes (ca. 20 sekunder) og leser språket via SharePoints admin-API.
3. Beholder første treff. Bestilt alias foretrekkes hvis det traff.
4. Sletter de andre kandidatene permanent: gruppen slettes og tømmes fra papirkurven i Entra, og området slettes. Når rundene er ferdige, tømmes områdene også fra SharePoints papirkurv.
5. Legger til medlemmene på gruppen som ble beholdt.

Deretter fortsetter provisjoneringen som vanlig (Teams, mal, `ConfigureSpace` osv.) mot området som ble beholdt.

**Konsekvenser:**

- **URL og alias kan få suffiks**, for eksempel `/sites/prosjekt-x-3f2a1`. Bestillingen oppdateres med faktisk `SiteURL`, `SiteAlias` og `MailboxAlias`, og e-poster og varsler bruker faktisk URL.
- **Kortlevde ekstra grupper**: hver bom er en ekte gruppe med postboks i noen sekunder før den slettes. Eierne kan se dem kort. Medlemmer legges først til på gruppen som beholdes, så de får ingen e-post fra kandidatene.
- **Bom slettes permanent, også fra SharePoints papirkurv**. Kandidatene har aldri hatt innhold, og et område i papirkurven holder på URL-en i 93 dager. Uten tømming ville et bestilt alias som bommet vært sperret for nye bestillinger. Tømmingen skjer når rundene er ferdige og venter opptil 3 minutter på områder som ikke har kommet i papirkurven ennå. Områder som ikke ble tømt, står i jobbloggen.

## Når bestillingen feiler

Får ingen kandidat riktig språk etter `GroupLanguageRetryMaxRounds` runder, sletter runbooken alle kandidatene, og bestillingen får status **Space Creation Failed** med årsaken i `StatusReason`. Bestill på nytt, eller øk antall kandidater eller runder.

Feiler det å legge medlemmene til på gruppen som ble beholdt, slettes også den, inkludert fra papirkurven, så aliaset er ledig når bestillingen sendes på nytt.

Detaljer om hver runde står i jobbloggen til `CreateGroupWithLanguage` i Automation-kontoen (Jobs).

## Tillatelser

Ingen nye. Runbooken bruker Automation-kontoens managed identity med tillatelsene den allerede har: Graph `Group.ReadWrite.All` og SharePoint `Sites.FullControl.All`.

Hvorfor slettingen er tungvint: SharePoints admin-API nekter å slette et gruppeområde, også etter at gruppen er slettet, og `GroupSiteManager/Delete` avviser app-only. Runbooken sletter derfor gruppen permanent, fjerner koblingen til gruppen på området (`ClearGroupId`), sletter området via tenant-CSOM og tømmer det fra papirkurven (`Remove-PnPTenantDeletedSite`).

## Tenanter uten Bestillingsportalen

[`New-PPSiteWithLanguageRetry.ps1`](./Source/Scripts/provisioning-workaround/New-PPSiteWithLanguageRetry.ps1) gjør det samme som et frittstående skript, lokalt eller som runbook. [`Test-GroupSiteLanguageRetry.ps1`](./Source/Diagnostics/Test-GroupSiteLanguageRetry.ps1) måler treffraten i en tenant uten å beholde noe.

## Når Microsoft retter feilen

Sett `EnableGroupLanguageRetry` til `false`. Om feilen er borte i en tenant, kan du sjekke med testskriptet: treffraten blir da 100 %.
