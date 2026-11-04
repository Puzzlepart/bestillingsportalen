import * as React from 'react'
import { Button, Field, MessageBar, MessageBarBody, Select, Text } from '@fluentui/react-components'
import * as strings from 'ProvisionWebPartsStrings'

import {
  accessForPrincipal,
  buildAccessOperations,
  currentDesiredAccess,
  planAccessChanges
} from '../../services/parties'
import { format } from '../../utils/format'
import { AccessPreview } from './AccessPreview'
import { AccessTree, type AccessMap } from './AccessTree'
import { useExternalPartiesContext } from './context'
import { OperationProgress } from './OperationProgress'
import { DrawerShell } from './PartyDrawers'
import { useOperationRun } from './useOperationRun'
import styles from './ExternalParties.module.scss'

/**
 * «Gi tilgang» and «Endre tilgang»: the party's access today is ticked in the
 * tree. The owner ticks, changes the level or clears ticks, sees what will
 * happen, and saves. The steps run one at a time with status for each.
 */
export const GrantDrawer: React.FC<{ partyId?: number }> = ({ partyId }) => {
  const { data, config, refresh, services, markNeedsRefresh } = useExternalPartiesContext()
  const { snapshot, externalProjectManager: epl } = data
  const parties = data.rows.filter((r) => !r.party.isExternalProjectManager).map((r) => r.party)
  const [selectedId, setSelectedId] = React.useState<number | undefined>(partyId ?? parties[0]?.id)
  const party = parties.find((p) => p.id === selectedId)
  const { run, start, reset } = useOperationRun()

  const current = React.useMemo(
    () => (selectedId === undefined ? {} : currentDesiredAccess(snapshot, selectedId)),
    [snapshot, selectedId]
  )
  const currentNames = React.useMemo(() => {
    const names: Record<string, string> = {}
    if (selectedId !== undefined) {
      for (const a of accessForPrincipal(snapshot, selectedId)) names[a.target.key] = a.roleName
    }
    return names
  }, [snapshot, selectedId])
  const [desired, setDesired] = React.useState<AccessMap>(current)
  // Start from today's access when another party is chosen or the access is read again.
  React.useEffect(() => setDesired(current), [current])

  const plan = React.useMemo(
    () =>
      selectedId === undefined
        ? { changes: [], steps: [], rejected: [] }
        : planAccessChanges({
            snapshot,
            partyId: selectedId,
            externalProjectManagerId: epl?.id,
            desired
          }),
    [snapshot, selectedId, epl, desired]
  )

  const operations = React.useRef<ReturnType<typeof buildAccessOperations>>()
  /** Reads the access again after a run. After a failure it is read when the panel closes. */
  const runAndRefresh = async (): Promise<void> => {
    if (await start(operations.current, services.logger)) await refresh()
    else markNeedsRefresh()
  }
  const save = async (): Promise<void> => {
    if (!party) return
    operations.current = buildAccessOperations(
      services.writer,
      plan,
      { id: party.id, title: party.title },
      epl ? { id: epl.id, title: epl.title, name: epl.name } : undefined
    )
    await runAndRefresh()
  }
  const retry = async (): Promise<void> => {
    if (operations.current) await runAndRefresh()
  }

  const busy = run?.status === 'running'
  const count = plan.changes.length
  let footer: React.ReactNode
  if (!run) {
    footer = (
      <Button
        appearance='primary'
        disabled={count === 0}
        onClick={() => {
          void save()
        }}>
        {count === 0
          ? strings.Parties.Save
          : count === 1
            ? strings.Parties.SaveChangesOne
            : format(strings.Parties.SaveChangesMany, count)}
      </Button>
    )
  } else if (run.status === 'failed') {
    footer = (
      <Button
        appearance='primary'
        onClick={() => {
          void retry()
        }}>
        {strings.Parties.TryAgain}
      </Button>
    )
  } else if (run.status === 'ok') {
    footer = <Button onClick={reset}>{strings.Parties.ChangeAccess}</Button>
  }

  return (
    <DrawerShell
      title={party ? format(strings.Parties.GrantTitle, party.name) : strings.Parties.GrantAccess}
      footer={footer}
      closeLabel={run ? strings.Parties.Close : strings.Parties.Cancel}
      focusKey={run?.status || 'edit'}>
      {parties.length === 0 ? (
        <Text>{strings.Parties.EmptyParties}</Text>
      ) : run ? (
        <>
          {run.status === 'ok' && (
            <MessageBar intent='success'>
              <MessageBarBody>{strings.Parties.SavedMessage}</MessageBarBody>
            </MessageBar>
          )}
          {run.status === 'failed' && (
            <MessageBar intent='error'>
              <MessageBarBody>{strings.Parties.FailedMessage}</MessageBarBody>
            </MessageBar>
          )}
          <OperationProgress states={run.states} label={strings.Parties.StepStatus} />
        </>
      ) : (
        <>
          <Field label={strings.Parties.PartyLabel}>
            <Select
              value={selectedId === undefined ? '' : String(selectedId)}
              disabled={busy}
              onChange={(_, d) => setSelectedId(Number(d.value))}>
              {parties.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </Select>
          </Field>

          <div>
            <h3 className={styles.sectionTitle}>{strings.Parties.TreeTitle}</h3>
            <p className={styles.hint}>{strings.Parties.TreeHint}</p>
          </div>
          <AccessTree
            allowSiteAccess={config.allowSiteAccess}
            snapshot={snapshot}
            current={current}
            currentNames={currentNames}
            value={desired}
            onChange={setDesired}
          />

          <AccessPreview
            title={strings.Parties.PreviewTitle}
            changes={plan.changes}
            roleNames={currentNames}
          />
          {plan.rejected.length > 0 && (
            <MessageBar intent='warning'>
              <MessageBarBody>
                {format(strings.Parties.Rejected, plan.rejected.join(', '))}
              </MessageBarBody>
            </MessageBar>
          )}
        </>
      )}
    </DrawerShell>
  )
}
