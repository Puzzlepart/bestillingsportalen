import {
  BuildingFilled,
  BuildingRegular,
  type FluentIcon,
  GuestFilled,
  GuestRegular,
  PersonFilled,
  PersonRegular
} from '@fluentui/react-icons'

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
  },
  Person: {
    regular: PersonRegular,
    filled: PersonFilled
  },
  Building: {
    regular: BuildingRegular,
    filled: BuildingFilled
  }
}
