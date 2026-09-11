<!-- Takk for bidraget. Les CONTRIBUTING.md først – større endringer bør være diskutert i et issue før PR-en. -->

## Hva endres, og hvorfor

<!-- Beskriv endringen og problemet den løser. Lenk til issuet: Fixes #123 -->

## Type endring

- [ ] Feilretting
- [ ] Ny funksjonalitet
- [ ] Dokumentasjon
- [ ] Annet: <!-- beskriv -->

## Sjekkliste

- [ ] Endringen er beskrevet under `## Ikke utgitt` i `CHANGELOG.md` (ikke nødvendig for rene skrivefeil)
- [ ] Endringer i Logic Apps er gjort direkte i ARM-malene under `Source/ARMTemplates/LogicApps/`, ikke eksportert fra designeren (se CONTRIBUTING.md)
- [ ] Dokumentasjonen er oppdatert der oppførselen endres (Deployment-guide, Configuration-guide, Upgrade.md, Data-access-security.md ved nye tillatelser)
- [ ] Ingen tenant-ID-er, subscription-ID-er, brukernavn eller skjermbilder fra reelle miljøer
- [ ] Verifisert i en tenant: <!-- hva ble testet, og hvordan (ny installasjon / -Upgrade / kun webdel) -->

## Oppgraderingshensyn

<!-- Krever endringen full deploy, re-autorisering av API-tilkoblinger eller manuelle steg? Nye ressurser eller skjemaendringer? Hvis nei, skriv «Ingen». -->
