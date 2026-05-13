# Retention Labels

Bestillingsportalen støtter anvendelse av oppbevaringsmerker (retention labels) på SharePoint-området som står bak et opprettet samarbeidsområde.

Merket anvendes kun på **det innebygde `Documents`-biblioteket**.

For å bruke denne funksjonaliteten må oppbevaringsmerker være opprettet i Microsoft Purview Compliance Portal.

**Vent 24 timer etter at merker er opprettet og publisert før du følger denne veiledningen.**

Når merkene er opprettet, må du aktivere funksjonaliteten i Bestillingsportalen. Følg stegene nedenfor for å gjøre dette.

Vi går først gjennom hvordan funksjonaliteten fungerer, og deretter hvordan du aktiverer den.

### Hvordan ser dette ut?

Oppbevaringsmerker lagres som listeelementer i en SharePoint-liste kalt `Retention Labels` i SharePoint-området som står bak Bestillingsportalen.

Merker må legges til manuelt i listen `Retention Labels`. Sørg for at verdien i kolonnen `Label Name` **matcher nøyaktig navnet på merket i Purview**.

![Retention labels list screenshot](./images/RetentionLabelsList.png)

Hvis funksjonaliteten er aktivert, vises merkene til brukeren i en kombinasjonsboks på «Datakategorisering»-steget.

Du kan angi et standardmerke og velge om brukeren skal måtte velge et merke ved å konfigurere innstillingene `DefaultRetentionLabel` og `RequireRetentionLabel` i `Provisioning Request Settings`-listen. Dette dekkes i Konfigurasjon-seksjonen.

## Aktivere funksjonaliteten

1. Gå til listen **`Provisioning Request Settings`** i SharePoint-området.
2. Rediger listeelementet **`EnableRetentionLabels`** og sett Value-feltet til **`true`**. Standardverdien er `false`.

## Konfigurasjon

Når funksjonaliteten er aktivert, kan den konfigureres slik:

1. Opprett merkene dine i listen **`Retention Labels`** ved å opprette listeelementer manuelt. Sørg for at `Label Name` matcher nøyaktig navnet på merket.
2. Angi et standardmerke (valgfritt) ved å sette verdien på listeelementet **`DefaultRetentionLabel`** i **`Provisioning Request Settings`**-listen til navnet på det valgte merket. Navnet må **nøyaktig** matche et gyldig merkenavn fra Retention Labels-listen. Du finner navnet i kolonnen **`Label Name`**.
3. Velg om brukeren skal måtte velge et merke (valgfritt). Standardverdien er **`false`**, som betyr at brukeren ikke er tvunget til å velge et merke og kan la kombinasjonsboksen stå tom. For å kreve at brukere velger et merke, sett verdien på listeelementet **`RequireRetentionLabel`** til **`true`**.

![Retention label configuration in settings list screenshot](./images/RetentionLabelSettings.png)

5. Funksjonaliteten er nå konfigurert, og når brukere starter Bestillingsportalen webdel eller Teams app for å bestille områder, vil de se kombinasjonsboksen for oppbevaringsmerke på «Datakategorisering»-skjermen.
