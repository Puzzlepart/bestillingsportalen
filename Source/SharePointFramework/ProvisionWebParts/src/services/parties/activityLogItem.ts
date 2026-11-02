import type { IActivityLogEntry } from './operationRunner'

export const ACTIVITY_LOG_SOURCE = 'Samarbeidsparter'

/** Generic field names, so the list can be shared with other features later. */
export const ACTIVITY_LOG_FIELDS: { name: string; type: 'Text' | 'Note' }[] = [
  { name: 'LogSource', type: 'Text' },
  { name: 'LogAction', type: 'Text' },
  { name: 'LogStatus', type: 'Text' },
  { name: 'LogTargetUrl', type: 'Note' },
  { name: 'LogTargetType', type: 'Text' },
  { name: 'LogPrincipal', type: 'Text' },
  { name: 'LogRole', type: 'Text' },
  { name: 'LogDetails', type: 'Note' },
  { name: 'LogCorrelationId', type: 'Text' }
]

export const fieldXml = (f: { name: string; type: 'Text' | 'Note' }): string =>
  f.type === 'Note'
    ? `<Field Type="Note" Name="${f.name}" StaticName="${f.name}" DisplayName="${f.name}" NumLines="4" RichText="FALSE" UnlimitedLengthInDocumentLibrary="FALSE" />`
    : `<Field Type="Text" Name="${f.name}" StaticName="${f.name}" DisplayName="${f.name}" MaxLength="255" />`

/** Values for one log item. Pure, so it can be tested. */
export const toLogItem = (entry: IActivityLogEntry): Record<string, string> => ({
  Title: entry.action,
  LogSource: ACTIVITY_LOG_SOURCE,
  LogAction: entry.action,
  LogStatus: entry.status,
  LogTargetUrl: entry.targetUrl || '',
  LogTargetType: entry.targetType || '',
  LogPrincipal: (entry.principal || '').substring(0, 255),
  LogRole: entry.role || '',
  LogDetails: entry.details || '',
  LogCorrelationId: entry.correlationId
})
