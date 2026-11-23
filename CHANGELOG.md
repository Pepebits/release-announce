# Changelog

All notable changes to this workflow are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Callers on `@v1`
get every 1.x release as soon as it is tagged.

## [Unreleased]

## [1.5.1] - 2026-11-23

### Fixed

- A `## ` or `### ` line inside fenced code no longer ends the version's notes
  or opens a section: everything after it was lost or misplaced. Code is kept
  exactly as written, tabs, `[x]: …` lines and `<!-- -->` included.
- A button with a null or empty field, a url that is not `http(s)://` or
  `tg://`, a `copy_text` over 256 characters once its placeholders are filled,
  or a `buttons` input that is not one JSON array is refused before anything
  is built, instead of failing the build or every send.
- An upgrade note is one paragraph again, as in 1.4: what follows its blank
  line is no longer folded away with it.
- Quotes count towards Telegram's 16 levels as lists do.
- `#### Support for C#` keeps its `#`; empty headings, items and table cells
  never reach Telegram as empty text, and short table rows are filled out.
- A cut falls at a line or a word when no item ends near the limit, instead
  of dropping a whole long table or item.
- `[core]: fixes` is no longer taken for a link definition and dropped.
- A lightweight tag is announced without notes, as the warning says, instead
  of with its commit's message.
- After a refused message, a fallback that gets no answer is not followed by
  another, so a message that may have arrived is not sent twice. If the plain
  text is refused too, it is sent once more without its buttons.

### Changed

- `---`, `***` and `___` rules are dividers; one at the end of a section is
  dropped. Section titles read inline Markdown. A list indented under its
  title folds like one at the margin. Button texts take placeholders.

## [1.5.0] - 2026-11-23

### Added

- Sections keep their structure: prose before or instead of a list, several
  paragraphs and fenced code inside a list item, `####` sub-headings, `>`
  quotes, Markdown tables and `- [x]` task checkboxes. An upgrade note of
  several paragraphs folds whole, and a title followed by a blank line still
  folds its list.
- If Telegram refuses the message, it is sent again without the banner, then
  as plain text with the buttons, instead of being lost.
- `message_thread_id`, `disable_notification` and `protect_content` inputs,
  for a forum topic, a silent post and a post that cannot be forwarded.
- `fold` input: `auto` leaves a list of three items or fewer open, `never`
  leaves every section open.
- Buttons can copy text (`copy_text`), take a `style` (`primary`, `success`,
  `danger`), and go in rows: they fill rows of up to 8, and a nested array is
  a row of its own.

### Fixed

- A long changelog is now cut under Telegram's limit of 500 blocks, which
  counts every list item, and not only under its character limit: a few
  hundred short items made Telegram refuse the whole announcement. The cut
  falls at a whole item instead of mid-word, and the message ends with a link
  to the full notes.
- Lists stop nesting at the fifth level, keeping the message within
  Telegram's 16 levels; deeper items sit beside the fifth.
- Numbered items no longer send `label`, a field Telegram only returns.
- Link definitions at the foot of a changelog (`[1.0.0]: https://…`) no
  longer show up in the notes of its oldest version.

### Changed

- Checked against Bot API 10.5. Folded sections are `details` blocks, which
  its change to expandable quotations does not touch, so nothing changes for
  callers. The message needs Bot API 10.3 or later.

## [1.4.0] - 2026-10-30

### Added

- Inline Markdown in the notes becomes real formatting, nested as written:
  `**bold**` or `__bold__`, `*italic*` or `_italic_`, `~~strikethrough~~`,
  `<https://…>` autolinks and bare `https://` URLs. Code stays beside bold or
  italic rather than inside, as Telegram does not allow it there.
- Indented list items nest under their parent, numbered items (`1.` or `1)`)
  keep their number, and `*` and `+` count as bullets.

### Fixed

- Bold and italic no longer reach Telegram with their marks showing, as in
  `**ki for macOS and Windows**:`. `2 * 3`, `*.js`, `snake_case` and `\*`
  escapes still stay literal.

## [1.3.0] - 2026-10-19

### Added

- `tag_prefix` announces each package of a monorepo from its own tags, such as
  `my-lib-php-v1.2.3`: `{version}` and `{minor}` come from what follows the
  prefix, `{tag}` stays the whole tag. A tag without the prefix is rejected.
  Empty keeps plain `vX.Y.Z` or `X.Y.Z` tags as before.

## [1.2.0] - 2026-10-18

### Added

- The `tag` input accepts `X.Y.Z` as well as `vX.Y.Z`, so repositories that tag
  without the `v` can announce too. `{version}` is the same either way;
  prereleases and prefixed tags are still rejected.

## [1.1.0] - 2026-10-18

### Added

- `banner_url` takes the banner from a fixed https URL, such as a generated
  social card, instead of the repository's own image. `{repo}`, `{owner}`,
  `{version}`, `{minor}` and `{tag}` are replaced, so one organization variable
  covers every repository. Empty keeps `banner_path` as before.

## [1.0.0] - 2026-10-02

### Added

- Announces a release as a Telegram rich message, with the notes taken from an
  annotated tag or from a Keep a Changelog file.
- The install command, buttons, banner and footer are inputs, with
  `{version}`, `{minor}`, `{tag}` and `{repo_url}` placeholders.

[Unreleased]: https://github.com/Pepebits/release-announce/compare/v1.5.1...HEAD
[1.5.1]: https://github.com/Pepebits/release-announce/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/Pepebits/release-announce/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/Pepebits/release-announce/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/Pepebits/release-announce/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Pepebits/release-announce/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/Pepebits/release-announce/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Pepebits/release-announce/releases/tag/v1.0.0
