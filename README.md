<p align="center">
  <img src="Images/bp_logo.png" alt="Bestillingsportalen logo" width="80" />
  <br />
  <strong style="font-size: 2em;">Bestillingsportalen</strong>
</p>

Bestillingsportalen er en Azure-basert løsning som gir et alternativ til selvbetjent opprettelse av samarbeidsområder i Microsoft 365. Den gir styring over prosessen gjennom en SPFx Teams app som lar brukere bestille samarbeidsområder (Teams, Groups, SharePoint Online-områder og Viva Engage-fellesskap), med bakenforliggende Azure-komponenter som sørger for automatisk provisjonering. Bestillingsportalen kan brukes som del av en Copilot for Microsoft 365-utrulling for å etablere styring over selvbetjening.

![Bestillingsportalen](/Images/bp_app.png)

## Funksjonalitet

Bestillingsportalen tilbyr følgende:

- SPFx-basert Bestillingsportalen webdel og Teams app som lar brukere bestille samarbeidsområder.
- Konfigurerbar godkjenningsprosess via Power Automate.
- SharePoint-område med støttelister som utgjør backenden for løsningen.
- Dashboard for bestillere som viser tidligere og pågående bestillinger med godkjenningsstatus.
- Automatisert provisjonering via Azure Logic Apps og Azure Automation.
- Selvbetjent invitasjon av eksterne gjester via `InviteGuests`-webdelen (SPFx 1.22, Fluent UI v9) som kan plasseres på et hvilket som helst SharePoint-område. Invitasjoner skrives til `Guest Requests`-listen og prosesseres av `ProcessGuestRequest` Logic App.

## Arkitektur

Løsningen bruker Microsoft Graph og SharePoint REST API-ene for provisjonering. Azure Runbooks brukes sammen med PnP PowerShell for oppgaver som ikke kan utføres via Graph API.

Logic Apps autentiserer mot Microsoft Graph, SharePoint REST og Azure Automation med en user-assigned managed identity, og runbookene med Automation-kontoens systemtildelte identity. **Løsningen har ingen client secret, ingen Key Vault og ingen egen Entra ID-app-registrering i drift** – ingenting som må fornyes eller kan lekke. Se [Migrering til managed identity](Managed-identity-migration.md) for bakgrunn.

> **Om tilganger:** Løsningen tildeles et minimert sett API-tillatelser der hver tillatelse er knyttet til konkrete kjøretidskall – se [Datatilgang og sikkerhet](Data-access-security.md) for den fulle koblingen. Merk at noen av tillatelsene kun er i bruk av **valgfri funksjonalitet**: gjesteinvitasjon (`User.Invite.All`, `User.ReadWrite.All`), Viva Engage-fellesskap (`Community.ReadWrite.All`) og sensitivitetsmerker (`InformationProtectionPolicy.Read.All`). Organisasjoner som ikke bruker disse funksjonene kan stramme inn ytterligere – se merknaden om funksjonsbundne tillatelser i sikkerhetsdokumentet.

Provisjonering og andre automatiseringsoppgaver løses gjennom Azure Logic Apps, som gir lav kjøretidkostnad og mulighet til å sikre tilgang til alle ressurser.

For arkitekturdiagrammer og en samlet oversikt over hva som installeres og hvilke tilganger som kreves – både for installasjon og for løsningen i drift – se [Teknisk løsningsbeskrivelse](Teknisk-losningsbeskrivelse.md).

## Kom i gang

For å komme i gang med en ny installasjon, følg [Installasjonsveiledningen](Deployment-guide.md).

## Oppgradering

Hvis du har en eksisterende Bestillingsportalen-installasjon og vil oppgradere til nyeste versjon, se [Oppgraderingsveiledningen](Upgrade.md) for detaljerte instruksjoner om hvordan du oppgraderer uten å miste data.

## Feil og problemer

Rapporter eventuelle problemer ved å opprette et [issue](https://github.com/Puzzlepart/bestillingsportalen/issues/new).

## Bidra

Vi elsker å motta bidrag.

Se våre [retningslinjer for bidrag](/CONTRIBUTING.md) for hvordan du kan bidra.

Hvis du ønsker å bli involvert i å videreutvikle Bestillingsportalen – enten det er å foreslå ny funksjonalitet, oppdatere dokumentasjonen eller fikse bugs – vil vi gjerne høre fra deg.

## Lisens

Bestillingsportalen er lisensiert under [MIT-lisensen](/LICENSE) © SoftwareOne. Løsningen er basert på [Provision Assist](https://github.com/pnp/provision-assist-m365) fra Microsoft 365 & Power Platform Community (PnP), også MIT-lisensiert – opphavsnotisen deres er beholdt i lisensfila.

---

| [Teknisk løsningsbeskrivelse](/Teknisk-losningsbeskrivelse.md) | [Installasjonsveiledning](/Deployment-guide.md) | [Oppgraderingsveiledning](/Upgrade.md) | [Managed identity](/Managed-identity-migration.md) | [Datalagre](/Data-stores.md) | [Datatilgang og sikkerhet](/Data-access-security.md) | [Navnekonvensjoner](/Naming-conventions.md) | [Forretningsenheter](/Business-units.md) | [Provisioning Types](/Provisioning-types.md) | [Site Templates](/Site-templates.md) | [Sensitivitetsmerker](/Sensitivity-labels.md) | [Teams Templates](/Teams-templates.md) | [PnP Templates](/PnP-templates.md) | [Oppbevaringsmerker](/Retention-labels.md) | [Godkjenningsflyt](/Approval-flow.md) | [Regionale innstillinger](/Regional-settings.md) | [Feilhåndtering](/Error-handling.md) |
| ----------------------------------------------- | ----------------------------------------------- | -------------------------------------- | ---------------------------- | ---------------------------- | ---------------------------------------------------- | ------------------------------------------- | ---------------------------------------- | -------------------------------------------- | ------------------------------------ | --------------------------------------------- | -------------------------------------- | ---------------------------------- | ------------------------------------------ | ------------------------------------- | ------------------------------------------------ | ------------------------------------ |
