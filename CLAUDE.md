# junban

- Wording on any page people read (site/template.html, site/manual.html, README.md, README.ja.md) ships only after the copy review in `tools/copy-review/README.md`: five or more passes per page and language by fresh reviewers, ending in a pass with no MUST.
- Run `~/.local/bin/shellcheck` and `bash tests/run.sh` before pushing; CI lints first.
- A version bump in `.claude-plugin/plugin.json` (with a CHANGELOG section) is a release that reaches every install within a day.
- After editing site/, run `python3 tools/build-site.py` and commit docs/ with it.
