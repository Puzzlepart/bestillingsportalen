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
- **FirstName** (Text, valgfri): Fornavn på gjesten — settes fra Graph-oppslag eller manuell input i drawer-en. Sendes til Graph som `invitedUserDisplayName` (sammen med LastName) på `/invitations`-kallet, og PATCH-es som `givenName` på Entra-brukeren etterpå.
- **LastName** (Text, valgfri): Etternavn — samme som FirstName, PATCH-es som `surname` på Entra-brukeren.
- **Company** (Text, valgfri): Selskap/organisasjon — PATCH-es som `companyName` på Entra-brukeren via Graph etter at invitasjonen er opprettet.
- SiteUrl: URL til området gjesten skal inviteres til.
- SiteTitle: Tittel på området (vises i invitasjons-e-posten).
- Status: `Pending` / `Invited` / `Failed`.
- GuestId: Entra ID-id til opprettet gjestebruker.
- InviteRedeemUrl: Innløsings-URL.
- ErrorMessage: Feilmelding ved `Status=Failed`.
- RequestedBy: Brukeren som initierte invitasjonen.
- **M365GroupRole** (Choice: `None`/`Visitor`/`Member`/`Owner`, default `Visitor`): Rolle gjesten skal ha på området. På M365-gruppe-koblede områder håndteres `Owner` og `Member` via Graph (`Add-PnPMicrosoft365GroupOwner`/`Member`); `Visitor` håndteres alltid via SP `AssociatedVisitorGroup`. På klassiske/Communication-områder håndteres alle tre rollene via tilsvarende SP `AssociatedOwner`/`Member`/`VisitorGroup`.
- **SPGroupAction** (Choice: `None`/`AddToExisting`/`CreateNew`): Hva som skal skje med en valgfri SharePoint-brukergruppe-tilføyelse.
- **SPGroupName** (Text): Navn på eksisterende eller ny SP-gruppe (avhengig av `SPGroupAction`).
- **SPPermissionLevel** (Choice: `Read`/`Contribute`/`Edit`/`Full Control`): Tilgangsnivå når `SPGroupAction = CreateNew`.

## Logic Apps

### ProcessGuestRequest (ny i 1.11.0)

Wrapper-Logic App ([Source/ARMTemplates/LogicApps/processguestrequest.json](Source/ARMTemplates/LogicApps/processguestrequest.json)) som trigges når et nytt item opprettes på `Guest Requests`-listen (SharePoint-connector, 1-min polling, trigger-condition `Status==Pending`). Flyt:

1. **Try-Catch** (kjerne-flyt): kaller `ProcessGuests` Logic App → lagrer GuestId/InviteRedeemUrl → kjører `AddGuestToSite` runbook → `Check_runbook_status` If sjekker `body('Add_Guest_To_Site')?.properties?.status` (Azure Automation-connector returnerer alltid HTTP 200) og setter `Status` til `Invited` eller `Failed` med runbook-exception. Catch-blokken fanger feil før runbook (Process_Guests, Store_guest_info) og setter `Status=Failed`.
2. **Site-fokusert e-post med to varianter** (kun else-branchen av `Check_runbook_status`, etter `Update_item_as_Invited`): `Check_if_guest_is_new` If grener på `@empty(outputs('Set_first_guest_result')?['InviteRedeemUrl'])`. Begge varianter bruker Office 365 Outlook-connector (`POST /Mail`), samme HTML-template, og hilsen tilpasses med `triggerBody()?['FirstName']` om satt. Branding via `variables('CompanyName')` (initialisert fra ARM-parameteren `tenantName`, tildelt via `spoTenantName` i deploy.ps1). Gjenbruker `bestillingsportalen-o365`-connection som `ProcessProvisionRequest` allerede oppretter via `apiconnections.json`.
   - **Ny i tenanten** (yes-branch, `InviteRedeemUrl` ikke-tom): `Send_guest_invitation_email` — emne «Du har fått tilgang til {SiteTitle}», CTA «Kom i gang» som peker på `outputs('Set_first_guest_result')?['InviteRedeemUrl']`. Gjesten må akseptere tenant-invitasjonen via redeem-flyten.
   - **Eksisterende tenant-gjest** (else-branch, `InviteRedeemUrl` tom): `Send_site_access_email` — samme emne, men CTA «Gå til området» som peker rett på `triggerBody()?['SiteUrl']`. Ingen invitasjon å akseptere — gjesten er allerede i tenanten og kan gå direkte til området. Dekker scenariet der en bruker som tidligere ble invitert (kanskje til et helt annet område) nå legges til vårt nye område via flyten.

   Diverger fra `ProcessProvisionRequest`s `Send_guest_invitation_email`-mønster ved å legge til else-grenen for eksisterende-gjest-tilfellet (upstream sender kun for nye gjester).

