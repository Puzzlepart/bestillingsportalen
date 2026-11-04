import * as React from 'react'
import {
  Button,
  Checkbox,
  Field,
  Input,
  MessageBar,
  MessageBarBody,
  Radio,
  RadioGroup
} from '@fluentui/react-components'
import { Checkmark16Regular } from '@fluentui/react-icons'
import * as strings from 'ProvisionWebPartsStrings'

import {
  buildAccessOperations,
  buildNewPartyOperations,
  defineNewParty,
  guestInvitationLink,
  type INewPartyContext,
  type IOperation,
  type LibraryCodeError,
  type PartyNameError,
  planAccessChanges,
  suggestLibraryCode,
  validateLibraryCode,
  validatePartyName
} from '../../services/parties'
import { format } from '../../utils/format'
import { AccessPreview } from './AccessPreview'
import { AccessTree, type AccessMap } from './AccessTree'
import { useExternalPartiesContext } from './context'
import { OperationProgress } from './OperationProgress'
import { roleText } from './operationText'
import { DrawerShell } from './PartyDrawers'
import { useOperationRun } from './useOperationRun'
import styles from './ExternalParties.module.scss'

type Step = 1 | 2 | 3

const NAME_ERRORS: Record<PartyNameError | 'InUse', string> = {
  Required: strings.Parties.NameRequired,
  TooLong: strings.Parties.NameTooLong,
  InvalidCharacters: strings.Parties.NameInvalid,
  InUse: strings.Parties.NameInUse
}

const CODE_ERRORS: Record<LibraryCodeError | 'InUse', string> = {
  Required: strings.Parties.CodeRequired,
  Invalid: strings.Parties.CodeInvalid,
  InUse: strings.Parties.CodeInUse
}

/** No party id yet. Used to plan access for a group that does not exist. */
const NEW_PARTY_ID = -1

const Stepper: React.FC<{ step: Step }> = ({ step }) => {
  const steps = [strings.Parties.StepPart, strings.Parties.StepAccess, strings.Parties.StepStatus]
  return (
    <ol className={styles.stepper} aria-label={strings.Parties.StepsLabel}>
      {steps.map((label, i) => {
        const n = (i + 1) as Step
        const state = n < step ? 'done' : n === step ? 'current' : 'next'
        return (
          <li key={label} className={styles.stepperItem} data-state={state}>
            <span className={styles.stepperDot} aria-hidden='true'>
              {state === 'done' ? <Checkmark16Regular /> : n}
            </span>
            <span aria-current={state === 'current' ? 'step' : undefined}>{label}</span>
          </li>
        )
      })}
    </ol>
  )
}

const SummaryRow: React.FC<{ label: string }> = ({ label, children }) => (
  <>
    <dt>{label}</dt>
    <dd>{children}</dd>
  </>
)

/**
 * «Ny part» in three steps: the party (name, type, own library), access to
 * libraries and folders, and status while it is created. Nothing is created
 * before the owner confirms in step 2. Every step can run again, so a new
 * attempt with the same name and code continues where the last one stopped.
 */
