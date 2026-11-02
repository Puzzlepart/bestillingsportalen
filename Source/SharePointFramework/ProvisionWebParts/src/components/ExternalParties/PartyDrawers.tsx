import * as React from 'react'
import {
  Button,
  DrawerBody,
  DrawerFooter,
  DrawerHeader,
  DrawerHeaderTitle,
  Link,
  MessageBar,
  MessageBarBody,
  Text
} from '@fluentui/react-components'
import { Dismiss24Regular, Open16Regular } from '@fluentui/react-icons'
import * as strings from 'ProvisionWebPartsStrings'

import { format } from '../../utils/format'
import { PartiesService } from '../../services/parties/PartiesService'
import { webRoleForPrincipal } from '../../services/parties/accessModel'
import { RoleKind } from '../../models/IExternalParties'
import { useExternalPartiesContext } from './context'
import { membersText } from './accessText'
import styles from './ExternalParties.module.scss'

const openInNewTab = (url: string) => (e: React.MouseEvent) => {
  e.preventDefault()
  window.open(url, '_blank')
}

/**
 * Header, body and footer of a panel. The OverlayDrawer itself lives in
 * ExternalParties and stays mounted: removing an open OverlayDrawer leaves
 * aria-hidden on the rest of the page, and screen readers lose the page.
 */
export const DrawerShell: React.FC<{
  title: string
  footer?: React.ReactNode
  closeLabel?: string
  /** When this changes, focus moves to the title, e.g. on a new step. */
  focusKey?: string | number
}> = ({ title, footer, closeLabel, focusKey, children }) => {
  const { setDrawer } = useExternalPartiesContext()
  const close = (): void => setDrawer({ kind: 'none' })
  const headingRef = React.useRef<HTMLHeadingElement>(null)
  const mounted = React.useRef(false)

  // Keep focus inside the panel when its content is replaced. Without this,
  // focus falls back to the page and Escape no longer closes the panel.
  React.useEffect(() => {
    const heading = headingRef.current
    const dialog = heading?.closest('[role="dialog"]')
    const focusLost = !dialog || !dialog.contains(document.activeElement)
    if (heading && (mounted.current || focusLost)) heading.focus()
    mounted.current = true
  }, [focusKey])

  return (
    <>
      <DrawerHeader>
        <DrawerHeaderTitle
          heading={{ ref: headingRef, tabIndex: -1 }}
          action={
            <Button
              appearance='subtle'
              aria-label={strings.Parties.Close}
              icon={<Dismiss24Regular />}
              onClick={close}
            />
          }>
          {title}
        </DrawerHeaderTitle>
      </DrawerHeader>
      <DrawerBody className={styles.drawerBody}>{children}</DrawerBody>
      <DrawerFooter>
        {footer}
        <Button onClick={close}>{closeLabel || strings.Parties.Close}</Button>
      </DrawerFooter>
    </>
  )
}

/** The party's group and the libraries and first-level folders it has access to today. */
export const PartyDrawer: React.FC<{ partyId: number }> = ({ partyId }) => {
  const { data, setDrawer } = useExternalPartiesContext()
  const row = data.rows.find((r) => r.party.id === partyId)
  if (!row) return null
  const { party } = row
  const groupUrl = PartiesService.groupPageUrl(data.site.absoluteUrl, party.id)

  return (
    <DrawerShell
      title={party.name}
      footer={
        <Button
          appearance='primary'
          onClick={() => setDrawer({ kind: 'grant', partyId: party.id })}>
          {strings.Parties.ChangeAccess}
        </Button>
      }>
      <div className={styles.groupLine}>
        <Text>{`${party.type} · ${membersText(party.memberCount)}`}</Text>
        <Link href={groupUrl} onClick={openInNewTab(groupUrl)}>
          {strings.Parties.OpenGroup} <Open16Regular />
        </Link>
      </div>
      <div className={styles.groupLine}>
        <span className={styles.groupTitle}>{party.title}</span>
      </div>

      <div>
        <h3 className={styles.sectionTitle}>{strings.Parties.AccessToday}</h3>
        <p className={styles.hint}>{strings.Parties.AccessTodayHint}</p>
      </div>

      {row.access.length === 0 ? (
        <Text>{strings.Parties.NoAccessYet}</Text>
      ) : (
        <ul className={styles.accessList}>
          {row.access.map((a) => (
            <li key={a.target.key} className={styles.accessItem}>
              <span>{a.target.title}</span>
              <span className={styles.accessRole}>{a.roleName}</span>
              <span className={styles.accessSource}>
                {a === row.ownLibrary
                  ? strings.Parties.KindOwnLibrary
                  : a.target.kind === 'library'
                    ? strings.Parties.KindLibrary
                    : strings.Parties.KindFolder}
              </span>
            </li>
          ))}
        </ul>
      )}

      <MessageBar intent='info'>
        <MessageBarBody>{strings.Parties.DrawerDisclaimer}</MessageBarBody>
      </MessageBar>
    </DrawerShell>
  )
}

/**
 * Access for the external project manager: the role on the site, and the
 * access on every library and first-level folder with unique role
 * assignments. Read-only: the web part does not change this role.
 */
export const EplDrawer: React.FC = () => {
  const { data } = useExternalPartiesContext()
  const epl = data.externalProjectManager
  if (!epl) return null
  const { snapshot, site } = data
  const webRole = webRoleForPrincipal(snapshot, epl.id)
  const broken = snapshot.targets.filter((t) => t.hasUniqueRoleAssignments)
  const groupUrl = PartiesService.groupPageUrl(site.absoluteUrl, epl.id)

  return (
    <DrawerShell title={strings.Parties.ExternalProjectManager}>
      <div className={styles.groupLine}>
        <Text>{`${strings.Parties.FixedRole} · ${membersText(epl.memberCount)}`}</Text>
        <Link href={groupUrl} onClick={openInNewTab(groupUrl)}>
          {strings.Parties.OpenGroup} <Open16Regular />
        </Link>
      </div>

      <div className={styles.summaryBox}>
        <h3 className={styles.sectionTitle}>{strings.Parties.EplSiteAccess}</h3>
        <Text>
          {webRole.kind !== RoleKind.None
            ? format(strings.Parties.EplSiteRole, webRole.name)
            : strings.Parties.EplNoSiteAccess}
        </Text>
      </div>

      <div>
        <h3 className={styles.sectionTitle}>{strings.Parties.EplBroken}</h3>
        <p className={styles.hint}>{strings.Parties.EplBrokenHint}</p>
      </div>

      {broken.length === 0 ? (
        <Text>{strings.Parties.NoBroken}</Text>
      ) : (
        <ul className={styles.accessList}>
          {broken.map((t) => {
            const ra = (snapshot.assignments[t.key] || []).find((a) => a.principalId === epl.id)
            const role = ra?.roles.map((r) => r.name).join(', ')
            return (
              <li
                key={t.key}
                className={[styles.accessItem, role ? '' : styles.accessItemMuted].join(' ')}>
                <span>{t.title}</span>
                <span className={styles.accessRole}>{role || strings.Parties.NoAccessLabel}</span>
                {t.isProtected && (
                  <span className={styles.accessSource}>{strings.Parties.ProtectedLibrary}</span>
                )}
              </li>
            )
          })}
        </ul>
      )}

      <MessageBar intent='info'>
        <MessageBarBody>
          {strings.Parties.EplReadOnly} {strings.Parties.DrawerDisclaimer}
        </MessageBarBody>
      </MessageBar>
    </DrawerShell>
  )
}
