import {
  DEFAULT_PART_TYPES,
  isProtectedLibrary,
  parsePartTypes,
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
