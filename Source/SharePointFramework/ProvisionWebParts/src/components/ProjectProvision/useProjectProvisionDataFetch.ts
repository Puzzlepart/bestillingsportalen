import { useEffect } from 'react'
import { IProjectProvisionProps, IProjectProvisionState } from './types'

/**
 * Component data fetch hook for `ProjectProvision`. This hook is responsible for
 * fetching data and setting state.
 *
 * @param props Props
 * @param refetch Timestamp for refetch. Changes to this variable refetches the data in `useEffect`
 * @param setState Set state callback
 */
export function useProjectProvisionDataFetch(
  props: IProjectProvisionProps,
  refetch: number,
  setState: (newState: Partial<IProjectProvisionState>) => void
) {
  useEffect(() => {
    Promise.all([
      props.provisionService.hasProvisionSiteAccess(props.provisionUrl),
      props.provisionService.isProvisionSiteAdmin(props.provisionUrl)
    ])
      .then(([hasAccess, isAdmin]) => {
        if (!hasAccess) {
          setState({
            accessDenied: true,
            loading: false,
            isRefetching: false
          })
          return
        }

        Promise.all([
          props.provisionService.getProvisionRequestSettings(props.provisionUrl),
          props.provisionService.getProvisionTypes(props.provisionUrl),
          props.provisionService.getSiteTemplates(props.provisionUrl),
          props.provisionService.getTeamTemplates(props.provisionUrl),
          props.provisionService.getSensitivityLabels(props.provisionUrl),
          props.provisionService.getRetentionLabels(props.provisionUrl),
          props.provisionService.fetchProvisionRequests(
            props.pageContext.user.email,
            props.provisionUrl
          )
        ])
          .then(
            ([
              settings,
              types,
              siteTemplates,
              teamTemplates,
              sensitivityLabels,
              retentionLabels,
              requests
            ]) => {
              setState({
                settings,
                types: types.filter(
                  (type) =>
                    !props.excludedTypes?.includes(type.title) &&
                    (!type.visibleTo ||
                      type.visibleTo?.some((user) =>
                        user?.EMail?.includes(props?.pageContext?.user?.loginName)
                      ))
                ),
                siteTemplates,
                teamTemplates,
                sensitivityLabels: sensitivityLabels.filter((label) => !label.isLibrary),
                sensitivityLabelsLibrary: sensitivityLabels.filter((label) => label.isLibrary),
                retentionLabels,
                requests,
                isProvisionSiteAdmin: isAdmin,
                loading: false,
                isRefetching: false
              })
            }
          )
          .catch((error) => {
            setState({
              error,
              loading: false,
              isRefetching: false
            })
          })
      })
      .catch(() => {
        setState({
          accessDenied: true,
          loading: false,
          isRefetching: false
        })
      })
  }, [refetch])
}
