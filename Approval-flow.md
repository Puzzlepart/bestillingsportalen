# Godkjenningsflyt

Bestillingsportalen inkluderer en Power Automate-flyt (`Provisioning Request Approval`) som håndterer godkjenning av bestillinger opprettet av brukere.

Godkjenning av bestillinger kan skje på to måter:

- Power Automate Approval-handling (godkjennings-epost og Approvals-app i Teams).
- Microsoft Teams Adaptive Card-godkjenning (adaptivt kort postet i en Teams-kanal).

Flyten kjører når statusen på en bestilling i **`Provisioning Requests`**-listen endres til **`Submitted`** (brukeren sender inn bestillingen i Bestillingsportalen webdel eller Teams app).

Når du installerer løsningen, sørg for å følge «Steg 1: Konfigurere godkjenningsprosess» i [Konfigurasjonsveiledningen](/Configuration-guide.md) for å sette opp godkjenning. Hvis du vil endre godkjenningsmetoden – f.eks. bytte fra Approvals til Teams adaptive cards – følger du samme steg i veiledningen.

## Påminnelser om godkjenning

Hvis godkjenningsprosessen er konfigurert til å bruke Approvals, kan påminnelses-eposter sendes til godkjenner(ne). Disse konfigureres i `Provisioning Request Settings`-listen.

![Approval reminder settings screenshot](/Images/ApprovalReminderSettings.png)

Rediger listeelementene og endre verdien etter behov:

- **`EnableApprovalReminderEmails`** – Aktiver eller deaktiver påminnelses-eposter til godkjennerne (`true`/`false`).
- **`DisableApprovalNotifications`** – Deaktiver de innebygde Power Automate-varslene om godkjenning. Nyttig hvis du vil redigere flyten og legge til en egen varselepost.
- **`ApprovalReminderInterval`** – Intervall (i dager) før en påminnelses-epost sendes til godkjennerne.

## Prosess

På et overordnet nivå fungerer `Provisioning Request Approval`-flyten slik:

1. Oppdaterer statusen på bestillingen til `Pending Approval`.
2. Henter innstillinger fra `Provisioning Request Settings`-listen.
3. Sender enten en godkjenningsoppgave til godkjenner(ne) ELLER poster et Teams adaptive card.
4. Venter på godkjenning og sender påminnelser til godkjenner(ne) avhengig av påminnelsesinnstillingene.
5. Sjekker godkjenningsresponsen – oppdaterer bestillingsstatusen til `Approved` eller `Rejected`.
6. Konkatinerer godkjenningskommentarer.
7. Sender epost og adaptive card i Teams til bestilleren for å varsle om utfallet.

Bestillinger som blir `Approved` trigger provisjonering.

Avviste bestillinger kan redigeres av brukere i webdel eller Teams app og sendes inn på nytt.

Som nevnt over kan du redigere godkjenningsflyten. Hvis løsningen oppgraderes i fremtiden, vil imidlertid ikke oppdateringer av godkjenningsflyten anvendes i tenanten din.

## Godkjenning kun av `Public`-områder

Bestillingsportalen kan konfigureres til kun å kreve godkjenning for `Public`-områder. Hvis konfigurert, vil bestillinger satt til `Private` automatisk godkjennes av godkjenningsflyten.

En innstilling i `Provisioning Request Settings` aktiverer/deaktiverer funksjonaliteten.

Oppdater verdien på innstillingen **`EnablePublicSpaceApprovalOnly`** til `true` eller `false`.

Dette er designet for organisasjoner der `Private`-områder anses å ha lavere risiko enn `Public`-områder.

**Merk: Dette alternativet er kanskje ikke tilgjengelig i den installerte versjonen av Bestillingsportalen.** Kjør en [oppgradering](Upgrade.md) (eller re-appliser PnP-malen) — manglende standardinnstillinger, inkludert **`EnablePublicSpaceApprovalOnly`**, opprettes da automatisk med standardverdi uten at eksisterende innstillinger endres. Aktiver eller deaktiver deretter funksjonaliteten ved å sette `Value` på elementet til `true` eller `false` i `Provisioning Request Settings`-listen.
