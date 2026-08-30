/**
 * Parses the `MinimumOwners` value from the "Provisioning Request Settings"
 * list. The list stores numbers as strings; anything unset/invalid/≤0 falls
 * back to 1 so tenants without the setting keep the default behavior (the
 * owner field is already required, so at least one owner is always enforced).
 */
export function parseMinimumOwners(value: unknown): number {
  const parsed = parseInt(String(value ?? ''), 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 1
}
