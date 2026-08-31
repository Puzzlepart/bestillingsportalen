import { calculateAliasValue } from './calculateAlias'

describe('calculateAliasValue', () => {
  it('strips spaces and illegal characters', () => {
    expect(calculateAliasValue('Mitt Nye Område!')).toBe('MittNyeOmrde')
  })

  it('keeps letters, digits and hyphens', () => {
    expect(calculateAliasValue('abc-123 XYZ')).toBe('abc-123XYZ')
  })

  it('truncates to the 64 character group alias limit', () => {
    expect(calculateAliasValue('a'.repeat(80))).toBe('a'.repeat(64))
  })

  it('reserves room for the naming convention prefix and suffix', () => {
    const alias = calculateAliasValue('a'.repeat(80), { prefixText: 'pre-', suffixText: '-suf' })
    expect(alias).toBe('a'.repeat(64 - 'pre-'.length - '-suf'.length))
  })

  it('always keeps at least one character', () => {
    const alias = calculateAliasValue('abc', {
      prefixText: 'p'.repeat(40),
      suffixText: 's'.repeat(40)
    })
    expect(alias).toBe('a')
  })
})
