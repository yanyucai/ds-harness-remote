export declare class HarmonyRuntime {
  validateImageAttachments(raw: string): void;
  downloadWorkspaceFile(path: string, write: (bytes: Uint8Array) => Promise<void>): Promise<void>;
  setTerminalRenderer(scope: string, enabled: boolean): void;
  acknowledgeTerminalRender(scope: string, revision: number): void;
  attachRtcBridge(send: (raw: string) => Promise<void>): void;
  receiveRtcBridge(raw: string): void;
  stageSharedText(value: string): void;
  readMarkdownImage(path: string, scope: string): Promise<string>;
  translate(text: string): string;
  setListener(listener: (snapshot: string) => void): void;
  attachContext(context: Object): void;
  initialize(): Promise<void>;
  perform(action: string, input: string): Promise<boolean>;
  onForeground(): Promise<void>;
  onBackground(): Promise<void>;
  dispose(): Promise<void>;
  handleNotificationNavigation(hostId: string, sessionId: string): Promise<void>;
  handleDeepLink(uri: string): Promise<boolean>;
  openBrowserUrl(url: string): Promise<void>;
}
