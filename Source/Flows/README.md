# Power Automate-flyter

Bestillingsportalen bruker to cloud-flyter som kjører i **tjenestekontoens** Power Automate-miljø (de er ikke en del av Azure-deployen):

| Flyt | Formål |
|--|--|
| Provisioning Request Approval | Godkjenningsprosessen — trigges når en bestilling i `Provisioning Requests`-listen får status `Submitted`. Se [Approval-flow.md](../../Approval-flow.md). |
| Check Space Availability | Sjekker om et område/en bestilling med samme navn allerede finnes når brukeren fyller ut skjemaet. |

## Distribusjon

Flytene distribueres i **`Bestillingsportalen-Flows_unmanaged.zip`** (denne mappen) — en Power Platform-løsningspakke som inneholder de to flytene, de fem connection references (SharePoint, Office 365 Groups, Approvals, Outlook, Teams) og de fire environment variables flytene bruker (site-URL og listenavn).

Pakken er avledet fra upstream-prosjektets løsningspakke (`ProvisionAssist_2_0_0_8_unmanaged.zip` fra [pnp/provision-assist-m365](https://github.com/pnp/provision-assist-m365)), trimmet til kun flytene: upstream sin canvas-app (som Bestillingsportalen ikke bruker — SPFx-webdelen erstatter den) og de ni app-spesifikke environment variables er fjernet fra manifestet og pakken.

Pakken er **unmanaged**, så flytene kan tilpasses fritt etter import. Har du et miljø med tilpassede flyter, kan du alternativt eksportere derfra (flyt → `Export` → `Package (.zip)`) og importere den pakken i det nye miljøet i stedet.

## Hvorfor importeres ikke flytene av installasjonsskriptet?

Bevisst valg: importen må gjøres **som tjenestekontoen** (flytene skal eies av den), og tilkoblingene flytene bruker er delegert OAuth som tjenestekontoen uansett må samtykke til interaktivt. Skriptet kjører som administratoren — automatisering ville krevd identitetsbytte, en tung verktøykjede (`pac` CLI/Dataverse API + deployment settings) og fjernet ingenting av det interaktive. Import-veiviseren håndterer tilkoblinger og environment variables i samme seanse, og gjøres én gang per miljø (flytene overlever senere deploys/oppgraderinger).

## Importere (ny installasjon)

1. Gå til `make.powerautomate.com` logget inn som **tjenestekontoen** (flytene skal eies av og kjøre som den), i standardmiljøet (løsningsimport krever Dataverse, som standardmiljøet har).
2. Velg `Solutions` → `Import solution` → last opp `Bestillingsportalen-Flows_unmanaged.zip`.
3. Koble til/opprett tilkoblingene (SharePoint, Office 365 Groups, Approvals, Outlook, Teams) **som tjenestekontoen** når du blir bedt om det.
4. Fyll inn de fire **environment variables** når importen spør:
   - `ProvisionAssistSPOSite` — URL-en til Bestillingsportalen-området (f.eks. `https://<tenant>.sharepoint.com/sites/Bestillingsportalen`)
   - `ProvisioningRequestsList`, `ProvisioningRequestSettingslist`, `BusinessUnitsList` — listenavnene (standardverdiene matcher listene PnP-malen oppretter)
5. Etter import: åpne løsningen «Bestillingsportalen Flows» og verifiser at begge flytene finnes.
6. Fortsett med aktivering og deling — se installasjonsveiledningens Steg 5 og 6.
