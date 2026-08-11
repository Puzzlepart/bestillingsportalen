# Datalagre

Bestillingsportalen bruker en rekke SharePoint-lister for ulike formål. Nedenfor finner du en beskrivelse av hver liste og hvert felt som brukes i løsningen.

## SharePoint-lister

### Provisioning Requests

Denne listen lagrer detaljene om alle bestillinger gjort gjennom Bestillingsportalen webdel eller Teams app. Listeelementer kan i prinsippet oppdateres av en administrator utenfor webdel/Teams app, men dette anbefales ikke siden flere felt styres av arbeidsflyten.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Tittel på bestillingen (vises som navn på samarbeidsområdet). |
| Description | Note | Beskrivelse av bestillingen. |
| BusinessJustification | Note | Forretningsmessig begrunnelse for hvorfor området trengs. |
| AdditionalInfo | Note | Ekstra informasjon som brukeren oppgir i bestillingen. |
| Requirements | Note | Kravene brukeren har valgt i anbefalingssteget. |
| RequirementIds | Text | Intern lagring av valgte krav-ID-er. |
| SpaceType | Choice | Type samarbeidsområde: `Team Site`, `Office 365 Group`, `Microsoft Teams Team`, `Communication Site`, `Hub Site`, `Viva Engage Community`. |
| SpaceTypeInternal | Text | Intern referanse til områdetypen (skjult i skjema). |
| SpaceDisplayName | Text | Visningsnavn for samarbeidsområdet. |
| SpaceImage | Note | Logo/områdebilde lagret som base64. |
| Owners | UserMulti | Eiere av det bestilte området. |
| Members | UserMulti | Medlemmer av det bestilte området. |
| RequestedBy | UserMulti | Brukeren bestillingen er gjort på vegne av. Brukes i "Mine bestillinger" sammen med `Created By`. |
| RequestedSource | Text | Kilden bestillingen kom fra (f.eks. `webdel`, `teamsapp`, `API`). |
| Approver | User | Godkjenneren av bestillingen. |
| ApprovedDate | DateTime | Dato da bestillingen ble godkjent. |
| Visibility | Choice | Synlighet for området: `Private` eller `Public`. |
| ConfidentialData | Yes/No | Indikerer om området skal inneholde konfidensielle data. |
| ExternalSharingRequired | Yes/No | Indikerer om ekstern deling er påkrevd. |
| ExternalSharingJustification | Note | Begrunnelse for ekstern deling. |
| Guests | Note | Liste over gjestebrukere som skal inviteres (lagret som tekst). |
| SiteURL | Hyperlink | URL til det opprettede SharePoint-området. |
| SiteAlias | Text | Alias brukt i URL-en til området. |
| TeamsURL | Hyperlink | URL til det opprettede Teams-teamet. |
| VivaEngageCommunityURL | Hyperlink | URL til det opprettede Viva Engage-fellesskapet. |
| ParentSite | Note | URL eller referanse til foreldreområde (brukes for hub-tilknytning). |
| SiteTemplate | Text | Internt referanse-ID til valgt Site Template. |
| SiteTemplateTitle | Text | Tittel på valgt Site Template. |
| SiteTemplateStore | Text | Store-verdi for Site Template (skjult). |
| TeamsTemplate | Text | Internt referanse-ID til valgt Teams-mal. |
| TeamsTemplateTitle | Text | Tittel på valgt Teams-mal. |
| TeamsChannelID | Text | ID til Teams-kanalen (brukes for intern kanal-funksjonalitet). |
| AdminCenterTemplate | Yes/No | Indikerer om den valgte Teams-malen er en Admin Center-mal. |
| ApplyPnPTemplate | Yes/No | Indikerer om en PnP-provisjoneringsmal skal anvendes. |
| PnPTemplateURL | Hyperlink | URL til PnP-malen som skal anvendes. |
| ThemeName | Text | Navn på SharePoint-temaet som skal anvendes. |
| JoinHub | Yes/No | Indikerer om området skal tilknyttes en hub. |
| HubSite | Text | ID til valgt hub-område. |
| HubSiteTitle | Text | Tittel på valgt hub-område. |
| HubSiteJustification | Note | Begrunnelse for hub-tilknytning. |
| BusinessUnit | Lookup | Forretningsenhet knyttet til bestillingen (oppslag mot Business Units-listen). |
| Teamify | Yes/No | Indikerer om området skal Teams-aktiveres. |
| InternalChannel | Yes/No | Indikerer om området skal ha en intern kanal i Teams. |
| ReadOnlyGroup | Yes/No | Indikerer om området skal ha en spesifikk gruppe med lesetilgang. |
| SensitivityLabelId | Text | ID til valgt sensitivitetsmerke. |
| SensitivityLabelName | Text | Navn på valgt sensitivitetsmerke. |
| SensitivityLabelLibraryId | Text | ID til sensitivitetsmerke for dokumentbibliotek. |
| SensitivityLabelLibraryName | Text | Navn på sensitivitetsmerke for dokumentbibliotek. |
| RetentionLabelName | Text | Navn på valgt oppbevaringsmerke. |
| TimeZoneId | Number | ID til valgt tidssone. |
| LCID | Number | Språk-ID (Locale ID) for området. |
| Prefix | Text | Prefiks anvendt på områdets navn (generert fra navnekonvensjonen). |
| Suffix | Text | Suffiks anvendt på områdets navn. |
| MailboxAlias | Text | Postboks-alias for gruppen. |
| GroupId | Text | Microsoft 365-gruppe-ID etter opprettelse. |
| ExpirationDate | DateTime | Utløpsdato for området. |
| Stage | Choice | Gjeldende steg i bestillingsflyten: `Requirements`, `Recommendation`, `Data Classification`, `Choose Template`, `Information`, `External Sharing`, `Join Hub`, `Review and Submit`, `Submitted`. |
| Status | Choice | Status på bestillingen: `Not Submitted`, `Submitted`, `Pending Approval`, `Approved`, `Rejected`, `Space Creation`, `Space Created`, `Space Creation Failed`, `Space Already Exists`, `Team Requested`. |
| StatusReason | Note | Begrunnelse/detaljer knyttet til statusen (f.eks. feilmelding ved `Space Creation Failed`). |
| Comments | Note | Kommentar fra godkjenner eller administrator. |
| RequestKey | Text | Unik nøkkel brukt for å identifisere bestillingen i integrasjoner. |
| Metadata | Note | JSON-objekt som lagrer prosjektinformasjon og property bag-verdier. Struktur: `{ "projectProperties": [...], "propertyBagProps": [...] }`. |

