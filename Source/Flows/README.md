# Power Automate-flyter

Denne mappen skal inneholde de eksporterte flyt-pakkene som Bestillingsportalen bruker:

| Pakke | Flyt | Formål |
|--|--|--|
| `ProvisioningRequestApproval.zip` | Provisioning Request Approval | Godkjenningsprosessen — trigges når en bestilling i `Provisioning Requests`-listen får status `Submitted`. Se [Approval-flow.md](../../Approval-flow.md). |
| `CheckSpaceAvailability.zip` | Check Space Availability | Sjekker om et område/en bestilling med samme navn allerede finnes når brukeren fyller ut skjemaet. |

## Bakgrunn

Upstream (pnp/provision-assist-m365) distribuerer disse flytene inne i Power Apps-løsningspakken. Da Bestillingsportalen erstattet Power-appen med SPFx-webdelen, fulgte ikke flytene med — de må derfor eksporteres fra et fungerende miljø og vedlikeholdes her.

## Eksportere (fra et fungerende miljø)

1. Gå til `make.powerautomate.com` logget inn som **tjenestekontoen**.
2. Finn flyten → `Export` → `Package (.zip)`.
3. Legg zip-filen i denne mappen med navnene over og commit.

## Importere (ny installasjon)

1. Gå til `make.powerautomate.com` logget inn som **tjenestekontoen** (flytene skal eies av og kjøre som den).
2. `My flows` → `Import` → `Import Package (Legacy)` → last opp zip-pakken.
3. Under *Review package content*: velg `Create as new` for flyten, og koble til/opprett tilkoblingene (SharePoint, Approvals, Teams, Outlook) **som tjenestekontoen**.
4. Etter import: åpne flyten og verifiser at SharePoint-referansene peker på riktig område/lister for denne installasjonen (`Provisioning Requests` m.fl.), og lagre.
5. Fortsett med aktivering og deling — se installasjonsveiledningens Steg 5 og 6.
