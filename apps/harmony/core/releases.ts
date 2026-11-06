export const HARMONY_VERSION = '0.6.3-harmony.29'
export const RELEASE_URL = 'https://github.com/liguobao/ds-harness-remote/releases/latest'
export async function latestRelease(signal: AbortSignal): Promise<string> {
  const response = await fetch('https://api.github.com/repos/liguobao/ds-harness-remote/releases/latest', {
    headers: { Accept: 'application/vnd.github+json' }, signal,
  })
  if (!response.ok) throw new Error(`更新检查失败（HTTP ${response.status}）`)
  const raw = await response.text()
  if (raw.length > 1024 * 1024) throw new Error('更新信息过大')
  const result = JSON.parse(raw) as { tag_name?: unknown; draft?: unknown; prerelease?: unknown }
  if (result.draft || result.prerelease || typeof result.tag_name !== 'string' || !/^v?\d+\.\d+\.\d+(?:[-.][\w.-]+)?$/.test(result.tag_name)) throw new Error('更新版本信息无效')
  return result.tag_name
}
