# Turns release notes into a Bot API sendRichMessage payload.
#
# Input (raw, -R -s): either an annotated tag's message, or a whole Keep a
# Changelog file, depending on --arg mode.
# Arguments: --arg mode (tag | changelog) --arg chat_id --arg tag
#            --arg version --arg minor --arg subject --arg repo_url
#            --arg project_name --arg install_title --arg install_command
#            --arg install_language --argjson buttons (array of {text, url})
#            --arg banner_url (empty: no banner) --arg footer (empty: none)
#
# The notes travel as plain JSON strings inside explicit blocks, never as
# Markdown or HTML, so nothing in them can be parsed as formatting or markup
# and there is nothing to escape. The one exception is `code` spans and
# [links](https://…), which become typed RichText pieces: still structured
# data, still no parse mode.

# {version}, {minor}, {tag} and {repo_url} in a caller-supplied string.
def subst:
  gsub("\\{version\\}"; $version)
  | gsub("\\{minor\\}"; $minor)
  | gsub("\\{tag\\}"; $tag)
  | gsub("\\{repo_url\\}"; $repo_url);

# Splits a line of notes into RichText: `code` and [text](url) become typed
# pieces, the rest stays plain. A line with neither stays a bare string.
def rich:
  . as $s
  | [match("`([^`]+)`|\\[([^\\]]+)\\]\\((https?://[^)\\s]+)\\)"; "g")] as $m
  | if ($m | length) == 0 then $s
    else
      reduce $m[] as $x ({pos: 0, out: []};
        .out += (if $x.offset > .pos then [$s[.pos:$x.offset]] else [] end)
        | .out += [if $x.captures[0].string != null
                   then {type: "code", text: $x.captures[0].string}
                   else {type: "url", text: $x.captures[1].string,
                         url: $x.captures[2].string} end]
        | .pos = $x.offset + $x.length)
      | .out + (if .pos < ($s | length) then [$s[.pos:]] else [] end)
    end;

def para: {type: "paragraph", text: rich};

# Joins wrapped lines back into one, as the tag message wraps at ~78 columns
# and a changelog bullet continues on indented lines.
def unwrap: map(sub("^\\s+"; "")) | join(" ");

# A section title gets an emoji matching what it holds; anything unrecognised
# still gets one, so every section reads the same. Covers the tag notes'
# usual titles and every Keep a Changelog one.
def section_emoji:
  ascii_downcase as $t
  | if ($t | test("fix|bug")) then "🐛"
    elif ($t | test("feat|new|add")) then "✨"
    elif ($t | test("secur|cve|advisor")) then "🔒"
    elif ($t | test("break|upgrade|migrat|deprecat")) then "⚠️"
    elif ($t | test("chang")) then "🔄"
    elif ($t | test("remov")) then "🗑️"
    elif ($t | test("depend")) then "📦"
    else "📝" end;

def titled: "\(section_emoji) \(.)";

# A paragraph that warns about upgrading ("Upgrade note: …") is folded like
# the lists: its title stays visible with a warning sign, and the explanation,
# usually the longest text in the notes, opens on a tap.
def lead_block:
  if test("^(upgrade|breaking|migration) note:"; "i") then
    capture("^(?<title>[^:]+):\\s*(?<rest>.*)$"; "s") as $m
    | {type: "details",
       summary: {type: "bold", text: "⚠️ \($m.title)"},
       blocks: [{type: "paragraph",
                 text: (($m.rest[0:1] | ascii_upcase) + $m.rest[1:] | rich)}]}
  else para end;

# "- " lines (with their wrapped continuations) as one bulleted list block.
def list_block:
  {type: "list",
   items: (
     reduce .[] as $l ([];
       if ($l | test("^- ")) then . + [[($l | sub("^- "; ""))]]
       else .[:-1] + [.[-1] + [$l]] end)
     | map({blocks: [{type: "paragraph", text: (unwrap | rich)}]}))};

