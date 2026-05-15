import * as React from 'react'
import { useInviteGuestsContext } from '../context'

interface IUseInviteDrawerArgs {
  open: boolean
  onOpenChange: (open: boolean) => void
}

interface IUseInviteDrawerResult {
  selected: string[]
  setSelected: (next: string[]) => void
  submitting: boolean
  submit: () => Promise<void>
  cancel: () => void
}

export function useInviteDrawer({
  open,
  onOpenChange
}: IUseInviteDrawerArgs): IUseInviteDrawerResult {
  const ctx = useInviteGuestsContext()
  const [selected, setSelected] = React.useState<string[]>([])
  const [submitting, setSubmitting] = React.useState(false)

  React.useEffect(() => {
    if (!open) setSelected([])
  }, [open])

  const submit = React.useCallback(async (): Promise<void> => {
    if (selected.length === 0) return
    setSubmitting(true)
    try {
      await ctx.invite(selected)
    } finally {
      setSubmitting(false)
    }
  }, [ctx, selected])

  const cancel = React.useCallback(() => onOpenChange(false), [onOpenChange])

  return { selected, setSelected, submitting, submit, cancel }
}
