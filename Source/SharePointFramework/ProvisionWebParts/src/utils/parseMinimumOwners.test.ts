import { parseMinimumOwners } from './parseMinimumOwners'

describe('parseMinimumOwners', () => {
  it('falls back to 1 for unset, empty, non-numeric and non-positive values', () => {
    expect(parseMinimumOwners(undefined)).toBe(1)
    expect(parseMinimumOwners('')).toBe(1)
    expect(parseMinimumOwners('abc')).toBe(1)
    expect(parseMinimumOwners('0')).toBe(1)
    expect(parseMinimumOwners('-2')).toBe(1)
    expect(parseMinimumOwners(true)).toBe(1)
  })

  it('parses positive numeric strings', () => {
    expect(parseMinimumOwners('1')).toBe(1)
    expect(parseMinimumOwners('2')).toBe(2)
    expect(parseMinimumOwners('10')).toBe(10)
  })

  it('accepts numbers as well', () => {
    expect(parseMinimumOwners(3)).toBe(3)
  })
})
