#!/usr/bin/env bash
# Builds the message for each fixture exactly as announce.yml does and asserts
# on the JSON. Run from anywhere: test/run.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
if [ -n "${KEEP:-}" ]; then trap - EXIT; fi

# build <mode> <notes file> <name> <tag> [extra jq args…] > $out/<name>.json
build() {
  local mode="$1" notes="$2" name="$3" tag="$4"; shift 4
  jq -R -s -f "$root/.github/announce.jq" \
    --arg mode "$mode" --arg chat_id -100123 --arg tag "$tag" \
    --arg version "${tag#v}" --arg minor "$(cut -d. -f1,2 <<< "${tag#v}")" \
    --arg subject "$(cat "$out/subject.txt")" \
    --arg repo_url https://github.com/Pepebits/demo \
    --arg project_name demo "$@" < "$notes" > "$out/$name.json"
}

fails=0
# check <file> <description> <jq filter that must be true>
check() {
  if jq -e "$3" "$out/$1.json" > /dev/null; then
    echo "ok   $1: $2"
  else
    echo "FAIL $1: $2"; fails=$((fails + 1))
  fi
}

# Both modes: the shared safety properties.
common() {
  check "$1" 'fits in one rich message' '[tostring | length] | .[0] < 32768'
  check "$1" 'no markdown or html mode' '[.. | objects | keys[] | select(. == "parse_mode" or . == "markdown" or . == "html")] | length == 0'
  check "$1" 'entities are not guessed' '.rich_message.skip_entity_detection == true'
  check "$1" 'chat id passed through' '.chat_id == "-100123"'
  check "$1" 'title heading comes first, no banner' '.rich_message.blocks[0] | .type == "heading" and .size == 1'
}

# --- annotated tag, share-stories v2.0.0 -----------------------------------
# The fixture is %(contents): the subject, a blank line, then the body.
head -n 1 "$root/test/fixtures/tag-notes.txt" > "$out/subject.txt"
sed '1,2d' "$root/test/fixtures/tag-notes.txt" > "$out/tag-body.txt"
docker_buttons='[{"text":"📝 Notes","url":"{repo_url}/releases/tag/{tag}"},{"text":"📦 Package","url":"https://example.com/pkg/{version}"}]'
build tag "$out/tag-body.txt" tag v2.0.0 \
  --arg install_title "🐳 Docker image" \
  --arg install_command "docker pull ghcr.io/pepebits/demo:{version}" \
  --arg install_language bash --argjson buttons "$docker_buttons" \
  --arg banner_url "" --arg footer "🏷️ Also tagged {minor} and latest"

common tag
check tag 'title, spacer, subject' '.rich_message.blocks[0:3] == [
  {type:"heading", size:1, text:["🚀 demo ", {type:"bold", text:"2.0.0"}]},
  {type:"paragraph", text:"\u00a0"},
  {type:"paragraph", text:["✨ ", {type:"italic", text:"Telegram on teleproto, the maintained GramJS fork"}]}]'
check tag 'block order' '[.rich_message.blocks[].type] == ["heading","paragraph","paragraph","details","details","details","divider","paragraph","pre","buttons","footer"]'
check tag 'upgrade note is a folded warning' '.rich_message.blocks[3] | .summary.text == "⚠️ Upgrade note" and (.blocks[0].text | startswith("The Telegram client moves"))'
check tag 'Features folded with ✨' '.rich_message.blocks[4] | .summary.text == "✨ Features" and (.blocks[0].items | length == 2)'
check tag 'Fixes folded with 🐛 and wrapped lines joined' '.rich_message.blocks[5] | .summary.text == "🐛 Fixes" and (.blocks[0].items | length == 3) and (.blocks[0].items[0].blocks[0].text | startswith("A revoked or expired Telegram session stops the bridge at once") and (contains("\n") | not))'
check tag 'install command has {version} replaced' '.rich_message.blocks[8] == {type:"pre", language:"bash", text:"docker pull ghcr.io/pepebits/demo:2.0.0"}'
check tag 'install title is bold' '.rich_message.blocks[7].text == {type:"bold", text:"🐳 Docker image"}'
check tag 'buttons substituted' '.rich_message.blocks[9] | .align == "center" and .buttons == [
  {text:"📝 Notes", url:"https://github.com/Pepebits/demo/releases/tag/v2.0.0"},
  {text:"📦 Package", url:"https://example.com/pkg/2.0.0"}]'
check tag 'footer has {minor}' '.rich_message.blocks[10] == {type:"footer", text:"🏷️ Also tagged 2.0 and latest"}'
check tag 'no placeholder left behind' '[tostring | test("\\{(version|minor|tag|repo_url)\\}")] | .[0] | not'

