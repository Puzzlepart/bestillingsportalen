# Tilpasninger gjort på Bestillingsportalen

## Når forket vi Bestillingsportalen?

- Før 09.06.2024
- Vi mangler commits etter 09.06.2024
- Vi har ikke fått med oss endringer som er gjort i Bestillingsportalen etter dette tidspunktet.

## Lister

### Provisioning Types

- External Sharing: Styrer synlighet av 'Ekstern deling' i skjema for bestilling av område
- Default Hub: Overstyrer standard hub for område i skjema for bestilling av område
- Default Sensitivity Label: Overstyrer standard sensitivitetsmerke for område i skjema for bestilling av område
- Default Retention Label: Overstyrer standard bevaringsmerke for område i skjema for bestilling av område

### Provisioning Requests

- Metadata: Nytt felt for å lagre metadata knyttet til prosjektinformasjon og property bag verdier
  - Metadata er et JSON objekt som inneholder følgende struktur:
  - ```json
    {
      [
        "projectProperties": {
          "internalName": "value",
          "value": "value"
        },
        "propertyBagProps": {
          "name": "value",
          "value": "value"
        }
      ]
    }
    ```
- RequestedBy: Nytt felt for å lagre informasjon om hvem som har bestilt området (dette muliggjør å bestille et område på vegne av noen andre), filtrering av "Mine bestillinger" sjekker opp mot dette feltet i tillegg til "Created By"
- Internal Channel: Nytt felt for å lagre informasjon om området skal ha en intern kanal i Teams (synliggjøres dersom "Teams" er valgt)
- RequestSource: Nytt felt for å lagre informasjon om bestillingen er gjort via for eksempel: webdel, API eller SPFx app.
- ReadOnlyGroup: Nytt felt for å lagre informasjon om det skal legges på en spesifikk gruppe med lesetilgang til området.
- SpaceImage: Nytt felt for å lagre informasjon om hvilket bilde (base64) som skal brukes som områdebilde (logo).

### Guest Requests (ny i 1.11.0)

Helt ny støtteliste for gjesteinvitasjon-flyten. Opprettes via PnP-templaten ([Source/Templates/Objects/Lists/Guest Requests.xml](Source/Templates/Objects/Lists/Guest%20Requests.xml)) og prosesseres av `ProcessGuestRequest` Logic App. Brukes av den nye `InviteGuests`-webdelen.

- Title: E-postadressen til gjesten som skal inviteres.
- SiteUrl: URL til området gjesten skal inviteres til.
- SiteTitle: Tittel på området (vises i invitasjons-e-posten).
- Status: `Pending` / `Invited` / `Failed`.
- GuestId: Entra ID-id til opprettet gjestebruker.
- InviteRedeemUrl: Innløsings-URL.
- ErrorMessage: Feilmelding ved `Status=Failed`.
- RequestedBy: Brukeren som initierte invitasjonen.
- **M365GroupRole** (Choice: `None`/`Guest`): Rolle på den tilkoblede Microsoft 365-gruppen. `Guest` legger til som gjestemedlem på M365-gruppen, automatisk hoppet over hvis siten ikke er gruppe-koblet.
- **SPGroupAction** (Choice: `None`/`AddToExisting`/`CreateNew`): Hva som skal skje med en valgfri SharePoint-brukergruppe-tilføyelse.
- **SPGroupName** (Text): Navn på eksisterende eller ny SP-gruppe (avhengig av `SPGroupAction`).
- **SPPermissionLevel** (Choice: `Read`/`Contribute`/`Edit`/`Full Control`): Tilgangsnivå når `SPGroupAction = CreateNew`.

## Runbooks

### AddGuestToSite (ny i 1.11.0)

Lokal runbook ([Source/Runbooks/AddGuestToSite.ps1](Source/Runbooks/AddGuestToSite.ps1)) som kalles av `ProcessGuestRequest` Logic App etter at en gjest er invitert via Graph. Authentiserer mot SP via system-assigned managed identity (PnP). To uavhengige steg basert på Guest Request-feltene:

1. **M365-gruppe-tilføyelse** (`M365GroupRole = 'Guest'`): legger gjesten som medlem på den koblede M365-gruppen via `Add-PnPMicrosoft365GroupMember`. Hoppes over hvis siten ikke har M365-gruppe.
2. **SP-gruppe-tilføyelse** (`SPGroupAction`):
   - `None`: hopp over
   - `AddToExisting`: `Add-PnPUserToGroup -Identity <SPGroupName>`
   - `CreateNew`: `New-PnPGroup` + `Set-PnPGroupPermissions -AddRole <SPPermissionLevel>` + `Add-PnPUserToGroup`

Runbook-ressursen opprettes via [Source/ARMTemplates/runbooks.bicep](Source/ARMTemplates/runbooks.bicep) (egen Bicep-fil kun for runbooks som "eies" av dette repoet — i motsetning til `ConfigureSpace`/`GetSiteTemplates` som ligger i `azureresources.bicep` og pulles fra `pnp/provision-assist-m365`). `runbooks.bicep` deployes ALLTID av `deploy.ps1`, også når `-SkipBicepDeploy` brukes i upgrade-mode, slik at nye runbooks får opprettet ressursen sin.

Foreløpig peker `uri` på `pnp/provision-assist-m365`s `ConfigureSpace.ps1` som placeholder — etter første deploy må man åpne Azure Portal → Automation Account → Runbooks → `AddGuestToSite` → Edit og lime inn innholdet fra [Source/Runbooks/AddGuestToSite.ps1](Source/Runbooks/AddGuestToSite.ps1). Senere re-deploys beholder manuelt-limt innhold så lenge `version` i `runbooks.bicep` er uendret. Når dette repoet blir public, oppdateres `uri` til vår egen raw URL og `version` bumpes for å tvinge re-import.

## SPFx-løsninger

### ProvisionWebParts (ny i 1.11.0)

Nytt SPFx 1.22-prosjekt under `Source/SharePointFramework/ProvisionWebParts/` (Heft-basert toolchain, Fluent UI v9, PnPjs 4.x). Speiler mappestrukturen til Puzzlepart `prosjektportalen365` (shared `src/components/`, `src/loc/`, `src/webparts/<name>/index.ts` + `manifest.json`).

- **InviteGuests-webdel**: Lar brukere invitere eksterne gjester direkte fra et SharePoint-område. UX bygget på `OverlayDrawer` + `TagPicker` (basert på PP365 `ProvisionDrawer/Guest`-mønster) og `DataGrid` for statusvisning (basert på PP365 `ProvisionStatus`-mønsteret).
  - **`M365GroupRoleSection`**: Viser hvilken rolle gjesten får på M365-gruppen. Disabled/grayed seksjon hvis siten ikke er gruppe-koblet (Communication site / klassisk).
  - **`SPGroupSection`** (valgfritt): Radio-valg mellom "ingen", "legg til i eksisterende gruppe" (dropdown fra `SiteService.getSiteGroups`) eller "opprett ny gruppe" (navn + permission level).
  - **`SiteService`**: Spør gjeldende side (ikke admin-siten) om M365-gruppe-status og tilgjengelige SP-grupper. Webparten har dermed to PnPjs `SPFI`-instanser: én mot Bestillingsportalen-siten (Guest Requests-liste), én mot gjeldende site (gruppe-info).
