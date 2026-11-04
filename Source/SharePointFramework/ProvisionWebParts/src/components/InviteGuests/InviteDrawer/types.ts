import type { InviteMode } from '../types'

export interface IInviteDrawerProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Group to choose when the panel opens, from ?inviteGroup=<id>. */
  preselectGroupId?: number
}

export interface IGuestPickerProps {
  mode: InviteMode
  guests: string[]
  onAdd: (email: string) => void
  onRemove: (email: string) => void
  disabled?: boolean
}
