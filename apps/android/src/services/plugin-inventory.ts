import type { HarnessSettingsDescribe, HarnessSettingsPathOp } from '@dsh-remote/client-core'
import { requireProxy } from '../state/store'
import { strings } from '../locales/i18n'
import { joinInventory as joinCatalog, type AdaptedPluginInfo, type PluginBundleView } from './plugin-catalog'

// The catalog projections are pure and shared with the HarmonyOS port; this module
// keeps only what needs the authenticated carrier and the store.
export { localized, olderThan, schemaFields } from './plugin-catalog'
export type {
  AdaptedPluginInfo, PluginBundleView, PluginCategory, PluginRowView, SchemaField, SchemaFieldKind,
} from './plugin-catalog'

export interface PluginInventory {
  bundles: PluginBundleView[]
  settingsWritable: boolean
}

/**
 * Plugins whose output this client renders natively, keyed by package name. The
 * Remote category lists them first, also when the Host lacks them, so the person
 * knows what to install on the computer for a richer mobile experience.
 */
export const REMOTE_ADAPTED_PLUGINS: Readonly<Record<string, AdaptedPluginInfo>> = {
  'deepseek-harness-intelligent-ui': {
    title: 'Intelligent UI',
    feature: () => strings.plugins.intelligentUiFeature,
    settingsSince: '0.2.10',
  },
}

/** Read bundles, live entries and settings forms through the authenticated Typert carrier. */
export async function loadPluginInventory(): Promise<PluginInventory> {
  const proxy = requireProxy()
  const [bundles, plugins, settings] = await Promise.all([
    proxy.pluginListBundles(),
    proxy.pluginListPlugins(),
    proxy.settingsDescribe().catch((): HarnessSettingsDescribe => ({ writable: false, namespaces: [] })),
  ])
  return { bundles: joinInventory(bundles, plugins, settings), settingsWritable: settings.writable }
}

export async function setPluginEnabled(kind: 'bundle' | 'plugin', target: string, enabled: boolean): Promise<string> {
  const result = await requireProxy().pluginSetEnabled(kind, target, enabled)
  return result.application
}

export async function mutatePluginSettings(ns: string, ops: HarnessSettingsPathOp[], revision: number): Promise<void> {
  await requireProxy().settingsMutate(ns, ops, revision)
}

export function joinInventory(bundles: unknown[], plugins: unknown[], settings: HarnessSettingsDescribe): PluginBundleView[] {
  return joinCatalog(bundles, plugins, settings, REMOTE_ADAPTED_PLUGINS)
}
