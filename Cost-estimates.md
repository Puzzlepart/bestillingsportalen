# Kostnadsestimater

## Forutsetninger

Estimatet nedenfor forutsetter:

- 500 brukere i tenanten

- Provisjonerings-Logic App kjører hver time (for å opprette samarbeidsområder for alle godkjente bestillinger)

- «Verify availability» kalles hver gang en bruker oppretter en bestilling, én gang per bruker per område.

## Anbefalte SKU-er

Anbefalte SKU-er for et produksjonsmiljø:

- Logic Apps
- API Connections
- Automation Account
- Azure Runbooks

## Estimert belastning

**Antall områdebestillinger**: 500 brukere × 1 bestilling/bruker/måned = 500 bestillinger/måned

## Estimert kostnad

**VIKTIG:** Dette er kun et estimat basert på forutsetningene ovenfor. Faktiske kostnader kan variere.

**Merk: Disse estimatene er fra mai 2020 og reflekterer kanskje ikke gjeldende Azure-priser. Verifiser mot gjeldende [Azure-priser](https://azure.microsoft.com/en-us/pricing/) før du stoler på disse tallene.**

Prisene er hentet fra [Pricing](https://azure.microsoft.com/en-us/pricing/) den 06. mai 2020, for regionen West US.

Bruk [Azure Pricing Calculator](https://azure.com/e/37608b74af8a4e57bc5834321c2a2c23) for å modellere ulike servicenivåer og bruksmønstre.

| Ressurs | Nivå | Belastning | Månedspris |
|--|--|--|--
| Azure Logic Apps | N/A | 1 handlingsutførelse/dag | $0,01 |
| Azure Automation | Process automation | 500 minutter prosessautomatisering og 744 timer watchers er gratis per måned. Belastes kun hvis gratiskvoten overskrides | $1,46 |
| Totalt | | | $1,47 |
