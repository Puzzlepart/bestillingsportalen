# Datatilgang og sikkerhet

Bestillingsportalen bruker **Microsoft Graph API** og **SharePoint REST API** for å provisjonere grupper, områder, team og Viva Engage-fellesskap.

Provisjoneringen utføres via en **user-assigned managed identity** som er koblet til alle Logic Apps og har de nødvendige app-rollene mot Microsoft Graph og SharePoint. Managed identity har ingen secret eller sertifikat som kan utløpe eller lekke – Entra ID utsteder tokens direkte til Azure-ressursen.

**Det finnes ingen unntak lenger.** Løsningen har ingen client secret, ingen Key Vault og ingen Entra ID-app-registrering i drift. Alt kjører på managed identity.

Også sensitivitetsmerker: `ConfigureSpace`-runbooken setter container-merket med Automation-kontoens managed identity via `Set-PnPTenantSite -SensitivityLabel`, som går gjennom SharePoints tenant-admin-API og propagerer merket til den koblede gruppen på tjenersiden. Microsoft Graph støtter fortsatt ikke `assignedLabels` på grupper med Application Permissions (re-verifisert august 2026 mot [group-update](https://learn.microsoft.com/en-us/graph/api/group-update); gjelder også `Group.ManageProtection.All`), men den begrensningen gjelder en annen vei enn den vi bruker. Runbooken leser alltid tilbake `assignedLabels` for å bekrefte at merket landet. Se [Sensitivitetsmerker](Sensitivity-labels.md).

> **Historikk og oppryddingskrav:** tidligere versjoner brukte en ROPC-flyt med en tjenestekonto uten MFA og en Entra ID-app med client secret, lagret i en dedikert Key Vault. I versjonene før 1.0 kjørte flyten som et scope i `ProcessProvisionRequest`, der `secureData` var feilplassert på Key Vault-kallet for passordet og manglet helt på URL-enkodingen, token-kallet og PATCH-en – tjenestekontoens passord, client secret og et levende delegert Graph-token var dermed lesbare i Logic App-ens kjørehistorikk ved hver merket bestilling.
>
> Har du kjørt en tidligere versjon med `enableSensitivity = true`: **roter tjenestekontoens passord** og **slett Entra ID-appen og Key Vault-en** etter oppgradering. Kjørehistorikk slettes ikke av en oppgradering. Se [Oppgraderingsveiledningen](Upgrade.md).

De delegerte API-tilkoblingene (SharePoint Online, Outlook, Office 365 Users, Teams) autoriseres interaktivt med tjenestekontoen – disse connectorene støtter ikke managed identity. Tjenestekontoen er også områdeeier og identiteten som poster velkomstmeldingen i Teams, men den har **ingen** krav om at MFA er avslått; det var utelukkende ROPC-flyten.

Den fullstendige listen over påkrevde API-tillatelser for Microsoft Graph og SharePoint-tenanten finner du nedenfor.

## API-tillatelser

### Managed identity (Logic Apps)

App-roller tildelt den user-assigned managed identityen:

#### Microsoft Graph

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Directory.Read.All | Application | Lese katalogdata | Brukes til å lese gruppe-lifecycle-policyer (`GET /groupLifecyclePolicies`) under provisjoneringen. Dette er dokumentert minste tillatelse for endepunktet (`Group.Read.All` dekker det ikke). |
| GroupSettings.ReadWrite.All | Application | Lese og skrive alle gruppeinnstillinger | Brukes til å deaktivere gjestedeling per gruppe (`Group.Unified.Guest`-innstillingen, `POST /groups/{id}/settings`) og lese gruppeinnstillinger for synkronisering. Erstatter tidligere `Directory.ReadWrite.All` (minste dokumenterte tillatelse for endepunktet). |
| Group.ReadWrite.All | Application | Lese og skrive alle grupper | Brukes til å opprette grupper/team og legge til/fjerne eiere og medlemmer. Eier-operasjonene (`/owners/$ref`) gjør denne til minste praktiske tillatelse. |
| InformationProtectionPolicy.Read.All | Application | Lese alle publiserte merker og merkepolicyer for en organisasjon. | Brukes til å synkronisere sensitivitetsmerker fra tenanten til en SharePoint-liste. |
| Sites.Read.All | Application | Lese elementer i alle områdesamlinger | Brukes av `CheckSiteExists` til å lese tenant-admin-områdets aggregerte områdeliste (sjekke om en URL er i bruk, inkl. papirkurv). Erstatter tidligere Graph `Sites.FullControl.All` — det finnes ingen Graph-site-skriving i løsningen. |
| TeamTemplates.Read.All | Application | Lese alle tilgjengelige Teams-maler | Brukes til å lese Teams-maler i tenanten og synkronisere dem til en SharePoint-liste. |
| Community.ReadWrite.All | Application | Lese og skrive alle Viva Engage-fellesskap. | Brukes til å opprette Viva Engage-fellesskap. |
| User.Invite.All | Application | Invitere gjestebrukere til organisasjonen | Brukes til å invitere gjestebrukere i Entra ID hvis forespurt. |
| User.ReadWrite.All | Application | Lese og skrive til alle brukeres fulle profiler | Brukes til å oppdatere profilfelter (navn/selskap) på inviterte gjestebrukere, og til å registrere bestilleren som gjestens **sponsor** (`POST /users/{id}/sponsors/$ref`). Sponsor er ren dokumentasjon av hvem som er ansvarlig for gjesten — den gir ingen rettigheter i seg selv. |

> **Funksjonsbundne tillatelser:** Tre av tillatelsene er kun i bruk av valgfri funksjonalitet: `User.Invite.All` + `User.ReadWrite.All` (gjesteinvitasjon), `Community.ReadWrite.All` (Viva Engage-fellesskap) og `InformationProtectionPolicy.Read.All` (sensitivitetsmerke-synkronisering). Bruker ikke organisasjonen disse funksjonene, kan tillatelsene fjernes manuelt fra managed identityen i Entra-portalen — men merk at de tilhørende Logic Apps da må deaktiveres (`SyncLabels` kjører f.eks. ukentlig og vil feile uten `InformationProtectionPolicy.Read.All`), og at `deploy.ps1` tildeler hele settet på nytt ved neste kjøring/oppgradering.

#### SharePoint

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Sites.FullControl.All | Application | Full kontroll over alle områder | Brukes til å opprette områdesamlinger (`POST /_api/SPSiteManager/create`), anvende site designs på nyopprettede områder og lese hub-områder. Kan ikke erstattes av `Sites.Selected`: målområdet finnes ikke før opprettelseskallet, så det er ingenting å gi en per-site-tillatelse på. |

### Systemtildelt managed identity (Azure Automation)

App-roller tildelt Automation-kontoens systemtildelte managed identity, som brukes av runbookene `ConfigureSpace`, `AddGuestToSite`, `GetSiteTemplates` og `CustomerSpecific` (organisasjonens eget utvidelsespunkt) via PnP PowerShell `-ManagedIdentity`:

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Group.ReadWrite.All (Microsoft Graph) | Application | Lese og skrive alle grupper | Brukes av runbookene til å endre gruppemedlemskap og -egenskaper. `AddGuestToSite` bruker den til gjestemedlemskap i områdets M365-gruppe, og — når `guestEntraGroup`-parameteren er konfigurert — til å legge gjesten inn i den felles Entra-gjestegruppen (`POST /groups/{id}/members/$ref`). |
| User.Read.All (Microsoft Graph) | Application | Lese alle brukeres fulle profiler | Kreves av `AddGuestToSite` for å slå opp gjestebrukere på e-post før de legges til. |
| Sites.FullControl.All (SharePoint) | Application | Full kontroll over alle områder | Brukes av `ConfigureSpace` til tenant-admin-operasjoner (`Set-PnPTenantSite`, hub-registrering/-tilknytning, site designs) og til etterkonfigurasjon av dynamisk opprettede områder, forelder- og hub-områder (PnP-maler, temaer m.m.). Tenant-admin-cmdletene kan ikke kjøres med `Sites.Selected`, og runbooken må kunne koble til områder som ikke fantes da tilgangen ble gitt. Dette er også tilgangen som muliggjør ad hoc-/lokale tilpasninger i runbooks mot provisjonerte områder. |

### Entra ID-app-registrering

**Løsningen har ingen egen app-registrering i drift.** Den som fantes ble kun brukt av ROPC-flyten for sensitivitetsmerker, og er fjernet. Har du en installasjon fra før: appen kan slettes – se [Oppgraderingsveiledningen](Upgrade.md).

Den eneste app-registreringen som er involvert er **PnP PowerShell-appen** (`pnpAppId`), og den brukes bare *under installasjon* med interaktiv pålogging. Den kan slettes eller få tilgangene fjernet etter fullført installasjon – se [Installasjonsveiledningen](Deployment-guide.md).

## Kompenserende kontroll: Azure RBAC på ressursgruppen

Managed identities har ingen credential som kan lekke — den reelle angrepsflaten for de brede tilgangene (`Sites.FullControl.All` på begge identitetene) er **hvem som kan redigere Logic Apps og runbooks** og dermed kjøre vilkårlig kode som identitetene. Begrens derfor hvem som har `Contributor`, `Logic App Contributor` eller `Automation Contributor` på løsningens ressursgruppe, og behandle disse rollene som tilsvarende SharePoint-administrator-tilgang i tilgangsstyringen.
