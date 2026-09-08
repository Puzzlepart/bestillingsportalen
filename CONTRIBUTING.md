# Retningslinjer for bidrag

Vi setter pris på at du vil bidra til Bestillingsportalen. Før du sender din første PR, vennligst les denne guiden. Vi vil ikke at du skal bruke tid på noe andre allerede jobber med, noe vi har bestemt oss for ikke å gjøre, eller noe som ikke passer prosjektet.

Sharing is caring!

## Du har en idé til ny funksjonalitet

Flott! Gode idéer er uvurderlige for ethvert produkt. Før du setter i gang, sjekk om en lignende idé allerede ligger i [issues-listen](https://github.com/Puzzlepart/bestillingsportalen/issues). Hvis ikke, opprett et nytt issue som beskriver idéen din. Når vi er enige om funksjonalitet og arkitektur, er idéen klar til å bygges. Ikke nøl med å nevne i issuet hvis du ønsker å bygge funksjonaliteten selv.

## Du har et forslag til forbedring av eksisterende funksjonalitet

Ingenting er perfekt. Hvis du har en idé til hvordan eksisterende funksjonalitet i Bestillingsportalen kan forbedres, gi oss beskjed ved å opprette et issue i [issues-listen](https://github.com/Puzzlepart/bestillingsportalen/issues). Noen ting er gjort slik av en grunn, andre ikke. La oss diskutere forslaget ditt og se hvordan Bestillingsportalen kan bli bedre for alle.

## Du har funnet en bug

Bugs skjer. Når du finner en bug, sjekk [issues-listen](https://github.com/Puzzlepart/bestillingsportalen/issues) for å se om en lignende bug allerede er rapportert. Hvis ikke, gi oss beskjed om hva som ikke fungerer og hvordan vi kan reprodusere det. Hvis vi ikke kan reprodusere feilen, vil vi be deg om klargjøring, noe som kun forlenger tiden det tar å fikse den.

## Retting av skrivefeil

Skrivefeil er pinlige! De fleste PR-er som retter skrivefeil aksepteres umiddelbart. For å gjøre det enklere å gå gjennom PR-en, snevre inn fokuset i stedet for å sende én stor PR med mange rettelser.

## Tips

Før du bidrar:

- Opprett en feature branch for endringen din. Hvis du står fast på et issue eller det vil ta tid å merge PR-en, sikrer dette at du har en ren main-branch som kan brukes til andre bidrag.

    ```sh
    git checkout -b my-contribution
    ```

## Dokumentasjon som PDF

Skal dokumentasjonen sendes til en kunde – typisk som underlag for en sikkerhetsgjennomgang – bygger `Source/Scripts/build-docs-pdf.mjs` én samlet PDF med tittelside, innholdsfortegnelse, rendrede mermaid-diagrammer og kryssreferansene skrevet om til interne anker:

```sh
npm install --no-save markdown-it markdown-it-anchor playwright-core mermaid
node Source/Scripts/build-docs-pdf.mjs
```

PDF-en havner i `docs-pdf/`. Legger du til et nytt markdown-dokument, føy det inn i `ORDER`-arrayen øverst i skriptet – ellers hoppes det over, og skriptet sier hvilke filer det gjelder.

## Versjonering

Løsningen følger [SemVer](https://semver.org/lang/no/): `MAJOR.MINOR.PATCH`. Kriteriene
er konkrete for denne løsningen:

| Ledd | Når det økes | Eksempel |
| --- | --- | --- |
| **MAJOR** | Oppgraderingen er ikke en ren `-Upgrade`: krever full deploy, manuelle oppryddingssteg, re-autorisering av API-tilkoblinger, eller rotasjon av hemmeligheter | 1.0.0: migreringen til managed identity |
| **MINOR** | Ny funksjonalitet som `-Upgrade` håndterer selv — nye lister, Logic Apps, runbooks, webdeler eller innstillinger | Ny `Guest Requests`-liste med `ProcessGuestRequest` |
| **PATCH** | Rettelser innenfor eksisterende komponenter, uten nye ressurser eller skjemaendringer | Feilmeldinger, innhold i `StatusReason`, nye pre-flight-sjekker |

### `VERSION` er eneste kilde

Versjonsnummeret står i **`VERSION`** i repo-rot, som én linje (`1.0.0`). `deploy.ps1`
leser den derfra — nummeret skal ikke hardkodes noe annet sted. Er fila borte eller
feilformatert, stopper ikke installasjonen: versjonen faller til `unknown`, og
pre-flight-sjekklista sier hvorfor.

### Release-rutine

Repoet har ingen CI, så rekkefølgen er manuell:

1. Oppdater `VERSION` med det nye nummeret.
2. Sett releasedato på den øverste seksjonen i [CHANGELOG.md](CHANGELOG.md) (erstatt `TBA`).
3. Commit endringene: `Release 1.0.0`.
4. Lag en annotert tag:

    ```sh
    git tag -a v1.0.0 -m "Bestillingsportalen 1.0.0"
    ```

5. Push begge: `git push && git push --tags`.

Ved installasjon stempler `deploy.ps1` versjonen inn i miljøet på to steder — se
[Upgrade.md](Upgrade.md#hvilken-versjon-kjører-miljøet).

## DO's og DON'Ts

- **DO** følg samme prosjektstruktur som eksisterende prosjekt.
- **DO** fremhev hvordan gjeldende oppførsel er feil når du fikser bugs.
- **DO** hold diskusjoner fokuserte. Når et nytt eller relatert tema dukker opp, er det ofte bedre å opprette et nytt issue enn å sidespore samtalen.
- **DO NOT** eksporter en Logic App fra designeren i Azure Portal tilbake til ARM-malene i `Source/ARMTemplates/LogicApps/`. Designeren gjør `[variables('uamiId')]` om til en hardkodet ressurs-ID, som binder malen til én ressursgruppe/subscription. Rediger malene manuelt og behold ARM-uttrykkene.
- **DO NOT** hardkod versjonsnummeret i `deploy.ps1` eller andre filer — `VERSION` i repo-rot er eneste kilde.
- **DO NOT** send inn PR-er for kodestilendringer.
- **DO NOT** overrask oss med store PR-er. Opprett heller et issue og start en diskusjon slik at vi kan bli enige om en retning før du investerer mye tid.
- **DO NOT** commit kode du ikke har skrevet selv.
- **DO NOT** send inn PR-er som refaktorerer eksisterende kode uten diskusjon først.
