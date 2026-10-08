# Begrense opprettelse av områder utenom Bestillingsportalen

Bestillingsportalen gir navnekonvensjoner, maler, merker og godkjenning – men bare for områder som bestilles gjennom den. Så lenge alle brukere fortsatt kan opprette team, grupper og SharePoint-områder direkte, er portalen den *anbefalte* veien, ikke den *eneste*. Denne veiledningen beskriver hvilke innstillinger i Microsoft 365 som styrer hvem som kan opprette områder, hva de påvirker, og hvordan de kan kombineres.

Bestillingsportalen endrer ingen av disse innstillingene. Det er en beslutning organisasjonen tar for tenanten som helhet, og kodesnuttene under er eksempler på enkeltkommandoer – ikke ferdige skript. Prøv endringene i en testtenant eller med en pilotgruppe først, og les Microsofts dokumentasjon (lenket i hvert avsnitt) før dere tar dem i bruk.

## Kort oppsummert

- Det finnes **ingen innstilling per Bestillingsportalen-installasjon**. Alle mekanismene under gjelder hele tenanten.
- To av dem kan likevel avgrenses med **Entra ID-sikkerhetsgrupper**, så det er ikke et valg mellom «alle» og «ingen».
- **Bestillingsportalen påvirkes ikke**: den oppretter grupper og områder app-only med en managed identity, ikke som bruker (se [Påvirker det Bestillingsportalen?](#påvirker-det-bestillingsportalen)).
- Administratorroller (Global Administrator, SharePoint Administrator, Groups Administrator, Teams Service Administrator m.fl.) kan fortsatt opprette grupper og områder gjennom admin-verktøyene sine.

## Mekanismene

| | Mekanisme | Hva den stopper | Omfang | Lisens |
|--|--|--|--|--|
| **A** | Begrense hvem som kan opprette Microsoft 365-grupper (`EnableGroupCreation` + `GroupCreationAllowedGroupId` i Entra ID) | Alt som oppretter en Microsoft 365-gruppe: Teams, Planner, Outlook-grupper, Viva Engage-fellesskap, gruppetilknyttede SharePoint-teamområder, Power BI (classic), Project for the web | Hele tenanten, med **én** unntaksgruppe | Entra ID P1 (inngår blant annet i Microsoft 365 E3/E5) |
| **B** | «Brukere kan opprette SharePoint-områder» i SharePoint admin center | Kommunikasjonsområder og teamområder uten gruppe, opprettet fra SharePoint, OneDrive, PnP PowerShell og REST | Hele tenanten, av eller på – ingen gruppestyring | Ingen ekstra |
| **C** | Restricted Site Creation (SharePoint Advanced Management) | Oppretting av områder per områdetype (`All`, `SharePoint`, `OneDrive`, `Team`, `Communication`) | Hele tenanten, styrt per sikkerhetsgruppe i *Allow*- eller *Deny*-modus | SharePoint Advanced Management Plan 1 |
| **D** | Teams-policyer for kanaler (*Create private channels*, *Create shared channels*) | Private og delte kanaler – hver av dem får sitt eget SharePoint-område | Per bruker eller gruppe via policytildeling | Ingen ekstra |

**A er den viktigste.** De fleste nye områder kommer fra Teams og grupper, og verken B eller C stopper dem alene: Microsoft skriver at innstillingen i B ikke påvirker om brukere kan opprette team eller Microsoft 365-grupper, og at begrensning av områdeoppretting i C ikke fjerner muligheten til å opprette grupper eller ressurser som bygger på grupper, som Teams.

### A – Begrense hvem som kan opprette Microsoft 365-grupper

Når `EnableGroupCreation` settes til `false`, kan bare medlemmer av sikkerhetsgruppen i `GroupCreationAllowedGroupId` opprette Microsoft 365-grupper. Det slår inn i alle tjenester som bygger på grupper: Outlook, SharePoint, Viva Engage, Teams, Planner, Power BI (classic) og Project for the web.

Verdt å vite:

- Det kan bare være **én** unntaksgruppe i tenanten, men andre grupper kan nøstes inn i den.
- Personene legges inn som **medlemmer** av unntaksgruppen, ikke eiere. De trenger ikke være eiere av noe område eller ha noen administratorrolle.
- Administratorer i rollene Microsoft lister opp (blant annet Global Administrator, SharePoint Administrator, Groups Administrator, Teams Service Administrator, Exchange Administrator og User Administrator) beholder muligheten gjennom sine admin-verktøy, og trenger ikke være med i gruppen. Global Administrator kan for eksempel opprette grupper fra Microsoft 365 admin center, Planner, Exchange og SharePoint, men ikke fra Teams.
- Innstillingen gjelder brukere og påvirker ikke service principals.
- Det kan ta opptil 15 minutter før endringen slår inn.
- Administratoren som konfigurerer innstillingen og medlemmene av unntaksgruppen trenger Entra ID P1.
- Ikke forveksle med bryteren «Users can create Microsoft 365 groups in Azure portals, API or PowerShell» under *Groups → General* i Entra admin center. Den styrer oppretting fra Azure-portalen, API og PowerShell, og er ikke det samme som `EnableGroupCreation`.

Innstillingen finnes ikke i noe admin-grensesnitt og settes med Microsoft Graph PowerShell (Beta-modulen, som Microsoft bruker i sin veiledning). Les gjeldende verdier først – `Group.Unified` kan også inneholde navnepolicy, gjesteinnstillinger og annet som skal beholdes:

```powershell
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Group.Read.All"
$setting = Get-MgBetaDirectorySetting | Where-Object DisplayName -eq "Group.Unified"
$setting.Values | Format-Table Name, Value
```

Finnes det ikke noe `Group.Unified`-objekt fra før, må det opprettes fra malen `62375ab9-6b52-47ed-826b-58e47e0e304b` – se Microsofts veiledning. Finnes det, endres de to verdiene og hele samlingen sendes tilbake, slik at de andre verdiene står urørt:

```powershell
$values = $setting.Values | ForEach-Object { @{ name = $_.Name; value = $_.Value } }
($values | Where-Object name -eq "EnableGroupCreation").value = "false"
($values | Where-Object name -eq "GroupCreationAllowedGroupId").value = "<objectId til unntaksgruppen>"
Update-MgBetaDirectorySetting -DirectorySettingId $setting.Id -BodyParameter @{ values = $values }
```

For å teste kan en bruker utenfor unntaksgruppen prøve å opprette en plan i Planner. Microsoft beskriver at brukeren da skal få beskjed om at oppretting av planer og grupper er deaktivert. For å oppheve begrensningen settes `EnableGroupCreation` tilbake til `true`.

Kilde: [Manage who can create Microsoft 365 Groups](https://learn.microsoft.com/en-us/microsoft-365/solutions/manage-creation-of-groups), [Overview of group settings](https://learn.microsoft.com/en-us/graph/group-directory-settings), [Set up self-service group management](https://learn.microsoft.com/en-us/entra/identity/users/groups-self-service-management)

### B – «Brukere kan opprette SharePoint-områder»

SharePoint admin center → **Innstillinger** → **Områdeoppretting** → **Brukere kan opprette SharePoint-områder**. Innstillingen styrer om brukere kan opprette områder fra SharePoint, OneDrive, PnP PowerShell og REST API. Den er av eller på for alle; det finnes ingen unntaksgruppe.

Den påvirker ikke om brukere kan opprette team eller Microsoft 365-grupper med tilhørende områder – det styres av A. Slått av alene fjerner den altså «Opprett område»-knappen i SharePoint, men et nytt team gir fortsatt et nytt område.

Kilde: [Manage site creation in SharePoint](https://learn.microsoft.com/en-us/sharepoint/manage-site-creation)

### C – Restricted Site Creation

Restricted Site Creation er en del av SharePoint Advanced Management og lar administratoren bestemme hvilke sikkerhetsgrupper som kan (Allow) eller ikke kan (Deny) opprette OneDrive- og SharePoint-områder, per områdetype.

Verdt å vite:

- Krever **SharePoint Advanced Management Plan 1**. Ifølge Microsofts oversikt er Restricted Site Creation den SAM-funksjonen som *ikke* følger med Microsoft 365 Copilot-lisensen.
- Krever SharePoint Online Management Shell 16.0.25513.12000 (november 2024) eller nyere.
- Når funksjonen slås på, starter den i Deny-modus uten policyer og påvirker ingen før policyer legges til.
- Modusen gjelder alle områdetyper samlet. Bytte av modus sletter alle eksisterende policyer.
- Opptil 10 sikkerhetsgrupper per områdetype, angitt med objekt-ID. Bare Entra ID-sikkerhetsgrupper støttes.
- **Områdetypen `All` omfatter OneDrive.** Brukes `All` i Allow-modus, risikerer brukere utenfor gruppene å ikke få OneDrive. Bruk `SharePoint` (eller `Team` og `Communication`) når målet er samarbeidsområder.
- Policyene styrer bare oppretting, ikke tilgang til eksisterende områder.
- Ikke tilgjengelig i offentlige skyer (GCC, GCC High, DoD, 21Vianet).

Eksempel på en Allow-policy for SharePoint-områder:

```powershell
Connect-SPOService -Url https://<tenant>-admin.sharepoint.com
Set-SPORestrictedSiteCreation -Enabled $true -Mode Allow
Set-SPORestrictedSiteCreation -SiteType SharePoint -RestrictedSiteCreationGroups "<objectId>"
Get-SPORestrictedSiteCreation
```

En policy for en områdetype fjernes ved å sende `""` som `-RestrictedSiteCreationGroups`. Kontroller parameternavnene mot cmdlet-referansen før bruk.

Kilde: [Restrict OneDrive and SharePoint site creation by users](https://learn.microsoft.com/en-us/sharepoint/restricted-site-creation), [Set-SPORestrictedSiteCreation](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/set-sporestrictedsitecreation), [SharePoint Advanced Management overview](https://learn.microsoft.com/en-us/sharepoint/advanced-management), [SAM features in Microsoft Copilot licenses](https://learn.microsoft.com/en-us/sharepoint/sharepoint-advanced-management-features-copilot-license)

### D – Private og delte kanaler i Teams

Hver private og delte kanal får sitt eget SharePoint-område. Det styres ikke av A–C, men av Teams-policyer: Teams admin center → **Teams** → **Teams policies** → *Create private channels* og *Create shared channels*. Begge er på som standard.

- Private kanaler kan som standard opprettes av både eiere og medlemmer av teamet. Eieren kan skru av muligheten for medlemmer i teamets innstillinger.
- Delte kanaler kan bare opprettes av teameiere.
- Policyer tildeles per bruker eller gruppe, og endringer kan ta opptil 24 timer.

Kilde: [Manage channel policies in Microsoft Teams](https://learn.microsoft.com/en-us/microsoftteams/teams-policies), [Private channels in Microsoft Teams](https://learn.microsoft.com/en-us/microsoftteams/private-channels), [Shared channels in Microsoft Teams](https://learn.microsoft.com/en-us/microsoftteams/shared-channels)

### Undermiljøer

Klassiske undermiljøer (subsites) styres separat, under de klassiske innstillingene i SharePoint admin center. Se [Manage site creation in SharePoint](https://learn.microsoft.com/en-us/sharepoint/manage-site-creation).

## Påvirker det Bestillingsportalen?

Nei, med ett forbehold.

- **A** gjelder brukere, ikke service principals. Bestillingsportalens Logic Apps oppretter grupper og Viva Engage-fellesskap med en user-assigned managed identity, som er en service principal.
- **B** og **C** styrer hva *brukere* kan opprette. Bestillingsportalen oppretter områder app-only (`POST /_api/SPSiteManager/create` med `Sites.FullControl.All`, se [Datatilgang og sikkerhet](./Data-access-security.md)). Microsoft dokumenterer ikke app-only-kall eksplisitt for disse to innstillingene, så bekreft med en testbestilling etter at de er slått på.
- **Forbeholdet:** Microsoft har også *Restricted Site Creation for apps* (`Set-SPORestrictedSiteCreationForApps`, i forhåndsversjon, krever SharePoint Advanced Management Plan 1). Den gjelder apper som ikke er fra Microsoft. Slås den på i Allow-modus, må app-ID-en til Bestillingsportalens managed identity være med på listen, ellers stopper provisjoneringen. Se [Restrict OneDrive and SharePoint site creation by apps](https://learn.microsoft.com/en-us/sharepoint/restricted-site-creation-by-apps).

## Anbefalt fremgangsmåte

1. **Opprett en sikkerhetsgruppe**, for eksempel «M365 Områdeopprettere», med de få som skal kunne opprette direkte – typisk M365-forvaltning eller IT. Hold den liten: områder disse oppretter, går utenom navnekonvensjoner, maler og godkjenning.
2. **Slå av B.** Liten konsekvens for de fleste brukere, og fjerner «Opprett område»-knappen.
3. **Slå på A** med sikkerhetsgruppen som unntak. Her kommer den reelle effekten, siden Teams er den største kilden til nye områder.
4. **Vurder D** hvis private og delte kanaler også skal styres.
5. **Valgfritt: C**, hvis dere har SharePoint Advanced Management og vil ha finere styring per områdetype, for eksempel at unntaksgruppen også kan opprette kommunikasjonsområder selv.
6. **Fortell brukerne** at nye områder bestilles i Bestillingsportalen, og gjør appen lett å finne i Teams.

### Hvis dere ikke vil stenge

Velger dere å la oppretting være åpen, kan noe av styringen tas igjen i etterkant: navnepolicy og utløpspolicy for grupper i Entra ID, policyer for inaktive områder og områdeeierskap i SharePoint Advanced Management (følger med Microsoft 365 Copilot-lisensen), sensitivitetsetiketter med container-innstillinger, og jevnlig gjennomgang av nye grupper. Områder opprettet utenom portalen får likevel ikke Bestillingsportalens maler, merker og godkjenning.

Vil dere avgrense til en del av organisasjonen først, kan C i Deny-modus rettes mot én eller flere sikkerhetsgrupper (for eksempel en dynamisk gruppe for en avdeling) uten å berøre resten. A kan ikke avgrenses slik – den gjelder alle utenom unntaksgruppen.

## Roller og rettigheter

Tabellen viser hvem som kan gjøre hva når A og B er slått på, og kan brukes i opplæring.

| Rolle | Opprette nye områder, team og grupper | I et eksisterende område eller team |
|--|--|--|
| **Ansatt** | Bestiller gjennom Bestillingsportalen, og blir eier når bestillingen er godkjent og provisjonert. Kan ikke opprette direkte | Avhenger av rollen på området, se under |
| **Medlem av unntaksgruppen** | Kan opprette direkte i Teams, SharePoint, Planner osv. | Som andre |
| **Godkjenner i Bestillingsportalen** | Godkjenner eller avviser bestillinger i Teams (Approvals). Ingen egen rett til å opprette | – |
| **Eier av område eller team** | Kan ikke opprette nye områder bare fordi hen er eier. Kan opprette private og delte kanaler hvis Teams-policyen tillater det | Administrerer medlemmer, eiere, innstillinger og deling innenfor tenantens grenser. Undermiljøer hvis det ikke er slått av |
| **Medlem av område eller team** | Kan opprette private kanaler hvis policyen tillater det og eieren ikke har skrudd det av. Kan ikke opprette delte kanaler | Redigerer innhold og oppretter standardkanaler, med mindre eieren har skrudd det av |
| **Besøkende** | Nei | Lesetilgang |
| **Administratorroller** | Ja, gjennom admin-verktøyene, uavhengig av unntaksgruppen | Full administrasjon |
| **Bestillingsportalen (managed identity)** | Ja, app-only. Påvirkes ikke av A og B | – |

## Kilder

- [Manage who can create Microsoft 365 Groups](https://learn.microsoft.com/en-us/microsoft-365/solutions/manage-creation-of-groups)
- [Overview of group settings (Microsoft Graph)](https://learn.microsoft.com/en-us/graph/group-directory-settings)
- [Set up self-service group management](https://learn.microsoft.com/en-us/entra/identity/users/groups-self-service-management)
- [Manage site creation in SharePoint](https://learn.microsoft.com/en-us/sharepoint/manage-site-creation)
- [Restrict OneDrive and SharePoint site creation by users](https://learn.microsoft.com/en-us/sharepoint/restricted-site-creation)
- [Set-SPORestrictedSiteCreation](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/set-sporestrictedsitecreation)
- [Restrict OneDrive and SharePoint site creation by apps](https://learn.microsoft.com/en-us/sharepoint/restricted-site-creation-by-apps)
- [SharePoint Advanced Management overview](https://learn.microsoft.com/en-us/sharepoint/advanced-management)
- [SharePoint Advanced Management features in Microsoft Copilot licenses](https://learn.microsoft.com/en-us/sharepoint/sharepoint-advanced-management-features-copilot-license)
- [Manage channel policies in Microsoft Teams](https://learn.microsoft.com/en-us/microsoftteams/teams-policies)
- [Private channels in Microsoft Teams](https://learn.microsoft.com/en-us/microsoftteams/private-channels)
- [Shared channels in Microsoft Teams](https://learn.microsoft.com/en-us/microsoftteams/shared-channels)
