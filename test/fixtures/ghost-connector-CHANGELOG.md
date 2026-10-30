# Changelog

## [0.1.5] — 2026-10-25

### Added

- Ghost authors: each panel user has default Ghost authors (one or more, with a primary), set in My account or by an admin in Settings → Users. New posts are credited to them, and the *New post* form lets you change them. A draft's authors show on its page and can be changed there; applying a plan never touches them. The staff list is read from Ghost.
- Results measure whether the panel's changes worked: for each post it changed, the clicks in up to 4 weeks before its latest change against the same weeks after, and against how the rest of the blog moved over those weeks. A summary on *Results* and a card on each post's page; changes too recent (or with too few clicks to say) are flagged as such.
- Results export: *Export CSV* downloads the list as shown (same filter and order), and each post's page downloads its weekly trend and top queries. Built from the saved data, so it doesn't query Google or Bing; text that a spreadsheet would run as a formula is neutralised.

