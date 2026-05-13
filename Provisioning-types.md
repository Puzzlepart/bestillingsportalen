# Provisioning Types

Bestillingsportalen støtter opprettelse av følgende typer samarbeidsområder (kalt «types»):

- SharePoint Team Site (uten gruppetilknytning)
- Office 365 Group
- Communication Site
- Hub Site
- Microsoft Teams Team
- Viva Engage Community

En SharePoint-liste kalt `Provisioning Types` lagrer hver type samarbeidsområde som en bruker kan bestille.

Områdetypene vises til sluttbrukere i Bestillingsportalen webdel eller Teams app på «Velg mal»-skjermen.

![Provisioning types list screenshot](/Images/ProvisioningTypesList.png)

## Tilpasning av områdetyper

For å tilpasse en type, rediger listeelementet og oppdater verdien på én av følgende kolonner:

- **Title** – Tittel på områdetypen. Du kan endre denne hvis terminologien er annerledes i organisasjonen din. For eksempel kan et Team Site (uten gruppe) være kjent som et «Dokumentlagringsområde». Dette er tittelen som vises til sluttbrukere i webdel eller Teams app.
- **SortOrder** – Tall som styrer rekkefølgen områdetypene vises i på «Velg mal»-skjermen.
- **Description** – Beskrivelse av områdetypen. Vises til sluttbrukere i webdel eller Teams app.
- **Allowed** – Om brukere skal kunne bestille denne områdetypen gjennom webdel eller Teams app. `False` skjuler typen, `True` viser den.
- **TemplateId** – Intern mal-ID for områdetypen. Gjelder kun enkelte typer og **skal IKKE endres**.
- **WebTemplateId** – Intern web-template-ID for områdetypen. Gjelder kun enkelte typer og **skal IKKE endres**.
- **Image** – Bilde av områdetypen som vises i webdel eller Teams app. Du kan endre dette for å matche organisasjonens branding. Dette er en hyperlenke – **sørg for at bildet er tilgjengelig for alle som skal bruke webdel/Teams app**.
- **Icon** – Ikon for områdetypen som vises på «Velg mal»-steget. Som standard brukes offisielle Microsoft-logoer. **Sørg for at bildet er tilgjengelig for alle brukere**.
- **Learn Video URL** – URL til en video som hjelper brukeren å lære om områdetypen (f.eks. YouTube). Videoen kan spilles av direkte i webdel eller Teams app.
- **Visible To** – Sikkerhetsgruppe med brukere som denne områdetypen skal være synlig for. MÅ være en gruppe, ikke enkeltbrukere. Blank = synlig for alle med tilgang til webdel/Teams app. Eksempel: begrense opprettelse av Communication Sites til brukere i Corporate Comms.
- **Managed Path** – Managed path som skal brukes ved opprettelse av områder av denne typen. Kan brukes til å opprette SharePoint-områder under `sites`-pathen selv om tenant-standarden er `teams`.
- **Prefix Text** / **Suffix Text** – Fast tekst som legges til foran/etter områdenavnet.
- **Prefix Use Attribute** / **Suffix Use Attribute** – Bruk brukerens profilattributt som prefiks/suffiks. Se [Navnekonvensjoner](/Naming-conventions.md).
- **Prefix Attribute** / **Suffix Attribute** – Hvilket attributt som skal brukes: `Department`, `Company`, `Office`, `StateOrProvince`, `CountryOrRegion`, `JobTitle`.
- **Default Visibility** – Standard synlighet for området: `Public` eller `Private`.
- **Default Confidential Data** – Standardverdi for «Konfidensielle data»-valget for denne områdetypen.
- **Default Metadata** – Standard metadata (JSON-objekt) som anvendes ved opprettelse av området. Brukes for å lagre prosjektinformasjon og property bag-verdier.
- **External Sharing** – Styrer om «Ekstern deling»-skjermen vises i bestillingsflyten for denne områdetypen.
- **Default Sensitivity Label** – Standard sensitivitetsmerke-ID som anvendes på området (overstyrer global standard). Se [Sensitivity Labels](/Sensitivity-labels.md).
- **Default Sensitivity Label Library** – Standard sensitivitetsmerke-ID for dokumentbiblioteker i området.
- **Default Retention Label** – Standard oppbevaringsmerke-ID som anvendes på området. Se [Retention Labels](/Retention-labels.md).
- **Teamify** – Om området skal Teams-aktiveres automatisk som standard.
- **Join Hub** – Om området som standard skal tilknyttes en hub.
- **Default Hub** – Standard hub-område denne områdetypen tilknyttes (overstyrer global standard).
- **Teams Channel ID** – Standard Teams-kanal-ID knyttet til denne områdetypen (brukes for intern kanal-funksjonalitet).

**Legg ikke til nye elementer i denne listen – de vil ikke fungere.**

Du kan også redigere kolonnene som definerer navnekonvensjonen for å lage en navnekonvensjon som er spesifikk for områdetypen. Se [Navnekonvensjoner](/Naming-conventions.md) for mer informasjon.
