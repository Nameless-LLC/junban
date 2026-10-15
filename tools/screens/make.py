#!/usr/bin/env python3
"""Regenerate the fake agent screens used by demo.sh / hero.sh."""
import os
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
E = "\033["
dim, b, r, o, g, c, gr = E + "2m", E + "1m", E + "0m", E + "38;5;173m", E + "32m", E + "36m", E + "90m"


def dw(s):
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in s)


def write(path, lines):
    with open(os.path.join(HERE, path), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


rule = gr + "─" * 148 + r


def box(title, body, opts):
    W = 86

    def ln(t, raw):
        return f"{c}│{r} {t}{' ' * (W - 1 - dw(raw))}{c}│{r}"
    out = [f"{c}╭{'─' * W}╮{r}", ln(b + title + r, title), ln("", "")]
    out += [ln(t, t) for t in body]
    out.append(ln("", ""))
    for i, t in enumerate(opts):
        pre = f"❯ {i + 1}. " if i == 0 else f"  {i + 1}. "
        out.append(ln((o if i == 0 else "") + pre + t + r, pre + t))
    return out + [f"{c}╰{'─' * W}╯{r}"]


def tool(name, arg, res):
    return [f"  {g}{name}{r}({dim}{arg}{r})", f"  {gr}⎿  {res}{r}"]


def dot(t):
    return f"{o}●{r} {t}"


def ask(t):
    return f"{o}❯{r} {t}"


footer = ["", rule, f"{o}❯{r} ", rule]
PSQL = box("Bash command",
           ["  psql $DEV_DATABASE_URL -f migrations/0042_plan_tier.sql",
            "  Apply the plan_tier migration to the dev database"],
           ["Yes", "Yes, and don't ask again for psql commands",
            "No, and tell Claude what to do differently (esc)"])

L = {
    "en": dict(
        names=["billing refactor", "fix flaky CI", "pricing page copy", "db migration", "k8s 1.31 upgrade", "docs: Thai i18n"],
        work=[ask("Split BillingService into invoice and payment modules, keep the public API"), "",
              dot("I'll start by mapping every caller of BillingService."),
              *tool("Search", '"BillingService\\.", path: src/', "Found 23 references in 9 files"), "",
              dot(f"Moving invoice logic into {b}src/billing/invoice.ts{r}"),
              *tool("Write", "src/billing/invoice.ts", "Wrote 184 lines"),
              *tool("Update", "src/billing/service.ts", "Removed 141 lines, added 12"), "",
              dot("Running the billing tests before touching payments."),
              *tool("Bash", "pnpm test src/billing", "Running…"), "",
              f"{o}✻ Refactoring…{r} {gr}(2m 14s · ↓ 6.1k tokens · esc to interrupt){r}", *footer],
        ci=[ask("The e2e suite fails about 1 in 5 runs on CI. Find out why"), "",
            dot("Pulled the last 40 CI runs. All 8 failures are in checkout.spec.ts, always at the same step."),
            *tool("Bash", "gh run list --workflow e2e --limit 40", "8 failed / 32 passed"), "",
            dot("The test clicks Pay before the Stripe iframe finishes loading. Two ways to fix it:"), "",
            *box("Which fix do you want?", [], ["Wait for the iframe's ready event (precise, 6 lines)",
                                                "Retry the click up to 3 times (quick, hides real slowness)",
                                                "Something else"])],
        price=[ask("Tighten the pricing page copy. Shorter, no jargon"), "",
               dot("Rewrote the three plan cards and the FAQ. Hero went from 31 to 12 words."),
               *tool("Update", "app/pricing/page.tsx", "Updated 3 sections"),
               *tool("Bash", "pnpm lint && pnpm test pricing", "All checks passed"), "",
               dot(f"{b}Done.{r} Diff is ready for review: 3 files, +41 −88."), *footer],
        db=[ask("Add a nullable plan_tier column to accounts and backfill it from subscriptions"), "",
            dot(f"Migration written: {b}migrations/0042_plan_tier.sql{r}. It needs to run against the dev database."),
            "", *PSQL],
        k8s=[ask("Upgrade the staging cluster to 1.31 and fix whatever breaks"), "",
             dot("Control plane upgraded. Draining nodes one at a time."),
             *tool("Bash", "kubectl drain node-2 --ignore-daemonsets", "node/node-2 drained"),
             *tool("Bash", "kubectl get pods -A | grep -v Running", "2 pods pending: PodDisruptionBudget"), "",
             f"{o}✻ Upgrading…{r} {gr}(6m 02s · ↓ 3.4k tokens · esc to interrupt){r}", *footer],
        docs=footer),
    "ja": dict(
        names=["請求モジュール分割", "CI の不安定テスト", "料金ページの文言", "DB マイグレーション", "k8s 1.31 更新", "タイ語ドキュメント"],
        work=[ask("BillingService を請求と決済のモジュールに分けて。公開 API は変えないで"), "",
              dot("まず BillingService の呼び出し元を洗い出します。"),
              *tool("Search", '"BillingService\\.", path: src/', "9 ファイルで 23 件"), "",
              dot(f"請求のロジックを {b}src/billing/invoice.ts{r} に移します"),
              *tool("Write", "src/billing/invoice.ts", "184 行"),
              *tool("Update", "src/billing/service.ts", "141 行削除、12 行追加"), "",
              dot("決済に触る前に請求のテストを流します。"),
              *tool("Bash", "pnpm test src/billing", "実行中…"), "",
              f"{o}✻ Refactoring…{r} {gr}(2m 14s · ↓ 6.1k tokens · esc to interrupt){r}", *footer],
        ci=[ask("CI の e2e が5回に1回くらい落ちる。原因を調べて"), "",
            dot("直近40回分を取得しました。失敗8回はすべて checkout.spec.ts の同じ手順です。"),
            *tool("Bash", "gh run list --workflow e2e --limit 40", "失敗 8 / 成功 32"), "",
            dot("Stripe の iframe が読み込み終わる前に「支払う」を押しています。直し方は2つ:"), "",
            *box("どちらで直しますか？", [], ["iframe の ready を待つ（正確・6行）",
                                             "クリックを3回まで再試行（早いが遅さを隠す）", "その他"])],
        price=[ask("料金ページの文言を締めて。短く、専門用語なしで"), "",
               dot("3つのプランカードと FAQ を書き直しました。見出しは31語→12語。"),
               *tool("Update", "app/pricing/page.tsx", "3 か所を更新"),
               *tool("Bash", "pnpm lint && pnpm test pricing", "すべて成功"), "",
               dot(f"{b}完了。{r}差分はレビューできます: 3 ファイル、+41 −88"), *footer],
        db=[ask("accounts に plan_tier 列を追加して、subscriptions から埋めて"), "",
            dot(f"マイグレーションを書きました: {b}migrations/0042_plan_tier.sql{r}。開発 DB で実行が必要です。"),
            "", *PSQL],
        k8s=[ask("ステージングを 1.31 に上げて、壊れたところを直して"), "",
             dot("コントロールプレーンは更新済み。ノードを1台ずつ退避しています。"),
             *tool("Bash", "kubectl drain node-2 --ignore-daemonsets", "node/node-2 drained"),
             *tool("Bash", "kubectl get pods -A | grep -v Running", "2 pods pending: PodDisruptionBudget"), "",
             f"{o}✻ Upgrading…{r} {gr}(6m 02s · ↓ 3.4k tokens · esc to interrupt){r}", *footer],
        docs=footer),
}
STATES = ["running", "waiting", "done", "waiting", "running", "-"]
FILES = ["work", "ci", "price", "db", "k8s", "docs"]
for lang, d in L.items():
    os.makedirs(os.path.join(HERE, lang), exist_ok=True)
    write(f"{lang}/windows.tsv", [f"{n}\t{s}\t{f}.txt" for n, s, f in zip(d["names"], STATES, FILES)])
    for f in FILES:
        write(f"{lang}/{f}.txt", d[f])
