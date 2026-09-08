# Sikkerhet

> **English:** Please do not report security vulnerabilities through public GitHub issues. Use GitHub's private vulnerability reporting (the **Security** tab → **Report a vulnerability**) for this repository. The rest of this document is in Norwegian.

## Rapportere en sårbarhet

Har du funnet en sårbarhet i Bestillingsportalen, **ikke opprett et offentlig issue**. Bruk GitHubs private sårbarhetsrapportering: gå til **Security**-fanen i dette repoet og velg **Report a vulnerability**. Rapporten er da kun synlig for vedlikeholderne.

Ta med det som trengs for å reprodusere funnet:

- Hvilken komponent det gjelder (installasjonsskript, Logic App, runbook, SPFx-webdel, Power Automate-flyt, PnP-mal)
- Hvilken versjon (`VERSION` i repo-rot, eller versjonen som vises i miljøet – se [Upgrade.md](./Upgrade.md#hvilken-versjon-kjører-miljøet))
- Steg for å reprodusere, og hva konsekvensen er
- Eventuelt forslag til utbedring

Vi bekrefter mottak, holder deg oppdatert underveis og krediterer deg i endringsloggen når rettelsen publiseres, om du ønsker det.

## Hvilke versjoner får sikkerhetsrettelser

| Versjon | Støttes |
| --- | --- |
| Siste 1.x | Ja |
| Eldre 1.x | Oppgrader til siste versjon med `deploy.ps1 -Upgrade` – se [Oppgraderingsveiledningen](./Upgrade.md) |
| Før 1.0 (client secret, Key Vault, sertifikat) | Nei – se [Oppgradere fra versjoner før 1.0](./Upgrade-from-pre-1.0.md) |

## Hva som er relevant å rapportere

Bestillingsportalen kjører i sin helhet i din egen Azure- og Microsoft 365-tenant, og har ingen hemmeligheter i drift: Logic Apps og runbooks autentiserer med managed identities. Løsningen tildeles likevel et sett API-tillatelser med høyt privilegienivå (blant annet `Sites.FullControl.All` og `Group.ReadWrite.All`), dokumentert i [Datatilgang og sikkerhet](./Data-access-security.md). Funn som er særlig relevante:

- Muligheter for at en vanlig bruker kan bestille, godkjenne eller endre noe utenfor sin egen rolle (for eksempel omgå godkjenning, eller invitere gjester med eierrettigheter)
- Injeksjon via brukerstyrte felt i bestillinger eller gjesteforespørsler som ender i Graph-, SharePoint- eller PowerShell-kall
- Tillatelser løsningen ber om, men ikke bruker
- Svakheter i installasjonsskriptene som kan eksponere tenant-informasjon eller gi feil identitet tilgang

Spørsmål om herding og tilgangsstyring som ikke er sårbarheter, kan tas som vanlige issues.
