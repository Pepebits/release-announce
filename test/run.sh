#!/usr/bin/env bash
# Builds the message for each fixture exactly as announce.yml does and asserts
# on the JSON. Run from anywhere: test/run.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

# The program lives inline in the workflow (see the comment there); pull out
# the lines of its heredoc, minus the YAML indentation.
sed -n "/<<'JQ'/,/^ *JQ\$/p" "$root/.github/workflows/announce.yml" | sed '1d;$d' | sed 's/^          //' > "$out/announce.jq"
[ -s "$out/announce.jq" ] || { echo "could not find the jq program in announce.yml"; exit 1; }

# build <mode> <notes file> <name> <tag> [extra jq args…] > $out/<name>.json
# VERSION overrides the version taken from the tag, for prefixed tags.
build() {
  local mode="$1" notes="$2" name="$3" tag="$4"; shift 4
  local version="${VERSION:-${tag#v}}"
  jq -R -s -f "$out/announce.jq" \
    --arg mode "$mode" --arg chat_id -100123 --arg tag "$tag" \
    --arg version "$version" --arg minor "$(cut -d. -f1,2 <<< "$version")" \
    --arg subject "$(cat "$out/subject.txt")" \
    --arg repo_url https://github.com/Pepebits/demo \
    --arg notes_url "https://github.com/Pepebits/demo/releases/tag/$tag" \
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
# Telegram's limits and shapes, for every rich message built (see the end).
limits() {
  check "$1" 'fits in one rich message' '[tostring | length] | .[0] < 32768'
  check "$1" 'at most 500 blocks, list items and table rows included' "$block_count"' <= 500'
  check "$1" 'at most 16 levels of blocks and formatting' "$depth"' <= 16'
  # Bot API 10.5 replaced text with blocks in expandable quotations; folded
  # sections are details blocks, and stay so.
  check "$1" 'no quotation holds bare text' '[.. | objects | select(.type? == "blockquote" or .type? == "expandable_blockquote") | select(has("text"))] | length == 0'
  check "$1" 'every folded section has a summary and blocks' '[.. | objects | select(.type? == "details")] | all(has("summary") and (.blocks | type == "array" and length > 0))'
  check "$1" 'list items carry only input fields' '[.. | objects | .items? | arrays | .[] | keys[]] | all(IN("blocks", "has_checkbox", "is_checked", "value", "type"))'
  check "$1" 'no empty text, list, quote or table' '[.. | objects | select(.type? and (.type | IN("paragraph", "heading", "pre")) and .text == "")] + [.. | objects | select(.type? and (.type | IN("list", "blockquote", "table")) and ((.items // .blocks // .cells) | length == 0))] | length == 0'
}
# Telegram's counting: blocks at any depth, plus list items and table rows.
block_count='[.rich_message | .. | objects | (.blocks?, .items?, .cells?) | arrays | .[]] | length'
# Levels of nested blocks and rich text, counted generously: every object
# inside another one, through blocks, items, text and summary.
depth='def d: if type == "array" then (map(d) | max // 0)
  elif type == "object" then 1 + ([.blocks?, .items?, .text?, .summary?] | map(select(type == "array" or type == "object") | d) | max // 0)
  else 0 end; .rich_message.blocks | d'

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
printf 'Features\n- Run `pnpm login` or see [the docs](https://example.com/a_b) now.\n- 2 * 3 * 4, *.js, snake_case_name, <b>not html</b>, [not a link](javascript:alert(1)).\n- **Login**: asks for the code, **run `pnpm login`** first.\n- **see [the docs](https://example.com/d)**\n- The *New post* form, _also_ *with `code`*.\n' > "$out/inline.txt"
build tag "$out/inline.txt" inline v1.2.3 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
check inline 'code and url pieces' '.rich_message.blocks[3].blocks[0].items[0].blocks[0].text == ["Run ", {type:"code", text:"pnpm login"}, " or see ", {type:"url", text:"the docs", url:"https://example.com/a_b"}, " now."]'
check inline 'bold pieces, code kept out of bold' '.rich_message.blocks[3].blocks[0].items[2].blocks[0].text == [{type:"bold", text:"Login"}, ": asks for the code, ", {type:"bold", text:"run "}, {type:"code", text:"pnpm login"}, " first."]'
check inline 'a link may sit inside bold' '.rich_message.blocks[3].blocks[0].items[3].blocks[0].text == [{type:"bold", text:["see ", {type:"url", text:"the docs", url:"https://example.com/d"}]}]'
check inline 'italic pieces, code kept out of italic' '.rich_message.blocks[3].blocks[0].items[4].blocks[0].text == ["The ", {type:"italic", text:"New post"}, " form, ", {type:"italic", text:"also"}, " ", {type:"italic", text:"with "}, {type:"code", text:"code"}, "."]'
check inline 'everything else stays literal' '.rich_message.blocks[3].blocks[0].items[1].blocks[0].text == "2 * 3 * 4, *.js, snake_case_name, <b>not html</b>, [not a link](javascript:alert(1))."'

# --- the rest of the inline Markdown changelogs use --------------------------
printf 'Features\n- **bold with *italic* inside**, __bold__, ~~gone~~ and \\*not italic\\*\n- See <https://example.com/a> or https://example.com/a_b. Done\n' > "$out/inline2.txt"
build tag "$out/inline2.txt" inline2 v1.2.3 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
check inline2 'styles nest, __bold__ and ~~strike~~, escapes stay literal' '.rich_message.blocks[3].blocks[0].items[0].blocks[0].text == [{type:"bold", text:["bold with ", {type:"italic", text:"italic"}, " inside"]}, ", ", {type:"bold", text:"bold"}, ", ", {type:"strikethrough", text:"gone"}, " and *not italic*"]'
check inline2 'autolinks and bare URLs, trailing full stop left out' '.rich_message.blocks[3].blocks[0].items[1].blocks[0].text == ["See ", {type:"url", text:"https://example.com/a", url:"https://example.com/a"}, " or ", {type:"url", text:"https://example.com/a_b", url:"https://example.com/a_b"}, ". Done"]'

# --- nested and numbered lists ----------------------------------------------
printf 'Fixes\n- parent\n  - child\n    wrapped\n  * second child\n- after\n\nSteps\n1. first\n2) second\n' > "$out/lists.txt"
build tag "$out/lists.txt" lists v1.2.3 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
check lists 'sub-items nest inside their parent' '.rich_message.blocks[3].blocks[0].items == [
  {blocks:[{type:"paragraph", text:"parent"}, {type:"list", items:[
    {blocks:[{type:"paragraph", text:"child wrapped"}]},
    {blocks:[{type:"paragraph", text:"second child"}]}]}]},
  {blocks:[{type:"paragraph", text:"after"}]}]'
check lists 'numbered items keep their number' '.rich_message.blocks[4] | .summary.text == "📝 Steps" and .blocks[0].items == [
  {blocks:[{type:"paragraph", text:"first"}], value:1, type:"1"},
  {blocks:[{type:"paragraph", text:"second"}], value:2, type:"1"}]'

