import type { IGuestRequest } from '../../../models/IGuestRequest'
import type { InviteStatusDisplayMode } from '../types'

export type InviteStatusRow = IGuestRequest

export interface IInviteStatusProps {
  mode: InviteStatusDisplayMode
}
