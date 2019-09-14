export script_name = "Lerp by Character"
export script_description = "Linearly interpolates a specified override tag character-by-character between stops in a line."
export script_version = "0.1.0"
export script_author = "line0"
export script_namespace = "l0.LerpByChar"

DependencyControl = require "l0.DependencyControl"
depCtrl = DependencyControl {
  feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
  {
    {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"l0.ASSFoundation", version:"0.4.4", url: "https://github.com/TypesettingTools/ASSFoundation",
      feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
    {"l0.Functional", version: "0.6.0", url: "https://github.com/TypesettingTools/Functional",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"},
    {"a-mo.ConfigHandler", version: "1.1.4", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
  }
}
LineCollection, ASS, Functional, ConfigHandler = depCtrl\requireModules!
{:list, :math, :string, :table, :unicode, :util, :re } = Functional
logger = depCtrl\getLogger!

dialogs = {
  lerpByCharacter: {
    {
      class: "label", label: "Select a tag to interpolate between states already present in the line.",
      x: 0, y: 0, width: 6, height: 1
    },
    {
      class: "label", label: "Tag:",
      x: 0, y: 1, width: 1, height: 1
    },
    tag: {
      class: "dropdown",
      items: table.pluck table.filter(ASS.tagMap, (tag) -> tag.type.lerp and not tag.props.global), "overrideName",
      value: "\\1c", config: true,
      x: 1, y: 1, width: 1, height: 1
    },
    cleanTags: {
      class: "checkbox", label: "Omit redundant tags",
      value: true, config: true,
      x: 0, y: 2, width: 2, height: 1
    },
  },
}

groupSectionsByTagState = (lineContents, tagName) ->
  groups, group = {}
  cb = (section, sections, i) ->
    if i == 1 or section.instanceOf[ASS.Section.Tag] and 0 < #section\getTags tagName -- TODO: support master tags and resets
      tagState = (section\getEffectiveTags true).tags[tagName]
      group.endTagState = tagState if group
      group = sections: {}, startTagState: tagState, firstLineIndex: i
      groups[#groups + 1] = group
    elseif i == #sections
      group.endTagState = (section\getEffectiveTags true).tags[tagName]
    group.sections[#group.sections + 1] = section

  lineContents\callback cb
  return groups

lerpGroup = (sections, startTagState, endTagState) ->
  totalCharCount = list.reduce sections, 0, (totalLength, section) ->
    totalLength + (section.instanceOf[ASS.Section.Text] and section.len or 0)
  return false if totalCharCount == 0

  processedCharCount = 0
  lerpedSections, l = {}, 1
  for s, section in ipairs sections
    unless section.instanceOf[ASS.Section.Text]
      lerpedSections[l], l = section, l+1
      continue

    charCount = section.len

    previousSection = sections[s-1]
    start = if previousSection and previousSection.instanceOf[ASS.Section.Tag]
      previousSection\removeTags startTagState.__tag.name
      previousSection\insertTags startTagState\lerp endTagState, processedCharCount / totalCharCount
      l, lerpedSections[l], section = l+1, section\splitAtChar 2, true
      2
    else 1

    for i = start, charCount
      tag = startTagState\lerp endTagState, (processedCharCount + i-1) / totalCharCount
      lerpedSections[l] = ASS.Section.Tag {tag}
      l, lerpedSections[l+1], section = l+2, section\splitAtChar 2, true

    processedCharCount += charCount

  return lerpedSections

showDialog = (macro) ->
  options = ConfigHandler dialogs, depCtrl.configFile, false, script_version, depCtrl.configDir
  options\read!
  options\updateInterface macro
  btn, res = aegisub.dialog.display dialogs[macro]
  if btn
    options\updateConfiguration res, macro
    options\write!
    return res

lerpByCharacter = (sub, sel) ->
  res = showDialog "lerpByCharacter"
  return aegisub.cancel! unless res

  tagName = ASS.tagNames[res.tag][1]
  lines = LineCollection sub, sel

  for line in *lines
    ass = ASS\parse line
    groups = groupSectionsByTagState(ass, tagName)

    insertOffset = 0
    for group in *groups do with group
      lerpedSections = lerpGroup .sections, .startTagState, .endTagState
      continue unless lerpedSections
      ass\removeSections insertOffset + .firstLineIndex , insertOffset + .firstLineIndex + #.sections - 1
      ass\insertSections lerpedSections, insertOffset + .firstLineIndex
      insertOffset += #lerpedSections - #.sections

    ass\cleanTags 4 if res.cleanTags
    ass\commit!
  lines\replaceLines!

depCtrl\registerMacro lerpByCharacter
