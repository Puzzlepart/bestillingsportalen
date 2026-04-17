# Forretningsenheter

Bestillingsportalen inkluderer muligheten til å definere navnekonvensjoner/policyer og egne godkjennere per forretningsenhet (business unit).

Når funksjonaliteten er aktivert i `Provisioning Request Settings`-listen, kan en bruker velge en forretningsenhet når hen bestiller et område.

Du kan definere et tekst-prefiks og -suffiks per forretningsenhet. For eksempel kan du anvende prefikset `HR-` og suffikset `-Contoso` for en forretningsenhet kalt «Human Resources».

Når en bruker bestiller via Bestillingsportalen webdel eller Teams app, anvendes navnekonvensjonen, og en forhåndsvisning av hvordan navnet blir seende ut i kombinasjon med tittelen brukeren har angitt vises (se `Space display name` nedenfor).

![Business units drop down screenshot](./images/BusinessUnitsApp.png)

En oppslagskolonne i `Provisioning Requests`-listen lagrer forretningsenheten brukeren valgte i webdel eller Teams app.

Hvis innstillingen for forretningsenhet-godkjenning er aktivert, vil godkjenningen av bestillinger bruke godkjennerne/gruppene definert i `Business Units`-listen basert på forretningsenheten brukeren valgte.

Les videre for hvordan du aktiverer og konfigurerer funksjonaliteten.

Denne funksjonaliteten bygger videre på eksisterende [navnekonvensjoner](/Naming-conventions.md) – sørg for at du forstår disse først.

**Merk: Hvis du oppgraderer fra en eldre versjon, må du utføre noen steg manuelt. Se nederst i dette dokumentet for detaljer.**

## Konfigurasjon

### Navnekonvensjon for forretningsenheter

For å aktivere funksjonaliteten MÅ verdien på innstillingen **`EnableBusinessUnits`** i `Provisioning Request Settings`-listen settes til `true`. Etter installasjon er denne satt til `false`.

I tillegg må verdien på innstillingen **`UseNamingConventions`** settes til `true` for at navnefunksjonaliteten for forretningsenheter skal fungere.

### Godkjenning per forretningsenhet

For å aktivere funksjonaliteten MÅ verdien på innstillingen **`EnableBusinessUnitsApproval`** i `Provisioning Request Settings`-listen settes til `true`. Etter installasjon er denne satt til `false`.

**Merk: For at godkjenning per forretningsenhet skal fungere, må verdien på innstillingen `PostToTeams` være satt til `false`.**

Godkjennere for forretningsenheter konfigureres i `Business Units`-listen – flere brukere eller Microsoft 365-grupper støttes.

**Godkjenning per forretningsenhet trenger ikke å være aktivert for at forretningsenhet-funksjonaliteten skal fungere. Hvis deaktivert, vil godkjenning skje som normalt.**

![Business units settings screenshot](./images/BusinessUnitsSettings.png)

## Opprette forretningsenheter

For å opprette en forretningsenhet, gå til `Business Units`-listen i Bestillingsportalen-området i SharePoint og opprett et nytt listeelement.

![Business units list screenshot](./images/BusinessUnitsList.png)

Fyll inn kolonnene som følger:

- **Title** – Navn på forretningsenheten, f.eks. `Human Resources`.
- **Prefix** – Ønsket prefiks, f.eks. `HR-`.
- **Suffix** – Ønsket suffiks, f.eks. `-Contoso`.
- **Approvers** – Godkjennere som skal godkjenne bestillingen.

## Begrensninger

I denne første utgivelsen er det noen begrensninger å være klar over:

- Navnekonvensjoner for forretningsenheter kan ikke kombineres med navnekonvensjoner for «Global», «Space» eller «Teams Template». Hvis navnekonvensjoner for forretningsenheter er aktivert, vil de overstyre andre konfigurerte navnekonvensjoner.
- Kun tekstbaserte prefikser og suffikser støttes. Mulighet for å bruke egenskaper som brukerens avdeling er foreløpig ikke tilgjengelig.
- En forretningsenhet må velges i webdel eller Teams app hvis funksjonaliteten er aktivert.
