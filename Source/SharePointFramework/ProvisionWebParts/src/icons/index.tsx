import { bundleIcon } from '@fluentui/react-icons'
import React, { type CSSProperties } from 'react'
import { iconCatalog } from './iconCatalog'
import type { FluentIconName, GetFluentIconOptions } from './types'

/**
 * Returns the Fluent icon with the specified name.
 *
 * @param name - The name of the icon to retrieve.
 * @param options - The options to use when retrieving the icon.
 *
 * @returns The specified Fluent icon as a JSX element (or component when `jsx: false`),
 * or undefined if the icon is not found in the catalog.
 */
export function getFluentIcon<T = JSX.Element>(
  name: FluentIconName,
  options?: GetFluentIconOptions
): T | undefined {
  const icon = iconCatalog[name]
  if (!icon) return undefined
  const bundle = options?.bundle ?? true
  const color = options?.color
  const size = options?.size
  const filled = options?.filled ?? false
  const jsx = options?.jsx ?? true
  const Icon = bundle ? bundleIcon(icon.filled, icon.regular) : icon.regular
  if (!jsx) return Icon as unknown as T
  const props: { style?: CSSProperties } = {}
  if (color) props.style = { color }
  if (size) {
    props.style = { ...props.style, width: size, height: size }
  }
  return (<Icon {...props} filled={filled} />) as unknown as T
}

/**
 * Returns an array of all available Fluent icon names.
 */
export function getFluentIcons(): { name: string; hasFilledIcon: boolean }[] {
  return Object.keys(iconCatalog).map((key) => ({
    name: key,
    hasFilledIcon: !!iconCatalog[key].filled
  }))
}

/**
 * Checks if an icon with the given name is available in the icon catalog.
 */
export function isIconAvailable(name: string): boolean {
  return !!iconCatalog[name]
}

export * from './types'
