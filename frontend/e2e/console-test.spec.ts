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
});
