# フロントエンド開発ガイド

このドキュメントは、Narou.rb MOD のフロントエンド開発に関する詳細情報を提供します。

## アーキテクチャ概要

### 技術選定の理由

#### Astro
- **静的サイト生成（SSG）**: 高速なページロード
- **アイランドアーキテクチャ**: 必要な部分だけJavaScriptを読み込み
- **フレームワーク非依存**: 複数のUIフレームワークを併用可能
- **優れたDX**: TypeScript完全サポート、Hot Module Replacement

#### Svelte
- **リアクティビティ**: 効率的な状態管理
- **軽量**: ランタイムが小さく高速
- **書きやすさ**: シンプルな構文
- **Svelte 5**: 新しいRunes APIによる改善された状態管理

#### Tailwind CSS
- **ユーティリティファースト**: 迅速なUI開発
- **レスポンシブ対応**: モバイル・タブレット・デスクトップに対応
- **ダークモード**: 簡単にダークモード実装
- **カスタマイズ性**: プロジェクトに合わせた調整が容易

## プロジェクト構造

```
frontend/
├── src/
│   ├── components/          # Svelteコンポーネント
│   │   ├── Header.svelte    # ヘッダーナビゲーション
│   │   ├── NovelList.svelte # 小説リストテーブル
│   │   └── ...              # その他のコンポーネント
│   │
│   ├── layouts/             # Astroレイアウト
│   │   └── BaseLayout.astro # 基本HTMLレイアウト
│   │
│   ├── lib/                 # ユーティリティ・ヘルパー
│   │   └── api.ts           # バックエンドAPIクライアント
│   │
│   ├── pages/               # ページコンポーネント（ルーティング）
│   │   └── index.astro      # メインページ
│   │
│   ├── styles/              # グローバルスタイル
│   │   └── global.css       # Tailwind CSSインポート
│   │
│   └── types/               # TypeScript型定義
│       └── api.ts           # API関連の型定義
│
├── public/                  # 静的ファイル
│   └── favicon.svg
│
├── astro.config.mjs         # Astro設定
├── svelte.config.js         # Svelte設定
├── tsconfig.json            # TypeScript設定
└── package.json             # 依存関係・スクリプト
```

## 開発ワークフロー

### 1. 新しいコンポーネントの作成

```bash
# Svelteコンポーネント
touch src/components/NewComponent.svelte

# Astroページ
touch src/pages/new-page.astro
```

#### Svelteコンポーネントの基本構造

```svelte
<!--
  コンポーネントの説明
  
  使用方法やpropsの説明
-->
<script lang="ts">
  import { onMount } from 'svelte';
  
  // Props定義
  interface Props {
    title: string;
    count?: number;
  }
  
  let { title, count = 0 }: Props = $props();
  
  // State (Svelte 5 Runes)
  let value = $state(0);
  
  // Lifecycle
  onMount(() => {
    console.log('Component mounted');
  });
  
  // Functions
  function handleClick() {
    value++;
  }
</script>

<div class="container">
  <h2>{title}</h2>
  <button onclick={handleClick}>
    Count: {value}
  </button>
</div>

<style>
  /* コンポーネント固有のスタイル（必要な場合） */
  .container {
    /* Tailwindで対応できない場合のみ使用 */
  }
</style>
```

### 2. API連携の追加

新しいAPIエンドポイントを追加する場合：

1. `src/types/api.ts` に型定義を追加
2. `src/lib/api.ts` にAPI関数を追加
3. コンポーネントから呼び出し

例：

```typescript
// src/types/api.ts
export interface NewData {
  id: number;
  name: string;
}

// src/lib/api.ts
export async function getNewData(): Promise<NewData[]> {
  return fetchApi<NewData[]>('/api/new_data');
}

// Component.svelte
<script lang="ts">
  import { getNewData } from '../lib/api';
  import type { NewData } from '../types/api';
  
  let data = $state<NewData[]>([]);
  
  onMount(async () => {
    data = await getNewData();
  });
</script>
```

### 3. スタイリング

Tailwind CSSを優先的に使用：

```svelte
<!-- 良い例 -->
<div class="flex items-center justify-between p-4 bg-white dark:bg-gray-800 rounded-lg shadow-md">
  <h2 class="text-2xl font-bold text-gray-900 dark:text-white">タイトル</h2>
  <button class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors">
    アクション
  </button>
</div>

<!-- カスタムCSSが必要な場合 -->
<style>
  .custom-gradient {
    background: linear-gradient(45deg, #667eea 0%, #764ba2 100%);
  }
</style>
```

