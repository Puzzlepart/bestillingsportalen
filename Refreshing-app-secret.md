# Fornye App Secret

Fra tid til annen må du oppdatere/fornye client secret-en som brukes i Entra ID-appen for Bestillingsportalen. Dette kan være fordi secret-en har utløpt, eller fordi du ønsker å generere en ny.

Når du installerer Bestillingsportalen, har secret-en som genereres for Entra ID-appen en standard utløpstid på 1 år fra datoen installasjonsskriptet ble kjørt.

Secret-en brukes flere steder i Bestillingsportalen:

- Key Vault
- Key Vault API Connection
- Kryptert variabel i Automation Account

**Det anbefales å notere ned datoen secret-en utløper. Når den har utløpt, vil Logic Apps og Automation Runbooks feile til en ny secret er opprettet og Bestillingsportalen oppdatert.**

## Fornye secret

***Passende tilganger kreves for å følge prosessen nedenfor. Sørg for at kontoen du bruker har tilganger til å generere Entra ID app secrets, oppdatere secrets i Key Vault og oppdatere Bestillingsportalen API Connections.**

Når secret-en utløper (ELLER når du vil opprette en ny), følg denne prosessen for å oppdatere Bestillingsportalen:

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

### Oppdatere API Connection

1. Finn API Connection-en `bestillingsportalen-kv` i Azure Portal. Du kan bruke søkeboksen.
2. Klikk `Edit API connection` i venstre meny.

![Key Vault API Connection screenshot](/Images/KeyVaultAPIConnection.png)

3. Skriv inn den nye secret-en i `Client secret`-tekstboksen og klikk `Save`.
4. API Connection er nå oppdatert.

### Oppdatere Automation Account-variabel

1. Åpne Azure Portal.
2. Finn Automation Account-en `bestillingsportalen-auto`.
3. Klikk `Variables` i venstre meny.

![Automation Account variables option screenshot](/Images/AutomationAccountVariables.png)

4. Klikk på variabelen `appSecret`.

![Automation Account appSecret variable screenshot](/Images/AutomationAccountAppSecretVariable.png)

5. Klikk `Edit value`.
6. Skriv inn verdien på den nye secret-en i `Value`-tekstboksen og klikk `Save`.
7. Automation Account er nå oppdatert.

Secret-en er nå oppdatert for Bestillingsportalen.
