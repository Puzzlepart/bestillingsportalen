# Datatilgang og sikkerhet

Bestillingsportalen bruker **Microsoft Graph API** og **SharePoint REST API** for å provisjonere grupper, områder, team og Viva Engage-fellesskap.

Provisjoneringen utføres via en **user-assigned managed identity** som er koblet til alle Logic Apps og har de nødvendige app-rollene mot Microsoft Graph og SharePoint. Managed identity har ingen secret eller sertifikat som kan utløpe eller lekke – Entra ID utsteder tokens direkte til Azure-ressursen. Se [Migrering til managed identity](Managed-identity-migration.md) for bakgrunn.

Det finnes ett unntak – anvendelse av sensitivitetsmerker. Per juli 2023 støttet ikke Graph API anvendelse av sensitivitetsmerker på grupper og team med Application Permissions. Denne begrensningen kan ha blitt fjernet siden – verifiser mot gjeldende [Microsoft Graph-dokumentasjon](https://learn.microsoft.com/en-us/graph/api/group-update). Inntil dette er bekreftet, brukes en tjenestekonto (uten MFA) med **Delegated Permissions** via en Entra ID App Registration (ROPC-flyt). Av samme grunn beholder Entra ID-appen en client secret – den brukes utelukkende i dette token-kallet.

Hvis du velger å deaktivere eller ikke bruke sensitivitetsmerkefunksjonaliteten, er verken tjenestekonto-credentials, app-secret eller den delegerte tillatelsen nødvendig.

**Client ID**, **Client Secret** og tjenestekonto-credentials (kun ved sensitivitetsmerker) lagres i en dedikert Key Vault som opprettes for Bestillingsportalen. Disse hentes ved behov i Logic Apps via Key Vault-handlingen (autentisert med managed identity), som er konfigurert til å skjule input og output slik at verdiene ikke er synlige i kjørehistorikken.

I tillegg autoriseres de delegerte API-tilkoblingene (SharePoint Online, Outlook, Office 365 Users, Teams) interaktivt med tjenestekontoen – disse connectorene støtter ikke managed identity.

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
| TeamsTemplates.Read.All | Application | Lese alle tilgjengelige Teams-maler | Brukes til å lese Teams-maler i tenanten og synkronisere dem til en SharePoint-liste. |
| Community.ReadWrite.All | Application | Lese og skrive alle Viva Engage-fellesskap. | Brukes til å opprette Viva Engage-fellesskap. |
| User.Invite.All | Application | Invitere gjestebrukere til organisasjonen | Brukes til å invitere gjestebrukere i Entra ID hvis forespurt. |
| User.ReadWrite.All | Application | Lese og skrive til alle brukeres fulle profiler | Brukes til å oppdatere profilfelter (navn/selskap) på inviterte gjestebrukere. |

> **Funksjonsbundne tillatelser:** Tre av tillatelsene er kun i bruk av valgfri funksjonalitet: `User.Invite.All` + `User.ReadWrite.All` (gjesteinvitasjon), `Community.ReadWrite.All` (Viva Engage-fellesskap) og `InformationProtectionPolicy.Read.All` (sensitivitetsmerke-synkronisering). Bruker ikke organisasjonen disse funksjonene, kan tillatelsene fjernes manuelt fra managed identityen i Entra-portalen — men merk at de tilhørende Logic Apps da må deaktiveres (`SyncLabels` kjører f.eks. ukentlig og vil feile uten `InformationProtectionPolicy.Read.All`), og at `deploy.ps1` tildeler hele settet på nytt ved neste kjøring/oppgradering.

#### SharePoint

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Sites.FullControl.All | Application | Full kontroll over alle områder | Brukes til å opprette områdesamlinger (`POST /_api/SPSiteManager/create`), anvende site designs på nyopprettede områder og lese hub-områder. Kan ikke erstattes av `Sites.Selected`: målområdet finnes ikke før opprettelseskallet, så det er ingenting å gi en per-site-tillatelse på. |

### Systemtildelt managed identity (Azure Automation)

App-roller tildelt Automation-kontoens systemtildelte managed identity, som brukes av runbookene `ConfigureSpace`, `AddGuestToSite` og `GetSiteTemplates` (PnP PowerShell `-ManagedIdentity`):

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Group.ReadWrite.All (Microsoft Graph) | Application | Lese og skrive alle grupper | Brukes av runbookene til å endre gruppemedlemskap og -egenskaper. |
| User.Read.All (Microsoft Graph) | Application | Lese alle brukeres fulle profiler | Kreves av `AddGuestToSite` for å slå opp gjestebrukere på e-post før de legges til. |
| Sites.FullControl.All (SharePoint) | Application | Full kontroll over alle områder | Brukes av `ConfigureSpace` til tenant-admin-operasjoner (`Set-PnPTenantSite`, hub-registrering/-tilknytning, site designs) og til etterkonfigurasjon av dynamisk opprettede områder, forelder- og hub-områder (PnP-maler, temaer m.m.). Tenant-admin-cmdletene kan ikke kjøres med `Sites.Selected`, og runbooken må kunne koble til områder som ikke fantes da tilgangen ble gitt. Dette er også tilgangen som muliggjør ad hoc-/kundetilpasninger i runbooks mot provisjonerte områder. |

### Entra ID-appen (kun sensitivitetsmerker)

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Group.ReadWrite.All | Delegated | Lese og skrive alle grupper | Brukes til å anvende sensitivitetsmerker på opprettede grupper/team (ROPC med tjenestekonto). |

> **Merk:** Nye installasjoner oppretter appen med kun denne delegerte tillatelsen. App registrations fra før managed identity-migreringen kan fortsatt ha application-tillatelser; disse er ikke lenger i bruk og kan fjernes når migreringen er verifisert – se [Migrering til managed identity](Managed-identity-migration.md). En SharePoint add-in-registrering (ACS) av appen er heller ikke lenger nødvendig.

## Kompenserende kontroll: Azure RBAC på ressursgruppen

Managed identities har ingen credential som kan lekke — den reelle angrepsflaten for de brede tilgangene (`Sites.FullControl.All` på begge identitetene) er **hvem som kan redigere Logic Apps og runbooks** og dermed kjøre vilkårlig kode som identitetene. Begrens derfor hvem som har `Contributor`, `Logic App Contributor` eller `Automation Contributor` på løsningens ressursgruppe, og behandle disse rollene som tilsvarende SharePoint-administrator-tilgang i tilgangsstyringen.
