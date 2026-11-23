import { deferRequestStatus, DEFERRED_REQUEST_STATUS } from './deferRequestStatus'

const owners = { FieldName: 'Owners', FieldValue: '[{"Key":"i:0#.f|membership|a@contoso.com"}]' }

describe('deferRequestStatus', () => {
  it('creates the item as Not Submitted and sets Submitted with the people', () => {
    const result = deferRequestStatus({ Title: 'X', Status: 'Submitted', Stage: 'Submitted' }, [
      owners
    ])
    expect(result.itemProperties).toEqual({
      Title: 'X',
      Status: DEFERRED_REQUEST_STATUS,
      Stage: 'Submitted'
    })
    expect(result.fieldUpdates).toEqual([owners, { FieldName: 'Status', FieldValue: 'Submitted' }])
  })

  it('defers Approved (auto approval) the same way', () => {
    const result = deferRequestStatus({ Status: 'Approved', Stage: 'Approved' }, [owners])
    expect(result.itemProperties).toEqual({ Status: DEFERRED_REQUEST_STATUS, Stage: 'Approved' })
    expect(result.fieldUpdates).toContainEqual({ FieldName: 'Status', FieldValue: 'Approved' })
  })

  it('puts Status last, after the people', () => {
    const members = { FieldName: 'Members', FieldValue: '[]' }
    const result = deferRequestStatus({ Status: 'Submitted' }, [owners, members])
    expect(result.fieldUpdates.map((u) => u.FieldName)).toEqual(['Owners', 'Members', 'Status'])
  })

  it('leaves the status in the first write when there is no second write', () => {
    const item = { Status: 'Submitted' }
    const result = deferRequestStatus(item, [])
    expect(result.itemProperties).toBe(item)
    expect(result.fieldUpdates).toEqual([])
  })

  it('does nothing when the item has no status', () => {
    const item: { Title: string; Status?: string } = { Title: 'X' }
    const result = deferRequestStatus(item, [owners])
    expect(result.itemProperties).toBe(item)
    expect(result.fieldUpdates).toEqual([owners])
  })

  it('does not change its input', () => {
    const item = { Status: 'Submitted' }
    const updates = [owners]
    deferRequestStatus(item, updates)
    expect(item).toEqual({ Status: 'Submitted' })
    expect(updates).toEqual([owners])
  })
})
