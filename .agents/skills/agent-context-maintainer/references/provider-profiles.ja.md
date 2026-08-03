# Provider Profiles

provider profile は、ポリシーを分岐させるためではなく、style と tool behavior を調整するために使います。

profile 文言の正本は `scripts/agent_context.py` の `PROVIDERS` dict であり、生成される `.agents/profiles/*.md` はそこからレンダリングされます。本書は各 profile の意図とアンチパターンを解説するものです — 生成される bullet の逐語コピーではなく意図的に言い換えて書くことで、両者を逐語一致で同期させる必要をなくしています。

## Codex / OpenAI

重視すること:

- 編集前にリポジトリを調査すること。
- 無関係な user changes に触れない、小さく scoped な patch。
- focused validation と、実行したコマンドの正確な報告。
- 長期作業での durable な repo-local artifact。

避けること:

- `core.md` 全体を繰り返す。
- 実装可能なタスクで長い speculative design essay に寄りすぎる。

## Claude

重視すること:

- design review や cross-document reconciliation で長文推論の強みを活かす。
- assumptions と open questions を明示する。
- architectural tradeoff を丁寧に扱う。

避けること:

- ユーザーが実装を求めているときに、分析だけで具体的なファイル更新を置き換えてしまう。

## Gemini

重視すること:

- 多数のファイルを横断した broad context synthesis。
- docs、manifests、generated artifacts の高速 inventory。
- repository facts に対する明確な source attribution。

避けること:

- ローカルファイルを確認せず、広い recall を verified current state として扱う。

## Cursor / IDE Agents

重視すること:

- 編集箇所の locality。
- file / symbol navigation。
- IDE review しやすい小さな変更。
- 無関係な formatting churn の回避。

避けること:

- task route なしに、多数ファイルへ hidden bulk rewrite を行う。

## GitHub Copilot

重視すること:

- cloud agent の探索を減らす concise な repository-wide guidance。
- `.github/copilot-instructions.md` を `AGENTS.md` への bridge として保つ。
- provider-specific な workflow details は `.agents/profiles/copilot.md` と routed skills に置く。

避けること:

- 共有ポリシー全体を `.github/copilot-instructions.md` にコピーする。
- routed skill や `.github/instructions/*.instructions.md` の方が狭く表現できる task-specific / path-specific rule を repository-wide bridge に置く。

## Antigravity

重視すること:

- ユーザーが検証しやすい plan、command result、screenshot、browser recording、review note などの artifact。
- 広範な autonomous edit や risky command の前に、user-visible な intent を明確にする。
- 利用可能な場合は、共有 `AGENTS.md` policy と Gemini-compatible bridge files を使う。

避けること:

- autonomous execution を repository safety rules を省略する許可として扱う。
- provider contract が確認できる前に、Gemini guidance 全体を Antigravity profile に重複させる。

## Unknown Agent

generic profile を使います。

- `AGENTS.md`、`.agents/core.md`、`.agents/routing.md` を読む。
- 自分の runtime と tools を識別する。
- provider-specific behavior がない場合は core rules に従い、不足した判断が意味のあるリスクになるときだけ質問する。
