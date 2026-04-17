# Regionale innstillinger

Bestillingsportalen støtter at brukeren kan velge tidssone og språk (locale) for et område som opprettes.

## Hvordan ser dette ut?

To lister i SharePoint-området brukes for å støtte denne funksjonaliteten:

**Time Zones:**

![Time zones list screenshot](./images/TimeZonesList.png)

Denne listen lagrer alle språk (LCID-er) som SharePoint Online støtter. Den brukes i Bestillingsportalen webdel eller Teams app for å la brukeren velge språk. Hvis du vil begrense hvilke språk en bruker kan velge, kan du slette elementer fra listen som ikke trengs.

**Locales:**

![Locales list screenshot](./images/LocalesList.png)

**Brukervisning:**

Når en bruker oppretter en bestilling, kan hen velge tidssone/språk fra kombinasjonsboksene på «Områdeinformasjon»-skjermen.

---

## Standard tidssone/språk – valgfritt

Du kan konfigurere en standard tidssone/språk som vises når brukeren oppretter en bestilling. Brukeren kan overstyre standarden og velge sin egen, men dette sikrer at feltet ikke er tomt når bestillingen opprettes.

Slik konfigurerer du standard tidssone/språk:

1. Gå til listen `Provisioning Request Settings` i SharePoint-området.
2. Rediger `DefaultTimeZone` og `DefaultLCID` og oppdater verdien i `Value`-kolonnen til tidssonen og LCID-en du vil ha som standard. Du finner ID-ene i listene Time Zones og Locales.

En standard tidssone/språk er nå konfigurert og vil ta effekt neste gang Bestillingsportalen webdel eller Teams app startes.
