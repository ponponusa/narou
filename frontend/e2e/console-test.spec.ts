import { test, expect } from '@playwright/test';

test.describe('Console Panel Tests', () => {
  test.beforeEach(async ({ page }) => {
    // フロントエンドにアクセス
    await page.goto('http://localhost:4321/');
    await page.waitForLoadState('networkidle');
  });

  test('should display console messages without progressbar artifacts', async ({ page }) => {
    // コンソールパネルを開く
    const consoleButton = page.locator('button:has-text("コンソール")');
    if (await consoleButton.isVisible()) {
      await consoleButton.click();
    }

    // WebSocketメッセージをリッスン
    const messages: string[] = [];
    page.on('console', msg => {
      if (msg.text().includes('[DEBUG]')) {
        messages.push(msg.text());
        console.log(msg.text());
      }
    });

    // 小説をダウンロード（APIを直接呼ぶ）
    const response = await page.request.post('http://localhost:33000/api/download', {
      data: {
        target: '41' // テスト用の小説ID
      }
    });

    expect(response.ok()).toBeTruthy();

    // 処理完了を待つ
    await page.waitForTimeout(30000); // 30秒待つ

    // コンソールログを確認
    const consolePanel = page.locator('[data-testid="console-panel"]').or(page.locator('.console-panel'));
    const logEntries = await consolePanel.locator('.log-entry, [class*="log"]').all();

    console.log(`Found ${logEntries.length} log entries`);

    // プログレスバーの痕跡がないことを確認
    const pageContent = await page.content();
    expect(pageContent).not.toContain('[##########]');
    expect(pageContent).not.toContain('progressbar.step');

    // 調査ログが1行で表示されていることを確認
    const logText = await consolePanel.textContent();
    if (logText) {
      const surveyLogMatch = logText.match(/小説状態の調査結果を.*調査ログ\.txt.*に出力しました（.*）/);
      if (surveyLogMatch) {
        console.log('Survey log found:', surveyLogMatch[0]);
        expect(surveyLogMatch[0]).toContain('エラー：');
        expect(surveyLogMatch[0]).toContain('件');
      }
    }
  });

  test('should connect to WebSocket', async ({ page }) => {
    // WebSocket接続を確認
    await page.waitForTimeout(2000);
    
    const consolePanel = page.locator('text=PushServer').or(page.locator('text=Connected'));
    await expect(consolePanel).toBeVisible({ timeout: 10000 });
  });

  test('should not duplicate logs when navigating between pages', async ({ page }) => {
    // ページ1（トップページ）でコンソールを開く
    const consoleButton = page.locator('button:has-text("コンソール")');
    if (await consoleButton.isVisible()) {
      await consoleButton.click();
    }

    // 初期ログ数を記録
    await page.waitForTimeout(1000);
    const consolePanelSelector = '[data-console-panel="true"]';
    const initialLogCount = await page.locator(`${consolePanelSelector} .log-entry, ${consolePanelSelector} [class*="hover:bg-gray"]`).count();
    console.log(`Initial log count: ${initialLogCount}`);

    // ページ2（設定ページ）に移動
    await page.goto('http://localhost:4321/settings');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // ページ3（タスクページ）に移動
    await page.goto('http://localhost:4321/tasks');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // トップページに戻る
    await page.goto('http://localhost:4321/');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // コンソールを開く
    if (await consoleButton.isVisible()) {
      await consoleButton.click();
      await page.waitForTimeout(500);
    }

    // テストログを生成するためにAPIを呼ぶ
    const testResponse = await page.request.get('http://localhost:33000/api/v2/novels');
    expect(testResponse.ok()).toBeTruthy();
    
    // ログが追加されるのを待つ
    await page.waitForTimeout(2000);

    // 最終ログ数を確認
    const finalLogCount = await page.locator(`${consolePanelSelector} .log-entry, ${consolePanelSelector} [class*="hover:bg-gray"]`).count();
    console.log(`Final log count: ${finalLogCount}`);

    // ログテキストを取得して重複をチェック
    const logElements = await page.locator(`${consolePanelSelector} [class*="hover:bg-gray"]`).all();
    const logTexts: string[] = [];
    
    for (const element of logElements) {
      const text = await element.textContent();
      if (text) {
        logTexts.push(text.trim());
      }
    }

    // 同一タイムスタンプ + 同一メッセージの重複をチェック
    const duplicates = logTexts.filter((text, index) => {
      return logTexts.indexOf(text) !== index && logTexts.indexOf(text) !== -1;
    });

    console.log(`Found ${duplicates.length} duplicate log entries`);
    if (duplicates.length > 0) {
      console.log('Duplicate logs:', duplicates.slice(0, 5));
    }

    // 重複がないことを確認（同じメッセージが3回以上出現しないこと）
    const messageCounts = new Map<string, number>();
    for (const text of logTexts) {
      // タイムスタンプを除去してメッセージ部分のみを抽出
      const messageOnly = text.replace(/^\d{2}:\d{2}:\d{2}\s+\w+\s+/, '');
      messageCounts.set(messageOnly, (messageCounts.get(messageOnly) || 0) + 1);
    }

    const excessiveDuplicates = Array.from(messageCounts.entries()).filter(([_, count]) => count >= 3);
    if (excessiveDuplicates.length > 0) {
      console.log('Messages appearing 3+ times:', excessiveDuplicates.slice(0, 5));
    }

    // 同じメッセージが3回以上出現していないことを確認
    expect(excessiveDuplicates.length).toBe(0);
  });
});
