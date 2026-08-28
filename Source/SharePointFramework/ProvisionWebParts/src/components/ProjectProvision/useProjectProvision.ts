import { useProjectProvisionState } from './useProjectProvisionState'
import { useProjectProvisionDataFetch } from './useProjectProvisionDataFetch'
import { IProjectProvisionProps } from './types'
import { useEditableColumn } from './useEditableColumn'
import { useId } from '@fluentui/react-components'
import { useEffect, useState } from 'react'
import { DEFAULT_PROVISION_ACCESS_GROUP } from './types'

/**
 * Component logic hook for `ProjectProvision`. This hook is responsible for
 * fetching data, sorting, filtering and other logic.
 *
 * @param props Props
 */
export const useProjectProvision = (props: IProjectProvisionProps) => {
  const { state, setState } = useProjectProvisionState()
  const [hasProjectProvisionAccess, setHasProjectProvisionAccess] = useState<boolean>(false)

  useProjectProvisionDataFetch(props, state.refetch, setState)

  const { column, setColumn, reset } = useEditableColumn(props, state, setState)

  const toasterId = useId('toaster')
  const fluentProviderId = useId('fp-project-provision')

  useEffect(() => {
    const checkProjectProvisionAccess = async () => {
      if (props.hasProjectProvisionAccess !== undefined) {
        setHasProjectProvisionAccess(props.hasProjectProvisionAccess)
      } else if (props.provisionService?.isUserInGroup) {
        try {
          const hasAccess = await props.provisionService.isUserInGroup(
            props.provisionAccessGroupTitle || DEFAULT_PROVISION_ACCESS_GROUP
          )
          setHasProjectProvisionAccess(hasAccess)
        } catch {
          setHasProjectProvisionAccess(false)
        }
      } else {
        setHasProjectProvisionAccess(true)
      }
    }

    void checkProjectProvisionAccess()
  }, [props.hasProjectProvisionAccess, props.provisionService])

  useEffect(() => {
    if (props.renderMode === 'inline' && !state.loading) {
      setState({ showProvisionDrawer: true })
    }
  }, [props.renderMode, state.loading])

  return {
    state,
    setState,
    column,
    setColumn,
    reset,
    toasterId,
    fluentProviderId,
    hasProjectProvisionAccess
  }
}