### Guest Requests

Denne listen lagrer gjesteforespørsler opprettet via `InviteGuests`-webdelen. Hver rad representerer én gjest som skal inviteres til et bestemt SharePoint-område. Listen prosesseres av `ProcessGuestRequest` Logic App, som kaller `ProcessGuests` Logic App og oppdaterer status på raden etter at invitasjonen er behandlet.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | E-postadressen til gjesten som skal inviteres. |
| SiteUrl | Hyperlink | URL til området gjesten skal inviteres til (settes fra `pageContext.web.absoluteUrl` der webdelen står). |
| SiteTitle | Single line of text | Tittel på området (brukes i invitasjons-e-posten). |
| Status | Choice | Status på forespørselen: `Pending` (under behandling), `Invited` (vellykket), `Failed` (feil oppstod). |
| GuestId | Text | Entra ID-id til den inviterte gjesten (populeres etter vellykket invitasjon). |
| InviteRedeemUrl | Note | Innløsings-URL gjesten kan bruke for å akseptere invitasjonen. |
| ErrorMessage | Note | Feilmelding hvis `Status=Failed`. Vises i tooltip på badge i webdel-DataGrid. |
| RequestedBy | User | Brukeren som initierte invitasjonen via webdelen. |
| FirstName | Single line of text | Fornavn (valgfri) — fra Graph-oppslag eller manuell input i drawer-en. Brukes i `invitedUserDisplayName` på invitasjonen og PATCH-es som `givenName` på Entra-brukeren. |
| LastName | Single line of text | Etternavn (valgfri) — PATCH-es som `surname` på Entra-brukeren. |
| Company | Single line of text | Selskap (valgfri) — PATCH-es som `companyName` på Entra-brukeren. |
| M365GroupRole | Choice | `None`/`Visitor`/`Member`/`Owner` (default `Visitor`) — rollen gjesten skal ha på området. På M365-gruppe-koblede områder håndteres `Owner`/`Member` via Graph-cmdletene; `Visitor` (og alle roller på ikke-gruppekoblede områder) via SP associated-gruppene. |
| SPGroupAction | Choice | `None`/`AddToExisting`/`CreateNew` — valgfri SharePoint-brukergruppe-tilføyelse. |
| SPGroupName | Single line of text | Navn på eksisterende eller ny SP-gruppe (avhengig av `SPGroupAction`). |
| SPPermissionLevel | Choice | `Read`/`Contribute`/`Edit`/`Full Control` — tilgangsnivå når `SPGroupAction = CreateNew`. |

