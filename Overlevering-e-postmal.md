# E-postmal: overlevering etter installasjon

En mal for e-posten til kunden når installasjonen er ferdig: hva som er installert, hvordan brukerne bestiller, og hva kunden selv må gjøre før løsningen åpnes for alle. Send den til kundens systemeier eller IT-ansvarlige etter testbestillingen i [Steg 8 i konfigurasjonsveiledningen](./Configuration-guide.md#steg-8-verifiser-med-en-testbestilling).

Slik bruker du malen:

- Bytt ut alt i `<vinkelparenteser>`.
- Stryk punktene i sjekklisten som allerede er gjort sammen med kunden, og setninger som ikke gjelder. Er automatisk godkjenning slått på, stryker du for eksempel avsnittet om godkjennere.
- Lenkene peker på dokumentasjonen på GitHub, så de virker også i e-post.

---

**Emne:** Bestillingsportalen er installert – slik kommer dere i gang

Hei <navn>,

Bestillingsportalen er nå installert hos <kundenavn> (versjon <versjon>, <dato>). Installasjonen er kontrollert punkt for punkt, og en testbestilling er sendt gjennom hele løpet.

**Dette er installert**

- **Bestillingsområdet** <område-URL>, med listene som styrer løsningen: bestillinger, områdetyper, maler, huber og innstillinger.
- **Bestillingsportalen** som webdel i SharePoint og som app i Teams.
- **Automatiseringen** i Azure-abonnementet <abonnement>, ressursgruppe <ressursgruppe>: Logic Apps, en Automation-konto og managed identities. Løsningen har ingen passord, hemmeligheter eller sertifikater som må fornyes.
- **Godkjenningsflyten** i Power Automate, eid av tjenestekontoen <tjenestekonto>.

**Slik bestiller brukerne**

Brukerne åpner Bestillingsportalen i Teams eller på <side-URL>, velger områdetype og fyller ut skjemaet. Bestillingen godkjennes av <godkjennere>, og området opprettes automatisk, vanligvis i løpet av 10–15 minutter. Brukerne følger status på egne bestillinger i appen. Brukerveiledningen ligger her: [Brukerveiledning for Bestillingsportalen-appen](https://github.com/Puzzlepart/bestillingsportalen/blob/main/App-brukerveiledning.md).

**Dette må dere gjøre før dere åpner for brukerne**

- [ ] **Godkjenning:** bestem hvem som godkjenner, og om det skjer i Approvals eller i en Teams-kanal ([Steg 1](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Configuration-guide.md#steg-1-konfigurere-godkjenningsprosess)). Bestillinger kan også godkjennes automatisk ([Steg 7](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Configuration-guide.md#steg-7-valgfritt-aktivere-automatisk-godkjenning-deaktivere-godkjenningsprosess)).
- [ ] **Tilgang:** del bestillingsområdet med dem som skal kunne bestille, og gi dem redigeringstilgang til listen `Provisioning Requests` ([Steg 3](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Configuration-guide.md#steg-3-dele-flyt-og-sharepoint-område)).
- [ ] **Områdetyper:** velg hvilke typer brukerne kan bestille, for eksempel Microsoft 365-gruppe og Teams ([Provisioning Types](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Provisioning-types.md)).
- [ ] **Maler og huber:** velg hvilke områdemaler og huber brukerne skal se ([Steg 5](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Configuration-guide.md#steg-5-valgfritt-aktivere-site-templates-og-hub-sites)).
- [ ] **Administratorer:** bestem hvem som skal administrere løsningen ([Steg 6](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Configuration-guide.md#steg-6-sette-opp-administratorgruppe)).
- [ ] **Teams-appen:** gjør appen tilgjengelig for brukerne i Teams admin center, og pinn den gjerne i app-linjen ([Aktivere Teams-appen](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Configuration-guide.md#merknad-aktivere-teams-appen-for-bestillingsportalen)).
- [ ] **Webdelen:** legg webdelen Bestillingsportalen inn på en SharePoint-side, for eksempel på intranettet ([Bestillings-webdelen](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Configuration-guide.md#merknad-bestillings-webdelen-følger-denne-løsningen)).
- [ ] **Valgfritt:** begrens hvem som kan opprette team, grupper og områder utenom portalen ([Begrense opprettelse av områder](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Restrict-site-creation.md)).

**Greit å vite**

- **Det første døgnet** etter at tilgangene ble gitt, kan en bestilling feile med tilgangsfeil, fordi Azure bruker de gamle tilgangene en stund. Det retter seg selv innen 24 timer, her senest <tidspunkt>.
- **Feiler en bestilling**, står den som «Space Creation Failed», og appen viser årsaken når brukeren holder musepekeren over statusen. Brukerne skal da kontakte dere med bestillingens navn, tidspunkt og årsaken. Hvordan dere feilsøker, står i [Feilhåndtering](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Error-handling.md).
- **Nye versjoner** og hva de endrer står i [endringsloggen](https://github.com/Puzzlepart/bestillingsportalen/blob/main/CHANGELOG.md).

All dokumentasjon finnes på [github.com/Puzzlepart/bestillingsportalen](https://github.com/Puzzlepart/bestillingsportalen). [Konfigurasjonsveiledningen](https://github.com/Puzzlepart/bestillingsportalen/blob/main/Configuration-guide.md) beskriver stegene over i detalj.

Har dere spørsmål, ta kontakt med <kontaktperson> på <e-post> eller <telefon>.

Hilsen
<navn>
<firma>

---