# Ten levels of indentation: lists stop nesting at the fifth.
{ printf 'Fixes\n'; for i in $(seq 0 9); do printf '%*s- level %s\n' $((i * 2)) '' "$i"; done; } > "$out/deep.txt"
build tag "$out/deep.txt" deep v1.2.3 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
common deep
check deep 'five list levels, the rest beside the fifth, none lost' '
  ([.. | objects | select(.type? == "paragraph") | .text | strings | select(startswith("level "))] | length == 10)
  and ([.rich_message.blocks[3] | paths(objects and .type? == "list") | map(select(. == "items")) | length] | max == 4)
  and ([.. | objects | select(.type? == "list") | select(.items | length == 6)] | length == 1)'

# --- real changelogs that once showed their Markdown marks ------------------
for fixture in ki:v1.1.0 ghost-connector:v0.1.5; do
  build changelog "$root/test/fixtures/${fixture%%:*}-CHANGELOG.md" "${fixture%%:*}" "${fixture#*:}" \
    --arg install_title x --arg install_command "" --arg install_language bash \
    --argjson buttons '[]' --arg banner_url "" --arg footer ""
  check "${fixture%%:*}" 'no Markdown marks left in the text' '[.. | strings] | all(test("\\*|__|~~") | not)'
done
check ki 'bold around code: code beside the bold' '.rich_message.blocks[3].blocks[0].items[0].blocks[0].text[0:3] == [{type:"code", text:"ki"}, {type:"bold", text:" for macOS and Windows"}, ": releases include "]'
check ghost-connector 'single stars are italic' '[.. | objects | select(.type? == "italic") | .text] == ["2026-10-25", "New post", "Results", "Export CSV"]'

# --- size cap ---------------------------------------------------------------
{ printf '## [3.0.0] - 2026-01-01\n\n### Fixed\n\n'; for i in $(seq 1 3000); do printf -- '- fix number %s with some padding words to make it longer\n' "$i"; done; } > "$out/big.md"
build changelog "$out/big.md" big v3.0.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
common big
check big 'a runaway changelog is cut under the limit' '[tostring | length] | .[0] < 32768'
check big 'cut at a whole item' '[.. | objects | select(.type? == "list") | .items[-1].blocks[0].text] | last | endswith("to make it longer")'
check big 'ends with a link to the full notes' '.rich_message.blocks[-2] == {type:"paragraph", text:{type:"italic", text:["… ", {type:"url", text:"the full notes", url:"https://github.com/Pepebits/demo/releases/tag/v3.0.0"}]}}'
check big 'keeps as much as the limits allow' "$block_count"' > 400'
check cl 'short notes are not marked as cut' '[tostring | test("the full notes")] | .[0] | not'

# A long list of long items reaches the character limit before the block one.
{ printf '## [3.0.1] - 2026-01-01\n\n### Fixed\n\n'; for i in $(seq 1 600); do printf -- '- fix %s %s\n' "$i" "$(printf 'word%.0s ' $(seq 1 30))end"; done; } > "$out/wide.md"
build changelog "$out/wide.md" wide v3.0.1 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
common wide
check wide 'cut at a whole item under the character limit' '([tostring | length] | .[0] <= 32000) and ([.. | objects | select(.type? == "list") | .items[-1].blocks[0].text] | last | endswith("end"))'

