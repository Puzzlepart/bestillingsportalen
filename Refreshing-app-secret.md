# Fornye App Secret

> **Gjelder kun installasjoner med sensitivitetsmerke-funksjonaliteten aktivert (`enableSensitivity`).** Etter [migreringen til managed identity](Managed-identity-migration.md) brukes client secret-en til Entra ID-appen utelukkende i ROPC-kallet som anvender sensitivitetsmerker. Logic Apps, API-tilkoblinger og runbooks autentiserer med managed identity og påvirkes ikke av at secret-en utløper. Bruker du ikke sensitivitetsmerker, trenger du ikke gjøre noe når secret-en utløper.

Når du installerer Bestillingsportalen med `enableSensitivity` aktivert, har secret-en som genereres for Entra ID-appen en standard utløpstid på 1 år fra datoen installasjonsskriptet ble kjørt.

**Det anbefales å notere ned datoen secret-en utløper. Når den har utløpt, vil anvendelse av sensitivitetsmerker i provisjoneringen feile til en ny secret er opprettet og Key Vault oppdatert.**

## Fornye secret

***Passende tilganger kreves for å følge prosessen nedenfor. Sørg for at kontoen du bruker har tilganger til å generere Entra ID app secrets og oppdatere secrets i Key Vault.***

### Generere en ny secret

1. Åpne Azure Portal.
2. Gå til Microsoft Entra ID.
3. Klikk `App registrations` i venstre meny.
4. Klikk `All applications`.
5. Finn Bestillingsportalen Entra ID-applikasjonen din og klikk på den.
6. Klikk `Certificates and secrets` i venstre meny.
7. Klikk `New client secret` under Client secrets.
8. Skriv inn en beskrivelse og velg utløpsdato. **Noter ned utløpsdatoen.**
9. Kopier **Value** på secret-en. **Når du forlater blade-et, vil verdien være permanent skjult.**

### Oppdatere Key Vault

1. Åpne Azure Portal.
2. Finn Key Vault for Bestillingsportalen.
3. Klikk `Secrets` i venstre meny. Hvis du ikke kan se secrets, må du opprette en access policy for kontoen du bruker, ELLER bruke en konto med passende tilganger.
4. Finn secret-en `appSecret` og klikk på den.

![Key Vault appSecret secret screenshot](/Images/KeyVaultAppSecret.png)

5. Klikk `New Version`, skriv inn verdien på den nye secret-en i `Secret value`-boksen og klikk `Create`.

![Key Vault create secret version screenshot](/Images/KeyVaultUpdateSecret.png)

6. Key Vault er nå oppdatert.

Secret-en er nå oppdatert for Bestillingsportalen. Logic App-en `ProcessProvisionRequest` henter alltid siste versjon av `appsecret` fra Key Vault ved kjøring, så ingen ytterligere oppdatering er nødvendig.
