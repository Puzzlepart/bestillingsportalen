import type { MSGraphClientV3 } from '@microsoft/sp-http'

export interface IUserLookupResult {
  exists: boolean
  givenName?: string
  surname?: string
  displayName?: string
}

/**
 * Looks up a user in the tenant via Microsoft Graph. Used by InviteDrawer to
 * pre-fill profile fields when the invitee already exists in Entra ID.
 * Requires the SPFx solution to be granted User.ReadBasic.All.
 */
export class GraphService {
  constructor(private readonly client: MSGraphClientV3) {}

  public async lookupUser(email: string): Promise<IUserLookupResult> {
    const trimmed = email.trim()
    if (!trimmed) return { exists: false }
    const escaped = trimmed.replace(/'/g, "''")
    const filter = `mail eq '${escaped}' or userPrincipalName eq '${escaped}' or otherMails/any(o:o eq '${escaped}')`
    try {
      const response = (await this.client
        .api('/users')
        .filter(filter)
        .select('givenName,surname,displayName')
        .top(1)
        .get()) as { value?: Array<{ givenName?: string; surname?: string; displayName?: string }> }
      const user = response.value?.[0]
      if (!user) return { exists: false }
      return {
        exists: true,
        givenName: user.givenName,
        surname: user.surname,
        displayName: user.displayName
      }
    } catch {
      return { exists: false }
    }
  }
}
