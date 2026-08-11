# Error Handling Flow Diagram

## Logic App Error Handling Flow

Hvert steg har et `Handle_Error_*`-scope som utløses på `Failed` eller `TimedOut`.
`Skipped` er ikke med: et steg blir Skipped først når en avhengighet feilet, og da har
den avhengighetens eget scope allerede kjørt `Terminate`.

Hvert scope henter den faktiske feilen med `result()` før statusen skrives, slik at
`StatusReason` inneholder både steget og den underliggende feilmeldingen.

```mermaid
graph TD
    A[Start: Provisioning Request Approved] --> B[Check_if_space_exists]
    B -->|Success| C[Check_space_type]
    B -->|Failed/TimedOut| B1[Handle_Error_Check_if_space_exists]
    B1 --> B2[result: hent feilmelding]
    B2 --> B3[Update Status: Space Creation Failed + feilmelding]
    B3 --> B4[Terminate Workflow]

    C -->|Success| D[Process_Owners_and_Members]
    C -->|Failed/TimedOut| C1[Handle_Error_Check_space_type]
    C1 --> C2[result -> Update Status -> Terminate]

    D -->|Success| E[Process_Team]
    D -->|Failed/TimedOut| D1[Handle_Error_Process_Owners_and_Members]
    D1 --> D2[result -> Update Status -> Terminate]

    E -->|Success| F[Apply_Site_Template]
    E -->|Failed/TimedOut| E1[Handle_Error_Process_Team]
    E1 --> E2[result -> Update Status -> Terminate]

    F -->|Success| G[Set_external_sharing]
    F -->|Failed/TimedOut| F1[Handle_Error_Apply_Site_Template]
    F1 --> F2[result -> Update Status -> Terminate]

    G -->|Success| H[Invite_guests]
    G -->|Failed/TimedOut| G1[Handle_Error_Set_external_sharing]
    G1 --> G2[result -> Update Status -> Terminate]

    H -->|Success| J[Store_expiration_date]
    H -->|Failed/TimedOut| H1[Handle_Error_Invite_guests]
    H1 --> H2[result -> Update Status -> Terminate]

    J -->|Success| K[Configure_space via Runbook]
    J -->|Failed/TimedOut| J1[Handle_Error_Store_expiration_date]
    J1 --> J2[result -> Update Status -> Terminate]

    K -->|Connector Failed/TimedOut| K1[Handle_Error_Configure_space]
    K1 --> K2[Update Status med job-exception]
    K2 --> K3[Terminate Workflow]

    K -->|HTTP 200| CS{Check_runbook_status:<br/>properties.status = Failed?}
    CS -->|Ja| CS1[Update Status: Space Creation Failed<br/>+ job-exception]
    CS1 --> CS2[Terminate Workflow]
    CS -->|Nei| L[Update Status: Space Created]

    L --> M[Send Notification Email]
    M --> N[End: Success]
```

`Check_runbook_status` finnes fordi Azure Automation-connectoren returnerer HTTP 200 selv
når runbook-jobben internt har status `Failed`. `Update Status: Space Created` er kjedet
etter denne sjekken, ikke etter `Configure_space` – ellers kunne de to kjørt i parallell
og stemplet bestillingen som opprettet før `Terminate` rakk å stoppe kjøringen.

Sensitivitetsmerking har ikke lenger eget scope her; den er et steg inne i runbooken.

## ConfigureSpace Runbook Error Handling Flow

```mermaid
graph TD
    A[Start: ConfigureSpace Runbook] --> A2["$ErrorActionPreference = 'Stop'"]
    A2 --> B[Initialize Error Tracking]
    B --> C{Connect-Admin + Get-PnPContext}
    C -->|Failed| E[Throw Exception]
    C -->|Success| VE{Viva Engage Community?}
    VE -->|Ja| S[End: konfigurasjon ikke nødvendig]

    VE -->|Nei| CL[Invoke-Step SetSensitivityLabel]
    CL --> CE[Invoke-Step SetExternalSharing]
    CE --> NS[Invoke-Step DisableNoScript]

    NS --> D["foreach step in configurationSteps:<br/>Invoke-Step step"]
    D --> FIN["finally: Invoke-Step EnableNoScript"]
    FIN --> SUM[Write-StepSummary]

    SUM --> K{hasErrors?}
    K -->|Nei| M[Report Success]
    K -->|Ja| L[Throw med navn på feilende steg]

    L --> P[Automation-jobb får status Failed]
    P --> Q[Logic App: Check_runbook_status<br/>eller Handle_Error_Configure_space]
    Q --> R[Update SP List: Space Creation Failed]

    M --> S2[End: Success]
```

## Invoke-Step

`Invoke-Step` erstatter de tidligere 22 identiske try/catch-blokkene i hvert steg.
Kombinert med `$ErrorActionPreference = 'Stop'` fanger den nå også ikke-terminerende
PnP-feil, som tidligere gikk rett forbi feilhåndteringen.

```mermaid
graph LR
    A[Invoke-Step Name] --> B{"& Name"}
    B -->|Success| C[stepResults += Succeeded]
    B -->|Terminating or non-terminating error| D[Catch]
    D --> E[Set-SpaceCreationFailed]
    E --> F[hasErrors = true<br/>errorMessages += melding]
    F --> G[stepResults += Failed + melding]
    C --> H[Neste steg]
    G --> H
```

## Benefits

1. **Consistent Error Handling**: ett `Invoke-Step` i stedet for 22 kopier av samme try/catch
2. **Ingen stille feil**: `Stop` gjør at ikke-terminerende PnP-feil faktisk fanges
3. **Clear Visibility**: `StatusReason` inneholder den faktiske feilmeldingen, ikke en fast streng
4. **Detaljert jobblogg**: `Write-StepSummary` viser status per steg
5. **Graceful Degradation**: runbooken fortsetter selv om ett steg feiler, og `EnableNoScript` kjører alltid
6. **Aggregated Reporting**: alle feil samles og rapporteres sammen
