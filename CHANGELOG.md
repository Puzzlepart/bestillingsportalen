# Endringslogg

Sjekk ut [release notes](#) for høydepunkter og mer detaljert endringslogg for siste hovedversjon.

## 1.11.0 - TBA

### Ny funksjonalitet

- **`InviteGuests`-webdel (SPFx 1.22 + Fluent UI v9)**: Ny frittstående SharePoint-webdel for å invitere eksterne gjester til et eksisterende område uten å gå via bestillingsskjemaet. Bygget med `OverlayDrawer` + `TagPicker` (basert på Puzzleparts `ProvisionDrawer/Guest`-mønster) og `DataGrid` for statusvisning (basert på `ProvisionStatus`-mønsteret). Prosjektet ligger under `Source/SharePointFramework/ProvisionWebParts/`.
- **`Guest Requests` SharePoint-liste**: Ny støtteliste på Bestillingsportalen-admin-området som lagrer alle gjesteforespørsler med felter for status, GuestId, InviteRedeemUrl og ErrorMessage. Opprettes automatisk via PnP-templaten ([Source/Templates/Objects/Lists/Guest Requests.xml](Source/Templates/Objects/Lists/Guest%20Requests.xml)).
- **`ProcessGuestRequest` Logic App**: Ny wrapper-Logic App som lytter på `Guest Requests`-listen (1-min polling), kaller eksisterende `ProcessGuests` Logic App og oppdaterer status på listeelementet (Invited / Failed med feilmelding).
- **Tilgangstildeling på siten ved invitasjon**: Webdelen viser nå to nye seksjoner i invite-drawer for å gi gjesten faktisk tilgang utover bare tenant-invitasjonen:
  - _M365-gruppe-seksjon_: legger gjesten som Guest på den koblede M365-gruppen (skjules/gråtones automatisk på sites uten gruppe).
  - _SharePoint-brukergruppe-seksjon_ (valgfritt): "Ikke legg til", "Legg til i eksisterende gruppe" (dropdown), eller "Opprett ny gruppe" (navn + tilgangsnivå Read/Contribute/Edit/Full Control).
- **`AddGuestToSite` runbook**: Ny PowerShell-runbook ([Source/Runbooks/AddGuestToSite.ps1](Source/Runbooks/AddGuestToSite.ps1)) som kalles av `ProcessGuestRequest` Logic App etter vellykket tenant-invitasjon. Bruker `Add-PnPMicrosoft365GroupMember` for M365-gruppen og `Add-PnPUserToGroup`/`New-PnPGroup` for SP-brukergruppen. Runbook-RESSURSEN opprettes via ny [Source/ARMTemplates/runbooks.bicep](Source/ARMTemplates/runbooks.bicep) som deploy.ps1 alltid kjører (også med `-SkipBicepDeploy` i upgrade-mode); INNHOLD må limes inn manuelt i Azure Portal etter første deploy (inntil dette repoet blir public — se [Bestillingsportalen.md](Bestillingsportalen.md#addguesttosite-ny-i-1110)).
- **`Guest Requests`-skjema utvidet**: Fire nye felt — `M365GroupRole` (Choice), `SPGroupAction` (Choice), `SPGroupName` (Text), `SPPermissionLevel` (Choice) — som bærer brukerens valg fra drawer-en gjennom Logic App-en og inn i runbooken.
- **Automatisk SPFx-bygging og publisering i deploy-scriptet**: Ny `DeploySPFxPackages`-funksjon kjører `npm install` (ved behov) + `npm run build` for alle SPFx-løsninger under `Source/SharePointFramework/*/` og publiserer `.sppkg` til tenant app-katalog via `Add-PnPApp -Overwrite -Publish`. Kan hoppes over med `-SkipSPFxDeploy`.

### Forbedringer

- **Forbedret feilhåndtering i bestillingsflyt**: Implementert omfattende feilhåndtering som automatisk oppdaterer Provisioning Requests-listen med status "Space Creation Failed" når feil oppstår i både Logic App og ConfigureSpace runbook. Dette gir bedre synlighet på feiltilstander og enklere feilsøking.
- **Upgrade-mode utvidet**: `DeployUpgradeLogicApp` deployer nå BÅDE `ProcessProvisionRequest` OG `ProcessGuestRequest`. SPFx-løsninger bygges og publiseres også i upgrade-mode (med mindre `-SkipSPFxDeploy` er satt).
- **Navigasjon bevares i upgrade-mode**: `Invoke-PnPSiteTemplate` kjøres uten `-ClearNavigation` når `-Upgrade` er aktiv, slik at egendefinerte nav-lenker ikke slettes.
- **Tydeligere "Site already exists"-prompt**: Prompten i `CreateRequestsSharePointSite` forklarer nå tydelig at `y` = re-anvend PnP-template (oppdaterer lister/felter/innstillinger) og `n` = hopp over template men fortsett med Logic Apps / SPFx. `n` stopper ikke lenger hele scriptet.
- **Race-condition-guard i `DeployUpgradeLogicApp`**: Kaster nå tydelig feilmelding hvis `$global:requestsListId` eller `$global:guestRequestsListId` er tomme før Logic Apps deployes.

### Feilrettinger
