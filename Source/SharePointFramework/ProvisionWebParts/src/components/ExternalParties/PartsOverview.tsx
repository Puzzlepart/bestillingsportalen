import * as React from 'react'
import {
  Button,
  Link,
  Table,
  TableBody,
  TableCell,
  TableHeader,
  TableHeaderCell,
  TableRow,
  Tag,
  Text
} from '@fluentui/react-components'
import { Add20Regular, ArrowClockwise20Regular, Open16Regular } from '@fluentui/react-icons'
import * as strings from 'ProvisionWebPartsStrings'

import { format } from '../../utils/format'
import { PartiesService } from '../../services/parties/PartiesService'
import {
  brokenTargetsWithoutPrincipal,
  webRoleForPrincipal
} from '../../services/parties/accessModel'
import { RoleKind } from '../../models/IExternalParties'
import { useExternalPartiesContext } from './context'
import { accessText } from './accessText'
import { StatusBadge } from './StatusBadge'
import { partyStatus } from './partyRows'
import styles from './ExternalParties.module.scss'

/** Opens a SharePoint page in a new tab. The SharePoint shell would otherwise navigate in place. */
const openInNewTab = (url: string) => (e: React.MouseEvent) => {
  e.preventDefault()
  window.open(url, '_blank')
}

export const PartsOverview: React.FC = () => {
  const { data, setDrawer, refresh } = useExternalPartiesContext()
  const { site, rows, snapshot, externalProjectManager: epl } = data

  const parties = rows.filter((r) => !r.party.isExternalProjectManager)
  const members = rows.reduce((sum, r) => sum + r.party.memberCount, 0)
  const withoutMembers = parties.filter((r) => r.party.memberCount === 0).length
  // Shown only when the page exists, see useExternalPartiesData.
  const guestInvitationUrl = data.guestInvitationUrl

  const eplWebRole = epl ? webRoleForPrincipal(snapshot, epl.id) : undefined
  const eplMissingCount = epl
    ? brokenTargetsWithoutPrincipal(snapshot, epl.id).filter((t) => !t.isProtected).length
    : 0

  return (
    <>
      <p className={styles.intro}>{strings.Parties.Intro}</p>

      <div className={styles.chips}>
        <Tag size='small' appearance='outline'>
          {format(strings.Parties.ChipParties, parties.length)}
        </Tag>
        <Tag size='small' appearance='outline'>
          {format(strings.Parties.ChipMembers, members)}
        </Tag>
        {withoutMembers > 0 && (
          <Tag size='small' appearance='outline'>
            {format(strings.Parties.ChipNoMembers, withoutMembers)}
          </Tag>
        )}
      </div>

      <div className={styles.toolbar}>
        <Button
          appearance='primary'
          icon={<Add20Regular />}
          onClick={() => setDrawer({ kind: 'new' })}>
          {strings.Parties.NewParty}
        </Button>
        <Button disabled={parties.length === 0} onClick={() => setDrawer({ kind: 'grant' })}>
          {strings.Parties.GrantAccess}
        </Button>
        <span className={styles.spacer} />
        {guestInvitationUrl && (
          <Link href={guestInvitationUrl}>{strings.Parties.InviteGuestsLink}</Link>
        )}
        <Button
          appearance='subtle'
          icon={<ArrowClockwise20Regular />}
          onClick={() => {
            void refresh()
          }}>
          {strings.Parties.Refresh}
        </Button>
      </div>

      <div className={styles.tableWrap}>
        <Table className={styles.table} aria-label={strings.Parties.TableLabel}>
          <TableHeader>
            <TableRow>
              <TableHeaderCell>{strings.Parties.ColumnParty}</TableHeaderCell>
              <TableHeaderCell>{strings.Parties.ColumnType}</TableHeaderCell>
              <TableHeaderCell>{strings.Parties.ColumnAccess}</TableHeaderCell>
              <TableHeaderCell>{strings.Parties.ColumnMembers}</TableHeaderCell>
              <TableHeaderCell>{strings.Parties.ColumnStatus}</TableHeaderCell>
              <TableHeaderCell>{strings.Parties.ColumnActions}</TableHeaderCell>
            </TableRow>
          </TableHeader>
          <TableBody>
            {epl && (
              <TableRow>
                <TableCell>
                  <Button
                    appearance='transparent'
                    className={styles.nameButton}
                    onClick={() => setDrawer({ kind: 'epl' })}>
                    {epl.name}
                  </Button>
                </TableCell>
                <TableCell>{strings.Parties.FixedRole}</TableCell>
                <TableCell>
                  {eplWebRole && eplWebRole.kind !== RoleKind.None ? (
                    <>
                      {strings.Parties.WholeSite}
                      <span className={styles.secondary}>
                        {eplMissingCount > 0
                          ? format(
                              strings.Parties.EplAccessMissing,
                              eplWebRole.name,
                              eplMissingCount
                            )
                          : eplWebRole.name}
                      </span>
                    </>
                  ) : (
                    strings.Parties.AccessNone
                  )}
                </TableCell>
                <TableCell>{epl.memberCount}</TableCell>
                <TableCell>
                  <StatusBadge
                    status={partyStatus(
                      epl.memberCount,
                      !!eplWebRole && eplWebRole.kind !== RoleKind.None
                    )}
                  />
                </TableCell>
                <TableCell>
                  <Link
                    href={PartiesService.groupPageUrl(site.absoluteUrl, epl.id)}
                    onClick={openInNewTab(PartiesService.groupPageUrl(site.absoluteUrl, epl.id))}>
                    {strings.Parties.OpenGroup} <Open16Regular />
                  </Link>
                </TableCell>
              </TableRow>
            )}

            {parties.map((row) => {
              const text = accessText(row)
              const groupUrl = PartiesService.groupPageUrl(site.absoluteUrl, row.party.id)
              return (
                <TableRow key={row.party.id}>
                  <TableCell>
                    <Button
                      appearance='transparent'
                      className={styles.nameButton}
                      onClick={() => setDrawer({ kind: 'party', partyId: row.party.id })}>
                      {row.party.name}
                    </Button>
                  </TableCell>
                  <TableCell>{row.party.type}</TableCell>
                  <TableCell>
                    {text.primary}
                    {text.secondary && <span className={styles.secondary}>{text.secondary}</span>}
                  </TableCell>
                  <TableCell>{row.party.memberCount}</TableCell>
                  <TableCell>
                    <StatusBadge status={row.status} />
                  </TableCell>
                  <TableCell>
                    <Link href={groupUrl} onClick={openInNewTab(groupUrl)}>
                      {strings.Parties.OpenGroup} <Open16Regular />
                    </Link>
                  </TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>

      {parties.length === 0 && <Text>{strings.Parties.EmptyParties}</Text>}

      <Text size={200} className={styles.disclaimer}>
        {strings.Parties.Disclaimer}
      </Text>
    </>
  )
}
