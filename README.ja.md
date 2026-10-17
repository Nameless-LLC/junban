<div align="center">

# junban

**いま、誰の番？**<br>
AI エージェントを何体も並列で回すための tmux 操縦席。

[English](README.md) · [日本語](README.ja.md) · [▶ 25秒のデモ](https://junban.namelessjp.com/)

<a href="https://junban.namelessjp.com/"><img src="docs/hero-ja.svg" alt="junban の画面。tmux で Claude Code を6つ動かしていて、赤い帯が「2件があなたの返事待ち」と表示。Alt+a でいちばん長く待っているウィンドウへ飛び、Alt+f で全エージェントをプレビュー付きで一覧する" width="100%"></a>

</div>

AI エージェントを並べて仕事を頼むと、どこかで1つが、`psql` を実行してよいかの許可を20分前から待っています。全部のウィンドウを順に開くまで、それに気づけません。

**junban（順番）** はこれを解決します。そのうえで、次に押すべきキーまで教えます。

- **✋ 赤**：エージェントがあなたの返事を待っている（許可・質問）
- **✓ 緑**：作業が終わったが、まだ見ていない
- **● 黄**：作業中

あとは **Alt+a** を押すだけで、いちばん長く待たせているウィンドウへ移動できます。

## 導入

ターミナルで1行実行するだけです。

```sh
curl -fsSL https://raw.githubusercontent.com/Nameless-LLC/junban/main/install.sh | bash
```

tmux に junban を入れて読み込み直し、Claude Code があればそちらにもつなぎます。あとは **Alt+a** を押すだけです。

<details>
<summary>TPM で入れる場合</summary>

`~/.tmux.conf` に追記して、prefix + I を押します。

```tmux
set -g @plugin 'Nameless-LLC/junban'
```

続けて Claude Code につなぎます。

```sh
claude plugin marketplace add Nameless-LLC/junban && claude plugin install junban@junban
```

</details>

Codex CLI と Gemini CLI は `~/.tmux/plugins/junban/scripts/setup.sh codex`（または `gemini`）です。詳しくは[Claude Code 以外のエージェント](#claude-code-以外のエージェント)を見てください。

必要なのは tmux 3.2 以上と bash です。fzf と python3 は任意ですが、入れておくのがおすすめです。

### うまく動かないとき

`~/.tmux/plugins/junban/scripts/doctor.sh` を実行してください（Claude Code なら `/junban:doctor`）。よくある問題なら直し方まで表示します。それでも直らなければ、その出力を[バグ報告](https://github.com/Nameless-LLC/junban/issues/new?template=bug.yml)に貼ってください。ウィンドウの名前や依頼の内容は出力に含まれません。質問や使い方の相談は [Discussions](https://github.com/Nameless-LLC/junban/discussions) へどうぞ。セキュリティの問題は公開せずに報告してください（[SECURITY.md](SECURITY.md)）。

## 覚えるキーは1つだけ

**Alt+a** です。何も待っていないとき、ステータスバーの2行目には覚えておくと便利な5つのキーが出ます。誰かが待っているときは、そこが「Alt+a で移動」という帯に変わります。何も覚えなくても、画面が次の操作を教えてくれます。

| キー | |
|---|---|
| **Alt+a** | 次に見るべきウィンドウへ移動。返事待ちが先、次に完了。それぞれ待った時間が長い順 |
| **Alt+f** | 全エージェントの一覧。困っている順に並び、文字を打つと絞り込め、画面のプレビューも出る |
| **Alt+n** | 今のディレクトリで新しいエージェントを開く（既に別のエージェントが作業中なら、別の worktree で開く） |
| **Alt+g** | ポップアップのシェル。閉じても中身が残る |
| **Alt+/** | 早見表。実際に割り当てたキーから自動で作る。今日のタイムラインと待ち時間の集計も出る |
| prefix T | 今日のタイムライン。ウィンドウごとに、作業中・返事待ち・完了の時間帯を1行で表示 |
| Alt+1…9 · Alt+[ ] · Alt+Tab · Alt+z | 番号のウィンドウへ · 前/次 · 直前 · 最大化 |

端末が Alt キーを横取りする場合は、prefix の後に `a` `f` `C` `g` `/` を押しても同じ操作ができます。

すべての設定項目を載せたマニュアル: [junban.namelessjp.com/manual](https://junban.namelessjp.com/manual/)

## 他のプラグインとの違い

タブにバッジを出すプラグインは[多く](#先行事例)、待たせた順に移動するもの（gs/tmux-agent-status）や待ち時間を測るもの（muxa）もあります（[比較表](https://junban.namelessjp.com/#compare)）。junban はそれらを常駐プロセスのない素の tmux プラグイン1つにまとめ、ほかで見つからなかった機能として、次のキーを示すステータス行・同じ Git 作業ツリーの相乗りへの警告・放置ウィンドウを沈める表示・短い返事で変わらない手元モデルのウィンドウ名を加えています。

**状態だけでなく、次の一手を示します。** 2行目の案内は状況に応じて変わるので、配属初日の人でもキーを1つも覚えずに使えます。

**バッジが「作業中」のまま止まりません。** フックには抜けがあります。作業の途中で Esc を押すと終了イベントが飛ばないため、フックだけで状態を作るツールは「作業中」を表示し続けます。junban は Claude Code 自身が書いているセッション記録（`~/.claude/sessions`）と照らし合わせて、止まった状態を直します。その際、プロセスが本当にそのウィンドウの中で動いているかも確かめます。ウィンドウの ID は tmux サーバーごとにしか一意でないので、プロセスの親子関係まで見ています。

**ウィンドウの名前は作業内容から付き、短い返事では変わりません。** 既定では、依頼の1行目がウィンドウの名前になります。モデルを指定すると、直近の依頼をまとめた名前にします。手元の Ollama に小さいモデルを常駐させておけば1秒かかりません。「OK」「進めて」のような短い返事では名前を変えません。自分で付けた名前（`prefix ,`）は二度と上書きしません。

**並列運用での事故のもとを、先に知らせます。** 1つ目は、同じ git の作業ツリーで2つのエージェントを動かすことです。互いの編集を上書きし、相手の書きかけをコミットしてしまいます。junban はそうしたウィンドウに ⚠ を付け、2行目の案内にそのウィンドウの名前を出します。そのうえで Alt+n を押すと、2体目の Claude Code は別の worktree（`claude --worktree`）で起動します。2つ目は、使い終わったウィンドウを開いたまま放置することです。1日以上触っていないウィンドウには薄い `z` が付き、Alt+f の一覧では下に沈み、件数がキー案内の後ろに出ます。放置されたウィンドウが40個あっても、あなたを待っている1枚を見失いません。

**エージェントがあなたを待った時間を測ります。** 2行目の案内に、今日の合計と返答の中央値が出ます（`⏱ 今日の待ち時間 42分 · 返答の中央値 3分10秒`）。Alt+/ を押すと、直近7日の日ごとの棒グラフ、先週との比較（返答の中央値と合計）、自己ベストの日、目標以内に返せた日の連続記録、今日いちばん待たせたウィンドウが出ます。`scripts/stats.sh 30` でさらに前までさかのぼれます。待ち時間は ✋ や ✓ が付いてから、返事をするかウィンドウを開くまでです。見ている最中に終わった分は数えず、一晩放置しても1回あたり最大1時間で打ち切ります。記録は手元の TSV ファイルにだけ残ります。

**1日のタイムラインが見られます。** prefix T（と Alt+/ の上部）で、ウィンドウごとに1行、黄色の █ が作業中、赤の ▓ があなたの返事待ち、緑の ▒ が完了・未確認として並びます。下には稼働していた時間帯、エージェントの作業時間と待たせた時間、最大いくつのウィンドウが同時に動いたかが出ます。`scripts/timeline.sh 1` で前日を表示します。自分の1日をふり返るための画面で、データは手元から出ません。Alt キーで開きたい場合は `@junban-key-timeline M-y` を設定します（Claude Code では Alt+t が思考の切り替えなので、標準では割り当てていません）。

**マスコットがいます。** ステータス行に掲示板の「目」が出て、状況に合わせて変わります。待っているウィンドウがあれば `[▮ ▮]!`、終わったら `[◠ ◠]`、動いている間は `[▮▮ ]` と左右を見回し、することがないときは `[▬ ▬]z` です。Alt+/ の集計では1週間の様子にひと言コメントします。初期設定でオンです。`set -g @junban-mascot off` で消せます。

**日本語とタイ語に対応しています。** 英語・日本語・タイ語を標準で同梱し、ロケールから自動で選びます。日本語やタイ語のウィンドウ名はバイト数ではなく表示幅で切り詰めるので、タブの並びが崩れません。

**何を求めているかを1行で出します。** エージェントが質問・許可を求めたときや作業を終えたとき、✋/✓ の帯と Alt+f の一覧に「何を求めているか／何が起きたか」を1行で出します（例:「テスト成功、PR #12 を作成」）。命名用のモデルを設定していればモデルが書き、なければ返答の最初の1行を使います。スマホ通知にも同じ1行が載ります。止めるときは `set -g @junban-recap off` です。

**tmux と bash だけで動きます。** 常駐プロセスは不要です。テストは175件あり、CI で Linux と macOS の両方で回しています。

## 設定

すべて任意です。`~/.tmux.conf` の、プラグインを読み込む行より**前に**書いてください。設定項目の一覧は [README.md](README.md#configuration) にあります。日本語での表示を固定したい場合は、次の1行を書きます。

```tmux
set -g @junban-lang ja
```

ウィンドウの名前付けを手元の LLM にさせる例:

```tmux
set -g @junban-rename llm
set -g @junban-namer-url http://localhost:11434
set -g @junban-namer-model qwen3:8b
```

## Claude Code 以外のエージェント

| エージェント | 導入 | できること |
|---|---|---|
| Claude Code | プラグイン（上の1行で入ります） | ✋ ✓ ●、1行要約、ウィンドウの名前。Esc で止めてもバッジが自動で直る |
| Codex CLI | `scripts/setup.sh codex` のあと、Codex で `/hooks` を開いて一度だけ信頼する | ✋ ✓ ●、実行したいコマンドを1行要約に出す、ウィンドウの名前。Esc でバッジが消える |
| Gemini CLI | `scripts/setup.sh gemini` | ✋ ✓ ●、実行したいコマンドを1行要約に出す、ウィンドウの名前 |

```sh
~/.tmux/plugins/junban/scripts/setup.sh codex    # ~/.codex/hooks.json に書く
~/.tmux/plugins/junban/scripts/setup.sh gemini   # ~/.gemini/settings.json に書く
```

どちらも既存のフックは残し、junban の分だけを入れ替えます（何度実行しても大丈夫です）。元のファイルは `.bak` に残し、`--print` を付けると書き込まずに中身だけ見られます。`set -g @junban-agent-cmd codex` にすると Alt+n で Codex が起動します。

ほかのツールも、コマンドを実行できれば何でもつなげられます。junban が見ているのは tmux のウィンドウオプション1つだけです。

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
