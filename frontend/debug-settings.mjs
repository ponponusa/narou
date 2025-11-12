import { chromium } from 'playwright';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  // コンソールログをキャプチャ
  const consoleLogs = [];
  page.on('console', msg => {
    consoleLogs.push({
      type: msg.type(),
      text: msg.text(),
      location: msg.location()
    });
  });

  // エラーをキャプチャ
  const errors = [];
  page.on('pageerror', error => {
    errors.push(error.message);
  });

  console.log('⏳ ページを読み込んでいます...');
  await page.goto('http://172.26.39.220:4321/settings', { waitUntil: 'networkidle' });
  
  // 少し待機してJavaScriptが実行されるのを待つ
  await page.waitForTimeout(2000);

  console.log('\n=== ページタイトル ===');
  console.log(await page.title());

  console.log('\n=== タブボタンの状態 ===');
  const tabs = await page.$$eval('button', buttons => 
    buttons
      .filter(btn => btn.textContent.match(/一般|詳細|WEB UI|Global|default|force|コマンド/))
      .map(btn => ({
        text: btn.textContent.trim(),
        classes: btn.className,
        visible: btn.offsetWidth > 0 && btn.offsetHeight > 0
      }))
  );
  console.log('検出されたタブ:', tabs.length);
  tabs.forEach((tab, i) => {
    console.log(`  ${i + 1}. ${tab.text} (visible: ${tab.visible})`);
  });

  console.log('\n=== 設定項目の数 ===');
  const settingItems = await page.$$eval('.setting-item', items => items.length);
  console.log(`設定項目: ${settingItems}個`);

  console.log('\n=== availableTabs の内容 ===');
  const availableTabs = await page.evaluate(() => {
    // Svelteのステートを取得する試み
    const buttons = Array.from(document.querySelectorAll('button'));
    const tabButtons = buttons.filter(btn => 
      btn.textContent.match(/一般|詳細|WEB UI|Global|default|force|コマンド/)
    );
    return tabButtons.map(btn => btn.textContent.trim());
  });
  console.log('表示されているタブ:', availableTabs);

  console.log('\n=== コンソールログ (最初の20件) ===');
  consoleLogs.slice(0, 20).forEach(log => {
    console.log(`[${log.type}] ${log.text}`);
  });

  if (errors.length > 0) {
    console.log('\n=== エラー ===');
    errors.forEach(err => console.log(`❌ ${err}`));
  }

  console.log('\n=== DOM構造（タブ部分） ===');
  const tabSection = await page.evaluate(() => {
    const container = document.querySelector('.mb-6');
    return container ? container.outerHTML.substring(0, 1000) : 'タブコンテナが見つかりません';
  });
  console.log(tabSection);

  console.log('\n=== スクリーンショット保存 ===');
  await page.screenshot({ path: '/tmp/settings-page.png', fullPage: true });
  console.log('スクリーンショットを /tmp/settings-page.png に保存しました');

  await browser.close();
})();
