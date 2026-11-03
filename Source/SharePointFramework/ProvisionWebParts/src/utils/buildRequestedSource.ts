export interface IRequestedSourceInput {
  /** The web part runs inside Teams (SPFx exposes the Teams SDK) */
  isTeams: boolean
  /** Team the tab lives in - empty for the personal app */
  teamName?: string
  /** Channel the tab lives in - empty for the personal app */
  channelName?: string
  /** Title of the SharePoint site the page belongs to */
  webTitle?: string
  /** Server-relative path of the page the web part is on, e.g. /sites/x/SitePages/Bestill-omrade.aspx */
  serverRequestPath?: string
  /** Label for the Teams personal app, e.g. "Teams: Bestillingsportalen" */
  teamsAppLabel: string
  /** Used when neither the host nor the page can be told */
  fallback: string
}

/** The `Requested Source` column is a 255-character text field. */
const MAX_LENGTH = 255

/**
 * Builds the `Requested Source` value written on a new request, so the status
 * list tells where an order came from: a Teams channel tab, the Teams personal
 * app, or a page on a SharePoint site.
 *
 * - Teams channel tab: `Teams: <team> / <channel>`
 * - Teams personal app: the `teamsAppLabel`
 * - SharePoint page: `<site title> - <page name>` (the page file name without
 *   `.aspx`, hyphens shown as spaces, since that is how SharePoint derives the
 *   file name from the page title)
 * - otherwise the `fallback`
 */
export function buildRequestedSource(input: IRequestedSourceInput): string {
  let value: string
  if (input.isTeams) {
    const team = clean(input.teamName)
    const channel = clean(input.channelName)
    value = team ? `Teams: ${team}${channel ? ` / ${channel}` : ''}` : input.teamsAppLabel
  } else {
    const site = clean(input.webTitle)
    const page = pageNameFromPath(input.serverRequestPath)
    value = site && page ? `${site} - ${page}` : site || input.fallback
  }
  return value.length > MAX_LENGTH ? value.substring(0, MAX_LENGTH) : value
}

function clean(value?: string): string {
  return (value || '').trim()
}

function pageNameFromPath(path?: string): string {
  if (!path) return ''
  const last = path.split('?')[0].split('#')[0].split('/').filter(Boolean).pop()
  if (!last) return ''
  let name = last
  try {
    name = decodeURIComponent(last)
  } catch {
    // keep the raw segment
  }
  if (!/\.aspx$/i.test(name)) return ''
  return name
    .replace(/\.aspx$/i, '')
    .replace(/-/g, ' ')
    .trim()
}
