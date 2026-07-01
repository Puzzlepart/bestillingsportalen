import type { FieldProps, Slot } from '@fluentui/react-components'
import type { FluentIconName } from '../../icons'

export interface IFieldContainerProps extends FieldProps {
  /**
   * Name of an icon registered in the local icon catalog.
   * Set this to render the field label with an icon (uses IconLabel internally).
   */
  iconName?: FluentIconName
  description?: string
  validationState?: 'error' | 'warning' | 'success' | 'none'
  validationMessage?: Slot<'div'>
}
