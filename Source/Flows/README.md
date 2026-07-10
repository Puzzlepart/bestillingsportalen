# Power Automate-flyter

Bestillingsportalen bruker to cloud-flyter som kjører i **tjenestekontoens** Power Automate-miljø (de er ikke en del av Azure-deployen):

| Flyt | Formål |
|--|--|
| Provisioning Request Approval | Godkjenningsprosessen — trigges når en bestilling i `Provisioning Requests`-listen får status `Submitted`. Se [Approval-flow.md](../../Approval-flow.md). |
| Check Space Availability | Sjekker om et område/en bestilling med samme navn allerede finnes når brukeren fyller ut skjemaet. |

## Distribusjon

Flytene distribueres i **`ProvisionAssist_2_0_0_8_unmanaged.zip`** (denne mappen) — upstream-prosjektets Power Platform-løsningspakke, som inneholder begge flytene (`Workflows/`), environment variables for site-URL og listenavn, samt upstream sin canvas-app (som Bestillingsportalen IKKE bruker — SPFx-webdelen erstatter den; appen kan ignoreres eller slettes etter import).

Pakken er **unmanaged**, så flytene kan tilpasses fritt etter import. Har du et miljø med tilpassede flyter, kan du alternativt eksportere derfra (flyt → `Export` → `Package (.zip)`) og importere pakken i det nye miljøet i stedet.

## Importere (ny installasjon)

1. Gå til `make.powerautomate.com` logget inn som **tjenestekontoen** (flytene skal eies av og kjøre som den), i standardmiljøet (løsningsimport krever Dataverse, som standardmiljøet har).
2. Velg `Solutions` → `Import solution` → last opp `ProvisionAssist_2_0_0_8_unmanaged.zip`.
3. Koble til/opprett tilkoblingene (SharePoint, Approvals, Teams, Outlook) **som tjenestekontoen** når du blir bedt om det.
4. Fyll inn **environment variables** når importen spør: URL-en til Bestillingsportalen-området (`ProvisionAssistSPOSite`) og listenavnene (standardverdiene matcher listene PnP-malen oppretter).
5. Etter import: åpne løsningen og verifiser at begge flytene finnes. Canvas-appen i pakken kan ignoreres.
6. Fortsett med aktivering og deling — se installasjonsveiledningens Steg 5 og 6.
