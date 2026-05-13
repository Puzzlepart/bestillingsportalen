import type { DisplayMode } from '@microsoft/sp-core-library';
import type { SPFI } from '@pnp/sp';

export interface IBaseComponentProps {
  title?: string;
  sp?: SPFI;
  displayMode?: DisplayMode;
  manifestId?: string;
  siteUrl?: string;
  siteTitle?: string;
}
