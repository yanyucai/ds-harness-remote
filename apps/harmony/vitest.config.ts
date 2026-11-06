import { defineConfig } from 'vitest/config'
import path from 'node:path'
const root = __dirname
export default defineConfig({
  esbuild: { define: { WebSocket: 'harmonyPlatform.NativeWebSocket' } },
  resolve: { alias: {
    ...Object.fromEntries(['crypto', 'protocol', 'client-core', 'webrtc'].map(name => [`@dsh-remote/${name}`, path.resolve(root, `../../packages/${name}/src/index.ts`)])),
    '@ohos.security.cryptoFramework': path.resolve(root, 'tests/native/crypto.ts'),
    '@ohos.util': path.resolve(root, 'tests/native/util.ts'),
    '@ohos.url': path.resolve(root, 'tests/native/url.ts'),
    '@ohos.net.webSocket': path.resolve(root, 'tests/native/socket.ts'),
    '@ohos.security.asset': path.resolve(root, 'tests/native/asset.ts'),
    '@ohos.data.preferences': path.resolve(root, 'tests/native/prefs.ts'),
    '@hms.collaboration.rcp': path.resolve(root, 'tests/native/rcp.ts'),
    '@ohos.resourceschedule.backgroundTaskManager': path.resolve(root, 'tests/native/background.ts'),
    '@ohos.app.ability.wantAgent': path.resolve(root, 'tests/native/wantagent.ts'),
    '@ohos.app.ability.common': path.resolve(root, 'tests/native/common.ts'),
    '@ohos.i18n': path.resolve(root, 'tests/native/i18n.ts'),
    '@ohos.notificationManager': path.resolve(root, 'tests/native/notification.ts'),
    '@ohos.pasteboard': path.resolve(root, 'tests/native/pasteboard.ts'),
    '@hms.collaboration.systemShare': path.resolve(root, 'tests/native/share.ts'),
    '@ohos.window': path.resolve(root, 'tests/native/window.ts'),
  } },
  test: { include: ['tests/**/*.test.ts'], setupFiles: ['tests/native/setup.ts'], testTimeout: 15000, fileParallelism: false },
})
