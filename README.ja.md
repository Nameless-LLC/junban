<div align="center">

# junban

**いま、誰の番？**<br>
複数の AI エージェントを tmux で動かすときに、返事待ちのエージェントを教えるプラグイン。

[English](README.md) · [日本語](README.ja.md) · [▶ 25秒のデモ](https://junban.namelessjp.com/)

<a href="https://junban.namelessjp.com/"><img src="docs/hero-ja.svg" alt="junban の画面。tmux で Claude Code を6つ動かしていて、ステータスバーに赤い表示で「2件があなたの返事待ち」と出ている。Alt+a でいちばん長く待っているウィンドウへ移動し、Alt+f で全エージェントをプレビュー付きで一覧する" width="100%"></a>

</div>

複数の AI エージェントを動かしていると、1つが20分も `psql` の実行許可を待っていた、ということが起きます。ウィンドウを1つずつ開くまで気づけません。

**junban（順番）** は、返事待ちのエージェントを tmux のタブに表示し、次に押すキーを教えます。

- **✋ 赤**：あなたの返事待ち（許可・質問）
- **✓ 緑**：作業が終わったが、まだ見ていない
- **● 黄**：作業中

**Alt+a** を押すと、いちばん長く待っているウィンドウへ移動します。

## 導入

ターミナルで1行実行します。

```sh
curl -fsSL https://raw.githubusercontent.com/Nameless-LLC/junban/main/install.sh | bash
```

tmux に junban が入り、Claude Code があれば連携も設定します。

<details>
<summary>tmux のプラグイン管理ツール（TPM）で入れる場合</summary>

`~/.tmux.conf` に追記して、prefix + I を押します。

```tmux
set -g @plugin 'Nameless-LLC/junban'
```

続けて Claude Code と連携します。

```sh
claude plugin marketplace add Nameless-LLC/junban && claude plugin install junban@junban
```

</details>

Codex CLI と Gemini CLI は `~/.tmux/plugins/junban/scripts/setup.sh codex`（または `gemini`）を実行します。詳しくは[Claude Code 以外のエージェント](#claude-code-以外のエージェント)を見てください。

tmux 3.2 以上と bash が必要です。python3 と fzf があれば、ウィンドウ名の自動設定・タイムライン・一覧の検索も使えます。

### うまく動かないとき

`~/.tmux/plugins/junban/scripts/doctor.sh` を実行してください（Claude Code なら `/junban:doctor`）。よくある問題なら直し方まで表示します。直らなければ、その出力を[バグ報告](https://github.com/Nameless-LLC/junban/issues/new?template=bug.yml)に貼ってください。ウィンドウの名前や依頼の内容は出力に含まれません。質問は [Discussions](https://github.com/Nameless-LLC/junban/discussions) へ。セキュリティの問題は公開せずに報告してください（[SECURITY.md](SECURITY.md)）。

## 覚えるキーは1つだけ

**Alt+a** です。ステータスバーの一番下の行には、よく使うキーが出ます。返事待ちがあると、その上の行に「Alt+a で移動」と出ます。

| キー | |
|---|---|
| **Alt+a** | 次に見るべきウィンドウへ移動。返事待ちが先、次に完了。それぞれ待った時間が長い順 |
| **Alt+f** | 全エージェントの一覧。待たせている順に並び、文字を打つと絞り込める。画面のプレビュー付き |
| **Alt+n** | 今のディレクトリで新しいエージェントを起動（ほかのエージェントが作業中なら、別の worktree で起動） |
| **Alt+,** | 設定。Alt+n で起動するもの・言語・ステータス行の数など。`~/.config/junban/settings.conf` に保存 |
| **Alt+/** | キーの一覧。今日のタイムラインと待ち時間の集計も出る |
| prefix T | 今日のタイムライン。ウィンドウごとに、作業中・返事待ち・完了の時間帯を1行で表示 |
| Alt+1…9 · Alt+[ ] · Alt+Tab · Alt+z · Alt+w | 番号のウィンドウへ · 前/次 · 直前 · 最大化 · 閉じる（確認あり） |

端末が Alt キーを使ってしまう場合は、prefix の後に `a` `f` `C` `g` `/` を押しても同じ操作ができます。

すべての設定項目はマニュアルにあります: [junban.namelessjp.com/manual](https://junban.namelessjp.com/manual/)

## 似たツールとの違い

タブにアイコンを出すプラグインは[多く](#先行事例)あり、待たせた順に移動するもの（gs/tmux-agent-status）や待ち時間を測るもの（muxa）もあります（[比較表](https://junban.namelessjp.com/#compare)）。junban は、これらを常駐プロセスなしの tmux プラグイン1つで使えるようにしました。次に押すキーの表示と、放置したウィンドウを一覧の下に移す表示は、ほかのツールでは見つかりませんでした。

**「作業中」のまま残りません。** 途中で Esc を押すと Claude Code は終了を知らせないため、フックだけで状態を見るツールでは「作業中」のまま残ります。junban は Claude Code のセッション記録（`~/.claude/sessions`）を見て、正しい表示に直します。プロセスの親子関係もたどって、そのウィンドウのエージェントかどうかを確かめます。

**ウィンドウ名は作業内容から自動で付きます。** 標準では依頼の1行目が名前になります。LLM を設定すると、直近の依頼をまとめた名前にします（ローカルの Ollama で小さいモデルを動かせば1秒以内）。「OK」「進めて」のような短い返事では変わらず、自分で付けた名前（`prefix ,`）も上書きしません。

**Alt+n で開いても固まって見えません。** エージェントが立ち上がるまで、画面ではスピナーが回り、タブには薄い ◌ が付きます。

**放置したウィンドウは下へ移ります。** 1日以上触っていないウィンドウには `z` が付き、Alt+f の一覧の下に移ります。放置したウィンドウが多くても、返事を待っているものを見失いません。

**待ち時間を測ります。** ステータスバーに、今日エージェントを待たせた合計と、返事までの時間の中央値が出ます（`今日の待ち時間 42分 · 返答の中央値 3分10秒`）。Alt+/ では、直近7日の棒グラフ、先週との比較、自己ベストの日、目標以内に返せた日の連続記録、今日いちばん待たせたウィンドウが見られます。`scripts/stats.sh 30` で30日前までさかのぼれます。待ち時間は ✋ や ✓ が付いてから、返事をするかウィンドウを開くまでです。見ている最中に終わった分は数えず、1回あたり最大1時間で打ち切ります。記録は自分の PC の TSV ファイルにだけ残ります。

**1日のタイムラインが見られます。** prefix T（と Alt+/ の上部）で、ウィンドウごとに1行、黄色の █ が作業中、赤の ▓ が返事待ち、緑の ▒ が完了・未確認として並びます。下には、稼働していた時間帯、作業時間、待たせた時間、同時に動いたウィンドウの最大数が出ます。`scripts/timeline.sh 1` で前日を表示します。Alt キーで開きたい場合は `@junban-key-timeline M-y` を設定します（Claude Code では Alt+t が思考の切り替えなので、標準では割り当てていません）。

**マスコットがいます。** ステータスバーに、状況に合わせて表情が変わるマスコットが出ます。返事待ちがあれば `[▮ ▮]!`、終わったら `[◠ ◠]`、作業中は `[▮▮ ]`、何もないときは `[▬ ▬]z` です。`set -g @junban-mascot off` で消せます。

**英語・日本語・タイ語に対応しています。** OS の言語設定に合わせて切り替わります。日本語やタイ語のウィンドウ名も表示幅で切り詰めるので、タブの幅が崩れません。

**何を求めているかを1行で出します。** エージェントが質問・許可を求めたときや作業を終えたときに、その内容を1行でステータスバーと Alt+f の一覧に出します（例:「テスト成功、PR #12 を作成」）。LLM を設定していれば LLM がまとめ、なければ返答の最初の1行を使います。スマホ通知にも同じ1行が出ます。止めるときは `set -g @junban-recap off` です。作業を終えたときは、変わったもの（`3ファイル +41 −88 · 2コミット · PR #12`）も出ます。Alt+f の一覧では、プレビューの先頭に変更したファイルの一覧が出て、Ctrl+o で PR を開けます。

**完了の知らせはまとめて受け取れます。** `set -g @junban-done-batch 30` にすると、完了（✓）は毎時0分と30分にまとめて1通で届き、それまではステータスバーに件数だけが出ます。返事待ち（✋）はすぐに届きます。

**tmux と bash で動きます。** 一部の機能は python3 を使います。常駐プロセスはありません。テストは Linux と macOS の CI で実行しています。

## 設定

すべて任意です。`~/.tmux.conf` の、プラグインを読み込む行より**前に**書いてください。設定項目の一覧は [README.md](README.md#configuration) にあります。日本語の表示に固定したい場合は、次の1行を書きます。

```tmux
set -g @junban-lang ja
```

ウィンドウ名をローカルの LLM に付けさせる例:

```tmux
set -g @junban-rename llm
set -g @junban-namer-url http://localhost:11434
set -g @junban-namer-model qwen3:8b
```

## Claude Code 以外のエージェント

| エージェント | 導入 | できること |
|---|---|---|
| Claude Code | プラグイン（上の1行で入ります） | ✋ ✓ ●、1行要約、ウィンドウの名前。Esc で止めても表示が自動で直る |
| Codex CLI | `scripts/setup.sh codex` のあと、Codex で `/hooks` を開いて一度だけ承認する | ✋ ✓ ●、実行したいコマンドを1行要約に出す、ウィンドウの名前。Esc で表示が消える |
| Gemini CLI | `scripts/setup.sh gemini` | ✋ ✓ ●、実行したいコマンドを1行要約に出す、ウィンドウの名前 |

```sh
~/.tmux/plugins/junban/scripts/setup.sh codex    # ~/.codex/hooks.json に書く
~/.tmux/plugins/junban/scripts/setup.sh gemini   # ~/.gemini/settings.json に書く
```

どちらも既存のフックは残し、junban の分だけを入れ替えます（何度実行しても大丈夫です）。元のファイルは `.bak` に残ります。`--print` を付けると、書き込まずに内容だけ表示します。`set -g @junban-agent-cmd codex` にすると Alt+n で Codex が起動します。

ほかのツールも、コマンドを実行できればつなげられます。junban が見ているのは tmux のウィンドウオプション1つだけです。

```sh
~/.tmux/plugins/junban/scripts/state.sh running   # waiting | done | idle | clear
```

## 先行事例

機能が重なるプラグインです。用途によってはこちらの方が合うかもしれません。
[tmux-agent-indicator](https://github.com/accessd/tmux-agent-indicator) ·
[tmux-agent-status (RatulMaharaj)](https://github.com/RatulMaharaj/tmux-agent-status) ·
[tmux-agent-status (rorhcdream)](https://github.com/rorhcdream/tmux-agent-status)（セッション記録がフックより確かだと示したのはこのプロジェクトです） ·
[tmux-handlr](https://github.com/CRThaze/tmux-handlr) ·
[claude-code-tmux-status](https://github.com/XavierYounan/claude-code-tmux-status) ·
[tmux-window-notifier](https://github.com/mrf/tmux-window-notifier)

MIT ライセンス。開発元の [Nameless](https://namelessjp.com) で毎日使っています。
