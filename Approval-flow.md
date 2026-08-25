# Godkjenningsflyt

Bestillingsportalen inkluderer en Azure Logic App (**`ProcessApprovalRequest`**) som håndterer godkjenning av bestillinger opprettet av brukere. Logic Appen deployes av `deploy.ps1` sammen med de øvrige Logic Appene og erstatter Power Automate-flyten `Provisioning Request Approval` som ble brukt i tidligere versjoner (se [Upgrade.md](/Upgrade.md) for migrering).

Godkjenning av bestillinger kan skje på to måter:

- Godkjennings-epost (epost med Approve/Reject-valg sendt til godkjenner(ne) via Office 365 Outlook-connectoren).
- Microsoft Teams Adaptive Card-godkjenning (adaptivt kort postet i en Teams-kanal).

Logic Appen kjører når statusen på en bestilling i **`Provisioning Requests`**-listen endres til **`Submitted`** (brukeren sender inn bestillingen i Bestillingsportalen webdel eller Teams app).

Når du installerer løsningen, sørg for å følge «Steg 1: Konfigurere godkjenningsprosess» i [Konfigurasjonsveiledningen](/Configuration-guide.md) for å sette opp godkjenning. Hvis du vil endre godkjenningsmetoden – f.eks. bytte fra godkjennings-epost til Teams adaptive cards – følger du samme steg i veiledningen.

## Påminnelser om godkjenning

Hvis godkjenningsprosessen er konfigurert til å bruke godkjennings-epost, kan påminnelses-eposter sendes til godkjenner(ne). Disse konfigureres i `Provisioning Request Settings`-listen.

![Approval reminder settings screenshot](/Images/ApprovalReminderSettings.png)

Rediger listeelementene og endre verdien etter behov:

- **`EnableApprovalReminderEmails`** – Aktiver eller deaktiver påminnelses-eposter til godkjennerne (`true`/`false`).
- **`ApprovalReminderInterval`** – Intervall (i dager) før en påminnelses-epost sendes til godkjennerne.
- **`DisableApprovalNotifications`** – *Utgått.* Innstillingen styrte de innebygde varslene fra Power Automate Approvals og har ingen effekt i Logic Appen. Den beholdes i listen for bakoverkompatibilitet.

## Prosess

På et overordnet nivå fungerer `ProcessApprovalRequest`-Logic Appen slik:

1. Henter innstillinger fra `Provisioning Request Settings`-listen (og godkjennere fra `Business Units`-listen hvis forretningsenheter er aktivert).
2. Sender en bekreftelses-epost til bestilleren og oppdaterer statusen på bestillingen til `Pending Approval` (eller godkjenner automatisk, se under).
3. Sender enten en godkjennings-epost med Approve/Reject-valg til godkjenner(ne) ELLER poster et Teams adaptive card i den konfigurerte kanalen.
4. Venter på svar (inntil 60 dager) og sender påminnelses-eposter til godkjenner(ne) avhengig av påminnelsesinnstillingene. Uten svar innen fristen settes statusen tilbake til `Submitted`, og en ny godkjenningsrunde startes automatisk.
5. Sjekker godkjenningsresponsen – oppdaterer bestillingsstatusen til `Approved` eller `Rejected`, med godkjenner og svardato i `Comments` og godkjenneren i `Approver`-kolonnen (se merknad under).
6. Sender epost og adaptive card i Teams til bestilleren for å varsle om utfallet.

Bestillinger som blir `Approved` trigger provisjonering.

Avviste bestillinger kan redigeres av brukere i webdel eller Teams app og sendes inn på nytt.

Du kan redigere Logic Appen i Azure-portalen, men endringer overskrives av neste `deploy.ps1`-kjøring (full eller `-Upgrade`) — varige tilpasninger gjøres i `Source/ARMTemplates/LogicApps/processapprovalrequest.json`.

### Forskjeller mellom de to metodene

- **Godkjennings-epost**: Godkjenneren svarer med Approve/Reject-knappene direkte i eposten (actionable message i Outlook). Første svar avgjør utfallet når flere godkjennere er konfigurert. Eposten har ikke kommentarfelt — trenger dere begrunnelser fra godkjenner, bruk Teams-metoden. Hvem som svarte registreres i `Approver`-kolonnen når svaret kommer via knappene i eposten; svar via fallback-lenken (bl.a. for mottakere utenfor tenanten) registreres uten identitet.
- **Teams adaptive card**: Kortet postes i den konfigurerte kanalen, og alle med tilgang til kanalen kan svare. Godkjenneren kan legge inn en kommentar, og navnet på den som svarte registreres i `Comments` og `Approver`-kolonnen. Private kanaler støttes ikke av Teams-connectoren.

## Godkjenning kun av `Public`-områder

Bestillingsportalen kan konfigureres til kun å kreve godkjenning for `Public`-områder. Hvis konfigurert, vil bestillinger satt til `Private` automatisk godkjennes av godkjenningsprosessen.

En innstilling i `Provisioning Request Settings` aktiverer/deaktiverer funksjonaliteten.

Oppdater verdien på innstillingen **`EnablePublicSpaceApprovalOnly`** til `true` eller `false`.

Dette er designet for organisasjoner der `Private`-områder anses å ha lavere risiko enn `Public`-områder.

**Merk: Dette alternativet er kanskje ikke tilgjengelig i den installerte versjonen av Bestillingsportalen.** Kjør en [oppgradering](Upgrade.md) (eller re-appliser PnP-malen) — manglende standardinnstillinger, inkludert **`EnablePublicSpaceApprovalOnly`**, opprettes da automatisk med standardverdi uten at eksisterende innstillinger endres. Aktiver eller deaktiver deretter funksjonaliteten ved å sette `Value` på elementet til `true` eller `false` i `Provisioning Request Settings`-listen.