### Provisioning Request Settings

Denne listen lagrer alle konfigurerbare innstillinger for Bestillingsportalen som nøkkel/verdi-par.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Navnet på innstillingen. |
| Description | Note | Beskrivelse av innstillingen. |
| Value | Note | Verdien til innstillingen. |
| ExternalSharingSetting | Choice | Standardinnstilling for ekstern deling: `Anyone`, `NewExistingGuests`, `ExistingGuests`. |
| PrefixAttribute | Choice | Attributt brukt for prefiks i navnekonvensjonen. |
| SuffixAttribute | Choice | Attributt brukt for suffiks i navnekonvensjonen. |
| PrefixText | Text | Tekst-prefiks for navnekonvensjonen. |
| SuffixText | Text | Tekst-suffiks for navnekonvensjonen. |
| PrefixUseAttribute | Yes/No | Om attributt skal brukes som prefiks. |
| SuffixUseAttribute | Yes/No | Om attributt skal brukes som suffiks. |
| BlockedWordsValue | Note | Blokkerte ord konfigurert i Entra ID, lagret som kommaseparert streng (skjult i skjema). |
| LogoImage | Thumbnail | Logo som vises i Bestillingsportalen (overstyrer standard logo). |

### Provisioning Types

Denne listen lagrer hvilke typer samarbeidsområder som kan bestilles og provisjoneres – Team Site, Office 365 Group osv. Legg ikke til nye rader i denne listen siden de ikke støttes.

Du bør kun endre verdien på følgende kolonner: Title, Description, Allowed, Image, Icon, Learn Video URL, SortOrder, Prefix Text, Suffix Text, Prefix Use Attribute, Suffix Use Attribute, Visible To, Managed Path, Default Visibility, Default Confidential Data, External Sharing, Default Sensitivity Label, Default Sensitivity Label Library, Default Retention Label, Default Hub, Default Metadata, Join Hub og Teams Channel ID.

