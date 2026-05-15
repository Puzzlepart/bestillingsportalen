import { type FluentIcon, GuestFilled, GuestRegular } from '@fluentui/react-icons'

interface IIconBundle {
  regular: FluentIcon
  filled: FluentIcon
}

/**
 * Available Fluent icons keyed by short name. Add new icons here to make them available
 * via getFluentIcon('Name').
 */
export const iconCatalog: Record<string, IIconBundle> = {
  Guest: {
    regular: GuestRegular,
    filled: GuestFilled
  }
}
