import {
  DEFAULT_PART_TYPES,
  guestInvitationLink,
  isProtectedLibrary,
  parsePartTypes,
  resolvePartiesConfig,
  resolveGroupPrefix,
  splitList,
  stripGroupPrefix,
  toServerRelativeUrl
} from './partyConfig'

describe('splitList', () => {
  it('splits on comma, semicolon and newline and trims', () => {
    expect(splitList('Interne dokumenter; Kontrakter,\n Arkiv ')).toEqual([
      'Interne dokumenter',
      'Kontrakter',
      'Arkiv'
    ])
  })

  it('returns an empty list for empty input', () => {
    expect(splitList('')).toEqual([])
    expect(splitList(undefined)).toEqual([])
  })
})

describe('parsePartTypes', () => {
  it('falls back to the defaults for empty or invalid JSON', () => {
    expect(parsePartTypes(undefined)).toBe(DEFAULT_PART_TYPES)
    expect(parsePartTypes('')).toBe(DEFAULT_PART_TYPES)
    expect(parsePartTypes('{not json')).toBe(DEFAULT_PART_TYPES)
    expect(parsePartTypes('[{"label":"Uten nøkkel"}]')).toBe(DEFAULT_PART_TYPES)
  })

  it('accepts a list or an object with partTypes, and fills in missing values', () => {
    const fromList = parsePartTypes('[{"key":"rad","label":"Rådgiver","ownLibraryRole":"Reader"}]')
    expect(fromList).toEqual([
      {
        key: 'rad',
        label: 'Rådgiver',
        libraryTitle: 'Rådgiver – {name}',
        libraryUrl: '{code}',
        folders: [],
        ownLibraryRole: 'Reader'
      }
    ])
    const fromObject = parsePartTypes(
      '{"partTypes":[{"key":"a","label":"A","ownLibraryRole":"Owner"}]}'
    )
    expect(fromObject[0].ownLibraryRole).toBe('Contributor')
  })
})

describe('group prefix', () => {
  it('replaces {sitename} with the site title', () => {
    expect(resolveGroupPrefix('{sitename} – ', 'Kaiprosjekt')).toBe('Kaiprosjekt – ')
    expect(resolveGroupPrefix(undefined, 'Kaiprosjekt')).toBe('Kaiprosjekt – ')
  })

  it('strips the prefix case-insensitively and leaves other titles alone', () => {
    expect(stripGroupPrefix('Kaiprosjekt – Leverandør A', 'kaiprosjekt – ')).toBe('Leverandør A')
    expect(stripGroupPrefix('Annet prosjekt – X', 'Kaiprosjekt – ')).toBe('Annet prosjekt – X')
  })
})

describe('toServerRelativeUrl', () => {
  it('joins site-relative paths and keeps server-relative paths', () => {
    expect(toServerRelativeUrl('/sites/kai', 'Lists/ActivityLog')).toBe(
      '/sites/kai/Lists/ActivityLog'
    )
    expect(toServerRelativeUrl('/sites/kai/', '/Lists/ActivityLog')).toBe('/Lists/ActivityLog')
    expect(toServerRelativeUrl('/sites/kai', '')).toBe('/sites/kai')
  })
})

describe('isProtectedLibrary', () => {
  it('matches title or URL name case-insensitively', () => {
    expect(
      isProtectedLibrary('Interne dokumenter', '/sites/kai/Interne dokumenter', [
        'interne dokumenter'
      ])
    ).toBe(true)
    expect(
      isProtectedLibrary('Interne', '/sites/kai/InterneDokumenter', ['InterneDokumenter'])
    ).toBe(true)
    expect(
      isProtectedLibrary('Dokumenter', '/sites/kai/Shared Documents', ['Interne dokumenter'])
    ).toBe(false)
  })

  it('decodes encoded URL names', () => {
    expect(isProtectedLibrary('X', '/sites/kai/Interne%20dokumenter', ['Interne dokumenter'])).toBe(
      true
    )
  })
})

describe('resolvePartiesConfig', () => {
  it('has neutral defaults, so the web part works on any site', () => {
    const c = resolvePartiesConfig({})
    expect(c.externalProjectManager).toBe('')
    expect(c.protectedLibraries).toEqual([])
    expect(c.guestInvitationUrl).toBe('')
    expect(c.navigationHeading).toBe('Samarbeidsparter')
    expect(c.allowSiteAccess).toBe(true)
    expect(c.groupPrefix).toBe('{sitename} – ')
    expect(c.partTypes.map((t) => t.label)).toEqual(['Konsulent', 'Leverandør', 'Intern'])
    expect(c.partTypes.every((t) => t.folders.length === 0)).toBe(true)
  })

  it('uses the values a template sets, and an empty value turns a feature off', () => {
    const c = resolvePartiesConfig({
      externalProjectManager: ' Ekstern prosjektleder ',
      protectedLibraries: 'Interne dokumenter',
      navigationHeading: '',
      guestInvitationUrl: 'SitePages/Inviter-gjester.aspx',
      librariesFilter: '  ',
      activityLogUrl: '',
      allowSiteAccess: false
    })
    expect(c.externalProjectManager).toBe('Ekstern prosjektleder')
    expect(c.protectedLibraries).toEqual(['Interne dokumenter'])
    expect(c.navigationHeading).toBe('')
    expect(c.allowSiteAccess).toBe(false)
    expect(c.guestInvitationUrl).toBe('SitePages/Inviter-gjester.aspx')
    // Required values fall back to the default when empty.
    expect(c.librariesFilter).toContain('BaseTemplate eq 101')
    expect(c.activityLogUrl).toBe('Lists/ActivityLog')
  })
})

describe('guestInvitationLink', () => {
  it('adds the group to the guest invitation page link', () => {
    expect(guestInvitationLink('/sites/k/SitePages/Inviter-gjester.aspx', 12)).toBe(
      '/sites/k/SitePages/Inviter-gjester.aspx?inviteGroup=12'
    )
    expect(guestInvitationLink('/sites/k/SitePages/Inviter.aspx?a=1#top', 7)).toBe(
      '/sites/k/SitePages/Inviter.aspx?a=1&inviteGroup=7#top'
    )
    expect(guestInvitationLink('/sites/k/SitePages/Inviter.aspx', undefined)).toBe(
      '/sites/k/SitePages/Inviter.aspx'
    )
  })
})
