import { ListMenuItem } from '../../../Toolbar'
import { useContext } from 'react'
import { ProjectProvisionContext } from '../../context'
import strings from 'ProvisionWebPartsStrings'

/**
 * Component logic hook for `Commands`. This hook is responsible for
 * rendering the toolbar and handling its actions.
 */
export function useCommands() {
  const context = useContext(ProjectProvisionContext)

  const toolbarItems = [
    new ListMenuItem(null, strings.Provision.UpdateLabel).setIcon('ArrowSync').setOnClick(() => {
      context.setState({
        isRefetching: true,
        refetch: new Date().getTime()
      })
    })
  ]

  return { toolbarItems }
}