**Sikkerhetsmodell**: Autorisasjon enforces av to ting i kombinasjon:

- **SPFx-UI-sjekk** (`SiteService.getCurrentUserAccessLevel()` + `inviteAccessLevel`-property): bestemmer hvem som ser Inviter-knappen i webdelen
- **Listetillatelser på `Guest Requests`**: må låses i admin-siten så kun trusted brukere kan opprette items direkte (forhindrer REST-bypass av UI-sjekken)

Tidligere forsøk på en server-side autorisasjonsjekk i Logic App-en (SP REST mot målsitens AssociatedOwnerGroup/AssociatedMemberGroup) ble fjernet — SP-connectoren authentiserer som connection-brukeren, som ofte ikke har tilgang til målsiten → 403. List-tillatelser er den reelle sikkerhetsgrensen.

### ProcessGuests (forket fra `pnp/provision-assist-m365`)

Indre Logic App ([Source/ARMTemplates/LogicApps/processguests.json](Source/ARMTemplates/LogicApps/processguests.json)) som håndterer selve Graph-kallene mot `/invitations` og `/users/{id}` PATCH. Authentiserer med den delte user-assigned managed identityen (se [Managed-identity-migration.md](Managed-identity-migration.md)).

- **Get_Guest** → sjekker om gjesten finnes som ekstern bruker i tenanten via `/users?$filter=userType eq 'Guest' and mail eq …`
- **Check_if_Guest_exists** (If):
  - Eksisterer ikke → `Send_guest_invitation` POST /invitations (med `invitedUserDisplayName` fra Fornavn+Etternavn, `sendInvitationMessage: false`)
  - Eksisterer → bruker eksisterende `id` direkte uten ny invitasjon
- **Patch_user_profile** (If, kun yes-branch): hvis Fornavn/Etternavn/Selskap er ikke-tomme, PATCH `/users/{invitedUser.id}` med `givenName`/`surname`/`companyName`. Trenger `User.ReadWrite.All`-app-rollen på den user-assigned managed identityen (tildeles automatisk av `deploy.ps1` via `AssignUamiPermissions`).
- **Append_invited_guest_to_Guests_variable** → bygger response-array.

Loopen `Loop_through_Guests` fra opprinnelig `pnp/provision-assist-m365`-template er fjernet siden vår `ProcessGuestRequest` alltid sender én e-post per kall. Diverger fra upstream-mønsteret — merging av upstream-endringer må skje manuelt.

## Runbooks

### AddGuestToSite (ny i 1.11.0)

Lokal runbook ([Source/Runbooks/AddGuestToSite.ps1](Source/Runbooks/AddGuestToSite.ps1)) som kalles av `ProcessGuestRequest` Logic App etter at en gjest er invitert via Graph. Authentiserer mot SP via system-assigned managed identity (PnP).

Managed identityen trenger tre app-roller (tildelt automatisk av `deploy.ps1` via `AssignManagedIdentityPermissions`): `Office 365 SharePoint Online — Sites.FullControl.All` (for å håndtere SP-grupper på vilkårlige site collections), `Microsoft Graph — Group.ReadWrite.All` (for å mutere M365-gruppe-medlemskap) og `Microsoft Graph — User.Read.All` (fordi `Add-PnPMicrosoft365GroupMember`/`Owner` resolver gjesten via `GET /users/{email}` før den poster `members/$ref` — uten dette returnerer brukeroppslaget 403 «Insufficient privileges»).

