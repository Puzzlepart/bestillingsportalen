import type { FieldProps, Slot } from '@fluentui/react-components';

export interface IFieldContainerProps extends FieldProps {
  description?: string;
  validationState?: 'error' | 'warning' | 'success' | 'none';
  validationMessage?: Slot<'div'>;
}
