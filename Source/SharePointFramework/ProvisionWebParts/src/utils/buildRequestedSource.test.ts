import { buildRequestedSource } from './buildRequestedSource'

const base = {
  teamsAppLabel: 'Teams: Bestillingsportalen',
  fallback: 'Prosjektportalen - Bestillingsskjema'
}

describe('buildRequestedSource', () => {
  it('names the team and channel for a Teams channel tab', () => {
    expect(
      buildRequestedSource({
        ...base,
        isTeams: true,
        teamName: 'Prosjektkontoret',
        channelName: 'Generelt'
      })
    ).toBe('Teams: Prosjektkontoret / Generelt')
  })

  it('names only the team when the channel is unknown', () => {
    expect(buildRequestedSource({ ...base, isTeams: true, teamName: 'Prosjektkontoret' })).toBe(
      'Teams: Prosjektkontoret'
    )
  })

  it('uses the app label for the Teams personal app', () => {
    expect(buildRequestedSource({ ...base, isTeams: true })).toBe('Teams: Bestillingsportalen')
    expect(buildRequestedSource({ ...base, isTeams: true, teamName: '  ', channelName: 'x' })).toBe(
      'Teams: Bestillingsportalen'
    )
  })

  it('names the site and the page for a SharePoint page', () => {
    expect(
      buildRequestedSource({
        ...base,
        isTeams: false,
        webTitle: 'Prosjektportalen',
        serverRequestPath: '/sites/nfkprosjekter/SitePages/Bestill-omr%C3%A5de.aspx'
      })
    ).toBe('Prosjektportalen - Bestill område')
  })

  it('ignores query string and hash, and is case-insensitive on .aspx', () => {
    expect(
      buildRequestedSource({
        ...base,
        isTeams: false,
        webTitle: 'Portal',
        serverRequestPath: '/sites/x/SitePages/Home.ASPX?env=WebView#top'
      })
    ).toBe('Portal - Home')
  })

  it('falls back to the site title when the path is not a page', () => {
    expect(
      buildRequestedSource({
        ...base,
        isTeams: false,
        webTitle: 'Portal',
        serverRequestPath: '/sites/x'
      })
    ).toBe('Portal')
    expect(buildRequestedSource({ ...base, isTeams: false, webTitle: 'Portal' })).toBe('Portal')
  })

  it('falls back to the default label when nothing is known', () => {
    expect(buildRequestedSource({ ...base, isTeams: false })).toBe(base.fallback)
    expect(buildRequestedSource({ ...base, isTeams: false, webTitle: ' ' })).toBe(base.fallback)
  })

  it('keeps a malformed escape sequence as it is', () => {
    expect(
      buildRequestedSource({
        ...base,
        isTeams: false,
        webTitle: 'Portal',
        serverRequestPath: '/s/SitePages/%E0%A4%A.aspx'
      })
    ).toBe('Portal - %E0%A4%A')
  })

  it('cuts the value to the 255 characters the column holds', () => {
    const value = buildRequestedSource({ ...base, isTeams: true, teamName: 'a'.repeat(300) })
    expect(value.length).toBe(255)
  })
})
