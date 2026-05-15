# Løsningsarkitektur

Diagrammet nedenfor viser arkitekturen til Bestillingsportalen-løsningen og komponentene som brukes på et overordnet nivå.

## Bestillingsflyt (provisjonering)

``` mermaid
graph TD
    A(SPFx Webdel / Teams App) --> | Submit data | B[(SharePoint List)] --> C(Power Automate Approval Flow) --> D(Logic App) --> E(Entra ID App) <--> | Secret stored in Key Vault | F(Azure Key Vault) --> G{Type of collaboration space} --> |SharePoint Site| H[SharePoint REST API] 
    G --> | Office 365 Group | I(Microsoft Graph)
    G --> | Viva Engage Community | J(Microsoft Graph) 
    I --> K(Azure Automation)
    H --> K
    J --> K
    K --> | Additional configuration using Managed Identity | L(PnP PowerShell) --> M(Provisioned space)
``````

## Gjeste-invitasjonsflyt

Frittstående flyt som lar brukere invitere eksterne gjester til et eksisterende område uten å gå via bestillingsskjemaet. Hver invitasjon kan i tillegg til selve tenant-invitasjonen gi gjesten medlemskap i den koblede M365-gruppen og/eller en valgfri SharePoint-brukergruppe på selve siten.

``` mermaid
graph TD
    A(InviteGuests SPFx-webdel) --> | Read M365 group status + SP groups | A2(Gjeldende SP-site)
    A --> | Write item per guest with M365GroupRole, SPGroupAction, SPGroupName, SPPermissionLevel | B[("Guest Requests SharePoint-liste")]
    B --> | When an item is created (1 min poll) | C(ProcessGuestRequest Logic App)
    C --> | Workflow action | D(ProcessGuests Logic App)
    D --> E(Microsoft Graph /invitations API) --> F(Guest user in Entra ID)
    D --> | Status, GuestId, InviteRedeemUrl | B
    C --> | After successful invite, with guest + group params | G(AddGuestToSite runbook)
    G --> | Managed Identity | H(PnP PowerShell)
    H --> | Add-PnPMicrosoft365GroupMember | I(M365-gruppen på siten)
    H --> | Add-PnPUserToGroup / New-PnPGroup | J(SP-brukergruppe på siten)
    A --> | DataGrid view filtered by SiteUrl | B
``````
