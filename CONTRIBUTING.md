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

## DO's og DON'Ts

- **DO** følg samme prosjektstruktur som eksisterende prosjekt.
- **DO** fremhev hvordan gjeldende oppførsel er feil når du fikser bugs.
- **DO** hold diskusjoner fokuserte. Når et nytt eller relatert tema dukker opp, er det ofte bedre å opprette et nytt issue enn å sidespore samtalen.
- **DO NOT** eksporter en Logic App fra designeren i Azure Portal tilbake til ARM-malene i `Source/ARMTemplates/LogicApps/`. Designeren gjør `[variables('uamiId')]` om til en hardkodet ressurs-ID, som binder malen til én ressursgruppe/subscription. Rediger malene manuelt og behold ARM-uttrykkene.
- **DO NOT** send inn PR-er for kodestilendringer.
- **DO NOT** overrask oss med store PR-er. Opprett heller et issue og start en diskusjon slik at vi kan bli enige om en retning før du investerer mye tid.
- **DO NOT** commit kode du ikke har skrevet selv.
- **DO NOT** send inn PR-er som refaktorerer eksisterende kode uten diskusjon først.
