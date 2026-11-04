import { buildPartyDescription, parsePartyType } from './partyMarker'

describe('partyMarker', () => {
  it('builds a description that parses back to the type', () => {
    const description = buildPartyDescription('Leverandør', 'Opprettet av Samarbeidsparter.')
    expect(description).toBe('Samarbeidspart: Leverandør. Opprettet av Samarbeidsparter.')
    expect(parsePartyType(description)).toBe('Leverandør')
  })

  it('reads descriptions written by the PowerShell prototype', () => {
    expect(parsePartyType('Samarbeidspart: Konsulent. Opprettet med New-Samarbeidspart.ps1.')).toBe(
      'Konsulent'
    )
  })

  it('returns undefined for groups without the marker', () => {
    expect(parsePartyType(undefined)).toBeUndefined()
    expect(parsePartyType('')).toBeUndefined()
    expect(parsePartyType('Eiere av prosjektet')).toBeUndefined()
    expect(parsePartyType('Samarbeidspart: .')).toBeUndefined()
  })
})
