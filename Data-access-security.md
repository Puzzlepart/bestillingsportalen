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
| Directory.Read.All | Application | Lese katalogdata | Brukes til å lese Users, Groups og Teams fra tenanten. |
| Directory.ReadWrite.All | Application | Lese og skrive katalogdata | Brukes til å opprette gjestebrukere i Entra ID hvis forespurt. |
| Group.ReadWrite.All | Application | Lese og skrive alle grupper | Brukes til å opprette og oppdatere egenskaper på grupper/team. |
| InformationProtectionPolicy.Read.All | Application | Lese alle publiserte merker og merkepolicyer for en organisasjon. | Brukes til å synkronisere sensitivitetsmerker fra tenanten til en SharePoint-liste. |
| Sites.FullControl.All | Application | Full kontroll over alle områder. | Oppdatere egenskapene til provisjonerte SharePoint-områder. |
| TeamsTemplates.Read.All | Application | Lese alle tilgjengelige Teams-maler | Brukes til å lese Teams-maler i tenanten og synkronisere dem til en SharePoint-liste. |
| Community.ReadWrite.All | Application | Lese og skrive alle Viva Engage-fellesskap. | Brukes til å opprette Viva Engage-fellesskap. |
| User.Invite.All | Application | Invitere gjestebrukere til organisasjonen | Brukes til å invitere gjestebrukere i Entra ID hvis forespurt. |
| User.ReadWrite.All | Application | Lese og skrive til alle brukeres fulle profiler | Brukes til å oppdatere gjestebrukere i Entra ID hvis forespurt. |

#### SharePoint

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Sites.FullControl.All | Application | Full kontroll over alle områder | Brukes til å lese og skrive til opprettede SharePoint-områder. |

### Entra ID-appen (kun sensitivitetsmerker)

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Group.ReadWrite.All | Delegated | Lese og skrive alle grupper | Brukes til å anvende sensitivitetsmerker på opprettede grupper/team (ROPC med tjenestekonto). |

> **Merk:** App registration kan fortsatt ha application-tillatelser fra før managed identity-migreringen. Disse er ikke lenger i bruk og kan fjernes når migreringen er verifisert – se [Migrering til managed identity](Managed-identity-migration.md). En SharePoint add-in-registrering (ACS) av appen er heller ikke lenger nødvendig.
