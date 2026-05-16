# Repository Guidelines (Frontend / Astro + Svelte)

`narou-mod` のフロントエンド (`frontend/`) 向けガイドです。Astro 5 + Svelte 5 + Tailwind CSS 4 + TypeScript で構成されています。リポジトリ全体のルールとバックエンド (Ruby) のガイドは [../AGENTS.md](../AGENTS.md) を参照してください。

## Tech Stack

- **Astro 5.x**: ルーティング / 静的サイト生成 / アイランドアーキテクチャ。
- **Svelte 5.x**: UI コンポーネント。Runes API (`$state`, `$props`, `$derived`) を使用。
- **Tailwind CSS 4.x**: ユーティリティファースト CSS。設定は `tailwind.config.js`、Vite プラグインは `astro.config.mjs` で適用。
- **TypeScript 5.x**: `tsconfig.json` は `astro/tsconfigs/strict` を継承。
- **Playwright**: E2E テスト (`e2e/`)。

## Project Structure & Module Organization

```
frontend/
├── src/
│   ├── components/     # Svelte コンポーネント (Header, NovelList, Modal 系 など)
│   │   └── console/    # コンソール関連の細分コンポーネント
│   ├── layouts/        # Astro レイアウト (BaseLayout.astro など)
│   ├── lib/            # API クライアント・ストア・ユーティリティ
│   │   ├── api.ts             # バックエンド REST API ラッパ
│   │   ├── backend-config.ts  # public/backend-port.json から動的にポート解決
│   │   ├── progressStore.ts   # 進捗ストア
│   │   ├── pushserver.ts      # WebSocket / Push 連携
│   │   └── stores/            # Svelte stores
│   ├── pages/          # Astro ページ (index, settings, tasks, help, settings-debug)
│   ├── styles/         # グローバル CSS (Tailwind import)
│   └── types/          # API・ドメイン型定義
├── public/             # 静的ファイル (`backend-port.json` は実行時生成・gitignore)
├── e2e/                # Playwright E2E テスト
├── astro.config.mjs    # Astro / Vite / プロキシ / Svelte 設定
├── svelte.config.js    # Svelte preprocess
├── tailwind.config.js  # Tailwind 設定
├── tsconfig.json       # TypeScript 設定
├── .prettierrc         # Prettier 設定 (tab=2, double quote, trailing comma=es5)
└── package.json
```

## Build, Test, and Development Commands

すべて `frontend/` ディレクトリ内で実行します。

- `npm install`: 依存をインストール。
- `npm run dev`: 開発サーバ起動 (`http://localhost:4321`)。`/api/*` はバックエンドへプロキシ。
- `npm run build`: プロダクションビルド (`dist/`)。ビルド後に `git describe --always` の結果を `dist/.build-commit` に書き出す。
- `npm run preview`: ビルド成果物のプレビュー。
- `npm run check`: `astro check` で TypeScript / テンプレートの型検査。
- `npm run format` / `npm run format:check`: Prettier の整形 / 検査。
- `npx playwright test`: E2E テストを実行（必要に応じて `npx playwright install`）。

### バックエンドとの連携

- 開発時は `astro.config.mjs` の Vite プロキシ経由で `/api/*` が `http://localhost:<port>` に転送されます。
- バックエンドポートは `public/backend-port.json` から読み込み、未生成時は `5678` をフォールバック。本ファイルは `.gitignore` 対象なので、ローカル起動スクリプトに任せて手動で作らない。
- API 連携ロジックの追加は `src/lib/api.ts` と `src/types/` の型定義をペアで更新する。

## Coding Style & Naming Conventions

- インデント 2 スペース、ダブルクォート、行幅 80、末尾カンマは `es5`（`.prettierrc`）。
- ファイル命名:
  - Svelte コンポーネント: `PascalCase.svelte`
  - Astro ページ: `kebab-case.astro`（または `index.astro`）
  - ユーティリティ / 型: `camelCase.ts`
- TypeScript は strict。`any` の使用は避け、`src/types/` に型を寄せる。
- Svelte は Svelte 5 Runes (`$state`, `$props`, `$derived`, `$effect`) を採用。`export let` 等の旧記法を新規追加しない。
- スタイリングは Tailwind を第一選択。コンポーネント固有の `<style>` は Tailwind で表現困難な場合のみ。
- `husky` + `lint-staged` でステージ済みファイルが `prettier --write` されるため、コミット前にローカルで整形しておく。

## Testing Guidelines

- E2E は `e2e/*.spec.ts` に Playwright で記述。`playwright.config.ts` を参照。
- 型の健全性は `npm run check` で必ず通す。CI でも同コマンドが走る (`.github/workflows/ci.yml`)。
- ユニットテストは未導入（Vitest 導入予定）。新規導入時は `*.test.ts` を対象コンポーネントの近くに配置する方針。

## Commit & Pull Request Guidelines

- フロントエンド単独の変更でも、コミット件名は命令形でリポジトリ全体の方針 ([../AGENTS.md](../AGENTS.md)) に従う。
- PR には UI 変更のスクリーンショット、または操作録画を添付する。
- API 仕様や URL を変える場合は、対応するバックエンド側の変更とまとめる（あるいは PR を相互リンク）。
- CI では `npm ci` → `npm run build` → `npm run check` が走る。ローカルで同じ流れを通してから push する。

## Security & Configuration Tips

- `.env` は `.env.example` を雛形にローカルで作成。シークレットや本番 URL は含めない。
- 公開ビルドに含めたくない値は `PUBLIC_` プレフィックスを付けない (Astro の規約)。
- バックエンド API の URL 直書きは避け、`src/lib/backend-config.ts` か `import.meta.env` 経由で取得する。
- `public/backend-port.json` と `dist/.build-commit` はランタイム / ビルド生成物。`.gitignore` 済みのまま運用する。

## Agent-Specific Instructions

- 既存 Svelte 5 + Astro 5 のパターンに沿う。レガシー記法 (`<script context="module">` の濫用、`export let` の新規追加、Svelte 4 ストア記法への退行) は避ける。
- 不要な依存追加・大規模リライトは行わず、最小スコープの変更を心がける。
- 変更後は最低限 `npm run check` を走らせる。UI 変更時はブラウザでの動作確認を併用する（バックエンド未起動でも `ServerStoppedBanner` 経由でフォールバックが見える設計）。
- ルートの [../AGENTS.md](../AGENTS.md) のコミット ID 規約（`ponpon.USA <init0531.usa@gmail.com>` 固定）はフロントエンド作業時も同様に遵守する。
