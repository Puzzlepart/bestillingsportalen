# Fornye sertifikat

Fra tid til annen må sertifikatet som Bestillingsportalen bruker til å autentisere mot Microsoft Graph fornyes. Sertifikatet er app-only-autentisering og brukes av Logic Apps (f.eks. `CheckSiteExists`, `ProcessProvisionRequest`, `ProcessGuests`, `GetHubSites`, `GetTeamsTemplates`, `SyncLabels`).

Skriptet for fornyelse ligger i [Source/Scripts/renew-certificate.ps1](Source/Scripts/renew-certificate.ps1).

> **Sertifikat vs. client secret:** Sertifikatet og client secret-en (`appSecret`) er to forskjellige credentials som fornyes hver for seg. Dette dokumentet dekker **sertifikatet**. For client secret, se [Refreshing-app-secret.md](Refreshing-app-secret.md).

## Hvordan autentiseringen henger sammen

- Sertifikatet ligger som en secret i **Key Vault** (`kv-12019-bp`, secret `cert-12019-bestillingsportalen`).
- Logic Apps henter sertifikatet **uten å låse til en versjon** (`/secrets/<certName>/value`), og får derfor alltid den **nyeste aktiverte versjonen** i Key Vault.
- For at autentiseringen skal lykkes må **thumbprint-en til den nyeste versjonen være registrert som en keyCredential på app-registreringen** i Entra ID (`83c1c4a9-6f1c-4c51-88cd-9447aa620870`).

Skriptet kjører begge halvdelene samtidig: det lager en ny sertifikatversjon i Key Vault **og** registrerer thumbprint-en på app-registreringen.

## Symptom: «certificate thumbprint»-feil

En thumbprint-feil betyr at Key Vault serverer en sertifikatversjon hvis thumbprint **ikke** er registrert på app-registreringen. Dette kan skje **før** utløpsdato, typisk fordi:

1. **Key Vault auto-roterer** sertifikatet. Den nye versjonen får en ny thumbprint som aldri blir registrert på app-registreringen. Logic Apps plukker opp den nye versjonen umiddelbart og feiler.
2. **Validitetsmismatch:** KV-sertifikatets fysiske gyldighet (policy, ofte 12 måneder) utløper før app-credentialens `--end-date` (900 dager). Da serveres en utløpt pfx.

> **Hvorfor feiler `CheckSiteExists`, men ikke `ProcessProvisionRequest`?**
> `CheckSiteExists` bruker **kun** sertifikat (app-only) og er derfor det første som feiler. `ProcessProvisionRequest` har i tillegg en client-secret/service-account-sti, og kan se ut til å «fungere» selv om sertifikatet er ødelagt. Hvis du ser thumbprint-feil i `CheckSiteExists` mens `ProcessProvisionRequest` går gjennom, er det sertifikatet – ikke client secret-en – som er problemet.

## Fornye sertifikatet

***Passende tilganger kreves: kontoen du bruker må kunne tilbakestille credentials på Entra ID-app-registreringen og opprette/lese sertifikater i Key Vault.**

1. Åpne [Source/Scripts/renew-certificate.ps1](Source/Scripts/renew-certificate.ps1) og bekreft at `$appId`, `$keyVaultName` og `$certName` stemmer med miljøet ditt (sjekk Bestillingsportalen-ressursgruppen).
2. Kjør skriptet. Det logger inn (`az login`), fornyer sertifikatet og kjører verifiseringen automatisk.

## Bekreft etter fornyelse

Skriptet skriver ut dette automatisk – kontroller følgende:

- **Synk:** Verifiseringen skal skrive `OK: Nyeste Key Vault-thumbprint er registrert på app-registreringen`. Hvis den i stedet skriver `MISMATCH`, vil Logic Apps fortsatt feile – kjør fornyelsen på nytt eller registrer thumbprint-en manuelt.
- **Utløpsdato:** At den nyeste Key Vault-versjonen har en utløpsdato langt frem i tid.
- **Rotation-policy:** Skriptet skriver ut `validityMonths` og `lifetimeActions` for sertifikatet. Hvis `lifetimeActions` inneholder en auto-renew-handling, **auto-roterer Key Vault sertifikatet** – det er den vanligste årsaken til at thumbprint-feilen kommer tilbake gjentatte ganger.

## Manuelle steg og ting å sjekke

1. **Hent den faktiske feilmeldingen** fra den feilende Logic App-kjøringen (f.eks. `CheckSiteExists`) for å bekrefte at det er en thumbprint-feil og ikke en annen årsak (Key Vault-tilgang, utløpt client secret osv.).
2. **Rotation-policy:** Hvis Key Vault auto-roterer sertifikatet, enten fjern auto-rotation, eller sørg for at dette skriptet kjøres hver gang en ny versjon lages, slik at thumbprint-en alltid registreres på app-registreringen.
3. **Validitet:** Hvis `validityMonths` er kortere enn de 900 dagene som settes på app-credentialen, vil pfx-en i Key Vault utløpe før app-credentialen. Juster KV-policyen slik at de samsvarer.
4. **Opprydding:** `--append` akkumulerer credentials på app-registreringen for hver kjøring. Slett utløpte/gamle keyCredentials (alle unntatt den gjeldende) i Entra ID → App registrations → Certificates & secrets, eller med:
   ```powershell
   az ad app credential delete --id <appId> --key-id <keyId> --cert
   ```
5. **Client secret (`appSecret`):** Egen credential som ikke berøres av dette skriptet. Den utløper separat (standard 1 år) og brukes av Key Vault API Connection, Automation Account og service-account-flyten. Forny den samtidig hvis den nærmer seg utløp. Se [Refreshing-app-secret.md](Refreshing-app-secret.md).
