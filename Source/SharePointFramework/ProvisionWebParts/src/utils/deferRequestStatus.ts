export interface IFieldUpdate {
  FieldName: string
  FieldValue: string
}

/** The status a request has between its two writes. No Logic App triggers on it. */
export const DEFERRED_REQUEST_STATUS = 'Not Submitted'

/**
 * A provisioning request is saved in two writes: `items.add` with everything
 * but the people fields, then `validateUpdateListItem` with the people. The
 * Logic Apps trigger on every new version whose status is `Submitted`
 * (ProcessApprovalRequest) or `Approved` (ProcessProvisionRequest), so with the
 * status in the first write both versions matched and the request was
 * processed twice - two approval emails, the first one without owners.
 *
 * This moves the status to the second write: the item is created as
 * `Not Submitted` and gets its real status together with the people, so only
 * the complete version matches a trigger. Without field updates there is no
 * second write, and the status stays in the first.
 *
 * `Stage` stays in the first write on purpose: `validateUpdateListItem` checks
 * choice values, and `Approved` is not one of Stage's choices.
 */
export function deferRequestStatus<T extends { Status?: string }>(
  itemProperties: T,
  fieldUpdates: IFieldUpdate[]
): { itemProperties: T; fieldUpdates: IFieldUpdate[] } {
  if (fieldUpdates.length === 0 || !itemProperties.Status) {
    return { itemProperties, fieldUpdates }
  }
  return {
    itemProperties: { ...itemProperties, Status: DEFERRED_REQUEST_STATUS },
    fieldUpdates: [...fieldUpdates, { FieldName: 'Status', FieldValue: itemProperties.Status }]
  }
}
