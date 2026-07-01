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

Application permissions brukes gjennom en Entra ID app registration. Secret-en for Entra ID-appen lagres i en Key Vault.

Provisjonering og andre automatiseringsoppgaver løses gjennom Azure Logic Apps, som gir lav kjøretidkostnad og mulighet til å sikre tilgang til alle ressurser.

For mer detaljer om arkitekturen, les [Arkitektur](Architecture.md)-dokumentasjonen.

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

---

| [Installasjonsveiledning](/Deployment-guide.md) | [Oppgraderingsveiledning](/Upgrade.md) | [Arkitektur](/Architecture.md) | [Datalagre](/Data-stores.md) | [Kostnadsestimater](/Cost-estimates.md) | [Datatilgang og sikkerhet](/Data-access-security.md) | [Navnekonvensjoner](/Naming-conventions.md) | [Forretningsenheter](/Business-units.md) | [Provisioning Types](/Provisioning-types.md) | [Site Templates](/Site-templates.md) | [Sensitivitetsmerker](/Sensitivity-labels.md) | [Teams Templates](/Teams-templates.md) | [PnP Templates](/PnP-templates.md) | [Oppbevaringsmerker](/Retention-labels.md) | [Godkjenningsflyt](/Approval-flow.md) | [Regionale innstillinger](/Regional-settings.md) | [Fornye App Secret](/Refreshing-app-secret.md) | [Feilhåndtering](/Error-handling.md) |
| ----------------------------------------------- | -------------------------------------- | ------------------------------ | ---------------------------- | --------------------------------------- | ---------------------------------------------------- | ------------------------------------------- | ---------------------------------------- | -------------------------------------------- | ------------------------------------ | --------------------------------------------- | -------------------------------------- | ---------------------------------- | ------------------------------------------ | ------------------------------------- | ------------------------------------------------ | ---------------------------------------------- | ------------------------------------ |