Se [Provisioning types](./Provisioning-types.md) for mer informasjon.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Tittel på områdetypen vist i brukergrensesnittet. Kan endres for å matche organisasjonens terminologi. |
| InternalTitle | Text | Intern tittel (skjult, brukes av løsningen for å identifisere typen). |
| SortOrder | Number | Sorteringsrekkefølge for hvordan områdetypen vises i brukergrensesnittet. |
| Description | Note | Beskrivelse av områdetypen vist til sluttbrukere. |
| Allowed | Yes/No | Om områdetypen kan bestilles. Settes til `Nei` for å skjule typen. |
| TemplateId | Text | Intern mal-ID (skal ikke endres). Gjelder enkelte typer. |
| WebTemplateId | Text | Intern web-template-ID (skal ikke endres). Gjelder SharePoint Sites og O365 Groups. |
| Image | Hyperlink or Picture | Bilde som vises for områdetypen på «Velg mal»-skjermen. |
| Icon | Hyperlink or Picture | Ikon som vises for områdetypen. |
| Learn Video URL | Hyperlink | URL til en video som forklarer denne typen område (f.eks. YouTube). |
| Prefix Text | Single line of text | Tekst-prefiks som legges til foran navnet på området. |
| Prefix Use Attribute | Yes/No | Om attributt fra brukerens profil skal brukes som prefiks. |
| Prefix Attribute | Choice | Attributt å bruke for prefiks: `Department`, `Company`, `Office`, `StateOrProvince`, `CountryOrRegion`, `JobTitle`. |
| Suffix Text | Single line of text | Tekst-suffiks som legges til etter navnet på området. |
| Suffix Use Attribute | Yes/No | Om attributt fra brukerens profil skal brukes som suffiks. |
| Suffix Attribute | Choice | Attributt å bruke for suffiks (samme valg som Prefix Attribute). |
| Visible To | Person or Group | Sikkerhetsgruppe som denne områdetypen er synlig for. MÅ være en gruppe. Blank = synlig for alle med tilgang til webdel/Teams app. |
| Managed Path | Text | Managed path som skal brukes for denne områdetypen (f.eks. `sites` eller `teams`). |
| Default Visibility | Choice | Standard synlighet for denne områdetypen: `Public` eller `Private`. |
| Default Confidential Data | Yes/No | Standardverdi for «Konfidensielle data»-valget for denne områdetypen. |
| Default Metadata | Note | Standard metadata (JSON-objekt) som anvendes for denne områdetypen. |
| External Sharing | Yes/No | Styrer om «Ekstern deling»-skjermen vises for denne områdetypen. |
| Default Sensitivity Label | Text | Standard sensitivitetsmerke-ID for denne områdetypen (overstyrer global standard). |
| Default Sensitivity Label Library | Text | Standard sensitivitetsmerke-ID for dokumentbibliotek. |
| Default Retention Label | Text | Standard oppbevaringsmerke-ID for denne områdetypen (overstyrer global standard). |
| Teamify | Yes/No | Om området skal Teams-aktiveres som standard. |
| Join Hub | Yes/No | Om området skal tilknyttes en hub som standard. |
| Default Hub | Text | Standard hub-ID som området tilknyttes (overstyrer global standard). |
| Teams Channel ID | Text | Standard Teams-kanal-ID for denne områdetypen. |

### Site Templates

Denne listen lagrer SharePoint Site Templates (tidligere Site Designs) som finnes i tenanten. En Logic App (`GetSiteTemplates`) synkroniserer disse fra tenanten til listen.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Tittel på Site Template. |
| Description | Note | Beskrivelse av Site Template. |
| SiteTemplateId | Single line of text | ID til Site Template. |
| PreviewImage | Hyperlink or Picture | URL til forhåndsvisningsbilde for malen. |
| WebTemplate | Single line of text | Intern web-template-ID (1 for Team Site uten gruppe, 64 for gruppetilknyttet Team Site, 68 for Communication/Hub site). |
| Store | Single line of text | Store-verdi for malen (gjelder kun «out of the box»-maler). |
| Enabled | Yes/No | Om malen skal vises i webdel/Teams app. |
| VisibleTo | Person | Brukere/grupper som skal se denne Site Templaten. Blank = synlig for alle. |
| ApplyPnPTemplate | Yes/No | Om en PnP-mal skal anvendes sammen med denne Site Templaten. Se [PnP Templates](/PnP-templates.md). |
| PnPTemplateURL | Hyperlink | URL til en PnP-mal lagret i «PnP Templates»-biblioteket. |
| ThemeName | Single line of text | Navn på et SharePoint-tema som skal anvendes, f.eks. `Blue`. |

### Teams Templates

