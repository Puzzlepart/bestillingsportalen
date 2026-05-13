# Datatilgang og sikkerhet

Bestillingsportalen bruker **Microsoft Graph API** og **SharePoint REST API** for å provisjonere grupper, områder, team og Viva Engage-fellesskap.

Provisjoneringen utføres via en **Entra ID App Registration** som har de nødvendige tillatelsene til Microsoft Graph API. For det meste brukes **Application Permissions**, med ett unntak – anvendelse av sensitivitetsmerker.

Per juli 2023 støttet ikke Graph API anvendelse av sensitivitetsmerker på grupper og team med Application Permissions. Denne begrensningen kan ha blitt fjernet siden – verifiser mot gjeldende [Microsoft Graph-dokumentasjon](https://learn.microsoft.com/en-us/graph/api/resources/security-api-overview). Inntil dette er bekreftet, brukes en tjenestekonto (uten MFA) med **Delegated Permissions** konfigurert mot det relevante Graph-endepunktet.

Hvis du velger å deaktivere eller ikke bruke sensitivitetsmerkefunksjonaliteten, er ikke dette nødvendig.

**Client ID** og **Client Secret** for Entra ID-appen lagres i en dedikert Key Vault som opprettes for Bestillingsportalen. Disse hentes deretter til bruk i Logic Apps via Key Vault-handlingen, som er konfigurert til å skjule input og output slik at secret-verdien ikke er synlig i kjørehistorikken.

Den fullstendige listen over påkrevde API-tillatelser for Microsoft Graph og SharePoint-tenanten finner du nedenfor.

## API-tillatelser

Påkrevde API-tillatelser for Entra ID-appen:

### Microsoft Graph

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Directory.Read.All | Application | Lese katalogdata | Brukes til å lese Users, Groups og Teams fra tenanten. |
| Directory.ReadWrite.All | Application | Lese og skrive katalogdata | Brukes til å opprette gjestebrukere i Entra ID hvis forespurt. |
| Group.ReadWrite.All | Delegated | Lese og skrive alle grupper | Brukes til å anvende sensitivitetsmerker på opprettede grupper/team. |
| Group.ReadWrite.All | Application | Lese og skrive alle grupper | Brukes til å opprette og oppdatere egenskaper på grupper/team. |
| InformationProtectionPolicy.Read.All | Application | Lese alle publiserte merker og merkepolicyer for en organisasjon. | Brukes til å synkronisere sensitivitetsmerker fra tenanten til en SharePoint-liste. |
| Sites.FullControl.All | Application | Full kontroll over alle områder. | Oppdatere egenskapene til provisjonerte SharePoint-områder. |
| TeamsTemplates.Read.All | Application | Lese alle tilgjengelige Teams-maler | Brukes til å lese Teams-maler i tenanten og synkronisere dem til en SharePoint-liste. |
| Community.ReadWrite.All | Application | Lese og skrive alle Viva Engage-fellesskap. | Brukes til å opprette Viva Engage-fellesskap. |
| User.Invite.All | Application | Invitere gjestebrukere til organisasjonen | Brukes til å invitere gjestebrukere i Entra ID hvis forespurt. |
| User.ReadWrite.All | Application | Lese og skrive til alle brukeres fulle profiler | Brukes til å oppdatere gjestebrukere i Entra ID hvis forespurt. |

### SharePoint

| API Permission | Type | Beskrivelse | Årsak |
|--|--|--|--|
| Sites.FullControl.All | Application | Full kontroll over alle områder | Brukes til å lese og skrive til opprettede SharePoint-områder. |

I tillegg må Entra ID-appen registreres som en **SharePoint add-in** og få **Full Control**-tillatelser mot SharePoint-tenanten.

Dette er nødvendig fordi provisjoneringen sjekker om et SharePoint-område som matcher URL-en allerede finnes – både som et aktivt område og i tenantens papirkurv.
