import type { DisplayMode } from '@microsoft/sp-core-library'
import type { PageContext } from '@microsoft/sp-page-context'
import type { SPFI } from '@pnp/sp'
import type { ProvisionService } from '../services/ProvisionService'

export interface IBaseComponentProps {
  title?: string
  sp?: SPFI
  displayMode?: DisplayMode
  manifestId?: string
  siteUrl?: string
  siteTitle?: string

  /**
   * Service handling all data operations against the provisioning site.
   * Used by the `ProjectProvision` component tree.
   */
  provisionService?: ProvisionService

  /**
   * SPFx page context for the current page.
   */
  pageContext?: PageContext

  /**
   * Absolute URL of the current web.
   */
  webAbsoluteUrl?: string
}