# --- banner, no install, no footer, no buttons ------------------------------
build tag "$out/tag-body.txt" bare v2.0.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url https://example.com/b.png --arg footer ""
common_bare() { :; }
check bare 'banner leads' '.rich_message.blocks[0] == {type:"photo", photo:{type:"photo", media:"https://example.com/b.png"}}'
check bare 'no install, buttons or footer' '[.rich_message.blocks[].type] | (index("pre") == null and index("buttons") == null and index("footer") == null and .[-1] == "divider")'

# --- Keep a Changelog, search-builder 0.2.0 --------------------------------
npm_buttons='[{"text":"📝 Changelog","url":"{repo_url}/blob/{tag}/CHANGELOG.md"},{"text":"📦 npm","url":"https://www.npmjs.com/package/@pepebits/demo/v/{version}"}]'
build changelog "$root/test/fixtures/CHANGELOG.md" cl v0.2.0 \
  --arg install_title "📦 npm" --arg install_command "npm i @pepebits/demo@{version}" \
  --arg install_language bash --argjson buttons "$npm_buttons" \
  --arg banner_url "" --arg footer ""

common cl
check cl 'block order' '[.rich_message.blocks[].type] == ["heading","paragraph","paragraph","details","details","divider","paragraph","pre","buttons"]'
check cl 'subtitle is the date' '.rich_message.blocks[2].text == ["📅 ", {type:"italic", text:"2026-09-17"}]'
check cl 'Added ✨ and Changed 🔄' '[.rich_message.blocks[3,4].summary.text] == ["✨ Added", "🔄 Changed"]'
check cl 'only this version, 2 added + 1 changed' '(.rich_message.blocks[3].blocks[0].items | length) == 2 and (.rich_message.blocks[4].blocks[0].items | length) == 1 and ([tostring | test("0\\.1\\.1|First published")] | .[0] | not)'
check cl 'code spans are typed pieces' '.rich_message.blocks[3].blocks[0].items[0].blocks[0].text | any(.[]; type == "object" and .type == "code" and .text == "data-fs=\"skeleton\"")'
check cl 'wrapped bullet is one paragraph' '.rich_message.blocks[4].blocks[0].items[0].blocks[0].text | map(if type == "string" then . else .text end) | join("") | contains("Typing now matches") and (contains("\n") | not)'
check cl 'npm command' '.rich_message.blocks[7].text == "npm i @pepebits/demo@0.2.0"'
check cl 'buttons' '.rich_message.blocks[8].buttons | map(.url) == ["https://github.com/Pepebits/demo/blob/v0.2.0/CHANGELOG.md", "https://www.npmjs.com/package/@pepebits/demo/v/0.2.0"]'

# Other versions: the right section, Fixed 🐛, a paragraph before the first ###.
build changelog "$root/test/fixtures/CHANGELOG.md" cl011 v0.1.1 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
check cl011 'Fixed 🐛 then Changed 🔄' '[.rich_message.blocks[] | select(.type == "details") | .summary.text] == ["🐛 Fixed", "🔄 Changed"]'
build changelog "$root/test/fixtures/CHANGELOG.md" cl010 v0.1.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
check cl010 'intro paragraph kept, last section reaches the end of the file' '(.rich_message.blocks | map(select(.type == "paragraph") | .text) | any(. == "First published release.")) and ([.rich_message.blocks[] | select(.type == "details")] | length == 1) and ([tostring | test("Type declarations")] | .[0])'
check cl010 'links and package names stay plain' '[.. | objects | select(.type? == "url")] | length == 0'

# A version with no section still announces, without notes.
build changelog "$root/test/fixtures/CHANGELOG.md" cl999 v9.9.9 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
check cl999 'missing section: title and divider only' '[.rich_message.blocks[].type] == ["heading","divider"]'

# --- inline markup, from a tag ----------------------------------------------
printf 'Features\n- Run `pnpm login` or see [the docs](https://example.com/a_b) now.\n- *not bold*, <b>not html</b>, [not a link](javascript:alert(1)).\n' > "$out/inline.txt"
build tag "$out/inline.txt" inline v1.2.3 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
check inline 'code and url pieces' '.rich_message.blocks[3].blocks[0].items[0].blocks[0].text == ["Run ", {type:"code", text:"pnpm login"}, " or see ", {type:"url", text:"the docs", url:"https://example.com/a_b"}, " now."]'
check inline 'everything else stays literal' '.rich_message.blocks[3].blocks[0].items[1].blocks[0].text == "*not bold*, <b>not html</b>, [not a link](javascript:alert(1))."'

# --- size cap ---------------------------------------------------------------
{ printf '## [3.0.0] - 2026-01-01\n\n### Fixed\n\n'; for i in $(seq 1 3000); do printf -- '- fix number %s with some padding words to make it longer\n' "$i"; done; } > "$out/big.md"
build changelog "$out/big.md" big v3.0.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
check big 'a runaway changelog is cut under the limit' '[tostring | length] | .[0] < 32768'

if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all checks passed"
