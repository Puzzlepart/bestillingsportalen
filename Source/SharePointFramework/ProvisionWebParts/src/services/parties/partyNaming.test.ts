import { DEFAULT_PART_TYPES } from './partyConfig'
import {
  defineNewParty,
  errorMessage,
  isLinklessHeading,
  normalizeNavUrl,
  suggestLibraryCode,
  validateLibraryCode,
  validatePartyName
} from './partyNaming'

// A type as a template sets it up, with standard folders. The defaults have no folders.
const leverandor = {
  ...DEFAULT_PART_TYPES[1],
  folders: ['01 Grunnlag', '02 Korrespondanse', '03 Leveranser']
}
const intern = DEFAULT_PART_TYPES[2]

describe('validatePartyName', () => {
  it('accepts normal names and rejects empty, long and forbidden names', () => {
    expect(validatePartyName('Rådgiver A')).toBeUndefined()
    expect(validatePartyName('  ')).toBe('Required')
    expect(validatePartyName('x'.repeat(61))).toBe('TooLong')
    expect(validatePartyName('A/S Bygg')).toBe('InvalidCharacters')
    expect(validatePartyName("O'Brien")).toBe('InvalidCharacters')
  })
})

describe('validateLibraryCode', () => {
  it('requires 2–20 letters and digits starting with a letter', () => {
    expect(validateLibraryCode('RadA')).toBeUndefined()
    expect(validateLibraryCode('')).toBe('Required')
    expect(validateLibraryCode('1Rad')).toBe('Invalid')
    expect(validateLibraryCode('R')).toBe('Invalid')
    expect(validateLibraryCode('Råd')).toBe('Invalid')
  })
})

describe('suggestLibraryCode', () => {
  it('turns the name into a valid code', () => {
    expect(suggestLibraryCode('Rådgiver Ø-Æ')).toBe('RadgiverOAe')
    expect(suggestLibraryCode('3D Skanning')).toBe('DSkanning')
    expect(suggestLibraryCode('é')).toBe('')
    expect(
      validateLibraryCode(suggestLibraryCode('Byggmester Bjørnsen AS – avd. Sør'))
    ).toBeUndefined()
  })
})

describe('defineNewParty', () => {
  it('resolves group and library names like the PowerShell prototype', () => {
    const def = defineNewParty(
      { name: ' Leverandør A ', type: leverandor, ownLibrary: true, code: 'LevA' },
      'Kaiprosjekt',
      '/sites/kai/',
      '{sitename} – '
    )
    expect(def).toEqual({
      name: 'Leverandør A',
      groupTitle: 'Kaiprosjekt – Leverandør A',
      groupDescription: 'Samarbeidspart: Leverandør. Opprettet med Samarbeidsparter.',
      library: {
        title: 'Leverandør – Leverandør A',
        urlName: 'LevLevA',
        serverRelativeUrl: '/sites/kai/LevLevA',
        description: 'Samarbeidspart: Leverandør. Eget bibliotek for Kaiprosjekt – Leverandør A.',
        folders: ['01 Grunnlag', '02 Korrespondanse', '03 Leveranser'],
        role: 'Contributor'
      }
    })
  })

  it('has no library without ownLibrary', () => {
    const def = defineNewParty(
      { name: 'Evaluering', type: intern, ownLibrary: false },
      'K',
      '/sites/k',
      ''
    )
    expect(def.groupTitle).toBe('Evaluering')
    expect(def.library).toBeUndefined()
  })
})

describe('navigation helpers', () => {
  it('normalizes URLs and recognizes linkless headings', () => {
    expect(normalizeNavUrl('https://t.sharepoint.com/sites/k/Lev%20A/')).toBe('/sites/k/lev a')
    expect(normalizeNavUrl('/sites/k/%E0%A4%A')).toBe('/sites/k/%e0%a4%a')
    expect(isLinklessHeading('http://linkless.header/')).toBe(true)
    expect(isLinklessHeading('/sites/k')).toBe(false)
  })
})

describe('errorMessage', () => {
  it('reads the SharePoint message from a PnPjs error', () => {
    const e = new Error(
      'Error making HttpClient request in queryable [400] Bad Request ::> {"odata.error":{"code":"-1","message":{"lang":"nb-NO","value":"Gruppen finnes"}}}'
    )
    expect(errorMessage(e)).toBe('Gruppen finnes')
    expect(errorMessage(new Error('Nettverksfeil'))).toBe('Nettverksfeil')
  })
})
