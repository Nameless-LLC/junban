import React from "react";
import { Composition } from "remotion";
import { JunbanDemo, totalFrames } from "./JunbanDemo";

export const Root: React.FC = () => (
  <>
    <Composition id="JunbanDemoEN" component={JunbanDemo} durationInFrames={totalFrames()} fps={30}
      width={1920} height={1080} defaultProps={{ lang: "en" as const }} />
    <Composition id="JunbanDemoJA" component={JunbanDemo} durationInFrames={totalFrames()} fps={30}
      width={1920} height={1080} defaultProps={{ lang: "ja" as const }} />
    <Composition id="JunbanDemoSquare" component={JunbanDemo} durationInFrames={totalFrames()} fps={30}
      width={1080} height={1080} defaultProps={{ lang: "en" as const, square: true }} />
    <Composition id="JunbanDemoSquareJA" component={JunbanDemo} durationInFrames={totalFrames()} fps={30}
      width={1080} height={1080} defaultProps={{ lang: "ja" as const, square: true }} />
    <Composition id="JunbanDemoMobileEN" component={JunbanDemo} durationInFrames={totalFrames()} fps={30}
      width={1080} height={1350} defaultProps={{ lang: "en" as const, mobile: true }} />
    <Composition id="JunbanDemoMobileJA" component={JunbanDemo} durationInFrames={totalFrames()} fps={30}
      width={1080} height={1350} defaultProps={{ lang: "ja" as const, mobile: true }} />
  </>
);
