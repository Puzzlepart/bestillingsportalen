# Sensitivitetsmerker

Bestillingsportalen støtter anvendelse av sensitivitetsmerker på opprettede Teams eller Office 365 Groups.

For å bruke denne funksjonaliteten må sensitivitetsmerker være aktivert for Teams og Groups. Mer informasjon finnes på <https://learn.microsoft.com/en-us/microsoft-365/compliance/sensitivity-labels-teams-groups-sites?view=o365-worldwide>.

**Du må ha merker opprettet i Microsoft Purview Compliance Portal og publisert med Label Policies før dette fungerer. Vent 24 timer etter at merker er opprettet og publisert før du følger denne veiledningen.**

Funksjonaliteten må aktiveres og konfigureres for å fungere.

_Merk – På grunn av begrensninger i Microsoft Graph API kan merker kun anvendes ved hjelp av Delegated permissions. Dette betyr at en tjenestekonto (kan være samme som Bestillingsportalen bruker) er påkrevd. Denne kontoen MÅ IKKE ha MFA konfigurert._

_Brukernavn og passord for denne kontoen lagres i Key Vault for å sikre at det er så trygt som mulig._

_Når denne begrensningen fjernes, vil vi oppdatere Bestillingsportalen til å bruke Application permissions, slik at behovet for en tjenestekonto uten MFA elimineres._

Vi går først gjennom hvordan funksjonaliteten fungerer, og deretter hvordan du aktiverer den.

### Hvordan ser dette ut?

Sensitivitetsmerker hentes fra Purview via Microsoft Graph API. En Logic App kalt `SyncLabels` utfører synkroniseringen. Logic App-en er som standard satt til å kjøre ukentlig – dette kan endres ved behov.

Merker lagres som listeelementer i en SharePoint-liste kalt `IP Labels` i SharePoint-området som står bak Bestillingsportalen.

![IP labels list screenshot](./Images/IPLabelsList.png)

For at et merke skal vises i Bestillingsportalen webdel eller Teams app, må `Enabled`-kolonnen være huket av. Denne kolonnen er lagt til fordi Graph API ikke tillater filtrering på merker som kan anvendes på Sites/Groups vs. Document/Email-merker, og den sikrer at brukere ikke velger feil type merke. Du kan se at det finnes document/email-merker i IP Labels-listen. Sørg for at disse ikke er markert som `Enabled`, og at kun merker som kan anvendes på områder eller grupper er aktivert.

Du kan validere hvilke merker som kan anvendes på områder/grupper via Security & Compliance Center.

Hvis funksjonaliteten er aktivert, vises merkene til brukeren i en kombinasjonsboks på «Datakategorisering»-skjermen.

Du kan angi et standardmerke og velge om brukeren må velge et merke ved å konfigurere innstillingene `DefaultSensitivityLabel` og `RequireSensitivityLabel` i `Provisioning Request Settings`-listen. Dette dekkes i Konfigurasjon-seksjonen nedenfor.

## Aktivere funksjonaliteten

Det finnes to måter å aktivere funksjonaliteten på:

1. Under kjøring av skriptet – en parameter `EnableSensitivity` finnes i `parameters.json` som aktiverer sensitivitetsmerke-funksjonaliteten. Hvis den er satt til `true`, aktiveres funksjonaliteten automatisk. Dette er dokumentert i [Installasjonsveiledningen](./Deployment-guide.md).

2. Manuell aktivering – Følg stegene nedenfor for å aktivere funksjonaliteten manuelt hvis du ikke aktiverte den i `parameters.json`.

### Manuell aktivering

1. Gå til listen **`Provisioning Request Settings`** i SharePoint-området.
2. Rediger listeelementet **`EnableSensitivityLabels`** og sett `Value`-feltet til **`true`**. Standardverdien er `false`.
3. Gå til **Azure Portal > Key Vaults** og klikk på Key Vault-en for Bestillingsportalen-installasjonen din.
4. Velg **`Secrets`** fra venstre panel.

![Key vault secrets screenshot](./Images/KeyVaultSecrets.png)

5. Klikk **`Generate/Import`** og opprett følgende secret:

![Generate secret screenshot](./Images/KeyVaultGenerateSecret.png)

Name: `sausername`

Value: UPN for tjenestekontoen din

Klikk `Create` når ferdig.

![Create username secret screenshot](./Images/KeyVaultUsernameSecret.png)

6. Gjenta steget over og opprett følgende secret:

Name: `sapassword`

Value: Passord for tjenestekontoen

7. Finn Logic App-en **`SyncLabels`** i Azure Portal og klikk på den.
8. Klikk **`Run Trigger > Run`** og vent til kjøringen fullfører.

![Sync labels logic app screenshot](./Images/SyncLabelsLA.png)

9. Gå til listen **`IP Labels`** i SharePoint-området og valider at merkene er tilstede (se skjermbildet av IP Labels-listen øverst i dokumentet). Hvis det ikke finnes noen listeelementer, har **`SyncLabels`** Logic App-en feilet under kjøring. Sjekk kjørehistorikken til Logic App-en og undersøk eventuelle feil.

## Konfigurasjon

Når aktivert kan funksjonaliteten konfigureres slik:

1. Hvis ikke allerede gjort, finn **`SyncLabels`** Logic App-en i Azure Portal og kjør den – **`Run Trigger > Run`**. Dette synkroniserer merkene inn i IP Labels-listen (se skjermbildet ovenfor).
2. Aktiver noen merker som skal vises i Bestillingsportalen webdel eller Teams app ved å redigere listeelementene, sette **`Enabled`**-kolonnen til **`true`** og lagre elementene.

![Enabling a label screenshot](./Images/EnableIPLabel.png)

3. Angi et standardmerke (valgfritt) ved å sette verdien på listeelementet **`DefaultSensitivityLabel`** i listen **`Provisioning Request Settings`** til merkets ID (label id). ID-en må **nøyaktig** matche en gyldig `LabelId` fra IP Labels-listen. Du finner ID-en i kolonnen **`Label Id`**.

![Set default label screenshot](./Images/SetDefaultLabel.png)

4. Velg om brukeren må velge et merke (valgfritt). Standardverdien er **`false`**, som betyr at brukeren ikke er tvunget til å velge et merke og kombinasjonsboksen kan stå tom. For å tvinge brukere til å velge et merke, sett verdien på listeelementet **`RequireSensitivityLabel`** til **`true`**.
5. Funksjonaliteten er nå konfigurert. Når brukere starter Bestillingsportalen webdel eller Teams app for å bestille samarbeidsområder, vil de se sensitivitets-kombinasjonsboksen på «Datakategorisering»-steget (kun for `Microsoft Teams Team` eller `Office 365 Group`).
