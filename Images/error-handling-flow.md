# Error Handling Flow Diagram

## Logic App Error Handling Flow

```mermaid
graph TD
    A[Start: Provisioning Request Approved] --> B[Check_if_space_exists]
    B -->|Success| C[Check_space_type]
    B -->|Failed/Skipped/TimedOut| B1[Handle_Error_Check_if_space_exists]
    B1 --> B2[Update Status: Space Creation Failed]
    B2 --> B3[Terminate Workflow]
    
    C -->|Success| D[Process_Owners_and_Members]
    C -->|Failed/Skipped/TimedOut| C1[Handle_Error_Check_space_type]
    C1 --> C2[Update Status: Space Creation Failed]
    C2 --> C3[Terminate Workflow]
    
    D -->|Success| E[Process_Team]
    D -->|Failed/Skipped/TimedOut| D1[Handle_Error_Process_Owners_and_Members]
    D1 --> D2[Update Status: Space Creation Failed]
    D2 --> D3[Terminate Workflow]
    
    E -->|Success| F[Apply_Site_Template]
    E -->|Failed/Skipped/TimedOut| E1[Handle_Error_Process_Team]
    E1 --> E2[Update Status: Space Creation Failed]
    E2 --> E3[Terminate Workflow]
    
    F -->|Success| G[Set_external_sharing]
    F -->|Failed/Skipped/TimedOut| F1[Handle_Error_Apply_Site_Template]
    F1 --> F2[Update Status: Space Creation Failed]
    F2 --> F3[Terminate Workflow]
    
    G -->|Success| H[Invite_guests]
    G -->|Failed/Skipped/TimedOut| G1[Handle_Error_Set_external_sharing]
    G1 --> G2[Update Status: Space Creation Failed]
    G2 --> G3[Terminate Workflow]
    
    H -->|Success| I[Apply_sensitivity_label]
    H -->|Failed/Skipped/TimedOut| H1[Handle_Error_Invite_guests]
    H1 --> H2[Update Status: Space Creation Failed]
    H2 --> H3[Terminate Workflow]
    
    I -->|Success| J[Store_expiration_date]
    I -->|Failed/Skipped/TimedOut| I1[Handle_Error_Apply_sensitivity_label]
    I1 --> I2[Update Status: Space Creation Failed]
    I2 --> I3[Terminate Workflow]
    
    J -->|Success| K[Configure_space via Runbook]
    J -->|Failed/Skipped/TimedOut| J1[Handle_Error_Store_expiration_date]
    J1 --> J2[Update Status: Space Creation Failed]
    J2 --> J3[Terminate Workflow]
    
    K -->|Success| L[Update Status: Space Created]
    K -->|Failed/Skipped/TimedOut| K1[Handle_Error_Configure_space]
    K1 --> K2[Update Status: Space Creation Failed]
    K2 --> K3[Terminate Workflow]
    
    L --> M[Send Notification Email]
    M --> N[End: Success]
```

## ConfigureSpace Runbook Error Handling Flow

```mermaid
graph TD
    A[Start: ConfigureSpace Runbook] --> B[Initialize Error Tracking]
    B --> C{Connect to SharePoint}
    C -->|Success| D[Execute Configuration Functions]
    C -->|Failed| E[Log Error & Throw Exception]
    
    D --> F[SetExternalSharing]
    F -->|Success| G[AddOwners]
    F -->|Failed| F1[Set-SpaceCreationFailed]
    F1 --> G
    
    G -->|Success| H[AddMembers]
    G -->|Failed| G1[Set-SpaceCreationFailed]
    G1 --> H
    
    H -->|Success| I[AddVisitors]
    H -->|Failed| H1[Set-SpaceCreationFailed]
    H1 --> I
    
    I -->|Success| J[More Functions...]
    I -->|Failed| I1[Set-SpaceCreationFailed]
    I1 --> J
    
    J --> K{Check: hasErrors?}
    K -->|Yes| L[Combine Error Messages]
    K -->|No| M[Report Success]
    
    L --> N[Update-ProvisioningRequestStatus]
    N --> O[Throw Exception]
    O --> P[Logic App Catches Exception]
    P --> Q[Handle_Error_Configure_space Activates]
    Q --> R[Update SP List: Space Creation Failed]
    
    M --> S[End: Success]
```

## Error Tracking in Functions

```mermaid
graph LR
    A[Function Execution] --> B{Try Block}
    B -->|Success| C[Continue]
    B -->|Exception| D[Catch Block]
    D --> E[Set-SpaceCreationFailed]
    E --> F[Log to script:errorMessages]
    F --> G[Log to Write-Error]
    G --> C
```

## Benefits

1. **Consistent Error Handling**: Same pattern across all steps
2. **Clear Visibility**: All errors visible in SharePoint list
3. **Detailed Logging**: Error messages identify exact failure point
4. **Graceful Degradation**: Runbook continues even if one function fails
5. **Aggregated Reporting**: All errors collected and reported together
