# Site Templates

Bestillingsportalen inkluderer muligheten til å anvende Site Templates (tidligere kjent som Site Designs) når en bruker bestiller opprettelse av et SharePoint-område (Team Site, Office 365 Group, Communication Site eller Hub Site).

Løsningen inkluderer også muligheten til å anvende PnP Provisioning-maler, som kan anvendes **i stedet for** Site Templates. Se [PnP Templates](/PnP-templates.md) for mer informasjon.

Alle tilgjengelige Site Templates i tenantens SharePoint hentes av en Logic App og en Runbook – begge kalt `GetSiteTemplates`.

Dette inkluderer innebygde maler – Topic, Showcase, Blank osv. – og eventuelle egendefinerte maler som er opprettet.

Malene lagres i en SharePoint-liste kalt `Site Templates` i Bestillingsportalen-området.

Følgende egenskaper lagres i listen:

- **Title** – Tittel på malen, f.eks. Topic
- **SiteTemplateId** – Unik ID (GUID) på malen
- **PreviewImage** – Lenke til forhåndsvisningsbilde
- **WebTemplate** – Web template malen gjelder for (1 for Team Site uten gruppetilknytning, 64 for gruppetilknyttet Team Site, 68 for Communication/Hub site)
- **Enabled** – Om malen skal vises i Bestillingsportalen webdel eller Teams app for valg. Standard er `false`, og du kan aktivere dem du ønsker.
- **ThemeName** – Navn på et SharePoint-tema i tenanten som skal anvendes på området når det er opprettet. Blank hvis du ikke vil anvende et tema. Kan være et innebygd tema (f.eks. `Blue`) eller et egendefinert (f.eks. `Contoso Dark`).

![Site templates list screenshot](/Images/SiteTemplatesList.png)

Brukere kan velge en av disse fra webdel eller Teams app når de oppretter en bestilling. Logic App-en `ProcessProvisionRequest` anvender dem via SharePoint REST API.

Webdel eller Teams app viser **kun** maler der `WebTemplate` matcher den valgte områdetypen. For eksempel: hvis en bruker velger et gruppetilknyttet Team Site, vises kun Site Templates med `WebTemplate = 64`. Sørg for at du oppretter dine egne Site Templates for ønsket `WebTemplate`.

Som nevnt over: for å vise en mal, sett `Enabled`-kolonnen til `true`.

Logic App-en `GetSiteTemplates` håndterer opprettelse, oppdatering og sletting av listeelementer i Site Templates-listen. Den håndterer ikke oppdatering av `ThemeName`-kolonnen – denne må populeres manuelt.
