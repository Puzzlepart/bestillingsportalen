export interface IInviteDrawerProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export interface IGuestPickerProps {
  selected: string[]
  onChange: (selected: string[]) => void
  disabled?: boolean
}
