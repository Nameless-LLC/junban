# Copy review

Every page people read goes through this before its wording changes ship:
the landing page (`site/template.html`), the manual (`site/manual.html`),
`README.md` and `README.ja.md`.

## The rule

- **At least five review passes per page and language.** English and Japanese
  are reviewed separately.
- **Each pass is a fresh reviewer** (a new agent with no memory of earlier
  passes), briefed with `brief-en.md` or `brief-ja.md`. A reviewer that saw the
  last round tends to agree with it.
- **Fix every MUST before the next pass.** Take a NICE when it is clearly
  better; skip one only with a reason (for example, it would add a pattern the
  brief itself forbids).
- **Done = five passes or more, and the last one finds no MUST.** If pass five
  still finds one, keep going.
- **Facts come from the code and README**, never from the reviewer: check each
  "this is wrong" against the scripts before changing a claim.
- A small wording change (one sentence) still gets the full round for the page
  it is on.

## Running a pass

Give the reviewer the brief, with `{PAGE}` replaced by the file and `{SCOPE}`
by what to read on it (for example `lang="en" elements` or `the whole file`).
Ask for a numbered list (location, exact current text, problem, replacement,
MUST or NICE) and a last line of `Verdict: ship as is` / `Verdict: needs
another pass` (`判定: このまま公開してよい` / `判定: もう1回必要`).