### 4. 型安全性の確保

常にTypeScriptの型を活用：

```typescript
// 明示的な型定義
let count: number = 0;

// 型推論を活用
const items = [1, 2, 3]; // number[]

// インターフェースの使用
interface User {
  id: number;
  name: string;
  email?: string; // オプショナル
}

const user: User = {
  id: 1,
  name: 'Taro',
};
```

### 5. テストの追加（今後実装予定）

```bash
# Vitestをインストール
npm install -D vitest @testing-library/svelte

# テストファイルを作成
touch src/components/Component.test.ts
```

## バックエンド連携

### プロキシ設定

開発時は `astro.config.mjs` でプロキシ設定済み：

```javascript
vite: {
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:33000',
        changeOrigin: true,
      },
    },
  },
}
```

### 環境変数

`.env` ファイルで設定：

```bash
PUBLIC_API_BASE_URL=http://localhost:33000
PUBLIC_DEV_MODE=true
```

コンポーネントから使用：

```typescript
const apiUrl = import.meta.env.PUBLIC_API_BASE_URL;
```

## パフォーマンス最適化

### 1. コンポーネントの遅延ロード

```astro
---
// client:load - ページロード時に読み込み
// client:idle - アイドル時に読み込み
// client:visible - ビューポートに入ったら読み込み
---

<Header client:load />
<NovelList client:idle />
<Footer client:visible />
```

### 2. 画像最適化

```astro
---
import { Image } from 'astro:assets';
import coverImage from '../assets/cover.jpg';
---

<Image 
  src={coverImage} 
  alt="Cover" 
  width={400} 
  height={600}
  loading="lazy"
/>
```

### 3. バンドルサイズの最適化

不要なライブラリは削除し、tree-shakingを活用：

```typescript
// 悪い例
import _ from 'lodash';

// 良い例
import debounce from 'lodash/debounce';
```

## デバッグ

### 開発ツール

1. **Astro Dev Toolbar**: 開発時に自動表示
2. **Svelte DevTools**: Chrome拡張機能
3. **VS Code Extensions**:
   - Astro
   - Svelte for VS Code
   - Tailwind CSS IntelliSense

### ログ出力

```typescript
// 開発時のみログ出力
if (import.meta.env.DEV) {
  console.log('Debug info:', data);
}
```

## ビルドとデプロイ

### ビルド

```bash
npm run build
```

出力: `dist/` ディレクトリ

### プレビュー

```bash
npm run preview
```

### バックエンドへの統合（今後実装予定）

ビルド済みファイルをバックエンドの静的ファイルディレクトリに配置：

```bash
# ビルド後、distをコピー
cp -r frontend/dist/* lib/web/public/
```

## コーディング規約

### ファイル命名

- コンポーネント: `PascalCase.svelte`
- ページ: `kebab-case.astro`
- ユーティリティ: `camelCase.ts`

### コメント

```typescript
/**
 * 関数の説明（日本語）
 * 
 * @param id - パラメータの説明
 * @returns 戻り値の説明
 */
function fetchNovel(id: number): Promise<Novel> {
  // 実装
}
```

### インポート順序

1. 外部ライブラリ
2. Astro/Svelteモジュール
3. 内部モジュール（型、ユーティリティ）
4. 相対パス

```typescript
import { onMount } from 'svelte';
import type { Novel } from '../types/api';
import { getNovels } from '../lib/api';
```

## トラブルシューティング

### よくある問題

#### 1. APIリクエストが失敗する

- バックエンドが起動しているか確認
- `.env` のAPI URLが正しいか確認
- CORS設定を確認

#### 2. 型エラーが出る

```bash
npm run astro check
```

#### 3. ビルドエラー

```bash
# キャッシュをクリア
rm -rf node_modules .astro dist
npm install
npm run build
```

## 今後の拡張計画

- [ ] WebSocket対応（リアルタイム更新）
- [ ] PWA化（オフライン対応）
- [ ] E2Eテスト（Playwright）
- [ ] ユニットテスト（Vitest）
- [ ] アクセシビリティ改善（ARIA属性）
- [ ] 国際化対応（i18n）
- [ ] パフォーマンスモニタリング

## 参考リンク

- [Astro Documentation](https://docs.astro.build)
- [Svelte Documentation](https://svelte.dev/docs)
- [Svelte 5 Runes](https://svelte.dev/docs/svelte/what-are-runes)
- [Tailwind CSS Documentation](https://tailwindcss.com/docs)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
