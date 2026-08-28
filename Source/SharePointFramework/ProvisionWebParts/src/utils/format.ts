/**
 * Formats a string by replacing `{0}`, `{1}`, ... placeholders with the
 * provided values. Local replacement for the `format` helper previously
 * imported from Fluent UI v8 (`@fluentui/react`).
 *
 * @param template Template string with `{n}` placeholders
 * @param values Values to insert into the template
 */
export function format(template: string, ...values: any[]): string {
  return (template ?? '').replace(/\{(\d+)\}/g, (match, index) => {
    const value = values[Number(index)]
    return value === undefined || value === null ? match : String(value)
  })
}
