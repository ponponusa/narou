<!--
  コンソールパネルコンポーネント
  
  PushServerからのechoイベントを受信してコンソールログを表示する
-->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { getPushServer, type EchoMessage } from '../lib/pushserver';

  interface LogEntry {
    id: number;
    timestamp: Date;
    console: 'stdout' | 'stdout2';
    message: string;
    isProgress?: boolean; // 進捗メッセージかどうか
    progressKey?: string; // 進捗を識別するキー
    processType?: 'download' | 'convert' | 'other'; // 処理タイプ
    novelId?: string; // 小説ID
  }

  // localStorageから設定を読み込む
  const STORAGE_KEY = 'narou-console-settings';
  
  function loadSettings() {
    if (typeof window === 'undefined') return;
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const settings = JSON.parse(saved);
        if (typeof settings.splitView === 'boolean') splitView = settings.splitView;
        if (typeof settings.compactProgress === 'boolean') compactProgress = settings.compactProgress;
        if (typeof settings.autoScroll === 'boolean') autoScroll = settings.autoScroll;
        if (typeof settings.updateThrottle === 'number') updateThrottle = settings.updateThrottle;
      }
    } catch (e) {
      console.error('Failed to load console settings:', e);
    }
  }

  function saveSettings() {
    if (typeof window === 'undefined') return;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({
        splitView,
        compactProgress,
        autoScroll,
        updateThrottle
      }));
    } catch (e) {
      console.error('Failed to save console settings:', e);
    }
  }

  let logs = $state<LogEntry[]>([]);
  let isOpen = $state(false);
  let autoScroll = $state(true); // 進捗を1行で表示するか
  let compactProgress = $state(true); // 進捗を1行で表示するか
  let updateThrottle = $state(100); // 更新頻度（ms）
  let splitView = $state(true); // 左右分割表示
  let logContainer: HTMLDivElement | undefined;
  let leftPaneContainer: HTMLDivElement | undefined;
  let rightPaneContainer: HTMLDivElement | undefined;
  let nextId = 0;
  let unsubscribe: (() => void) | null = null;
  let isConnected = $state(false);
  let lastUpdateTime = 0;
  let pendingLogs: Array<{console: 'stdout' | 'stdout2', message: string}> = [];

  // 設定変更時に保存
  $effect(() => {
    saveSettings();
  });
  /**
   * コンソールを開く
   */
  export function open() {
    isOpen = true;
    // 開いた直後に最下部にスクロール
    setTimeout(() => {
      scrollToBottom();
    }, 50);
  }

  /**
   * コンソールを閉じる
   */
  export function close() {
    isOpen = false;
  }

  /**
   * コンソールをトグル
   */
  export function toggle() {
    isOpen = !isOpen;
    if (isOpen) {
      setTimeout(() => {
        scrollToBottom();
      }, 50);
    }
  }

  /**
   * ログをクリア
   */
  function clearLogs() {
    logs = [];
    nextId = 0;
  }

  /**
   * ログエントリを追加
   */
  function addLog(console: 'stdout' | 'stdout2', message: string) {
    const now = Date.now();
    
    // スロットリング: 指定間隔内は追加をペンディング
    if (now - lastUpdateTime < updateThrottle && pendingLogs.length > 0) {
      pendingLogs.push({ console, message });
      return;
    }
    
    // ペンディングされたログがあれば処理
    if (pendingLogs.length > 0) {
      pendingLogs.forEach(log => processLog(log.console, log.message));
      pendingLogs = [];
    }
    
    processLog(console, message);
    lastUpdateTime = now;
  }

  /**
   * ログを処理して追加
   */
  function processLog(console: 'stdout' | 'stdout2', message: string) {
    const cleanMessage = message.replace(/\n$/, ''); // 末尾の改行を削除
    
    // 処理タイプと小説IDを抽出
    const { processType, novelId } = extractProcessInfo(cleanMessage);
    
    // 進捗メッセージかどうかを判定
    const isProgress = isProgressMessage(cleanMessage);
    // novelIdがある場合はそれを含めたprogressKeyを生成
    const baseProgressKey = isProgress ? extractProgressKey(cleanMessage) : undefined;
    const progressKey = baseProgressKey && novelId ? `${baseProgressKey}-novel-${novelId}` : baseProgressKey;
    
    // コンパクトモードで進捗メッセージの場合、既存のエントリを更新
    if (compactProgress && isProgress && progressKey) {
      const existingIndex = logs.findIndex(
        log => log.isProgress && log.progressKey === progressKey
      );
      
      if (existingIndex !== -1) {
        // 既存の進捗メッセージを更新
        logs[existingIndex] = {
          ...logs[existingIndex],
          message: cleanMessage,
          timestamp: new Date(),
          processType,
          novelId,
        };
        logs = [...logs]; // リアクティビティをトリガー
        scrollIfNeeded();
        return;
      }
    }
    
    // 新しいログエントリを追加
    logs = [...logs, {
      id: nextId++,
      timestamp: new Date(),
      console,
      message: cleanMessage,
      isProgress,
      progressKey,
      processType,
      novelId,
    }];

    // 最大1000件まで保持
    if (logs.length > 1000) {
      logs = logs.slice(-1000);
    }

    scrollIfNeeded();
  }

  /**
   * 進捗メッセージかどうかを判定
   */
  function isProgressMessage(message: string): boolean {
    // 空のメッセージは進捗メッセージではない
    if (decodeMessage(message).trim().length === 0) {
      return false;
    }
    
    // プログレスバー風のパターン: [####...] や 50% や (n/m) を含む
    // ダウンロード中の "第n部分" パターンも検出
    // "第一話", "第二十話" などの漢数字パターンも検出
    return /\[#+[.\s]*\]|\d+%|\(\d+\/\d+\)|第\d+部分|部分.*\(\d+\/\d+\)|第[一二三四五六七八九十百千]+話/.test(message);
  }

  /**
   * 進捗メッセージから識別キーを抽出
   */
  function extractProgressKey(message: string): string {
    // 小説IDがある場合は、それを最優先でキーにする
    // これにより「第1部分」「第2部分」などが同じキーでまとめられる
    const idMatch = message.match(/ID[:：]\s*(\d+)/i);
    if (idMatch) return `progress-id-${idMatch[1]}`;
    
    // 「第n部分」パターン: 全て同じキー "chapter-download" にまとめる
    if (/第\d+部分/.test(message)) {
      return 'progress-chapter-download';
    }
    
    // 「第一話」「第二十話」などの漢数字パターン: 全て同じキー "chapter-title" にまとめる
    if (/第[一二三四五六七八九十百千]+話/.test(message)) {
      return 'progress-chapter-title';
    }
    
    // 章タイトル + (n/m) パターン: 全て同じキー "chapter-progress" にまとめる
    // 例: "01．温め鳥 (1/31)" -> "chapter-progress"
    if (/.*\(\d+\/\d+\)/.test(message)) {
      return 'progress-chapter-progress';
    }
    
    // (n/m) 形式のパターンがある場合、その前の文字列をキーにする
    // 例: "処理中 (1/10)" -> "処理中"
    const progressMatch = message.match(/^(.+?)\s*\(\d+\/\d+\)/);
    if (progressMatch) return `progress-${progressMatch[1].trim()}`;
    
    // プログレスバーを除いた部分をキーにする
    const barMatch = message.match(/^(.+?)\s*\[#+/);
    if (barMatch) return `progress-${barMatch[1].trim()}`;
    
    // それ以外は先頭20文字をキーにする
    const titleMatch = message.match(/^(.{0,20})/);
    if (titleMatch) return `progress-${titleMatch[1].trim()}`;
    
    return 'progress-unknown';
  }

  /**
   * ログメッセージから処理タイプと小説IDを抽出
   */
  function extractProcessInfo(message: string): { processType?: 'download' | 'convert' | 'other', novelId?: string } {
    // 小説IDを抽出
    const idMatch = message.match(/ID[:：]\s*(\d+)/i);
    const novelId = idMatch ? idMatch[1] : undefined;
    
    // 処理タイプを判定
    let processType: 'download' | 'convert' | 'other' | undefined;
    
    if (/ダウンロード|download|DL/i.test(message)) {
      processType = 'download';
    } else if (/変換|convert|epub/i.test(message)) {
      processType = 'convert';
    } else if (novelId || /処理|progress/i.test(message)) {
      processType = 'other';
    }
    
    return { processType, novelId };
  }

  /**
   * 最下部にスクロール（強制）
   */
  function scrollToBottom() {
    setTimeout(() => {
      if (splitView) {
        if (leftPaneContainer) {
          leftPaneContainer.scrollTop = leftPaneContainer.scrollHeight;
        }
        if (rightPaneContainer) {
          rightPaneContainer.scrollTop = rightPaneContainer.scrollHeight;
        }
      } else {
        if (logContainer) {
          logContainer.scrollTop = logContainer.scrollHeight;
        }
      }
    }, 10);
  }

  /**
   * 自動スクロール（autoScrollがtrueの場合のみ）
   */
  function scrollIfNeeded() {
    if (autoScroll) {
      scrollToBottom();
    }
  }

  /**
   * ダウンロード系のログをフィルタ
   */
  function getDownloadLogs(): LogEntry[] {
    return logs.filter(log => 
      log.processType === 'download' || 
      (!log.processType && /ダウンロード|download|DL|フェッチ|fetch/i.test(log.message))
    );
  }

  /**
   * 変換系のログをフィルタ
   */
  function getConvertLogs(): LogEntry[] {
    return logs.filter(log => 
      log.processType === 'convert' ||
      (!log.processType && /変換|convert|epub/i.test(log.message))
    );
  }

  /**
   * その他のログをフィルタ（分割時は左ペインに表示）
   */
  function getOtherLogs(): LogEntry[] {
    return logs.filter(log => 
      !log.processType || log.processType === 'other'
    );
  }

  /**
   * コンパクト表示用: 進捗メッセージの重複を除外し最新のみ返す
   */
  function compactLogs(logList: LogEntry[]): LogEntry[] {
    // 空のメッセージを除外
    const filtered = logList.filter(log => {
      const decoded = decodeMessage(log.message).trim();
      return decoded.length > 0;
    });

    if (!compactProgress) {
      return filtered;
    }

    const progressMap = new Map<string, LogEntry>();
    const nonProgressLogs: LogEntry[] = [];

    for (const log of filtered) {
      if (log.isProgress && log.progressKey) {
        // 進捗メッセージは progressKey ごとに最新のものだけ保持
        const existing = progressMap.get(log.progressKey);
        if (!existing || log.timestamp > existing.timestamp) {
          progressMap.set(log.progressKey, log);
        }
      } else {
        // 非進捗メッセージはそのまま保持
        nonProgressLogs.push(log);
      }
    }

    // 非進捗 + 最新の進捗メッセージを結合し、タイムスタンプ順にソート
    return [...nonProgressLogs, ...Array.from(progressMap.values())]
      .sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
  }

  /**
   * ログをファイルにエクスポート
   */
  function exportLogs() {
    const text = logs.map(log => {
      const time = formatTime(log.timestamp);
      const console = log.console === 'stdout2' ? 'stderr' : 'stdout';
      const message = decodeMessage(log.message);
      return `[${time}] [${console}] ${message}`;
    }).join('\n');
    
    const blob = new Blob([text], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `console-${new Date().toISOString().replace(/[:.]/g, '-')}.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  /**
   * HTMLエスケープされたメッセージをデコード
   */
  function decodeMessage(html: string): string {
    const txt = document.createElement('textarea');
    txt.innerHTML = html;
    return txt.value;
  }

  /**
   * TermColorタグをHTMLに変換
   */
  function formatMessage(message: string): string {
    // HTMLエスケープされているのでデコード
    let text = decodeMessage(message);
    
    // TermColorタグをHTMLクラスに変換
    // <red>text</red> -> <span class="tc-red">text</span>
    const colorTags = ['red', 'green', 'blue', 'yellow', 'cyan', 'magenta', 'white', 'black'];
    colorTags.forEach(color => {
      const regex = new RegExp(`<${color}>([^<]*)</${color}>`, 'g');
      text = text.replace(regex, `<span class="tc-${color}">$1</span>`);
    });
    
    // <bold>text</bold> -> <strong>text</strong>
    text = text.replace(/<bold>([\s\S]*?)<\/bold>/g, '<strong>$1</strong>');
    
    // <underline>text</underline> -> <u>text</u>
    text = text.replace(/<underline>([\s\S]*?)<\/underline>/g, '<u>$1</u>');
    
    // ネストされたタグを処理するため、再帰的に適用
    // 例: <bold><green>text</green></bold>
    if (/<(red|green|blue|yellow|cyan|magenta|white|black|bold|underline)>/.test(text)) {
      text = formatMessage(text);
    }
    
    return text;
  }

  /**
   * タイムスタンプをフォーマット
   */
  function formatTime(date: Date): string {
    const h = date.getHours().toString().padStart(2, '0');
    const m = date.getMinutes().toString().padStart(2, '0');
    const s = date.getSeconds().toString().padStart(2, '0');
    return `${h}:${m}:${s}`;
  }

  onMount(() => {
    // 設定を読み込み
    loadSettings();
    
    const pushServer = getPushServer();
    
    // 接続イベント
    pushServer.on('connected', () => {
      isConnected = true;
      addLog('stdout', '[PushServer] Connected');
    });

    pushServer.on('disconnected', () => {
      isConnected = false;
      addLog('stdout', '[PushServer] Disconnected');
    });

    // echoイベント
    pushServer.on('echo', (data: EchoMessage) => {
      if (!data.no_history) {
        addLog(data.target_console, data.body);
      }
    });

    // 接続開始
    pushServer.connect();
  });

  onDestroy(() => {
    const pushServer = getPushServer();
    pushServer.disconnect();
  });
</script>

{#if isOpen}
  <div class="fixed bottom-0 left-0 right-0 z-40 bg-gray-900 dark:bg-gray-950 border-t border-gray-700 shadow-lg">
    <!-- ヘッダー -->
    <div class="flex items-center justify-between px-4 py-2 bg-gray-800 dark:bg-gray-900 border-b border-gray-700">
      <div class="flex items-center gap-3">
        <h3 class="text-sm font-semibold text-gray-100">コンソール</h3>
        <div class="flex items-center gap-2">
          <div class="w-2 h-2 rounded-full {isConnected ? 'bg-green-500' : 'bg-red-500'}"></div>
          <span class="text-xs text-gray-400">
            {isConnected ? '接続中' : '切断'}
          </span>
        </div>
        <span class="text-xs text-gray-500">
          {logs.length} 件
        </span>
      </div>

      <div class="flex items-center gap-2">
        <label class="flex items-center gap-2 text-xs text-gray-400 cursor-pointer" title="進捗を1行で表示">
          <input
            type="checkbox"
            bind:checked={compactProgress}
            class="rounded border-gray-600 bg-gray-700 text-blue-600 focus:ring-blue-500 focus:ring-offset-gray-900"
          />
          コンパクト
        </label>
        <label class="flex items-center gap-2 text-xs text-gray-400 cursor-pointer" title="ダウンロードと変換を分割表示">
          <input
            type="checkbox"
            bind:checked={splitView}
            class="rounded border-gray-600 bg-gray-700 text-blue-600 focus:ring-blue-500 focus:ring-offset-gray-900"
          />
          分割表示
        </label>
        <label class="flex items-center gap-2 text-xs text-gray-400 cursor-pointer">
          <input
            type="checkbox"
            bind:checked={autoScroll}
            class="rounded border-gray-600 bg-gray-700 text-blue-600 focus:ring-blue-500 focus:ring-offset-gray-900"
          />
          自動スクロール
        </label>
        <select
          bind:value={updateThrottle}
          class="text-xs bg-gray-700 border-gray-600 text-gray-300 rounded px-2 py-1 focus:ring-blue-500 focus:border-blue-500"
          title="更新頻度"
        >
          <option value={50}>高速 (50ms)</option>
          <option value={100}>標準 (100ms)</option>
          <option value={500}>低速 (500ms)</option>
          <option value={1000}>最低速 (1s)</option>
        </select>
        <button
          onclick={exportLogs}
          class="px-3 py-1 text-xs bg-gray-700 hover:bg-gray-600 text-gray-300 rounded transition-colors"
          title="ログをエクスポート"
        >
          保存
        </button>
        <button
          onclick={clearLogs}
          class="px-3 py-1 text-xs bg-gray-700 hover:bg-gray-600 text-gray-300 rounded transition-colors"
          title="ログをクリア"
        >
          クリア
        </button>
        <button
          onclick={close}
          class="text-gray-400 hover:text-gray-200 text-xl leading-none"
          title="閉じる"
        >
          ×
        </button>
      </div>
    </div>

    <!-- ログ表示エリア -->
    {#if splitView}
      <!-- 左右分割表示 -->
      <div class="flex h-64">
        <!-- 左ペイン: ダウンロード・その他 -->
        <div class="flex-1 flex flex-col border-r border-gray-700">
          <div class="px-3 py-1 bg-gray-800 border-b border-gray-700 text-xs font-semibold text-blue-300">
            📥 ダウンロード・フェッチ
          </div>
          <div
            bind:this={leftPaneContainer}
            class="flex-1 overflow-y-auto px-4 py-2 font-mono text-xs bg-gray-900 dark:bg-black text-gray-300"
          >
            {#if getDownloadLogs().length === 0 && getOtherLogs().length === 0}
              <div class="text-gray-500 text-center py-8">
                ログがありません
              </div>
            {:else}
              {#each compactLogs([...getDownloadLogs(), ...getOtherLogs()]) as log (log.id)}
                <div class="flex gap-2 hover:bg-gray-800 dark:hover:bg-gray-900 px-2 py-1 rounded">
                  <span class="text-gray-500 shrink-0">
                    {formatTime(log.timestamp)}
                  </span>
                  <span class="text-gray-400 shrink-0 w-16">
                    {log.console === 'stdout2' ? 'stderr' : 'stdout'}
                  </span>
                  {#if log.processType}
                    <span class="shrink-0 px-1.5 py-0.5 rounded text-[10px] leading-none {
                      log.processType === 'download' ? 'bg-blue-900/50 text-blue-300 border border-blue-700/50' :
                      log.processType === 'convert' ? 'bg-green-900/50 text-green-300 border border-green-700/50' :
                      'bg-purple-900/50 text-purple-300 border border-purple-700/50'
                    }" title="処理タイプ">
                      {log.processType === 'download' ? 'DL' : log.processType === 'convert' ? '変換' : '他'}
                    </span>
                  {/if}
                  {#if log.novelId}
                    <span class="shrink-0 px-1.5 py-0.5 rounded text-[10px] leading-none bg-gray-700 text-gray-300 border border-gray-600" title="小説ID">
                      ID:{log.novelId}
                    </span>
                  {/if}
                  <span class="flex-1 whitespace-nowrap overflow-hidden text-ellipsis {log.console === 'stdout2' ? 'text-yellow-400' : 'text-gray-300'}">
                    {@html formatMessage(log.message)}
                  </span>
                </div>
              {/each}
            {/if}
          </div>
        </div>

        <!-- 右ペイン: 変換 -->
        <div class="flex-1 flex flex-col">
          <div class="px-3 py-1 bg-gray-800 border-b border-gray-700 text-xs font-semibold text-green-300">
            ⚙️ 変換・EPUB生成
          </div>
          <div
            bind:this={rightPaneContainer}
            class="flex-1 overflow-y-auto px-4 py-2 font-mono text-xs bg-gray-900 dark:bg-black text-gray-300"
          >
            {#if getConvertLogs().length === 0}
              <div class="text-gray-500 text-center py-8">
                ログがありません
              </div>
            {:else}
              {#each compactLogs(getConvertLogs()) as log (log.id)}
                <div class="flex gap-2 hover:bg-gray-800 dark:hover:bg-gray-900 px-2 py-1 rounded">
                  <span class="text-gray-500 shrink-0">
                    {formatTime(log.timestamp)}
                  </span>
                  <span class="text-gray-400 shrink-0 w-16">
                    {log.console === 'stdout2' ? 'stderr' : 'stdout'}
                  </span>
                  {#if log.processType}
                    <span class="shrink-0 px-1.5 py-0.5 rounded text-[10px] leading-none {
                      log.processType === 'download' ? 'bg-blue-900/50 text-blue-300 border border-blue-700/50' :
                      log.processType === 'convert' ? 'bg-green-900/50 text-green-300 border border-green-700/50' :
                      'bg-purple-900/50 text-purple-300 border border-purple-700/50'
                    }" title="処理タイプ">
                      {log.processType === 'download' ? 'DL' : log.processType === 'convert' ? '変換' : '他'}
                    </span>
                  {/if}
                  {#if log.novelId}
                    <span class="shrink-0 px-1.5 py-0.5 rounded text-[10px] leading-none bg-gray-700 text-gray-300 border border-gray-600" title="小説ID">
                      ID:{log.novelId}
                    </span>
                  {/if}
                  <span class="flex-1 whitespace-nowrap overflow-hidden text-ellipsis {log.console === 'stdout2' ? 'text-yellow-400' : 'text-gray-300'}">
                    {@html formatMessage(log.message)}
                  </span>
                </div>
              {/each}
            {/if}
          </div>
        </div>
      </div>
    {:else}
      <!-- 統合表示 -->
      <div
        bind:this={logContainer}
        class="overflow-y-auto h-64 px-4 py-2 font-mono text-xs bg-gray-900 dark:bg-black text-gray-300"
      >
        {#if logs.length === 0}
          <div class="text-gray-500 text-center py-8">
            ログがありません
          </div>
        {:else}
          {#each compactLogs(logs) as log (log.id)}
            <div class="flex gap-2 hover:bg-gray-800 dark:hover:bg-gray-900 px-2 py-1 rounded">
              <span class="text-gray-500 shrink-0">
                {formatTime(log.timestamp)}
              </span>
              <span class="text-gray-400 shrink-0 w-16">
                {log.console === 'stdout2' ? 'stderr' : 'stdout'}
              </span>
              {#if log.processType}
                <span class="shrink-0 px-1.5 py-0.5 rounded text-[10px] leading-none {
                  log.processType === 'download' ? 'bg-blue-900/50 text-blue-300 border border-blue-700/50' :
                  log.processType === 'convert' ? 'bg-green-900/50 text-green-300 border border-green-700/50' :
                  'bg-purple-900/50 text-purple-300 border border-purple-700/50'
                }" title="処理タイプ">
                  {log.processType === 'download' ? 'DL' : log.processType === 'convert' ? '変換' : '他'}
                </span>
              {/if}
              {#if log.novelId}
                <span class="shrink-0 px-1.5 py-0.5 rounded text-[10px] leading-none bg-gray-700 text-gray-300 border border-gray-600" title="小説ID">
                  ID:{log.novelId}
                </span>
              {/if}
              <span class="flex-1 whitespace-nowrap overflow-hidden text-ellipsis {log.console === 'stdout2' ? 'text-yellow-400' : 'text-gray-300'}">
                {@html formatMessage(log.message)}
              </span>
            </div>
          {/each}
        {/if}
      </div>
    {/if}
  </div>
{/if}

<!-- フローティング開閉ボタン（閉じている時） -->
{#if !isOpen}
  <button
    onclick={open}
    class="fixed bottom-4 right-4 z-40 px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg shadow-lg border border-gray-700 flex items-center gap-2 transition-colors"
    title="コンソールを開く"
  >
    <div class="w-2 h-2 rounded-full {isConnected ? 'bg-green-500' : 'bg-red-500'}"></div>
    <span class="text-sm">コンソール</span>
    {#if logs.length > 0}
      <span class="px-2 py-0.5 bg-blue-600 text-white text-xs rounded-full">
        {logs.length}
      </span>
    {/if}
  </button>
{/if}

<style>
  /* TermColor タグのスタイル */
  :global(.tc-red) { color: #ef4444; }
  :global(.tc-green) { color: #22c55e; }
  :global(.tc-blue) { color: #3b82f6; }
  :global(.tc-yellow) { color: #eab308; }
  :global(.tc-cyan) { color: #06b6d4; }
  :global(.tc-magenta) { color: #d946ef; }
  :global(.tc-white) { color: #f3f4f6; }
  :global(.tc-black) { color: #1f2937; }
</style>