# One blank-line-separated chunk of the notes. A short title line followed by
# "- " items becomes a collapsed section, so a long list of fixes does not
# bury the rest of the message; otherwise the lead lines are a paragraph (or a
# heading, when it is a single short line with no full stop) and any items a
# plain list.
def chunk_blocks:
  split("\n") as $lines
  | ([$lines | to_entries[] | select(.value | test("^- ")) | .key] | first) as $first
  | (if $first == null then $lines else $lines[:$first] end) as $lead
  | (if $first == null then [] else $lines[$first:] end) as $rest
  | (($lead | length) == 1 and ($lead[0] | length) <= 40
     and ($lead[0] | test("[.:]$") | not)) as $is_title
  | if $is_title and ($rest | length) > 0 then
      [{type: "details",
        summary: {type: "bold", text: ($lead[0] | titled)},
        blocks: [$rest | list_block]}]
    else
      (if ($lead | length) == 0 then []
       elif $is_title then [{type: "heading", size: 3, text: ($lead[0] | titled)}]
       else [$lead | unwrap | lead_block]
       end)
      + (if ($rest | length) == 0 then [] else [$rest | list_block] end)
    end;

# The section of a Keep a Changelog file for this version: the lines after its
# "## [X.Y.Z] — date" heading up to the next "## ". Returns {date, body}, with
# body rewritten into the tag notes' shape (a "### Fixed" line becomes a bare
# "Fixed" title, its bullets lose the blank lines between them), or null when
# the version has no section.
def changelog_section:
  split("\n") as $lines
  | ("^##\\s+\\[?v?" + ($version | gsub("\\."; "\\.")) + "\\]?(\\s|$)") as $heading
  | ([$lines | to_entries[] | select(.value | test($heading)) | .key] | first) as $at
  | if $at == null then null
    else
      ($lines[$at + 1:]
       | (([to_entries[] | select(.value | test("^## ")) | .key] | first) as $end
          | if $end == null then . else .[:$end] end)) as $section
      | {date: (($lines[$at] | capture("(?<d>\\d{4}-\\d{2}-\\d{2})").d) // ""),
         body: (
           reduce $section[] as $l ({out: [], in_list: false};
             if ($l | test("^###\\s")) then
               .out += ["", ($l | sub("^###\\s+"; "") | sub("\\s+$"; ""))] | .in_list = true
             elif .in_list then
               if ($l | test("^\\s*$")) then .
               elif ($l | test("^[-*]\\s")) then .out += [($l | sub("^\\*\\s"; "- "))]
               else .out += [$l] end
             else .out += [$l] end)
           | .out | join("\n"))}
    end;

# The whole message, with the notes cut at $cap characters.
def message($cap):
  (if $mode == "changelog" then
     (changelog_section // {date: "", body: ""})
   else
     {date: "", body: .}
   end) as $notes
  | ($notes.body[0:$cap] | sub("\\s+$"; "")) as $body
  | ([$body | splits("\\n\\s*\\n")] | map(sub("^\\s+"; "") | sub("\\s+$"; "")) | map(select(. != ""))) as $chunks
  | (if $mode == "changelog" then
       (if $notes.date == "" then null else "📅 " end)
     else "✨ " end) as $sub_icon
  | (if $mode == "changelog" then $notes.date else $subject end) as $sub_text
  | {
      chat_id: $chat_id,
      rich_message: {
        skip_entity_detection: true,
        blocks: (
          (if $banner_url == "" then []
           else [{type: "photo", photo: {type: "photo", media: $banner_url}}] end)
          + [{type: "heading", size: 1,
              text: ["🚀 \($project_name) ", {type: "bold", text: $version}]}]
          + (if $sub_text == "" then []
             else [
               # Blocks carry no spacing of their own; a line holding only a
               # non-breaking space sets the version apart from its subtitle.
               {type: "paragraph", text: " "},
               {type: "paragraph", text: [$sub_icon, {type: "italic", text: $sub_text}]}
             ] end)
          + ($chunks | map(chunk_blocks) | add // [])
          + [{type: "divider"}]
          + (if $install_command == "" then []
             else [
               # A code block rather than inline code: Telegram gives it a copy
               # button, and the whole command is what people paste.
               {type: "paragraph", text: {type: "bold", text: $install_title}},
               {type: "pre", language: $install_language, text: ($install_command | subst)}
             ] end)
          + (if ($buttons | length) == 0 then []
             else [{type: "buttons", align: "center",
                    buttons: ($buttons | map({text: .text, url: (.url | subst)}))}] end)
          + (if $footer == "" then []
             else [{type: "footer", text: ($footer | subst)}] end)
        )
      }
    };

# Rich messages take up to 32768 characters, and the JSON around the text
# counts against that in the worst case, so a runaway changelog is cut (in
# halves) until the whole payload fits: the announcement is never lost, and the
# full notes are one tap away on GitHub.
def fit($cap):
  message($cap) as $m
  | if ($m | tostring | length) <= 32000 or $cap < 500 then $m
    else fit($cap / 2 | floor) end;

fit(30000)
