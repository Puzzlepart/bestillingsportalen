import * as React from 'react'
import { Badge, Checkbox, Select } from '@fluentui/react-components'
import * as strings from 'ProvisionWebPartsStrings'

import type { IAccessSnapshot, IAccessTarget, PartyRole } from '../../models/IExternalParties'
import { inheritedFrom, pruneInheritedDesired } from '../../services/parties/accessModel'
import { format } from '../../utils/format'
import { roleText } from './operationText'
import styles from './ExternalParties.module.scss'

export type AccessMap = Record<string, PartyRole | undefined>

export interface IAccessTreeProps {
  snapshot: IAccessSnapshot
  /** The party's access today. Empty for a new party. */
  current: AccessMap
  /** Role names today, as SharePoint shows them, e.g. "Bidra" or "Rediger". */
  currentNames?: Record<string, string>
  value: AccessMap
  onChange: (value: AccessMap) => void
  /** Row shown first, e.g. the new party's own library. */
  leading?: React.ReactNode
  disabled?: boolean
  /** Show «Hele området» first. Existing access on the site is shown anyway. */
  allowSiteAccess?: boolean
}

type ChangeBadge = 'new' | 'changed' | 'removed' | undefined

const changeBadge = (have: PartyRole | undefined, want: PartyRole | undefined): ChangeBadge => {
  if (!have && want) return 'new'
  if (have && !want) return 'removed'
  if (have && want && have !== want) return 'changed'
  return undefined
}

const BADGE_TEXT = {
  new: strings.Parties.BadgeNew,
  changed: strings.Parties.BadgeChanged,
  removed: strings.Parties.BadgeRemoved
}

/**
 * Libraries and their first-level folders with a tick and an access level for
 * each. Changes from today are marked Ny, Endres and Fjernes, so the owner
 * sees what will happen before saving. Protected libraries are shown but can
 * never be ticked.
 */
export const AccessTree: React.FC<IAccessTreeProps> = (props) => {
  const {
    snapshot,
    current,
    currentNames = {},
    value,
    onChange,
    leading,
    disabled,
    allowSiteAccess = true
  } = props
  const libraries = snapshot.targets.filter((t) => t.kind === 'library')
  const site = snapshot.targets.find((t) => t.kind === 'web')
  const showSite =
    !!site && ((allowSiteAccess && !site.isProtected) || current[site.key] !== undefined)
  const foldersOf = (key: string): IAccessTarget[] =>
    snapshot.targets.filter((t) => t.kind === 'folder' && t.parentKey === key)

  // Choosing a target clears choices below it that inherit from it: they get
  // the access through inheritance.
  const set = (key: string, role: PartyRole | undefined): void =>
    onChange(pruneInheritedDesired(snapshot, { ...value, [key]: role }))

  const row = (target: IAccessTarget, nested: boolean): React.ReactNode => {
    const have = current[target.key]
    const want = value[target.key]
    const badge = changeBadge(have, want)
    const label =
      target.kind === 'web'
        ? strings.Parties.SiteAccessLabel
        : nested
          ? target.name || target.title
          : target.title
    const inherited = inheritedFrom(snapshot, target, value)
    if (inherited) {
      return (
        <div className={[styles.treeRow, styles.treeRowInherited].join(' ')}>
          <Checkbox checked disabled label={label} />
          <span className={styles.treeToday}>
            {format(
              inherited.target.kind === 'web'
                ? strings.Parties.InheritsFromSite
                : strings.Parties.InheritsFromLibrary,
              roleText(inherited.role)
            )}
          </span>
        </div>
      )
    }
    if (target.isProtected) {
      return (
        <div className={[styles.treeRow, styles.treeRowMuted].join(' ')}>
          <Checkbox
            disabled
            checked={false}
            label={`${label} · ${strings.Parties.CannotBeShared}`}
          />
        </div>
      )
    }
    return (
      <div className={styles.treeRow}>
        <Checkbox
          checked={want !== undefined}
          disabled={disabled}
          label={label}
          onChange={(_, data) => set(target.key, data.checked ? have || 'Reader' : undefined)}
        />
        {have && (
          <span className={styles.treeToday}>
            {format(strings.Parties.TodayRole, currentNames[target.key] || roleText(have))}
          </span>
        )}
        {badge && (
          <Badge
            size='small'
            appearance='tint'
            color={badge === 'removed' ? 'danger' : badge === 'new' ? 'success' : 'warning'}>
            {BADGE_TEXT[badge]}
          </Badge>
        )}
        {want !== undefined && (
          <Select
            size='small'
            className={styles.treeRole}
            disabled={disabled}
            aria-label={format(strings.Parties.TreeLevelLabel, target.title)}
            value={want}
            onChange={(_, data) => set(target.key, data.value as PartyRole)}>
            <option value='Contributor'>{strings.Parties.RoleContributor}</option>
            <option value='Reader'>{strings.Parties.RoleReader}</option>
          </Select>
        )}
      </div>
    )
  }

  if (libraries.length === 0 && !leading) return <p>{strings.Parties.NoLibraries}</p>

  return (
    <ul className={styles.tree} aria-label={strings.Parties.TreeTitle}>
      {showSite && (
        <li>
          {row(site, false)}
          <p className={styles.treeHint}>{strings.Parties.SiteAccessHint}</p>
        </li>
      )}
      {leading && <li>{leading}</li>}
      {libraries.map((lib) => {
        const folders = lib.isProtected ? [] : foldersOf(lib.key)
        return (
          <li key={lib.key}>
            {row(lib, false)}
            {folders.length > 0 && (
              <ul className={styles.treeChildren}>
                {folders.map((f) => (
                  <li key={f.key}>{row(f, true)}</li>
                ))}
              </ul>
            )}
          </li>
        )
      })}
    </ul>
  )
}
