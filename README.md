<p align="center">
  <img src="Images/bp_logo.png" alt="Bestillingsportalen logo" width="80" />
  <br />
  <strong style="font-size: 2em;">Bestillingsportalen</strong>
</p>

| [Installasjonsveiledning](/Deployment-guide.md) | [Oppgraderingsveiledning](/Upgrade.md) | [Arkitektur](/Architecture.md) | [Datalagre](/Data-stores.md) | [Kostnadsestimater](/Cost-estimates.md) | [Datatilgang og sikkerhet](/Data-access-security.md) | [Navnekonvensjoner](/Naming-conventions.md) | [Forretningsenheter](/Business-units.md) | [Provisioning Types](/Provisioning-types.md) | [Site Templates](/Site-templates.md) | [Sensitivitetsmerker](/Sensitivity-labels.md) | [Teams Templates](/Teams-templates.md) | [PnP Templates](/PnP-templates.md) | [Oppbevaringsmerker](/Retention-labels.md) | [Godkjenningsflyt](/Approval-flow.md) | [Regionale innstillinger](/Regional-settings.md) | [Fornye App Secret](/Refreshing-app-secret.md) | [Feilhåndtering](/Error-handling.md) |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |

Bestillingsportalen er en Azure-basert løsning som gir et alternativ til selvbetjent opprettelse av samarbeidsområder i Microsoft 365. Den gir styring over prosessen gjennom en SPFx Teams app som lar brukere bestille samarbeidsområder (Teams, Groups, SharePoint Online-områder og Viva Engage-fellesskap), med bakenforliggende Azure-komponenter som sørger for automatisk provisjonering. Bestillingsportalen kan brukes som del av en Copilot for Microsoft 365-utrulling for å etablere styring over selvbetjening.

![Bestillingsportalen](/Images/bp_app.png)

## Funksjonalitet

Bestillingsportalen tilbyr følgende:

- SPFx-basert Bestillingsportalen webdel og Teams app som lar brukere bestille samarbeidsområder.
- Konfigurerbar godkjenningsprosess via Power Automate.
- SharePoint-område med støttelister som utgjør backenden for løsningen.
- Dashboard for bestillere som viser tidligere og pågående bestillinger med godkjenningsstatus.
- Automatisert provisjonering via Azure Logic Apps og Azure Automation.

## Arkitektur

Løsningen bruker Microsoft Graph og SharePoint REST API-ene for provisjonering. Azure Runbooks brukes sammen med PnP PowerShell for oppgaver som ikke kan utføres via Graph API.

Application permissions brukes gjennom en Entra ID app registration. Secret-en for Entra ID-appen lagres i en Key Vault.

Provisjonering og andre automatiseringsoppgaver løses gjennom Azure Logic Apps, som gir lav kjøretidkostnad og mulighet til å sikre tilgang til alle ressurser.

For mer detaljer om arkitekturen, les [Arkitektur](Architecture.md)-dokumentasjonen.

## Kom i gang

For å komme i gang med en ny installasjon, følg [Installasjonsveiledningen](Deployment-guide.md).

## Oppgradering

Hvis du har en eksisterende Bestillingsportalen-installasjon og vil oppgradere til nyeste versjon, se [Oppgraderingsveiledningen](Upgrade.md) for detaljerte instruksjoner om hvordan du oppgraderer uten å miste data.

## Feil og problemer

Rapporter eventuelle problemer ved å opprette et [issue](https://github.com/Puzzlepart/bestillingsportalen/issues/new/choose).

## Bidra

Vi 💖 å motta bidrag.

Se våre [retningslinjer for bidrag](/CONTRIBUTING.md) for hvordan du kan bidra.

Hvis du ønsker å bli involvert i å videreutvikle Bestillingsportalen – enten det er å foreslå ny funksjonalitet, oppdatere dokumentasjonen eller fikse bugs – vil vi gjerne høre fra deg.

## En stor takk til

Takk til de nedenfor som har vært med på å bygge denne løsningen.

- [@alexc-MSFT](https://github.com/alexc-MSFT)
- [@OlgKis](https://www.github.com/OlgKis)
- [@PalinaSolik](https://www.github.com/PalinaSolik)

## Støtte

Denne løsningen er åpen kildekode og leveres av fellesskapet uten aktiv support. Løsningen vedlikeholdes av både Microsoft-ansatte og bidragsytere i fellesskapet, og er ikke en Microsoft-levert løsning. Det finnes derfor ingen SLA eller direkte støtte fra Microsoft. Rapporter problemer ved å opprette et [issue](https://github.com/Puzzlepart/bestillingsportalen/issues/new/choose).

## Microsoft 365 og Power Platform Community

Bestillingsportalen er et Microsoft 365 og Power Platform Community (PnP)-prosjekt. Microsoft 365 og Power Platform Community er et virtuelt team bestående av Microsoft-ansatte og bidragsytere i fellesskapet som fokuserer på å hjelpe brukere med å få mest mulig ut av Microsoft-produkter. Bestillingsportalen er et åpen kildekode-prosjekt som ikke er tilknyttet Microsoft og ikke dekket av Microsoft-support. Hvis du opplever problemer, opprett gjerne et [issue](https://github.com/Puzzlepart/bestillingsportalen/issues).

## «Sharing is Caring»

![Parker PnP](/Images/parker-pnp.png)

## Ansvarsfraskrivelse

**DENNE KODEN LEVERES «SOM DEN ER» UTEN GARANTIER AV NOE SLAG, VERKEN UTTRYKTE ELLER UNDERFORSTÅTTE, INKLUDERT GARANTIER OM EGNETHET FOR ET BESTEMT FORMÅL, SALGBARHET ELLER IKKE-KRENKELSE.**

## Code of Conduct

Dette repositoriet har adoptert Microsoft Open Source Code of Conduct. For mer informasjon, se [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) eller kontakt opencode@microsoft.com.
