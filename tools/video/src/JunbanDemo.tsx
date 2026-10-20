// junban demo: a real tmux session, recorded scene by scene (record.sh), with
// small captions and a keycap for each key press. The one emphasis is a zoom on
// the status bar while agents are waiting; everything else stays quiet.
import React from "react";
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig, Easing } from "remotion";
// Both languages film the same scenes with the same timings (record.sh).
import timeline from "../build/en/timeline.json";

const FPS = 30;
const END_SEC = 2.6;
const BG = "#0e1013";
const MUTED = "#8b9099";
const TEXT = "#e8e6e3";
const RED = "#ff6b5e";

type Lang = "en" | "ja";
const CAPTIONS: Record<Lang, string[]> = {
  en: ["Six agents at work.", "One needs your approval.", "Then another.",
       "Alt+a goes to whoever waited longest.", "Approve it. Back to work.", "Alt+a again. The next one.",
       "Nobody is waiting. One finished.", "Alt+f lists every agent.", "", "", "", "Straight there."],
  ja: ["エージェントが並行して作業中。", "エージェントがあなたの許可を待っています。", "もう1つも返事待ちに。",
       "Alt+a で、いちばん長く待たせているウィンドウへ。", "許可すると、作業に戻ります。", "もう一度 Alt+a。次のウィンドウへ。",
       "返事待ちはなし。1つが作業を完了。", "Alt+f で全エージェントを一覧に。", "", "", "", "そのまま移動。"],
};
// scenes where the status bar is the story
const ZOOM = new Set([1, 2]);

const starts = (() => {
  let t = 0;
  return timeline.map((s) => { const a = t; t += Math.round(s.sec * FPS); return a; });
})();
export const totalFrames = () =>
  starts[starts.length - 1] + Math.round(timeline[timeline.length - 1].sec * FPS) + Math.round(END_SEC * FPS);

const Keycap: React.FC<{ label: string; at: number }> = ({ label, at }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (!label || f < at) return null;
  const s = spring({ frame: f - at, fps, config: { damping: 18, stiffness: 220 } });
  const out = interpolate(f - at, [fps * 1.1, fps * 1.5], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const keys = label.split("+");
  return (
    <div style={{ position: "absolute", right: 64, bottom: 56, zoom: 1, display: "flex", gap: 10, alignItems: "center",
      opacity: s * out, transform: `translateY(${(1 - s) * 12}px)` }}>
      {keys.map((k, i) => (
        <React.Fragment key={i}>
          {i > 0 && <span style={{ color: MUTED, font: "500 22px 'JetBrains Mono'" }}>+</span>}
          <span style={{ font: "600 24px 'JetBrains Mono'", color: TEXT, padding: "10px 16px", borderRadius: 10,
            background: "#1b1e24", border: "1px solid #2e333b", borderBottom: "4px solid #2e333b" }}>{k}</span>
        </React.Fragment>
      ))}
    </div>
  );
};

export const JunbanDemo: React.FC<{ lang: Lang; square?: boolean; mobile?: boolean }> = ({ lang, square, mobile }) => {
  const f = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const endAt = totalFrames() - Math.round(END_SEC * FPS);
  let idx = 0;
  for (let i = 0; i < starts.length; i++) if (f >= starts[i]) idx = i;

  // terminal box: 1292x694 svg, fitted with margins
  // mobile: show only the left 64 columns, big enough to read on a phone
  const termW = mobile ? 1284 * (width / (64 * 8.4 + 32)) : square ? width - 80 : width * 0.86;
  const scale = termW / 1284;
  const termH = 674 * scale;
  const left = mobile ? 0 : (width - termW) / 2;
  const top = mobile ? 40 : square ? (height - termH) / 2 - 20 : (height - termH) / 2 - 30;

  // zoom toward the status bar while agents are waiting (scenes 1-2), eased in and out
  const zStart = starts[1], zEnd = starts[3];
  const zoom = mobile ? 1 : interpolate(f, [zStart, zStart + 18, zEnd - 12, zEnd], [1, 1.55, 1.55, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.inOut(Easing.cubic) });

  const endFade = interpolate(f, [endAt, endAt + 14], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const cap = CAPTIONS[lang][idx] || CAPTIONS[lang][[8, 9, 10].includes(idx) ? 7 : idx];
  const capIn = interpolate(f - starts[idx], [0, 8], [0, 1], { extrapolateRight: "clamp" });
  const capFont = lang === "ja" ? "'Noto Sans CJK JP'" : "'Inter', 'Noto Sans', sans-serif";

  return (
    <AbsoluteFill style={{ background: BG }}>
      <div style={{ position: "absolute", left, top, width: termW, height: termH, opacity: endFade,
        transform: `scale(${zoom})`, transformOrigin: "8% 6%",
        filter: "drop-shadow(0 40px 60px rgba(0,0,0,.55))" }}>
        {timeline.map((s, i) => {
          if (Math.abs(i - idx) > 1) return null;
          // short cross-dissolve, none for the typing frames
          const fade = [9, 10, 11].includes(i) ? 0 : 5;
          const o = i === idx ? (fade ? interpolate(f - starts[i], [0, fade], [0, 1], { extrapolateRight: "clamp" }) : 1)
            : i === idx - 1 ? 1 : 0;
          return <Img key={i} src={staticFile(`${lang}/${s.file}`)}
            style={{ position: "absolute", inset: 0, width: "100%", height: "100%", opacity: o,
              zIndex: i === idx ? 2 : 1 }} />;
        })}
      </div>

      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 220, opacity: endFade,
        background: `linear-gradient(to bottom, rgba(14,16,19,0), ${BG} 62%)` }} />
      {f < endAt && cap ? (
        <div style={{ position: "absolute", left: mobile ? 48 : left, right: mobile ? 48 : undefined, bottom: mobile ? 150 : square ? 70 : 64, opacity: capIn * endFade,
          font: `400 ${mobile ? 44 : 30}px ${capFont}`, color: MUTED, letterSpacing: lang === "ja" ? 0 : "-0.01em" }}>
          {ZOOM.has(idx) ? <span style={{ color: RED, marginRight: 12 }}>●</span> : null}{cap}
        </div>
      ) : null}

      {f < endAt && <Keycap label={timeline[idx].key} at={starts[idx]} />}

      {f >= endAt && (() => {
        const t = f - endAt;
        const o = interpolate(t, [8, 22], [0, 1], { extrapolateRight: "clamp" });
        return (
          <div style={{ position: "absolute", left: mobile ? 48 : left, top: height / 2 - 40, opacity: o }}>
            <div style={{ font: "600 44px 'JetBrains Mono'", color: TEXT, letterSpacing: "-0.02em" }}>
              junban <span style={{ color: MUTED, fontWeight: 400, fontSize: 30 }}>順番</span>
            </div>
            <div style={{ font: "400 24px 'JetBrains Mono'", color: MUTED, marginTop: 14 }}>
              {lang === "ja" ? "いま、誰の番？" : "Whose turn is it?"} · github.com/Nameless-LLC/junban
            </div>
          </div>
        );
      })()}
    </AbsoluteFill>
  );
};