Denne listen lagrer Teams-maler som brukes for å opprette Teams, både Admin Center-maler og Teams som skal klones.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Navn på malen. |
| Description | Note | Beskrivelse av malen. |
| Template Id | Single line of text | ID til malen fra Teams Admin Center. |
| Team Id | Single line of text | ID til teamet som skal klones som mal (Office 365 Unified Group-ID). |
| Admin Center Template | Yes/No | Om malen er en Microsoft Team Template (Admin Center). `Ja` for Admin Center-maler, `Nei` for kloning. |
| PrefixAttribute | Choice | Attributt for prefiks. |
| SuffixAttribute | Choice | Attributt for suffiks. |
| PrefixText | Single line of text | Prefiks-tekst. |
| SuffixText | Single line of text | Suffiks-tekst. |
| PrefixUseAttribute | Yes/No | Om attributt skal brukes som prefiks. |
| SuffixUseAttribute | Yes/No | Om attributt skal brukes som suffiks. |

### Hub Sites

Denne listen lagrer Hub Sites som finnes i tenanten. En Logic App (`GetHubSites`) synkroniserer disse fra tenanten til listen.

**Endre ikke verdier direkte i denne listen (med unntak av `Enabled` og `isPP365`).**

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Tittel på Hub Site. |
| HubSiteId | Single line of text | ID til Hub Site. |
| Owner | Single line of text | Eier av Hub Site (foreløpig ikke i bruk). |
| SecondOwner | Single line of text | Sekundær eier av Hub Site (foreløpig ikke i bruk). |
| isPP365 | Yes/No | Indikerer om Hub-området er et Prosjektportalen 365-område. |
| Enabled | Yes/No | Om Hub Site skal vises som valg i webdel/Teams app. |

### Business Units

Denne listen lagrer forretningsenheter som kan velges under bestilling. Se [Business Units](/Business-units.md) for mer informasjon.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Navn på forretningsenheten. |
| Prefix | Single line of text | Prefiks som legges til foran områdets navn. |
| Suffix | Single line of text | Suffiks som legges til etter områdets navn. |
| Approvers | Person or Group | Godkjennere for bestillinger knyttet til denne enheten. |

### IP Labels

Denne listen lagrer sensitivitetsmerker (Information Protection Labels) hentet fra Microsoft Purview. En Logic App (`SyncLabels`) synkroniserer disse til listen.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Intern tittel. |
| LabelName | Single line of text | Visningsnavn på sensitivitetsmerket. |
| LabelId | Single line of text | GUID til sensitivitetsmerket i Purview. |
| LabelDescription | Note | Beskrivelse av sensitivitetsmerket. |
| Enabled | Yes/No | Om merket skal vises som valg i webdel/Teams app. |
| IsLibrary | Yes/No | Om merket gjelder dokumentbibliotek (i stedet for Group/Site). |

### Retention Labels

Denne listen lagrer oppbevaringsmerker som kan velges for SharePoint-dokumentbiblioteker.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Intern tittel. |
| LabelName | Single line of text | Visningsnavn på oppbevaringsmerket. |
| LabelDescription | Single line of text | Beskrivelse av oppbevaringsmerket. |

### Time Zones

Denne listen lagrer alle tidssonene som kan velges og anvendes på et SharePoint-område.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Navn på tidssonen. |
| TimeZoneId | Number | SharePoint-ID til tidssonen. |

### Locales

Denne listen lagrer alle språk/lokaler (LCID) som SharePoint Online støtter og som kan velges i webdel/Teams app.

| Kolonnenavn | Type | Beskrivelse |
|---|---|---|
| Title | Single line of text | Navn på språket/lokalen. |
| LCID | Number | Locale ID (f.eks. `1044` for norsk bokmål, `1033` for engelsk (USA)). |

### PnP Templates

Dette er et dokumentbibliotek (ikke en liste) som lagrer PnP-provisjoneringsmaler som kan anvendes under provisjonering. Se [PnP Templates](/PnP-templates.md) for mer informasjon.
