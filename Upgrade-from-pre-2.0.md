# Oppgradere fra versjoner før 2.0 (pre managed identity)

[Oppgraderingsveiledningen](Upgrade.md) dekker normaltilfellet: et miljø som allerede står på 2.0 eller nyere, og som oppgraderes med `./deploy.ps1 -Upgrade`. Denne veiledningen dekker det ene tilfellet den bare nevner i en setning — et **produksjonsmiljø installert før managed identity-migreringen**, som fortsatt kjører på Key Vault, client secret og sertifikat.

Slike miljøer kan **ikke** oppgraderes med `-Upgrade`. Oppgraderingsmodus deployer ikke `azureresources.bicep`, og stopper derfor med:

```text
User-assigned managed identity 'bestillingsportalen-uami' was not found in resource group '<rg>'.
Run a full deployment (without -Upgrade) once to migrate to managed identity before using upgrade mode.
```

Rekkefølgen er altså: **én full `deploy.ps1` nå, `-Upgrade` ved senere oppgraderinger.** Alt i [Upgrade.md](Upgrade.md) gjelder i tillegg til dette dokumentet — særlig avsnittene om listedata, den interaktive template-prompten og tilbakerulling.

## Er miljøet pre-2.0?

Sjekk noen av disse — én av dem er nok:

| Signal | Hvor |
|--|--|
| Key Vault med secretene `appid`, `appSecret`, `sausername`, `sapassword` | Ressursgruppa |
| API-tilkobling som slutter på `-kv` (seks tilkoblinger i alt, ikke fem) | Ressursgruppa |
| **Ingen** user-assigned managed identity i ressursgruppa | Ressursgruppa |
| Logic App-ene har HTTP-actions med `authentication.type = ActiveDirectoryOAuth` og `pfx` fra Key Vault | Logic App → Code view |
| Radene `InstalledVersion` / `InstalledDate` mangler i `Provisioning Request Settings`, og ressursgruppa mangler taggen `BestillingsportalenVersion` | SharePoint / Azure |
| Ingen `Guest Requests`-liste på området | SharePoint |
| Automation-kontoen har modulene `Az.Accounts` 1.6.2 og `PnP.PowerShell` 2.4.0, og runbookene er `PowerShell72` uten runtime environment | Automation-kontoen |
| `parameters.json` har `appName`, `keyVaultName`, `certName`, `enableSensitivity` | Installasjonsfilene |

### Symptomet som ofte utløser oppgraderingen

Logic App-ene begynner plutselig å feile med `AADSTS700027` — «The certificate with identifier used to sign the client assertion is not registered on application… The key was not found». Årsaken er ikke at sertifikatet er utløpt: Key Vault-sertifikatet ble opprettet av `az ad app credential reset --create-cert --keyvault`, som setter en policy med `AutoRenew` 90 dager før utløp. Key Vault fornyer sertifikatet med et **nytt tumbavtrykk**, uten å oppdatere app-registreringen. Logic App-ene henter siste secret-versjon og signerer med en nøkkel Entra ID aldri har sett.

Oppgraderingen fjerner årsaken permanent — det finnes ikke noe sertifikat i 2.0. **Trenger du produksjon opp før oppgraderingsvinduet**, last ned gjeldende sertifikat fra Key Vault og last opp den offentlige nøkkelen på app-registreringen (App registration → Certificates & secrets → Upload certificate):

```bash
az keyvault certificate download --vault-name <keyVaultName> --name <certName> --file bp-cert.cer --encoding DER
```

Det tar ti minutter, påvirker ikke oppgraderingen, og gir deg et fungerende miljø å rulle tilbake til.

## Er en full deploy trygg mot et miljø i produksjon?

Ja, fra 2.0 — men det var det ikke før, og det er derfor det er verdt å si eksplisitt:

- **Listedata røres ikke.** Standardelementene seedes nå av PnP-malens `<pnp:DataRows>` med `UpdateBehavior="Skip"`. Den gamle destruktive Excel-reseedingen (som slettet og gjenopprettet Settings, Provisioning Types, Teams Templates, Time Zones og Locales i fresh-modus) er borte. Bestillingsdata har aldri vært berørt.
- **Navigasjon** nullstilles derimot i full modus (`-ClearNavigation` brukes ikke bare i upgrade-modus). Har området egendefinerte nav-lenker, ta et skjermbilde først.
- **Bilder og ikoner** i `SiteAssets` lastes opp på nytt fra pakken i full modus (`UploadAssets`) — egne bilder med samme filnavn overskrives.
- **Runbook-innhold overskrives fra repoet.** Dette er den største risikoen — se punkt 4 under.

