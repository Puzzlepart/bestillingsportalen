import type { InviteMode } from '../types'

export interface IInviteDrawerProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export interface IGuestPickerProps {
  mode: InviteMode
  guests: string[]
  onAdd: (email: string) => void
  onRemove: (email: string) => void
  disabled?: boolean
}
