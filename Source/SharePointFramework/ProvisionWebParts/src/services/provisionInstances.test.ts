import { parseProvisionInstances, resolveProvisionUrl, sameInstanceUrl } from './provisionInstances'

describe('parseProvisionInstances', () => {
  it('returns an empty array for undefined, empty and whitespace input', () => {
    expect(parseProvisionInstances(undefined)).toEqual([])
    expect(parseProvisionInstances('')).toEqual([])
    expect(parseProvisionInstances('   ')).toEqual([])
  })

  it('treats a plain string as a single instance titled Bestillingsportalen', () => {
    expect(parseProvisionInstances('/sites/bp')).toEqual([
      { title: 'Bestillingsportalen', url: '/sites/bp' }
    ])
  })

  it('parses a JSON array of {title, url}', () => {
    const raw = JSON.stringify([
      { title: 'BP', url: '/sites/bp' },
      { title: 'BP Stab', url: 'https://contoso.sharepoint.com/sites/bp-stab' }
    ])
    expect(parseProvisionInstances(raw)).toEqual([
      { title: 'BP', url: '/sites/bp' },
      { title: 'BP Stab', url: 'https://contoso.sharepoint.com/sites/bp-stab' }
    ])
  })

  it('returns an empty array for malformed JSON', () => {
    expect(parseProvisionInstances('[{"title": "BP"')).toEqual([])
  })

  it('returns an empty array for a JSON value that is not an array', () => {
    expect(parseProvisionInstances('[1, 2]')).toEqual([])
  })

  it('drops entries without a url and falls back to url as title', () => {
    const raw = JSON.stringify([
      { title: 'No url' },
      { url: '/sites/bp' },
      { title: '', url: '/sites/bp2' }
    ])
    expect(parseProvisionInstances(raw)).toEqual([
      { title: '/sites/bp', url: '/sites/bp' },
      { title: '/sites/bp2', url: '/sites/bp2' }
    ])
  })

  it('reads title/url keys case-insensitively', () => {
    const raw = JSON.stringify([{ Title: 'BP', Url: '/sites/bp' }])
    expect(parseProvisionInstances(raw)).toEqual([{ title: 'BP', url: '/sites/bp' }])
  })

  it('normalizes trailing slashes and dedupes by lowercased url', () => {
    const raw = JSON.stringify([
      { title: 'A', url: '/sites/bp/' },
      { title: 'B', url: '/Sites/BP' },
      { title: 'C', url: '/sites/other' }
    ])
    expect(parseProvisionInstances(raw)).toEqual([
      { title: 'A', url: '/sites/bp' },
      { title: 'C', url: '/sites/other' }
    ])
  })
})

describe('resolveProvisionUrl', () => {
  const instances = [
    { title: 'BP', url: '/sites/bp' },
    { title: 'BP 2', url: '/sites/bp2' }
  ]

  it('lets the property win on SharePoint pages', () => {
    expect(resolveProvisionUrl('/sites/custom', instances, false)).toBe('/sites/custom')
  })

  it('falls back to the registry default on SharePoint pages when the property is empty', () => {
    expect(resolveProvisionUrl('', instances, false)).toBe('/sites/bp')
    expect(resolveProvisionUrl('  ', instances, false)).toBe('/sites/bp')
    expect(resolveProvisionUrl(undefined, instances, false)).toBe('/sites/bp')
  })

  it('lets the registry win in Teams', () => {
    expect(resolveProvisionUrl('/sites/preconfigured', instances, true)).toBe('/sites/bp')
  })

  it('falls back to the property in Teams when no registry exists', () => {
    expect(resolveProvisionUrl('/sites/preconfigured', [], true)).toBe('/sites/preconfigured')
  })

  it('falls back to the conventional default when nothing is configured', () => {
    expect(resolveProvisionUrl(undefined, [], false)).toBe('/sites/bestillingsportalen')
    expect(resolveProvisionUrl(undefined, [], true)).toBe('/sites/bestillingsportalen')
  })
})

describe('sameInstanceUrl', () => {
  it('ignores case and trailing slashes', () => {
    expect(sameInstanceUrl('/Sites/BP/', '/sites/bp')).toBe(true)
  })

  it('is false for different urls or missing values', () => {
    expect(sameInstanceUrl('/sites/bp', '/sites/bp2')).toBe(false)
    expect(sameInstanceUrl(undefined, '/sites/bp')).toBe(false)
    expect(sameInstanceUrl('/sites/bp', undefined)).toBe(false)
  })
})