Steg 1 — **EnsureUser**: en fersk B2B-gjest finnes i Entra ID, men ikke i målsitens user info-liste. PnP.PowerShell har ingen cmdlet-wrapper for EnsureUser, så vi bruker CSOM direkte: `$pnpContext.Web.EnsureUser($guestEmail)` + `Invoke-PnPQuery` materialiserer gjesten som SP-prinsipal og returnerer `LoginName` (claims-encoded UPN) som brukes videre. Uten dette feiler `Add-PnPGroupMember` med "Cannot bind argument to parameter 'LoginName' because it is an empty string."

Hver kjøring logger med `[INIT]`/`[STEP 1/2]`/`[STEP 2/2]`/`[DONE]`-prefikser så det er enkelt å se i runbook-output hvilke steg som faktisk fullførte ved delvis feil.

Steg 2 — to uavhengige tilføyelser basert på Guest Request-feltene:

1. **Områderolle** (`M365GroupRole`): hybrid-routing basert på om siten er M365-gruppe-koblet:
   - `None`: hopp over
   - `Visitor`: alltid `Get-PnPGroup -AssociatedVisitorGroup` + `Add-PnPGroupMember`
   - `Member`: gruppe-koblet → `Add-PnPMicrosoft365GroupMember -Identity $site.GroupId -Users $guestEmail`; ellers → `Get-PnPGroup -AssociatedMemberGroup` + `Add-PnPGroupMember`
   - `Owner`: gruppe-koblet → `Add-PnPMicrosoft365GroupOwner -Identity $site.GroupId -Users $guestEmail`; ellers → `Get-PnPGroup -AssociatedOwnerGroup` + `Add-PnPGroupMember`
2. **SP-gruppe-tilføyelse** (`SPGroupAction`):
   - `None`: hopp over
   - `AddToExisting`: `Get-PnPGroup -Identity <SPGroupName>` + `Add-PnPGroupMember -LoginName <ensuredLoginName> -Identity <group>`
   - `CreateNew`: `New-PnPGroup` + `Set-PnPGroupPermissions -AddRole <SPPermissionLevel>` + `Add-PnPGroupMember`

Runbook-ressursen opprettes via [Source/ARMTemplates/runbooks.bicep](Source/ARMTemplates/runbooks.bicep) (som nå eier alle tre runbookene og PowerShell 7.4-runtime-miljøet). `runbooks.bicep` deployes ALLTID av `deploy.ps1`, også når `-SkipBicepDeploy` brukes i upgrade-mode — og runbook-INNHOLDET lastes opp direkte fra [Source/Runbooks/](Source/Runbooks/) og publiseres av skriptet via management-APIet. Innholdet er dermed alltid i sync med repoet; endringer gjort direkte i Azure Portal overskrives ved neste deploy/upgrade.

## SPFx-løsninger

### ProvisionWebParts (ny i 1.11.0)

Nytt SPFx 1.22-prosjekt under `Source/SharePointFramework/ProvisionWebParts/` (Heft-basert toolchain, Fluent UI v9, PnPjs 4.x). Speiler mappestrukturen til Puzzlepart `prosjektportalen365` (shared `src/components/`, `src/loc/`, `src/webparts/<name>/index.ts` + `manifest.json`).