export const NewPartWizard: React.FC = () => {
  const { data, config, refresh, services, markNeedsRefresh } = useExternalPartiesContext()
  const { site, snapshot, externalProjectManager: epl } = data
  const types = config.partTypes
  const [step, setStep] = React.useState<Step>(1)
  const [name, setName] = React.useState('')
  const [typeKey, setTypeKey] = React.useState(types[0]?.key)
  const [ownLibrary, setOwnLibrary] = React.useState(true)
  const [code, setCode] = React.useState<string>()
  const [showErrors, setShowErrors] = React.useState(false)
  const [desired, setDesired] = React.useState<AccessMap>({})
  const { run, start } = useOperationRun()
  const operations = React.useRef<IOperation[]>()
  const newPartyContext = React.useRef<INewPartyContext>()

  const type = types.find((t) => t.key === typeKey) || types[0]
  const effectiveCode = code ?? suggestLibraryCode(name)
  const definition = React.useMemo(
    () =>
      defineNewParty(
        { name, type, ownLibrary, code: effectiveCode },
        site.title,
        site.serverRelativeUrl,
        config.groupPrefix
      ),
    [name, type, ownLibrary, effectiveCode, site, config.groupPrefix]
  )

  const nameKey = validatePartyName(name)
  const nameError =
    nameKey ??
    (data.parties.some((p) => p.title.toLowerCase() === definition.groupTitle.toLowerCase())
      ? 'InUse'
      : undefined)
  const codeKey = ownLibrary ? validateLibraryCode(effectiveCode) : undefined
  const codeError =
    codeKey ??
    (ownLibrary &&
    snapshot.targets.some(
      (t) => t.key.toLowerCase() === definition.library?.serverRelativeUrl.toLowerCase()
    )
      ? 'InUse'
      : undefined)
  const valid = !nameError && !codeError

  const plan = React.useMemo(
    () =>
      planAccessChanges({
        snapshot,
        partyId: NEW_PARTY_ID,
        externalProjectManagerId: epl?.id,
        desired
      }),
    [snapshot, epl, desired]
  )

  const next = (): void => {
    setShowErrors(true)
    if (valid) setStep(2)
  }

  /** Reads the access again after a run. After a failure it is read when the panel closes. */
  const runAndRefresh = async (): Promise<void> => {
    if (await start(operations.current, services.logger)) await refresh()
    else markNeedsRefresh()
  }
  const create = async (): Promise<void> => {
    const eplRef = epl ? { id: epl.id, title: epl.title, name: epl.name } : undefined
    const context: INewPartyContext = {}
    newPartyContext.current = context
    const party = {
      get id(): number {
        return context.groupId
      },
      title: definition.groupTitle
    }
    operations.current = [
      ...buildNewPartyOperations(
        services.writer,
        definition,
        { externalProjectManager: eplRef, navigationHeading: config.navigationHeading },
        context
      ),
      ...buildAccessOperations(services.writer, plan, party, eplRef)
    ]
    setStep(3)
    await runAndRefresh()
  }
  const retry = async (): Promise<void> => {
    if (operations.current) await runAndRefresh()
  }

  // Opens Inviter gjester with the new party's group chosen.
  const guestUrl =
    data.guestInvitationUrl &&
    guestInvitationLink(data.guestInvitationUrl, newPartyContext.current?.groupId)
  const ownLibraryAccess = definition.library
    ? format(
        strings.Parties.SummaryOwnLibraryAccess,
        definition.name,
        roleText(definition.library.role)
      )
    : undefined

  let body: React.ReactNode
  let footer: React.ReactNode
  if (step === 1) {
    body = (
      <>
        <Field
          label={strings.Parties.NameLabel}
          hint={strings.Parties.NameHint}
          required
          validationMessage={showErrors && nameError ? NAME_ERRORS[nameError] : undefined}>
          <Input value={name} maxLength={60} onChange={(_, d) => setName(d.value)} />
        </Field>
        <Field label={strings.Parties.TypeLabel}>
          <RadioGroup
            layout='horizontal'
            value={type?.key}
            onChange={(_, d) => setTypeKey(d.value)}>
            {types.map((t) => (
              <Radio key={t.key} value={t.key} label={t.label} />
            ))}
          </RadioGroup>
        </Field>
        <Field hint={strings.Parties.OwnLibraryHint}>
          <Checkbox
            checked={ownLibrary}
            label={strings.Parties.OwnLibraryLabel}
            onChange={(_, d) => setOwnLibrary(!!d.checked)}
          />
        </Field>
        {ownLibrary && (
          <Field
            label={strings.Parties.CodeLabel}
            hint={strings.Parties.CodeHint}
            required
            validationMessage={showErrors && codeError ? CODE_ERRORS[codeError] : undefined}>
            <Input value={effectiveCode} maxLength={20} onChange={(_, d) => setCode(d.value)} />
          </Field>
        )}

        <section className={styles.summaryBox} aria-label={strings.Parties.SummaryTitle}>
          <h3 className={styles.sectionTitle}>{strings.Parties.SummaryTitle}</h3>
          <dl className={styles.summaryList}>
            <SummaryRow label={strings.Parties.SummaryGroup}>{definition.groupTitle}</SummaryRow>
            {definition.library && (
              <>
                <SummaryRow label={strings.Parties.SummaryLibrary}>
                  {definition.library.title}
                  <span className={styles.secondary}>{definition.library.serverRelativeUrl}</span>
                </SummaryRow>
                {definition.library.folders.length > 0 && (
                  <SummaryRow label={strings.Parties.SummaryFolders}>
                    {definition.library.folders.join(', ')}
                  </SummaryRow>
                )}
                <SummaryRow label={strings.Parties.SummaryAccess}>{ownLibraryAccess}</SummaryRow>
                {config.navigationHeading && (
                  <SummaryRow label={strings.Parties.SummaryMenu}>
                    {format(strings.Parties.SummaryMenuText, config.navigationHeading)}
                  </SummaryRow>
                )}
              </>
            )}
          </dl>
          <p className={styles.hint}>{strings.Parties.NothingCreatedYet}</p>
        </section>
      </>
    )
    footer = (
      <Button appearance='primary' onClick={next}>
        {strings.Parties.NextGrant}
      </Button>
    )
  } else if (step === 2) {
    body = (
      <>
        <div>
          <h3 className={styles.sectionTitle}>
            {format(strings.Parties.AccessStepTitle, definition.name)}
          </h3>
          <p className={styles.hint}>{strings.Parties.AccessStepHint}</p>
        </div>
        <AccessTree
          snapshot={snapshot}
          current={{}}
          value={desired}
          onChange={setDesired}
          leading={
            definition.library && (
              <div className={styles.treeRow}>
                <Checkbox
                  checked
                  disabled
                  label={format(strings.Parties.OwnLibraryRow, definition.library.title)}
                />
                <span className={styles.treeToday}>{roleText(definition.library.role)}</span>
              </div>
            )
          }
        />
        <AccessPreview
          title={strings.Parties.PreviewTitle}
          changes={plan.changes}
          empty={strings.Parties.SummaryNoAccess}
        />
        {plan.rejected.length > 0 && (
          <MessageBar intent='warning'>
            <MessageBarBody>
              {format(strings.Parties.Rejected, plan.rejected.join(', '))}
            </MessageBarBody>
          </MessageBar>
        )}
      </>
    )
    footer = (
      <>
        <Button
          appearance='primary'
          onClick={() => {
            void create()
          }}>
          {strings.Parties.CreateParty}
        </Button>
        <Button onClick={() => setStep(1)}>{strings.Parties.Back}</Button>
      </>
    )
  } else {
    body = (
      <>
        {run?.status === 'ok' && (
          <MessageBar intent='success'>
            <MessageBarBody>
              {format(strings.Parties.CreatedMessage, definition.name)}
            </MessageBarBody>
          </MessageBar>
        )}
        {run?.status === 'failed' && (
          <MessageBar intent='error'>
            <MessageBarBody>{strings.Parties.FailedMessage}</MessageBarBody>
          </MessageBar>
        )}
        {run && <OperationProgress states={run.states} label={strings.Parties.StepStatus} />}
        {run?.status !== 'ok' && <p className={styles.hint}>{strings.Parties.ProgressHint}</p>}
      </>
    )
    if (run?.status === 'failed') {
      footer = (
        <Button
          appearance='primary'
          onClick={() => {
            void retry()
          }}>
          {strings.Parties.TryAgain}
        </Button>
      )
    } else if (run?.status === 'ok' && guestUrl) {
      footer = (
        <Button appearance='primary' as='a' href={guestUrl}>
          {strings.Parties.InviteGuestsLink}
        </Button>
      )
    }
  }

  return (
    <DrawerShell
      title={
        step === 3
          ? format(strings.Parties.CreatingTitle, definition.name)
          : strings.Parties.NewPartTitle
      }
      footer={footer}
      focusKey={`${step}-${run?.status || ''}`}
      closeLabel={
        step === 3 && run?.status === 'ok'
          ? strings.Parties.Done
          : step === 3
            ? strings.Parties.Close
            : strings.Parties.Cancel
      }>
      <Stepper step={step} />
      {body}
    </DrawerShell>
  )
}
