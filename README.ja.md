<div align="center">

# junban

**いま、誰の番？**<br>
AI エージェントを何体も並列で回すための tmux 操縦席。

[English](README.md) · [日本語](README.ja.md)

<img src="docs/hero-ja.svg" alt="junban の画面。tmux で Claude Code を6つ動かしていて、赤い帯が「2窓があなたの返事待ち」と表示。Alt+a でいちばん長く待っている窓へ飛び、Alt+f で全エージェントをプレビュー付きで一覧する" width="100%">

</div>

Claude Code を6つ並べて仕事を頼んだとします。そのうち1つが、`psql` を実行してよいかの許可を20分前から待っていました。全部の窓を順に開くまで、それに気づけません。

**junban（順番）** はこれを解決します。そのうえで、次に押すべきキーまで教えます。

- **✋ 赤**：エージェントがあなたの返事を待っている（許可・質問）
- **✓ 緑**：作業が終わったが、まだ見ていない
- **● 黄**：作業中

あとは **Alt+a** を押すだけで、いちばん長く待たせている窓へ飛べます。

## 導入

**1. tmux**（[TPM](https://github.com/tmux-plugins/tpm) を使う場合）

```tmux
set -g @plugin 'Nameless-LLC/junban'
```

TPM を使わない場合:

```sh
curl -fsSL https://raw.githubusercontent.com/Nameless-LLC/junban/main/install.sh | bash
```

**2. Claude Code**（どのセッションの中でも）

```
/plugin marketplace add Nameless-LLC/junban
/plugin install junban@junban
```

これで終わりです。新しく始めた Claude Code のセッションは、最初の依頼から状態を報告します。

必要なのは tmux 3.2 以上と bash です。fzf と python3 は任意ですが、入れておくのがおすすめです。

## 覚えるキーは1つだけ

**Alt+a** です。何も待っていないとき、ステータスバーの2行目には覚えておくと便利な5つのキーが出ます。誰かが待っているときは、そこが「Alt+a で飛ぶ」という帯に変わります。何も覚えなくても、画面が次の操作を教えてくれます。

| キー | |
|---|---|
| **Alt+a** | 次に見るべき窓へ飛ぶ。返事待ちが先、次に完了。それぞれ待った時間が長い順 |
| **Alt+f** | 全エージェントの一覧。困っている順に並び、文字を打つと絞り込め、画面のプレビューも出る |
| **Alt+n** | 今のディレクトリで新しいエージェントを開く（既に別のエージェントが作業中なら、別の worktree で開く） |
| **Alt+g** | 小窓のシェル。閉じても中身が残る |
| **Alt+/** | 早見表。実際に割り当てたキーから自動で作る |
| Alt+1…9 · Alt+[ ] · Alt+Tab · Alt+z | 番号の窓へ · 前/次 · 直前 · 最大化 |

端末が Alt キーを横取りする場合は、prefix の後に `a` `f` `C` `g` `/` を押しても同じ操作ができます。

## 他のプラグインとの違い

タブに状態アイコンを出すプラグインは、すでに[いくつもあります](#先行事例)。junban も最初はその1つでした。そこから、毎日8体を並べて使い込むうちに、次の点を作り込みました。

**状態だけでなく、次の一手を示します。** 2行目の案内は状況に応じて変わるので、配属初日の人でもキーを1つも覚えずに使えます。右端には小技が1分ごとに出ます。

**バッジが「作業中」のまま止まりません。** フックには抜けがあります。作業の途中で Esc を押すと終了イベントが飛ばないため、フックだけで状態を作るツールは「作業中」を表示し続けます。junban は Claude Code 自身が書いているセッション記録（`~/.claude/sessions`）と照らし合わせて、止まった状態を直します。その際、プロセスが本当にその窓の中で動いているかも確かめます。窓の ID は tmux サーバーごとにしか一意でないので、プロセスの親子関係まで見ています。

**窓の名前は作業内容から付き、相槌では変わりません。** 既定では、依頼の1行目が窓の名前になります。モデルを指定すると、直近の依頼をまとめた名前にします。手元の Ollama に小さいモデルを常駐させておけば1秒かかりません。「OK」「進めて」「ครับ」のような相槌では名前を変えません。自分で付けた名前（`prefix ,`）は二度と上書きしません。

**並列運用でいちばん損をする2つの癖を拾います。** 1つ目は、同じ git の作業ツリーで2体を動かすことです。互いの編集を上書きし、相手の書きかけをコミットしてしまいます。junban はそうした窓に ⚠ を付け、2行目の案内にその窓の名前を出します。そのうえで Alt+n を押すと、2体目の Claude Code は別の worktree（`claude --worktree`）で起動します。2つ目は、使い終わった窓を開いたまま放置することです。1日以上触っていない窓には薄い `z` が付き、Alt+f の一覧では下に沈み、件数がキー案内の後ろに出ます。放置された窓が40枚あっても、あなたを待っている1枚を見失いません。

**日本語とタイ語に対応しています。** 英語・日本語・タイ語を標準で同梱し、ロケールから自動で選びます。日本語やタイ語の窓名はバイト数ではなく表示幅で切り詰めるので、タブの並びが崩れません。

**tmux と bash だけで動きます。** デーモンも常駐プロセスもありません。テストは53件あり、CI で Linux と macOS の両方で回しています。

## 設定

すべて任意です。`~/.tmux.conf` の、プラグインを読み込む行より**前に**書いてください。設定項目の一覧は [README.md](README.md#configuration) にあります。日本語での表示を固定したい場合は、次の1行を書きます。

```tmux
set -g @junban-lang ja
```

窓の名前付けを手元の LLM にさせる例:

```tmux
set -g @junban-rename llm
set -g @junban-namer-url http://localhost:11434
set -g @junban-namer-model qwen3:8b
```

## Claude Code 以外のエージェント

junban が見ているのは tmux の窓オプション1つだけです。コマンドを実行できるツールなら何でもつなげられます。

```sh
~/.tmux/plugins/junban/scripts/state.sh running   # waiting | done | idle | clear
```

## 先行事例

重なる機能を持つプラグインがあり、用途によってはこちらの方が合うかもしれません。
[tmux-agent-indicator](https://github.com/accessd/tmux-agent-indicator) ·
[tmux-agent-status (RatulMaharaj)](https://github.com/RatulMaharaj/tmux-agent-status) ·
[tmux-agent-status (rorhcdream)](https://github.com/rorhcdream/tmux-agent-status)（セッション記録がフックより確かだと示したのはこのプロジェクトです） ·
[tmux-handlr](https://github.com/CRThaze/tmux-handlr) ·
[claude-code-tmux-status](https://github.com/XavierYounan/claude-code-tmux-status) ·
[tmux-window-notifier](https://github.com/mrf/tmux-window-notifier)

MIT ライセンス。[Nameless](https://namelessjp.com) で毎日使っています。
