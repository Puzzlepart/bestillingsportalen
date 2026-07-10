# Power Automate-flyter — pakken og vedlikeholdet

Denne mappen inneholder **`Bestillingsportalen-Flows_unmanaged.zip`** — Power Platform-løsningspakken med de to cloud-flytene løsningen bruker:

| Flyt | Formål |
|--|--|
| Provisioning Request Approval | Godkjenningsprosessen — trigges når en bestilling i `Provisioning Requests`-listen får status `Submitted`. Se [Approval-flow.md](../../Approval-flow.md). |
| Check Space Availability | Sjekker om et område/en bestilling med samme navn allerede finnes når brukeren fyller ut skjemaet. |

**Import og oppsett er beskrevet i [installasjonsveiledningens Steg 5](../../Deployment-guide.md)** — dette dokumentet handler om hvor pakken kommer fra og hvordan den vedlikeholdes.

## Hvor pakken kommer fra

Flytene stammer fra upstream-prosjektet [pnp/provision-assist-m365](https://github.com/pnp/provision-assist-m365), som distribuerer dem inne i sin Power Apps-løsningspakke (`Source/Power Apps/ProvisionAssist_<versjon>_unmanaged.zip`) sammen med canvas-appen sin. Bestillingsportalen bruker ikke appen (SPFx-webdelen erstatter den), så vår pakke er en **trimmet avledning** av upstream-pakken.

### Regenerere pakken fra upstream (ved oppgradering av flytene)

1. Last ned nyeste `ProvisionAssist_<versjon>_unmanaged.zip` fra upstream-repoets `Source/Power Apps/`-mappe og pakk ut zip-en.
2. **Fjern canvas-appen:**
   - Slett `CanvasApps/`-mappen.
   - Fjern `<RootComponent type="300" ... />`-linjen (appen) fra `solution.xml`.
   - Tøm `<CanvasApps>`-elementet i `customizations.xml` (→ `<CanvasApps />`).
   - Fjern `msapp`-Default- og CanvasApps-Override-deklarasjonene fra `[Content_Types].xml`.
3. **Fjern ubrukte environment variables:** behold kun de flytene refererer (per i dag `msftprov_ProvisionAssistSPOSite`, `msftprov_ProvisioningRequestsList`, `msftprov_ProvisioningRequestSettingslist`, `msftprov_BusinessUnitsList` — verifiser mot `msftprov_`-referansene i `Workflows/*.json`), slett de øvrige mappene under `environmentvariabledefinitions/`.
4. **Gi løsningen riktig identitet** i `solution.xml`: `<UniqueName>BestillingsportalenFlows</UniqueName>` og `LocalizedName description="Bestillingsportalen Flows"` (hindrer kollisjon med en ekte ProvisionAssist-løsning i samme miljø).
5. **Sett flytene i Draft-tilstand** i `customizations.xml`: endre `<StateCode>1</StateCode><StatusCode>2</StatusCode>` til `<StateCode>0</StateCode><StatusCode>1</StatusCode>` på begge `<Workflow>`-elementene (store bokstaver — små `statecode`/`statuscode`-elementer tilhører miljøvariablene og skal ikke røres). Upstream pakker flytene som «Aktivert», som tvinger importen til et aktiveringsforsøk som feiler med `FlowNotOriginalAuthor` — med Draft importerer pakken rent, og aktiveringen gjøres eksplisitt i installasjonsveiledningens Steg 5.
6. Zip innholdet på nytt (mappestrukturen i rot av zip-en, framoverskråstreker i stier) som `Bestillingsportalen-Flows_unmanaged.zip`, verifiser at all XML fortsatt parser, og test importen i et dev-miljø før commit.

## Vedlikeholdsnotater

- Pakken er **unmanaged** — flytene kan tilpasses fritt etter import. Tilpassede miljøer kan eksportere sine egne flyt-pakker (flyt → `Export` → `Package (.zip)`) og importere dem i nye miljøer i stedet for standardpakken.
- Flytene importeres **ikke** av installasjonsskriptet — bevisst valg: importen må gjøres *som tjenestekontoen* (eierskap), tilkoblingene er delegert OAuth som tjenestekontoen uansett må samtykke til interaktivt, og verktøykjeden (`pac` CLI/Dataverse API) er tung for en engangsoperasjon per miljø. Flytene overlever alle senere deploys/oppgraderinger.