# --- structure inside sections: a changelog using most of Markdown ---------
build changelog "$root/test/fixtures/rich-CHANGELOG.md" rich v2.0.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
common rich
section() { echo ".rich_message.blocks[] | select(.type == \"details\" and (.summary.text | endswith(\"$1\"))) | .blocks"; }
check rich 'intro, upgrade note, then each ### folded in order' '[.rich_message.blocks[] | .type + ":" + ((.summary.text // .text) | tostring)] == ["heading:[\"🚀 demo \",{\"type\":\"bold\",\"text\":\"2.0.0\"}]", "paragraph:\u00a0", "paragraph:[\"📅 \",{\"type\":\"italic\",\"text\":\"2026-11-20\"}]", "paragraph:A big one: the config format changed.", "details:⚠️ Upgrade note", "details:🔄 Changed", "details:🗑️ Removed", "details:🐛 Fixed", "details:🔒 Security", "divider:null"]'
check rich 'prose before a list stays inside its section' "[$(section Changed)[].type] == [\"paragraph\", \"list\"]"
check rich 'an item holds a paragraph, fenced code and another paragraph' "$(section Changed)[1].items[0].blocks == [
  {type:\"paragraph\", text:\"Settings are read from TOML instead of JSON. Run the migration:\"},
  {type:\"pre\", text:\"demo migrate --from ~/.demo.json\", language:\"bash\"},
  {type:\"paragraph\", text:\"The old file is kept as a backup.\"}]"
check rich 'a numbered sub-list inside an item' "$(section Changed)[1].items[1].blocks[1] == {type:\"list\", items:[{blocks:[{type:\"paragraph\", text:\"Old logs are gzipped.\"}], value:1, type:\"1\"}, {blocks:[{type:\"paragraph\", text:\"After 30 days they are removed.\"}], value:2, type:\"1\"}]}"
check rich 'a section of prose alone is folded too' "$(section Removed) | length == 1 and .[0].type == \"paragraph\""
check rich 'task checkboxes' "[$(section Fixed)[0].items[0:2][] | [.has_checkbox, .is_checked]] == [[true, true], [true, null]]"
check rich '#### is a smaller heading inside the section' "$(section Fixed)[1] == {type:\"heading\", size:4, text:\"Windows\"}"
check rich 'a > quote keeps its formatting' "$(section Security)[0] == {type:\"blockquote\", blocks:[{type:\"paragraph\", text:[\"Upgrade as soon as possible: CVE-2026-0001 allowed \", {type:\"bold\", text:\"remote\"}, \" code execution. Thanks to the reporter.\"]}]}"
check rich 'a Markdown table is a table, header and alignment kept' "$(section Security)[1] == {type:\"table\", is_bordered:true, cells:[
  [{text:\"Platform\", is_header:true, align:\"left\"}, {text:\"Status\", is_header:true, align:\"center\"}],
  [{text:\"Linux\", align:\"left\"}, {text:\"✅\", align:\"center\"}],
  [{text:\"macOS\", align:\"left\"}, {text:[\"✅ \", {type:\"code\", text:\"arm64\"}, \" too\"], align:\"center\"}]]}"
check rich 'link definitions and comments are dropped' '[tostring | test("not shown|compare/v1")] | .[0] | not'
check rich 'no Markdown marks or fences left in the text' '[.. | objects | select(.type? != "pre") | .text? | strings] | all(test("```|^#|^>|^\\|") | not)'

# The same from a tag: a note and the paragraph after it, a title then a blank line,
# continuation paragraphs, and text back at the margin after a section.
head -n 1 "$root/test/fixtures/tag-rich-notes.txt" > "$out/subject.txt"
sed '1,2d' "$root/test/fixtures/tag-rich-notes.txt" > "$out/tag-rich-body.txt"
build tag "$out/tag-rich-body.txt" tagrich v1.0.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
common tagrich
check tagrich 'block order' '[.rich_message.blocks[].type] == ["heading","paragraph","paragraph","details","paragraph","details","details","paragraph","pre","divider"]'
check tagrich 'the upgrade note is its own paragraph; the next one stays in sight' '(.rich_message.blocks[3] | .summary.text == "⚠️ Upgrade note" and .blocks == [{type:"paragraph", text:"The database moves to Postgres 17."}]) and .rich_message.blocks[4].text == "Back up before upgrading; the migration cannot be undone."'
check tagrich 'a title followed by a blank line still folds its list' '.rich_message.blocks[5] | .summary.text == "✨ Features" and .blocks[0].items[1].blocks[1].items[1].blocks == [{type:"paragraph", text:"JSON"}, {type:"paragraph", text:"Nested JSON is flattened."}]'
check tagrich 'a paragraph indented under an item stays with it' '.rich_message.blocks[6].blocks[0].items[0].blocks == [{type:"paragraph", text:"Login no longer loops."}, {type:"paragraph", text:"A second paragraph explaining why it looped."}] and (.rich_message.blocks[6].blocks[0].items | length == 2)'
check tagrich 'text back at the margin leaves the section' '.rich_message.blocks[7].text == "Thanks to everyone who reported bugs." and .rich_message.blocks[8] == {type:"pre", text:"make install"}'
head -n 1 "$root/test/fixtures/tag-notes.txt" > "$out/subject.txt"

# --- fold: always (default), auto, never --------------------------------------
build tag "$out/tag-body.txt" fold_auto v2.0.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer "" --arg fold auto
check fold_auto 'auto opens lists of three items or fewer, keeps the note folded' '[.rich_message.blocks[] | select(.type == "details") | .is_open] == [null, true, true]'
check tag 'always folds every section' '[.rich_message.blocks[] | select(.type == "details") | .is_open] == [null, null, null]'
build tag "$out/tag-body.txt" fold_never v2.0.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer "" --arg fold never
check fold_never 'never opens them all' '[.rich_message.blocks[] | select(.type == "details") | .is_open] == [true, true, true]'

# --- delivery options, buttons in rows, copy and style ------------------------
nine='[{"text":"1","url":"https://e.com/{version}"},{"text":"2","url":"u"},{"text":"3","url":"u"},{"text":"4","url":"u"},{"text":"5","url":"u"},{"text":"6","url":"u"},{"text":"7","url":"u"},{"text":"8","url":"u"},{"text":"9","url":"u"},
  [{"text":"📋 Copy","copy_text":"npm i demo@{version}","style":"primary"},{"text":"Docs","url":"https://e.com","style":"success"}]]'
build tag "$out/tag-body.txt" opts v2.0.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons "$nine" --arg banner_url "" --arg footer "" \
  --arg message_thread_id 42 --arg disable_notification true --arg protect_content true
common opts
check opts 'topic, silence and protection sent' '.message_thread_id == 42 and .disable_notification == true and .protect_content == true'
check tag 'none of them unless asked' '[has("message_thread_id", "disable_notification", "protect_content")] == [false, false, false]'
check opts 'buttons fill rows of 8, a nested array is its own row' '[.rich_message.blocks[] | select(.type == "buttons") | .buttons | length] == [8, 1, 2]'
check opts 'copy and style buttons, placeholders replaced' '[.rich_message.blocks[] | select(.type == "buttons")][2].buttons == [{text:"📋 Copy", copy_text:{text:"npm i demo@2.0.0"}, style:"primary"}, {text:"Docs", url:"https://e.com", style:"success"}] and [.rich_message.blocks[] | select(.type == "buttons")][0].buttons[0].url == "https://e.com/2.0.0"'

# --- the plain-text fallback --------------------------------------------------
build tag "$out/tag-body.txt" plain v2.0.0 \
  --arg install_title "🐳 Docker image" --arg install_command "docker pull demo:{version}" --arg install_language bash \
  --argjson buttons "$nine" --arg banner_url https://example.com/b.png --arg footer "🏷️ {minor}" \
  --arg message_thread_id 42 --arg output plain
check plain 'plain text, no parse mode, no rich message' 'has("text") and (has("parse_mode") or has("rich_message") | not)'
check plain 'title, subject, install, notes link and footer' '.text == "🚀 demo 2.0.0\n✨ Telegram on teleproto, the maintained GramJS fork\n\n🐳 Docker image\ndocker pull demo:2.0.0\n\n📝 https://github.com/Pepebits/demo/releases/tag/v2.0.0\n\n🏷️ 2.0"'
check plain 'same chat and topic, no link preview' '.chat_id == "-100123" and .message_thread_id == 42 and .link_preview_options == {is_disabled: true}'
check plain 'buttons as an inline keyboard in the same rows' '[.reply_markup.inline_keyboard[] | length] == [8, 1, 2] and .reply_markup.inline_keyboard[2][0] == {text:"📋 Copy", copy_text:{text:"npm i demo@2.0.0"}, style:"primary"}'
build changelog "$root/test/fixtures/CHANGELOG.md" plaincl v0.2.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer "" --arg output plain
check plaincl 'changelog: the date as subtitle, no keyboard' '.text == "🚀 demo 0.2.0\n📅 2026-09-17\n\n📝 https://github.com/Pepebits/demo/releases/tag/v0.2.0" and (has("reply_markup") | not)'

# --- a changelog's last version: link definitions at the foot are not notes --
build changelog "$root/CHANGELOG.md" own v1.0.0 \
  --arg install_title x --arg install_command "" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer ""
check own 'no [x.y.z]: links from the foot of the file' '[tostring | test("\\[Unreleased\\]|compare/")] | .[0] | not'

# --- edge cases found in review --------------------------------------------
# quick <name> <mode> <tag> [extra jq args…] < notes: no install, buttons,
# banner or footer, so the notes are .rich_message.blocks[3:-1] (tag) or [1:-1]
# or [3:-1] (changelog, without or with a date).
quick() {
  local name="$1" mode="$2" tag="$3"; shift 3
  cat > "$out/$name.txt"
  build "$mode" "$out/$name.txt" "$name" "$tag" \
    --arg install_title x --arg install_command "" --arg install_language bash \
    --argjson buttons '[]' --arg banner_url "" --arg footer "" "$@"
}
notes='def notes: .rich_message.blocks | .[(if .[1].text == " " then 3 else 1 end):-1];'

# ## and ### inside fenced code are code, in both the section and its end.
quick fence_cl changelog v1.0.0 <<'EOF'
## [1.0.0] - 2026-01-01

### Changed

The README template is now:

```markdown
### Install

	Run it.
[ref]: https://e.com
<!-- keep -->
```

- Second item.

### Fixed

```bash
## build everything
make
```

- Fixed one.

## [0.9.0] - 2025-01-01
EOF
check fence_cl '### in code opens no section, ## in code ends nothing' "$notes"' [notes[] | .summary.text] == ["🔄 Changed", "🐛 Fixed"]'
check fence_cl 'code kept exactly: tabs, link definitions, comments' "$notes"' notes[0].blocks == [{type:"paragraph", text:"The README template is now:"}, {type:"pre", language:"markdown", text:"### Install\n\n\tRun it.\n[ref]: https://e.com\n<!-- keep -->"}, {type:"list", items:[{blocks:[{type:"paragraph", text:"Second item."}]}]}]'
check fence_cl 'the section after the code survives' "$notes"' notes[1].blocks[0] == {type:"pre", language:"bash", text:"## build everything\nmake"} and notes[1].blocks[1].items[0].blocks[0].text == "Fixed one."'

printf 'Fixes\n- a\n\n```\nrun\n\nUpgrade note: x\n- not an item\n```\n' | quick fence_tag tag v1.0.0
check fence_tag 'a title or a note inside code opens nothing' "$notes"' [notes[].type] == ["details", "pre"] and notes[1].text == "run\n\nUpgrade note: x\n- not an item"'
printf '~~~\nunclosed ~~~ fence\n- runs to the end\n' | quick fence_open tag v1.0.0
check fence_open '~~~ fences, an unclosed one runs to the end' "$notes"' notes == [{type:"pre", text:"unclosed ~~~ fence\n- runs to the end"}]'

# Headings: a closing run of # goes, C# keeps its #, an empty one is dropped.
printf '## [1.0.0]\n\n### Added\n\n#### Support for C#\n#### Issue #12 ##\n#### ###\n- a\n' | quick headings changelog v1.0.0
check headings 'C# kept, closing #s dropped, empty heading left out' "$notes"' [notes[0].blocks[] | select(.type == "heading") | .text] == ["Support for C#", "Issue #12"]'

# Link definitions go; a line that only looks like one stays.
printf 'Changes\n- one\n\n[core]: fixes\n[api]: speedups\n[1.0.0]: https://e.com/compare\n' | quick linkdefs tag v1.0.0
check linkdefs '[core]: fixes stays, [1.0.0]: https://… goes' "$notes"' [notes[1:][] | .text] == ["[core]: fixes [api]: speedups"]'

# Upgrade notes in a changelog: only outside a section.
printf '## [1.0.0]\n\nUpgrade note: before.\n\n### Fixed\n\nUpgrade note: inside.\n- a\n' | quick cl_note changelog v1.0.0
check cl_note 'a note before the sections folds; one inside a section is its text' "$notes"' [notes[] | .summary.text] == ["⚠️ Upgrade note", "🐛 Fixed"] and notes[1].blocks[0].text == "Upgrade note: inside."'

# A note is one paragraph: what follows, a list or a closing line, stays in sight.
printf 'Upgrade note: second one.\n\n- x\n\nThanks all.\n' | quick note_end tag v1.0.0
check note_end 'the note ends at its blank line' "$notes"' [notes[].type] == ["details", "list", "paragraph"] and notes[0].blocks == [{type:"paragraph", text:"Second one."}]'

# Rules: a divider between paragraphs, none at the end of a section.
printf '## [1.0.0]\n\n### Fixed\n\n- a\n\n---\n\n## [0.9.0]\n' | quick rule_end changelog v1.0.0
check rule_end 'a --- before the next version is dropped' "$notes"' notes[0].blocks == [{type:"list", items:[{blocks:[{type:"paragraph", text:"a"}]}]}]'
printf 'One.\n\n* * *\n\nTwo.\n' | quick rule_mid tag v1.0.0
check rule_mid '* * * between paragraphs is a divider, not a list' "$notes"' [notes[].type] == ["paragraph", "divider", "paragraph"]'

# Section titles read inline Markdown; code stays beside the bold.
printf '## [1.0.0]\n\n### Fixed in `core`\n\n- a\n\n### Empty\n' | quick title_md changelog v1.0.0
check title_md 'a title with code: bold pieces beside the code' "$notes"' notes[0].summary == [{type:"bold", text:"🐛 Fixed in "}, {type:"code", text:"core"}]'
check title_md 'an empty section is a heading' "$notes"' notes[1] == {type:"heading", size:3, text:"📝 Empty"}'

# A list indented under its title still folds.
printf 'Fixes\n  - a\n  - b\n' | quick indented tag v1.0.0
check indented 'an indented list under a title folds' "$notes"' notes[0].summary.text == "🐛 Fixes" and (notes[0].blocks[0].items | length) == 2'

# Items with nothing but code or a quote get a placeholder, never empty text.
printf 'Fixes\n- ```\n- > \n- [X] Done\n' | quick empties tag v1.0.0
check empties 'empty items hold a non-breaking space; [X] is checked' "$notes"' [notes[0].blocks[0].items[] | [.blocks[0].text, .is_checked]] == [[" ", null], [" ", null], ["Done", true]]'

# Tables: right alignment, an escaped pipe, short rows filled, more than 20 columns as code.
printf 'Notes\n\n| a | b | c |\n|---|--:|---|\n| x \\| y | 2 |\n' | quick table tag v1.0.0
check table 'right aligned, \| kept in a cell, a short row filled out' "$notes"' notes[1].cells == [[{text:"a", is_header:true}, {text:"b", is_header:true, align:"right"}, {text:"c", is_header:true}], [{text:"x | y"}, {text:"2", align:"right"}, {text:" "}]]'
{ printf 'Notes\n\n|'; for i in $(seq 1 21); do printf ' c%s |' "$i"; done; printf '\n|'; for i in $(seq 1 21); do printf -- '---|'; done; printf '\n'; } | quick wide_table tag v1.0.0
check wide_table '21 columns stay as written, in a code block' "$notes"' notes[1].type == "pre" and (notes[1].text | startswith("| c1 |"))'

# fold=auto: four items stay folded.
printf 'Fixes\n- a\n- b\n- c\n- d\n' | quick fold4 tag v1.0.0 --arg fold auto
check fold4 'auto keeps a list of four folded' "$notes"' notes[0] | has("is_open") | not'

# Nesting: quotes count towards Telegram's 16 levels too.
{ printf 'Notes\n\n'; printf '> %.0s' $(seq 1 20); printf 'deep\n'; } | quick quotes tag v1.0.0
check quotes 'twenty nested quotes keep their text within 16 levels' "$depth"' <= 16 and ([.. | strings | select(. == "deep")] | length == 1)'
{ printf 'Fixes\n'; for i in $(seq 0 7); do printf '%*s- > level %s\n' $((i * 4)) '' "$i"; done; } | quick alternate tag v1.0.0
check alternate 'lists and quotes in turn stay within 16 levels, nothing lost' "$depth"' <= 16 and ([.. | strings | select(startswith("level "))] | length == 8)'

# Cutting: back to a whole item when one is near, else a line, else a word.
{ printf '## [3.0.0]\n\n### Fixed\n\n| n | fix |\n|---|---|\n'; for i in $(seq 1 600); do printf '| %s | fixed %s |\n' "$i" "$i"; done; } | quick cut_table changelog v3.0.0
check cut_table 'a long table keeps as many rows as fit' "$notes"' (notes[0].blocks[0].cells | length) > 300 and (notes[1].text.text[1].text == "the full notes")'
{ printf '## [3.0.0]\n\n### Fixed\n\n- '; for i in $(seq 1 7000); do printf 'word%s ' "$i"; done; printf '\n'; } | quick cut_word changelog v3.0.0
check cut_word 'one huge line is cut at a word' "$notes"' (notes[0].blocks[0].items[0].blocks[0].text | test("word[0-9]+$")) and (notes[0].blocks[0].items[0].blocks[0].text | length) > 20000'

# The plain-text fallback stays within sendMessage's 4096 characters.
build tag "$out/tag-body.txt" plain_long v2.0.0 \
  --arg install_title x --arg install_command "$(printf 'x%.0s' $(seq 1 5000))" --arg install_language bash \
  --argjson buttons '[]' --arg banner_url "" --arg footer "" --arg output plain
check plain_long 'plain text cut at 4096' '.text | length == 4096'

# --- monorepo tag: prefix, then the version ---------------------------------
VERSION=0.2.0 build changelog "$root/test/fixtures/CHANGELOG.md" mono demo-php-v0.2.0 \
  --arg install_title x --arg install_command "composer require pepebits/demo:^{version}" --arg install_language bash \
  --argjson buttons '[{"text":"n","url":"{repo_url}/releases/tag/{tag}"}]' --arg banner_url "" --arg footer ""
check mono 'version is what follows the prefix' '.rich_message.blocks[0].text == ["🚀 demo ", {type:"bold", text:"0.2.0"}] and .rich_message.blocks[2].text == ["📅 ", {type:"italic", text:"2026-09-17"}]'
check mono '{tag} keeps the prefix, {version} does not' '(.rich_message.blocks[] | select(.type == "buttons") | .buttons[0].url) == "https://github.com/Pepebits/demo/releases/tag/demo-php-v0.2.0" and (.rich_message.blocks[] | select(.type == "pre") | .text) == "composer require pepebits/demo:^0.2.0"'

# --- the input check, run as the workflow's first step ------------------------
sed -n '/- name: Check the inputs/,/^$/p' "$root/.github/workflows/announce.yml" | sed '1,2d' | sed 's/^          //' > "$out/check.sh"
grep -q TAG_PREFIX "$out/check.sh" || { echo "could not find the input check in announce.yml"; exit 1; }
# tag_check <expected: ok|rejected> <tag_prefix> <tag>
tag_check() {
  local got=rejected
  if GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Pepebits/demo \
       NOTES_SOURCE=tag CHAT=test BUTTONS='[]' BANNER_URL='' FOLD=always MESSAGE_THREAD_ID='' TAG_PREFIX="$2" TAG="$3" \
       bash "$out/check.sh" > /dev/null 2>&1; then got=ok; fi
  if [ "$got" = "$1" ]; then echo "ok   check: prefix '$2', tag '$3' $1"
  else echo "FAIL check: prefix '$2', tag '$3' should be $1, was $got"; fails=$((fails + 1)); fi
}
tag_check ok       ''              v1.2.3
tag_check ok       ''              1.2.3
tag_check rejected ''              v1.2.3-rc.1
tag_check rejected ''              flex-url-v1.2.3
tag_check ok       flex-url-       flex-url-v3.1.0
tag_check ok       flex-url-php-   flex-url-php-v3.1.0
tag_check ok       flex-url-php-v  flex-url-php-v3.1.0
tag_check rejected flex-url-       flex-url-php-v3.1.0
tag_check rejected flex-url-php-   flex-url-v3.1.0
tag_check rejected flex-url-       v3.1.0
tag_check rejected 'flex*'         flex-url-v1.2.3
tag_check rejected 'pkg.'          pkgx1.2.3
tag_check rejected '$(id)'         '$(id)1.2.3'

# buttons_check <expected: ok|rejected> <buttons json>
buttons_check() {
  local got=rejected
  if GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Pepebits/demo \
       NOTES_SOURCE="${NOTES_SOURCE:-tag}" CHAT="${CHAT:-test}" BUTTONS="$2" BANNER_URL="${BANNER_URL:-}" \
       FOLD="${FOLD:-always}" MESSAGE_THREAD_ID="${MESSAGE_THREAD_ID:-}" TAG_PREFIX='' TAG=v1.2.3 \
       bash "$out/check.sh" > /dev/null 2>&1; then got=ok; fi
  if [ "$got" = "$1" ]; then echo "ok   check: ${3:-buttons $2} $1"
  else echo "FAIL check: buttons $2 should be $1, was $got"; fails=$((fails + 1)); fi
}
button='{"text":"b","url":"https://example.com"}'
buttons_check ok       "[$(printf "$button,%.0s" $(seq 1 8))$button]" '9 buttons, in rows'
buttons_check ok       "[[$(printf "$button,%.0s" $(seq 1 7))$button]]" 'a row of 8'
buttons_check rejected "[[$(printf "$button,%.0s" $(seq 1 8))$button]]" 'a row of 9'
buttons_check rejected '[[]]' 'an empty row'
buttons_check ok       '[{"text":"c","copy_text":"npm i x","style":"danger"}]'
buttons_check rejected '[{"text":"c","url":"https://e.com","copy_text":"x"}]'
buttons_check rejected '[{"text":"c"}]'
buttons_check rejected '[{"text":"c","url":"https://e.com","style":"link"}]'
buttons_check rejected '[{"text":"c","url":"https://e.com","callback_data":"x"}]'
buttons_check rejected "[{\"text\":\"c\",\"copy_text\":\"$(printf 'x%.0s' $(seq 1 257))\"}]" 'copy_text over 256 characters'
FOLD=auto buttons_check ok '[]' 'fold auto'
FOLD=sometimes buttons_check rejected '[]' 'fold sometimes'
MESSAGE_THREAD_ID=42 buttons_check ok '[]' 'message_thread_id 42'
MESSAGE_THREAD_ID=4x buttons_check rejected '[]' 'message_thread_id 4x'
MESSAGE_THREAD_ID=0 buttons_check rejected '[]' 'message_thread_id 0'
MESSAGE_THREAD_ID=9999999999999999 buttons_check rejected '[]' 'message_thread_id of 16 digits'
buttons_check rejected '[{"text":"a","url":null}]' 'url null'
buttons_check rejected '[{"text":"a","url":false}]' 'url false'
buttons_check rejected '[{"text":"a","copy_text":null}]' 'copy_text null'
buttons_check rejected '[] []' 'two JSON values'
buttons_check rejected 'nonsense' 'not JSON'
buttons_check rejected '[{"text":"","url":"https://e.com"}]' 'empty text'
buttons_check rejected '[{"text":"a","copy_text":""}]' 'empty copy_text'
buttons_check rejected '[{"text":"a","url":""}]' 'empty url'
buttons_check rejected '[{"text":"a","url":"not a url"}]' 'url that is not one'
buttons_check rejected '[{"text":"a","url":"javascript:alert(1)"}]' 'javascript: url'
buttons_check ok       '[{"text":"a","url":"tg://resolve?domain=x"}]' 'tg:// url'
buttons_check ok       '[{"text":"📦 v{version}","url":"{repo_url}/releases/tag/{tag}"}]' 'placeholders in text and url'
buttons_check rejected "[{\"text\":\"c\",\"copy_text\":\"$(printf '{repo_url}%.0s' $(seq 1 25))\"}]" 'copy_text over 256 once placeholders are filled'
buttons_check rejected '[{"text":"a","url":"https://e.com","style":null}]' 'style null'
NOTES_SOURCE=release buttons_check rejected '[]' 'notes_source release'
CHAT=everyone buttons_check rejected '[]' 'chat everyone'
BANNER_URL=http://e.com/b.png buttons_check rejected '[]' 'banner_url over http'
BANNER_URL=https://e.com/b.png buttons_check ok '[]' 'banner_url over https'

# --- the send step, against a fake Telegram -----------------------------------
# A stand-in curl answers like the Bot API: FAKE_TELEGRAM says what it refuses.
sed -n '/- name: Send to Telegram/,$p' "$root/.github/workflows/announce.yml" | sed -n '/run: |/,$p' | sed '1d' | sed 's/^          //' > "$out/send.sh"
grep -q sendMessage "$out/send.sh" || { echo "could not find the send step in announce.yml"; exit 1; }
mkdir -p "$out/bin"
cat > "$out/bin/curl" <<'CURL'
#!/usr/bin/env bash
url="$(sed -n 's/^url = "\(.*\)"$/\1/p')"
method="${url##*/}"
while [ $# -gt 0 ]; do
  case "$1" in --data-binary) data="${2#@}"; shift ;; --output) output="$2"; shift ;; esac
  shift
done
echo "$method $(jq -c 'if .rich_message then [.rich_message.blocks[].type | select(. == "photo")] | length elif .reply_markup then "plain" else "bare" end' "$data")" >> "$RUNNER_TEMP/calls"
case "$FAKE_TELEGRAM:$method" in
  down:*) echo '{"ok":false,"error_code":502,"description":"Bad Gateway"}' ;;
  photo:sendRichMessage) if jq -e 'any(.rich_message.blocks[]; .type == "photo")' "$data" > /dev/null
                         then echo '{"ok":false,"error_code":400,"description":"Bad Request: failed to get HTTP URL content"}'
                         else echo '{"ok":true,"result":{"message_id":7}}'; fi ;;
  rich:sendRichMessage | all:* | keyboard:sendRichMessage | silent:sendRichMessage)
    if [ "$FAKE_TELEGRAM" = silent ] && [ -e "$RUNNER_TEMP/once" ]; then exit 28; fi
    touch "$RUNNER_TEMP/once"
    echo '{"ok":false,"error_code":400,"description":"Bad Request: can'"'"'t parse"}' ;;
  keyboard:sendMessage) if jq -e 'has("reply_markup")' "$data" > /dev/null
                        then echo '{"ok":false,"error_code":400,"description":"Bad Request: BUTTON_URL_INVALID"}'
                        else echo '{"ok":true,"result":{"message_id":7}}'; fi ;;
  nothing:*) exit 7 ;;
  *) echo '{"ok":true,"result":{"message_id":7}}' ;;
esac > "$output"
CURL
chmod +x "$out/bin/curl"
# send_case <name> <FAKE_TELEGRAM> <banner: yes|no> <expected exit> <expected calls> <expected log pattern>
send_case() {
  local tmp="$out/send-$1"; mkdir -p "$tmp"
  if [ "$3" = yes ]; then jq '.rich_message.blocks = [{type:"photo", photo:{type:"photo", media:"https://e.com/b.png"}}] + .rich_message.blocks' "$out/tag.json" > "$tmp/message.json"
  else cp "$out/tag.json" "$tmp/message.json"; fi
  jq '.rich_message.blocks |= map(select(.type != "photo"))' "$tmp/message.json" > "$tmp/no-banner.json"
  cp "$out/plain.json" "$tmp/fallback.json"
  local code=0 log
  # GitHub runs a step with bash -e.
  log="$(PATH="$out/bin:$PATH" RUNNER_TEMP="$tmp" TELEGRAM_BOT_TOKEN=t FAKE_TELEGRAM="$2" bash -e "$out/send.sh" 2>&1)" || code=$?
  local calls; calls="$(paste -sd, "$tmp/calls")"
  if [ "$code" = "$4" ] && [ "$calls" = "$5" ] && grep -q -- "$6" <<< "$log"; then echo "ok   send: $1"
  else echo "FAIL send: $1 (exit $code, calls $calls, log: $log)"; fails=$((fails + 1)); fi
}
send_case 'accepted at once'               ok    yes 0 'sendRichMessage 1'                                     'Sent as message 7'
send_case 'banner refused: sent without'   photo yes 0 'sendRichMessage 1,sendRichMessage 0'                   'sent it without the banner'
send_case 'rich refused: plain text'       rich  yes 0 'sendRichMessage 1,sendRichMessage 0,sendMessage "plain"' 'sent a plain-text one instead'
send_case 'no banner to drop: plain text'  rich  no  0 'sendRichMessage 0,sendMessage "plain"'                 'sent a plain-text one instead'
send_case 'outage: no retry, a warning'    down  yes 1 'sendRichMessage 1'                                     '::warning::Telegram announcement not sent: 502'
send_case 'everything refused: a warning'  all   no  1 'sendRichMessage 0,sendMessage "plain",sendMessage "bare"' 'every fallback was refused too'
send_case 'buttons refused: plain, bare'   keyboard no 0 'sendRichMessage 0,sendMessage "plain",sendMessage "bare"' 'a plain-text one without buttons instead'
send_case 'no answer: nothing more sent'   nothing yes 1 'sendRichMessage 1'                                    'not sent: no response'
send_case 'refused, then no answer: stop'  silent yes 1 'sendRichMessage 1,sendRichMessage 0'                   'not sent: 400 .*then no response'

# --- Telegram's limits, on every rich message built above ---------------------
for f in "$out"/*.json; do
  name="$(basename "$f" .json)"
  jq -e 'has("rich_message")' "$f" > /dev/null 2>&1 && limits "$name"
done

if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all checks passed"
