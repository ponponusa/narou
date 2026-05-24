# Repository Guidelines for Gemini (Frontend / Astro + Svelte)

`narou-mod` のフロントエンド (`frontend/`) 向けに、Gemini (Antigravity) 用の開発ガイドおよびルールを定義します。
リポジトリ全体およびバックエンド (Ruby) のルールは [../GEMINI.md](../GEMINI.md) を参照してください。

## Tech Stack

- **Astro 5.x**: ルーティング / 静的サイト生成 / アイランドアーキテクチャ。
- **Svelte 5.x**: UI コンポーネント。Runes API (`$state`, `$props`, `$derived`, `$effect`) を使用。
- **Tailwind CSS 4.x**: ユーティリティファースト CSS。
- **TypeScript 5.x**: 厳格な型安全設計 (`astro/tsconfigs/strict` を継承)。
- **Playwright**: E2E テスト (`e2e/`)。

## Project Structure & Module Organization

```
frontend/
├── src/
│   ├── components/     # Svelte コンポーネント (Header, NovelList, Modal 系 など)
│   │   └── console/    # コンソール関連コンポーネント
│   ├── layouts/        # Astro レイアウト
│   ├── lib/            # API クライアント・ストア・ユーティリティ
│   │   ├── api.ts             # バックエンド REST API ラッパ
│   │   ├── backend-config.ts  # public/backend-port.json からポートを動的に解決
│   │   └── progressStore.ts   # 進捗管理ストア
│   ├── pages/          # Astro ページ (index.astro, settings.astro, etc.)
│   ├── styles/         # グローバル CSS
│   └── types/          # API・ドメイン型定義
├── public/             # 静的ファイル (`backend-port.json` は実行時に生成され、.gitignore 対象)
├── e2e/                # Playwright E2E テスト
├── astro.config.mjs    # Astro / Vite プロキシ / Svelte 設定
├── svelte.config.js    # Svelte プリプロセッサ設定
├── tailwind.config.js  # Tailwind 設定
└── package.json
```

## Build, Test, and Development Commands

すべて `frontend/` ディレクトリ内で実行します。

- `npm install`: 依存パッケージのインストール。
- `npm run dev`: 開発サーバー起動 (`http://localhost:4321`)。
  - `/api/*` はバックエンドに自動的にプロキシされます。
- `npm run build`: プロダクション用ビルド (`dist/` 配下に出力)。
- `npm run check`: Astro 及び TypeScript の型チェック。
- `npm run format`: Prettier によるコード整形。
- `npx playwright test`: E2E テストの実行。

## Coding Style & Naming Conventions

- インデント: 2 スペース。
- クォート: 原則としてダブルクォート (`"`) を使用 (Prettier 設定準拠)。
- ファイル命名規則:
  - Svelte コンポーネント: `PascalCase.svelte`
  - Astro ページ: `kebab-case.astro` (または `index.astro`)
  - ユーティリティ・型定義: `camelCase.ts`
- **Svelte 5 Runes**:
  必ず Svelte 5 の Runes (`$state`, `$props`, `$derived`, `$effect`) を使用してください。従来の `export let` や `$` ストア自動購読記法などのレガシーな構文は新規追加しないでください。
- **スタイリング**:
  原則として Tailwind CSS を使用し、インラインスタイルやコンポーネント固有の `<style>` は Tailwind での表現が困難な場合を除き、避けてください。

## Gemini (Antigravity) Specific Rules

- **Git コミットの署名**:
  フロントエンドの作業時も同様に、Git コミットの Author / Committer は必ず以下を設定してください。
  ```bash
  git config user.name "ponpon.USA"
  git config user.email "init0531.usa@gmail.com"
  ```
- **バックエンド連携**:
  API 呼び出しを行う際は、`src/lib/backend-config.ts` または `src/lib/api.ts` を経由し、接続先をハードコードしないでください。
- **型定義の徹底**:
  TypeScript は strict モードです。`any` 型の使用を避け、必ず適切な型定義を `src/types/` 内に定義、もしくはインポートして使用してください。
- **コード品質チェック**:
  コミットやプッシュを行う前に、ローカルで `npm run check` および `npm run format` を実行して、エラーやフォーマット崩れがないか確認してください。
