# release-announce

A reusable GitHub Actions workflow that announces a release on Telegram as a
[rich message](https://core.telegram.org/bots/api#rich-messages). Call it from
your release workflow, tell it where the notes come from and what to install,
and it posts one tidy message per release.

## The message

Top to bottom:

1. The banner image: `banner_url` if set, otherwise the repository's own
   banner when it has one at the tag.
2. A title, "🚀 *project* **1.2.3**", and under it either the tag's subject
   line in italics ("✨ …") or, for changelog notes, the release date.
3. The notes. Each titled list ("Fixes", or `### Fixed` in a changelog) is
   folded into a collapsed section with an emoji (✨ added or features, 🔄
   changed, ⚠️ deprecated, upgrade or breaking notes, 🗑️ removed, 🐛 fixed,
   🔒 security, 📦 dependencies, 📝 anything else), so a long list does not bury
   the rest. An "Upgrade note:" or "Breaking note:" paragraph is folded the
   same way under a ⚠️ title. Wrapped lines are joined back together.
4. A divider, the install command in a code block (Telegram gives it a copy
   button), buttons, and an optional footer line.

Notes are sent as structured blocks, never as Markdown or HTML, so nothing in
a changelog can break the message. The only inline formatting is `code` spans
and `[text](https://…)` links, which become real code and link pieces; all
other punctuation stays literal.

## Using it

Run it after the release is installable, and `needs:` whatever publishes it.

### A Docker image, notes from the annotated tag

```yaml
# .github/workflows/publish.yml, after the job that pushes the image
  announce:
    needs: publish
    if: startsWith(github.ref, 'refs/tags/v')
    permissions:
      contents: read
    uses: Pepebits/release-announce/.github/workflows/announce.yml@v1
    with:
      tag: ${{ github.ref_name }}
      notes_source: tag
      install_title: 🐳 Docker image
      install_command: docker pull ghcr.io/pepebits/share-stories:{version}
      buttons: >-
        [{"text": "📝 Notes", "url": "{repo_url}/releases/tag/{tag}"},
         {"text": "📦 Package", "url": "{repo_url}/pkgs/container/share-stories"}]
      footer: 🏷️ Also tagged {minor} and latest
    secrets: inherit
```

The tag has to be annotated for there to be notes: `git tag -a v1.2.3`, with a
subject line, a blank line, then paragraphs and `- ` lists. A lightweight tag
is announced without notes.

### An npm package, notes from CHANGELOG.md

A tag does not mean an npm version is installable when publishing waits for a
human to approve it, so run the announcement by hand afterwards (or in a job
that checks `npm view`):

```yaml
# .github/workflows/announce.yml
on:
  workflow_dispatch:
    inputs:
      tag:
        description: Existing release tag, e.g. v1.2.3
        required: true
      chat:
        type: choice
        options: [test, announcements]
        default: test
      dry_run:
        type: boolean
        default: true

jobs:
  announce:
    permissions:
      contents: read
    uses: Pepebits/release-announce/.github/workflows/announce.yml@v1
    with:
      tag: ${{ inputs.tag }}
      chat: ${{ inputs.chat }}
      dry_run: ${{ inputs.dry_run }}
      notes_source: changelog
      project_name: my-package
      install_title: 📦 npm
      install_command: npm i @scope/my-package@{version}
      buttons: >-
        [{"text": "📝 Changelog", "url": "{repo_url}/blob/{tag}/CHANGELOG.md"},
         {"text": "📦 npm", "url": "https://www.npmjs.com/package/@scope/my-package/v/{version}"}]
    secrets: inherit
```

The changelog is read at the tag. The workflow takes the section headed
`## [1.2.3]` (optionally followed by ` — date` or ` - date`) up to the next
`## `, in [Keep a Changelog](https://keepachangelog.com/) form. If there is
none it warns and announces without notes.

### An external banner

For repositories without a banner of their own, point `banner_url` at an
image service, such as a generated social card:

```yaml
    with:
      tag: ${{ github.ref_name }}
      banner_url: https://opensoutheners.com/gh_card/{repo}
```

`{repo}` becomes the repository's name (`laravel-apiable` in
`open-southeners/laravel-apiable`), so the same value fits every repository.
To set it once, keep it as an organization (or repository) variable and pass
it on; an empty or missing variable falls back to `banner_path`:

```yaml
      banner_url: ${{ vars.ANNOUNCE_BANNER_URL }}
```

Telegram downloads the image itself when the message is sent, so the URL must
be public and answer with an image (`image/png`, `image/jpeg`…), and it keeps
its own copy: a card that changes later does not change old posts. A URL
Telegram cannot fetch fails the send, which, like any send failure, is a
warning and not a failed release.

### Inputs

| Input | Default | |
|---|---|---|
| `tag` | required | The release tag, `vX.Y.Z` or `X.Y.Z`. `{version}` is the tag without a leading `v`. |
| `project_name` | the repository name | Shown in the title. |
| `notes_source` | `tag` | `tag` (the annotated tag's message) or `changelog`. |
| `changelog_path` | `CHANGELOG.md` | Only for `changelog`. |
| `install_title` | `📦 Install` | Heading above the command. |
| `install_command` | empty | `{version}` and `{tag}` are replaced. Empty omits the install section. |
| `install_language` | `bash` | Highlighting for the command. |
| `buttons` | a "📝 Notes" button to the GitHub release | JSON array of `{text, url}`. In the url, `{version}`, `{minor}`, `{tag}` and `{repo_url}` are replaced. `[]` for none. |
| `banner_path` | `docs/banner.png` | Used only if it exists at the tag and `banner_url` is empty; linked at the tag via raw.githubusercontent.com. |
| `banner_url` | empty | An image at a fixed `https://` URL, used instead of `banner_path`. `{repo}`, `{owner}`, `{version}`, `{minor}` and `{tag}` are replaced. See [An external banner](#an-external-banner). |
| `footer` | empty | `{version}`, `{minor}` and `{tag}` are replaced. |
| `chat` | `announcements` | `announcements` or `test`. |
| `dry_run` | `false` | Print the message, send nothing. |

## Secrets

| Secret | Value |
|---|---|
| `TELEGRAM_BOT_TOKEN` | The token @BotFather gives you |
| `TELEGRAM_CHAT_ID` | `@channelname` for a public channel, otherwise the numeric id (`-100…` for channels and supergroups) |
| `TELEGRAM_TEST_CHAT_ID` | Optional: a chat for `chat: test` |

Create them once as **organization secrets** shared with the repositories that
announce, or as repository secrets; pass them on with `secrets: inherit`, or
name them one by one under `secrets:`. A repository secret wins over an
organization secret of the same name. Without a token and a chat id nothing is
sent and the release is unaffected, so forks stay quiet.

To get them, create a bot with [@BotFather](https://t.me/BotFather)
(`/newbot`) and add it to your channel as an administrator allowed to post
messages (or to a group as a member). To find a numeric chat id, post something
in the chat and open `https://api.telegram.org/bot<token>/getUpdates` in a
browser on your own machine; the id is under `chat.id`.

The organization must allow the workflow to run: with a restricted Actions
policy, **Settings → Actions → General** has to permit
`Pepebits/release-announce@*` (or all actions and reusable workflows).

## Trying it out

Give the caller a `workflow_dispatch` trigger as above and run it with
`dry_run` on: the job log prints the exact payload and sends nothing. Turn
`dry_run` off with `chat: test` to see it rendered in a test chat first.

The message is built before it is sent, so a failure there is a red run. Sending
is deliberately forgiving: the release is already public by then, so a Telegram
outage or a revoked bot is a warning, not a failed release. The bot token goes
to curl over stdin, so it never shows up in a process list or an error message.

## Versioning

Pin the major version, `@v1`. It moves with every compatible release; a patch
or minor release never renames an input. Pin a full tag (`@v1.0.0`) or a
commit sha to freeze it. The workflow is self-contained (the jq program that
builds the message is inlined in it), so a pin covers everything that runs.

## Development

`test/run.sh` extracts the jq program from `announce.yml`, builds the message
from the fixtures in `test/fixtures/` (the notes of share-stories v2.0.0 and
search-builder's changelog) and asserts on the JSON; it needs only `jq` 1.7. CI runs it, and lints the workflows with
actionlint.