- **InviteGuests-webdel**: Lar brukere invitere eksterne gjester direkte fra et SharePoint-område. UX bygget på `OverlayDrawer` + `TagPicker` (basert på PP365 `ProvisionDrawer/Guest`-mønster) og `DataGrid` for statusvisning (basert på PP365 `ProvisionStatus`-mønsteret).
  - **`inviteMode`-property** (`Single`/`Multi`, default `Multi`): Single bruker en enkel `<Input>` for én gjest; Multi bruker TagPicker som støtter lim-inn med komma/semikolon/linjeskift som separatorer. I Multi når 2+ gjester er valgt vises `<GuestTabList>` med én Tab per gjest for å redigere profil-data og evt. rolle/SP-gruppe per gjest.
  - **`perGuestProfileMode`-property** (`Disabled`/`Optional`/`Enforced`, default `Optional`): Styrer en bryter i drawer-en for "Detaljer per gjest". `Optional` viser switch (default av); `Enforced` skjuler switch og tvinger på; `Disabled` skjuler switch og tvinger av. Når på vises Fornavn/Etternavn/Selskap-felter per gjest.
  - **`perGuestRoleMode`-property** (samme 3 nivåer, default `Optional`): Styrer bryter for "Rolle og brukergruppe per gjest". Når på flyttes `M365GroupRoleSection` + `SPGroupSection` inn i per-gjest-området (via TabList); når av deles én felles rolle/gruppe-seksjon for alle gjester nederst i drawer-en.
  - **`inviteAccessLevel`-property** (`Owner`/`Member`/`Anyone`, default `Owner`): Styrer hvem som kan se Inviter-knappen. `Owner` = kun medlemmer av sitens AssociatedOwnerGroup (= M365-gruppe-eiere på gruppe-koblede siter) eller site collection admins; `Member` = også AssociatedMemberGroup; `Anyone` = alle med tilgang til området. Brukere uten tilgang ser webdelens tittel + status-liste, men ikke selve Inviter-knappen. `SiteService.getCurrentUserAccessLevel()` sjekker via `web.currentUser.groups` mot AssociatedOwner/MemberGroup-ID-ene.
  - **`GuestProfileForm`**: Fornavn / Etternavn (to-kolonne) + Selskap/organisasjon per gjest. `Fornavn`/`Etternavn` blir readonly med "Finnes i Entra ID"-badge når Graph-oppslag finner brukeren; Selskap er alltid editerbart.
  - **`GraphService`**: Slår opp e-post via `MSGraphClientV3` mot `/users?$filter=mail eq … or userPrincipalName eq … or otherMails/any(o:o eq …)`. Krever `User.ReadBasic.All`-permission på SPFx-løsningen (registrert i `package-solution.json`, må godkjennes i SharePoint Admin → API access etter første deploy).
  - **`M365GroupRoleSection`**: Radio-velger for områderolle (`Ingen`/`Besøkende`/`Medlem`/`Eier`, default `Besøkende`). Vises alltid og fungerer på alle site-typer — runbooken håndterer hybrid-routing (Graph-cmdletene for Owner/Member på gruppe-koblede siter; SP-associated-gruppene ellers).
  - **`SPGroupSection`** (valgfritt): Radio-valg mellom "ingen", "legg til i eksisterende gruppe" (dropdown fra `SiteService.getSiteGroups`) eller "opprett ny gruppe" (navn + permission level). Default-valg: `AddToExisting` med sitens associated Visitors-gruppe pre-valgt (fra `SiteService.getSiteContext().associatedVisitorGroupTitle`), faller tilbake til `None` hvis siten mangler Visitors-gruppe.
  - **`SiteService`**: Spør gjeldende side (ikke admin-siten) om M365-gruppe-status, associated Visitors-gruppe og tilgjengelige SP-grupper. Webparten har dermed to PnPjs `SPFI`-instanser: én mot Bestillingsportalen-siten (Guest Requests-liste), én mot gjeldende site (gruppe-info).
  - **`AccessPreviewPanel`**: Alltid-synlig `<MessageBar>` som dynamisk lister hva gjesten faktisk får tilgang til basert på valgt M365-rolle + SP-gruppe + om siten er M365-gruppe-koblet. Intent veksler mellom `info` (begrenset tilgang) og `warning` (Owner/Member på gruppe-koblet site = Teams + alle gruppe-ressurser). Tydeliggjør M365-gruppe-medlemskaps-kaskaden (Member = Teams + SP + OneNote + Planner) som ofte er kilden til "for mye tilgang gitt"-problemer ved gjeste-invitasjoner. Komponenten gjengir punktliste over tilgangspunktene + en advarsels-footer ved warning-intent.