## 1. Kartlegg miljøet før du gjør noe

Dette steget avgjør om oppgraderingen blir en ren in-place-oppgradering eller får et halehode av gamle ressurser. Ikke hopp over det.

```bash
az group show -n <rg> --query "{location:location, tags:tags}"
```

```bash
az resource list -g <rg> -o table
```

**1. Ressursnavn-generasjonen.** Repoet har hatt to navnegenerasjoner: `provisionassist-*` (upstream) og `bestillingsportalen-*` (etter rebrandingen). Automation-konto-navnet er **hardkodet** i [deploy.ps1:184](Source/Scripts/deploy.ps1#L184) (`bestillingsportalen-auto`), og API-tilkoblingsnavnene i [apiconnections.json](Source/ARMTemplates/LogicApps/apiconnections.json).

| Miljøet har | Konsekvens |
|--|--|
| `bestillingsportalen-*` | Rene in-place-oppdateringer. Ingenting dupliseres. |
| `provisionassist-*` | Ny Automation-konto og nye API-tilkoblinger opprettes ved siden av de gamle. Logic App-navnene er identiske i begge generasjoner og oppdateres uansett in-place. Funksjonelt greit — men du må autorisere alle tilkoblingene på nytt, og rydde bort den gamle Automation-kontoen og de gamle tilkoblingene etterpå. |

**2. Regionen.** `region` i parameterfila må matche regionen de eksisterende ressursene faktisk står i. En Logic App kan ikke flyttes: en redeploy med annen `location` feiler.

**3. Områdets faktiske URL.** `requestsSiteAlias` er ny i 2.0 og bestemmer URL-en kjøringen peker på. Standardverdien er `bestillingsportalen`, fordi Teams-appen har URL-en `/<managedPath>/bestillingsportalen` hardkodet — noe et pre-2.0-miljø i drift normalt allerede oppfyller. Sjekk likevel:

- Området ligger på `/sites/bestillingsportalen` → standardverdien er riktig (det samme er en tom verdi, siden aliaset da utledes fra `requestsSiteName`).
- Området ligger et annet sted (typisk etter en URL-endring i SharePoint admin center) → sett `requestsSiteAlias` til **siste segment i den faktiske URL-en**. Merk at gruppens `mailNickname` ikke endres ved en URL-endring, så alias og gruppe-alias kan avvike — det er URL-segmentet som gjelder her. Ligger området et annet sted enn `/sites/bestillingsportalen`, virker webdelen (URL-en er en property), men Teams-appen finner ikke listene.

Alias-sjekken i pre-flight hopper over seg selv når området allerede finnes på den beregnede URL-en, så en kollisjon med tjenestekontoen blokkerer ikke en oppgradering.

**4. Runbook-innholdet — eksporter det nå.** I pre-2.0 ble `ConfigureSpace` og `GetSiteTemplates` limt inn manuelt i portalen. Fra 2.0 lastes innholdet opp fra `Source/Runbooks/` og publiseres ved **hver** deploy og oppgradering. Alle portal-side endringer forsvinner.

```bash
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Automation/automationAccounts/<aa>/runbooks/ConfigureSpace/content?api-version=2023-11-01" > ConfigureSpace.prod.ps1
```

Gjenta for `GetSiteTemplates`, diff mot `Source/Runbooks/`, og flytt eventuelle kundetilpasninger til `CustomerSpecific`-runbooken (opprettes tom av deployen og overskrives aldri).

**5. Logic App-tilpasninger.** Er noen av Logic App-ene redigert i portalen, blir endringene overskrevet. Hent ut definisjonene (Logic App → Code view, eller `az rest`) som referanse før du kjører.

**6. Listedata og innstillinger.** Eksporter `Provisioning Request Settings`, `Provisioning Types` (med bilder/ikoner), `Site Templates`, `Hub Sites`, `Teams Templates` og `Business Units`. Merk deg to ting spesielt:

- Standardelementer som bevisst er **slettet** kommer tilbake ved oppgradering (sett heller `Allowed`/`Enabled` til `false`).
- Standardelementer som er **omdøpt** blir duplikater, fordi `Title` er nøkkelen (`TimeZoneId` for Time Zones).

**7. Godkjenningsflyten.** Ta en eksportkopi av `Provisioning Request Approval`, men **ikke** importer solution-pakken over en flyt som virker — den kjørende flyten beholdes uendret gjennom oppgraderingen.

## 2. Tilganger

Oppgraderingen trenger mer enn Application Administrator. Fordelt på de to plattformene:

| Behov | Rolle | Merknad |
|--|--|--|
| Opprette managed identity, oppdatere Automation/Logic Apps, og **opprette RBAC-tildelinger** (`azureresources.bicep` gir UAMI-en Automation Job/Runbook Operator) | **Owner** på ressursgruppen, ev. Contributor + **User Access Administrator** | Azure RBAC, ikke Entra. Application Administrator dekker ikke dette. Er rollen PIM-basert: **aktiver den før du kjører** — pre-flight sjekker `Microsoft.Authorization/roleAssignments/write`. |
| Tildele app-roller til de to managed identityene (Graph + SharePoint Online) | **Global Administrator**, ev. **Privileged Role Administrator + Cloud Application Administrator** | **Application Administrator er ikke nok** — den kan ikke gi application permissions på Microsoft Graph, og `CheckAppRoleRights` i pre-flight godtar kun GA eller PRA+CAA. |
| Registrere resource providers | Rettigheter på **abonnementsnivå** | `Microsoft.ManagedIdentity` er ny for pre-2.0-miljøer og er sannsynligvis **ikke** registrert. Pre-flight registrerer den hvis kontoen har rettigheter, ellers skriver den ut kommandoene en abonnementsadministrator må kjøre. |
| Området, app-katalogen, tenant-innstillinger | **SharePoint Administrator** | Site collection admin på Bestillingsportalen-området gis automatisk av skriptet til kontoen som kjører. |
| Power Platform | **Power Platform Administrator** | Kun hvis flyten skal (re)importeres eller tjenestekontoen mangler System Customizer. Ikke nødvendig når flyten allerede finnes og virker. |

**Har du ikke GA:** kjør med `-SkipAppRoles`. Alt annet installeres, og skriptet skriver ut en ferdig kommando med object-ID-ene fylt inn. Send `Source/Scripts/AssignPermissionsToManagedIdentity.ps1` og kommandoen til en Global Administrator. **Logic App-ene får 401/403 til den er kjørt** — planlegg dette inn i vinduet, ikke etterpå.

## 3. Parameterfila

Bygg en ny fil fra `parameters.template.json` og kopier verdiene fra den gamle. `GenerateParameters.ps1` kan brukes, men den fyller feltene med standardverdier fra malen — gå gjennom resultatet mot det eksisterende miljøet før du kjører, særlig `requestsSiteAlias`, `region` og `managedPath`.

| Gammel nøkkel | Status i 2.0 |
|--|--|
| `appName`, `keyVaultName` | **Fjernet** — leses ikke lenger |
| `certName`, `createSelfSignedCert`, `certValidityDays` | **Fjernet** — det finnes ikke noe sertifikat |
| `enableSensitivity` | **Fjernet** — bryteren er raden `EnableSensitivityLabels` i innstillinger-lista |
| `fullTenantName` | **Ny, påkrevd** (`<kunde>.onmicrosoft.com`) |
| `pnpAppId` | **Ny, påkrevd** — Prosjektportalens PnP-app er standardverdi |
| `uamiName` | **Ny, valgfri** — standard `bestillingsportalen-uami` |
| `requestsSiteAlias` | **Ny** — standard `bestillingsportalen` (URL-en Teams-appen har hardkodet). Verifiser mot områdets faktiske URL, se punkt 3 i kartleggingen. Feil verdi = deployen peker på et annet område |
| Resten (`tenantId`, `spoTenantName`, `subscriptionId`, `region`, `resourceGroupName`, `managedPath`, `requestsSiteName`, `requestsSiteDesc`, `serviceAccountUPN`, `siteLogoPath`, `isEdu`, `skipApplySPOTemplate`) | Uendret — verifiser at verdiene fortsatt stemmer |

Bruk `-ParametersPath` hvis fila heter noe annet enn `parameters.json` (f.eks. én fil per kunde).

Sjekk også at `VERSION` finnes i repo-rot og inneholder versjonsnummeret — mangler den, blir versjonsstemplingen i miljøet stående som `unknown`.

## 4. Kjøreplan

Alt kjøres fra `Source/Scripts` i PowerShell 7.4+, i et **nytt** PowerShell-vindu (Az/PnP-assemblykonflikten kan ikke repareres i en økt der Az allerede er lastet).

**Steg 1 — pre-flight, uten å endre noe.**

```powershell
./deploy.ps1 -ParametersPath parameters-innlandet.json -Preflight
```

Fiks alt som står `MISSING`. `WARNING` på app-rolle-rettigheter er forventet uten aktiv GA — da planlegger du `-SkipAppRoles`.

**Steg 2 — varsle brukerne.** Regn 30–60 minutter for skriptet, pluss autorisering av tilkoblinger. Bestillinger som sendes inn i vinduet kan feile mens Logic App-ene byttes ut — be brukerne vente.

**Steg 3 — full deploy.**

```powershell
./deploy.ps1 -ParametersPath parameters-innlandet.json -SkipCreateResourceGroup
```

Legg til `-SkipAppRoles` hvis du ikke har GA, og `-SkipSPFxDeploy` hvis Node.js/app-katalog ikke er klart (SPFx kan deployes senere med `-Upgrade`).

- **Ikke bruk `-Force`** her: den svarer *nei* på template-prompten, og skjemaet må oppdateres.
- Svar **`y`** på «Site already exists» — `Guest Requests`-lista og de nye feltene kommer med malen. Eksisterende listeelementer beholdes.

**Steg 4 — les DEPLOYMENT SUMMARY.** Sjekk spesielt linja `Runbook runtime environment`. Står den `FAILED`, kjører runbookene fortsatt klassisk PowerShell 7.2 og vil feile med `Connect-PnPOnline is not recognized`. En runbooks type kan ikke endres in-place fra `PowerShell72` til runtime environment: **slett runbooken i Automation-kontoen og kjør deployen på nytt** — innholdet kommer fra repoet, så ingenting går tapt.

**Steg 5 — autoriser API-tilkoblingene som tjenestekontoen.**

```powershell
./Authorize-ApiConnections.ps1 -ResourceGroupName rg-bestillingsportalen
```

Tilkoblinger som allerede står `Connected` hoppes over. Logg inn **som tjenestekontoen** i nettleservinduene, ikke som deg selv. «Created from a different organization»-advarselen er forventet.

**Steg 6 — app-roller**, hvis du kjørte med `-SkipAppRoles`. Ingenting virker før dette er gjort.

**Steg 7 — verifiser i denne rekkefølgen:**

1. `CheckSiteExists` — kjør trigger manuelt. Dette er Logic App-en som feilet med `AADSTS700027`; nå skal den gå grønt uten sertifikat.
2. `GetHubSites`, `GetSiteTemplates`, `GetTeamsTemplates`, `SyncGroupSettings`, `SyncLabels` — kjør trigger manuelt, alle skal ende `Succeeded`.
3. Åpne området: lister og data intakte, `Guest Requests` opprettet, egne provisioning types på plass.
4. Send inn en **testbestilling** av en enkel områdetype, og følg `ProcessProvisionRequest` gjennom godkjenningsflyten til området er opprettet. Sjekk at `ConfigureSpace`-jobben i Automation-kontoen kjørte grønt.
5. `InstalledVersion` i innstillinger-lista viser den nye versjonen.

## 5. Etterarbeid

**Gjør nå:**

- **Roter tjenestekontoens passord.** Har miljøet kjørt med `enableSensitivity = true`, har passordet, client secret-en og et levende delegert Graph-token ligget lesbart i `ProcessProvisionRequest`s kjørehistorikk ved hver bestilling med merke. Oppgraderingen fjerner kilden, men **kjørehistorikk kan ikke slettes** — den utløper med oppbevaringstiden. Re-autoriser tilkoblingene etter rotasjonen (`Authorize-ApiConnections.ps1`).
- Fjern de døde nøklene fra parameterfila.

**Vent noen dager i drift, så rydd:** så lenge Key Vault, app-registreringen og sertifikatet står, kan du promotere de gamle Logic App-versjonene tilbake og ha et fungerende miljø. Det er hele tilbakerullingsmuligheten din — ikke slett den før løsningen er verifisert i produksjon.

| Rest | Handling |
|--|--|
| Key Vault med `appid`/`appSecret`/`sausername`/`sapassword` | Slett |
| API-tilkoblingen `*-kv` | Slett (ingen Logic App refererer til den) |
| Entra ID-app-registreringen (`Bestillingsportalen`) | Slett. **Ikke** PnP-appen (`pnpAppId`) |
| Automation-modulene `Az.Accounts` 1.6.2 og `PnP.PowerShell` 2.4.0 | Kan slettes — runbookene bruker runtime environmentet |
| Gamle `provisionassist-*`-ressurser (hvis aktuelt) | Slett Automation-kontoen og tilkoblingene når de nye er verifisert |

**Kan nå slås på:** MFA på tjenestekontoen. Kravet om MFA avslått gjaldt utelukkende ROPC-flyten, som er borte. Kontoen er fortsatt områdeeier, eier de delegerte tilkoblingene og poster velkomstmeldingen i Teams — ingenting av det krever MFA avslått.

## 6. Fallgruver

| Symptom | Årsak | Løsning |
|--|--|--|
| `Runbook runtime environment: FAILED` i summary | Runbook-typen kan ikke endres fra `PowerShell72` til runtime environment in-place | Slett runbooken, kjør deployen på nytt |
| Deployen oppretter en ny Automation-konto | Miljøet bruker `provisionassist-*`-navn; kontonavnet er hardkodet | Forventet. Verifiser den nye, rydd bort den gamle |
| ARM-feil om `location` på en Logic App | `region` i parameterfila matcher ikke eksisterende ressurser | Rett `region` til faktisk region |
| Deployen peker på feil/nytt område | `requestsSiteAlias` feil utfylt | Tom verdi = utledet fra `requestsSiteName`; ellers faktisk URL-segment |
| Slettede standardelementer er tilbake, eller finnes i to varianter | `DataRows` legger til manglende standardrader, med `Title` som nøkkel | Sett `Allowed`/`Enabled = false` framfor å slette; ikke gi standardelementer nytt navn |
| Tilkoblinger står `Unauthorized`/`Error` etter deploy | Redeploy av tilkoblingsressursene kan nullstille autoriseringen | `Authorize-ApiConnections.ps1`, ev. portalen: Edit API connection → Authorize |
| `Method 'get_Services' in type '...LoggingBuilder' does not have an implementation` | Az lastet før PnP.PowerShell i økten | Nytt PowerShell-vindu, kjør på nytt |
| `MissingSubscriptionRegistration` | `Microsoft.ManagedIdentity` (ny i 2.0) ikke registrert | `az provider register --namespace Microsoft.ManagedIdentity` som abonnementsadministrator |
| Egendefinert navigasjon borte etter deploy | Full modus bruker `-ClearNavigation` | Legg lenkene tilbake; senere `-Upgrade`-kjøringer bevarer navigasjonen |
| Bilder på provisioning types byttet ut | `UploadAssets` kjører i full modus | Last opp kundens bilder på nytt |
| Flyten kan ikke aktiveres (`FlowNotOriginalAuthor`) | Tjenestekontoen mangler System Customizer, ev. lisens | Gjelder kun ved import — se [Konfigurasjonsveiledningen, Steg 2](Configuration-guide.md). En flyt som allerede kjører, røres ikke |

## 7. Tilbakerulling

| Komponent | Mulighet |
|--|--|
| Logic Apps | Azure Portal → Logic App → `Versions` → velg forrige versjon → `Promote`. Gjør det per Logic App. Krever at Key Vault, app-registreringen og et **registrert** sertifikat fortsatt finnes |
| Runbooks | Publiser innholdet fra eksporten din på nytt. Runtime environmentet rulles ikke tilbake — gammelt innhold kjører på PnP 3.x, som stort sett er kompatibelt, men test |
| PnP-malen | Kan ikke rulles tilbake. Skjemaendringer må reverseres manuelt |
| Listedata | Ikke berørt av oppgraderingen |

## Sjekkliste

**Før vinduet**

- [ ] Bekreftet at miljøet er pre-2.0 (Key Vault finnes, ingen UAMI)
- [ ] Vurdert akutt sertifikat-fiks hvis produksjon må opp før vinduet
- [ ] Ressursnavn-generasjon kartlagt (`bestillingsportalen-*` eller `provisionassist-*`)
- [ ] Faktisk region på ressursgruppa/ressursene notert
- [ ] Områdets faktiske URL notert, og `requestsSiteAlias` bestemt
- [ ] `ConfigureSpace` og `GetSiteTemplates` eksportert og diffet mot `Source/Runbooks/`
- [ ] Kundetilpasninger i runbookene flyttet til `CustomerSpecific`
- [ ] Logic App-definisjoner eksportert hvis noen er redigert i portalen
- [ ] Listedata, bilder/ikoner og navigasjon dokumentert
- [ ] Bevisst slettede eller omdøpte standardelementer notert
- [ ] Kopi av godkjenningsflyten eksportert
- [ ] Ny parameterfil bygget fra `parameters.template.json`, gamle nøkler fjernet
- [ ] `VERSION` finnes i repo-rot
- [ ] Azure Owner (ev. PIM) aktivert på ressursgruppen
- [ ] GA eller PRA+CAA avklart — ellers avtalt GA-handover for `-SkipAppRoles`
- [ ] SharePoint Administrator på plass
- [ ] `Microsoft.ManagedIdentity` registrert i abonnementet
- [ ] PowerShell 7.4+, PnP.PowerShell 3.2+, Az, WriteAscii, ev. Node.js
- [ ] `./deploy.ps1 -Preflight` kjørt, ingen `MISSING`
- [ ] Brukerne varslet om vinduet

**Under vinduet**

- [ ] Nytt PowerShell-vindu
- [ ] `./deploy.ps1 -ParametersPath <fil> -SkipCreateResourceGroup` (uten `-Force`)
- [ ] Svart `y` på «Site already exists»
- [ ] DEPLOYMENT SUMMARY lest — ingen `FAILED`
- [ ] `Runbook runtime environment` står `OK`
- [ ] App-roller tildelt (kjørt av GA hvis `-SkipAppRoles`)
- [ ] `./Authorize-ApiConnections.ps1` kjørt, alle fire `Connected`
- [ ] `CheckSiteExists` kjørt manuelt — `Succeeded`
- [ ] Øvrige støttende Logic Apps kjørt manuelt — `Succeeded`
- [ ] Området lastes, lister og egne provisioning types intakte, `Guest Requests` opprettet
- [ ] Testbestilling gjennomført ende-til-ende, inkl. `ConfigureSpace`-jobben
- [ ] `InstalledVersion` viser ny versjon
- [ ] Navigasjon og bilder gjenopprettet hvis nødvendig

**Etter vinduet**

- [ ] Tjenestekontoens passord rotert, tilkoblingene re-autorisert
- [ ] Brukerne varslet om at oppgraderingen er fullført
- [ ] Logic App-kjøringer fulgt de første timene
- [ ] Etter noen dager i stabil drift: Key Vault, `*-kv`-tilkoblingen og Entra ID-app-registreringen slettet
- [ ] Gamle Automation-moduler og eventuelle `provisionassist-*`-rester ryddet
- [ ] MFA vurdert slått på for tjenestekontoen
- [ ] Ny versjon og eventuelle avvik dokumentert hos kunden

---

**Relatert dokumentasjon:**

- [Upgrade.md](Upgrade.md) – Oppgradering av miljøer som allerede står på 2.0+
- [Deployment-guide.md](Deployment-guide.md) – Forutsetninger og full installasjonsprosess
- [Configuration-guide.md](Configuration-guide.md) – Godkjenningsprosess, flyt-import, deling
- [CHANGELOG.md](CHANGELOG.md) – Hva som endret seg i 2.0.0
- [Error-handling.md](Error-handling.md) – Feilsøkingsveiledning
