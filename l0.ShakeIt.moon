export script_name = "Shake It"
export script_description = "Lets you add a shaking effect to fbf typesets with configurable constraints."
export script_version = "0.2.0"
export script_author = "line0"
export script_namespace = "l0.ShakeIt"

DependencyControl = require "l0.DependencyControl"
depCtrl = DependencyControl {
  feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
  {
    {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"l0.ASSFoundation", version:"0.4.3", url: "https://github.com/TypesettingTools/ASSFoundation",
      feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
    {"l0.Functional", version: "0.5.0", url: "https://github.com/TypesettingTools/Functional",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"},
    {"a-mo.ConfigHandler", version: "1.1.4", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
  }
}
LineCollection, ASS, Functional, ConfigHandler = depCtrl\requireModules!
{:list, :math, :string, :table, :unicode, :util, :re } = Functional
logger = depCtrl\getLogger!

-- Enums used in dialog
signChangeModes1D = {
  Any: "Allow Any"
  Force: "Force"
  Prevent: "Prevent"
}

signChangeModes2D = {
  Any: "Any number"
  Either: "At least one"
  One: "Exactly one"
}

tagShakeTargets = {
  LineBegin: "Beginning of every line"
  ExistingTags: "Every existing override tag"
  TagSections: "Every tag section"
}

dialogs = {
  shakePosition: {
    {
      class: "label", label: "Shaking Offset Limits (relative to original position): ",
      x: 0, y: 0, width: 10, height: 1,
    },
    offXMin: {
      class: "floatedit",
      value: 0, min: 0, step:1, config: true
      x: 0, y: 1, width: 3, height: 1
    },
    {
      class: "label", label: "<  x  <",
      x: 3, y: 1, width: 3, height: 1
    },
    offXMax: {
      class: "floatedit",
      value: 10, min: 0, step: 1, config: true
      x: 6, y: 1, width: 4, height: 1,
    },
    offYMin: {
      class: "floatedit",
      value: 0, min: 0, step: 1, config: true
      x: 0, y: 2, width: 3, height: 1
    },
    {
      class: "label", label: "<  y  <",
      x: 3, y: 2, width: 3, height: 1
    },
    offYMax: {
      class: "floatedit",
      x: 6, y: 2, width: 4, height: 1, config: true
      value: 10, min: 0, step: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 3, width: 10, height: 1
    },
    groupLines: {
      class: "checkbox", label: "Group lines by:",
      value: true, config: true
      x: 0, y: 4, width: 1, height: 1
    },
    groupLinesField: {
      class: "dropdown",
      items: {"start_time", "end_time", "layer", "effect", "actor"}, value: 'start_time', config: true
      x: 1, y: 4, width: 1, height: 1
    },
    {
      class: "label", label: "Shake interval: every",
      x: 0, y: 5, width: 1, height: 1
    },
    interval: {
      class:"intedit",
      value: 1, min: 1, config: true
      x: 1, y: 5, width: 1, height: 1
    },
    {
      class: "label", label: "line group(s)",
      x: 2, y: 5, width: 1, height: 1
    },
    {
      class: "label", label: "Angle between subsequent line group offsets:",
      x: 0, y: 6, width: 10, height: 1
    },
    {
      class: "label", label: "Min:",
      x: 0, y: 7, width: 1, height: 1
    },
    angleMin: {
      class: "floatedit",
      value: 0, min: 0, max: 180, step: 1, config: true
      x: 1, y: 7, width: 2, height: 1
    },
    {
      class: "label", label: "�    Max:",
      x: 3, y: 7, width: 3, height: 1
    },
    angleMax: {
      class: "floatedit",
      value: 180, min: 0, max: 180, step: 1, config: true
      x: 6, y: 7, width: 2, height: 1,
    },
    {
      class: "label", label: "�",
      x: 8, y: 7, width: 2, height: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 8, width: 10, height: 1
    },
    {
      class: "label", label: "Constraints:",
      x: 0, y: 9, width: 10, height: 1
    },
    signChangeX: {
      class: "dropdown",
      items: table.values(signChangeModes1D), value: signChangeModes1D.Any, config: true
      x: 0, y: 10, width: 2, height: 1
    },
    {
      class: "label", label: "sign change for X offsets of subsequent line groups.",
      x: 2, y: 10, width: 5, height: 1
    },
    signChangeY: {
      class: "dropdown",
      items: table.values(signChangeModes1D), value: signChangeModes1D.Any, config: true
      x: 0, y: 11, width: 2, height: 1
    },
    {
      class: "label", label: "sign change for Y offsets of subsequent line groups.",
      x: 2, y: 11, width: 5, height: 1
    },
    signChangeCmb: {
      class: "dropdown",
      items: table.values(signChangeModes2D), value: signChangeModes2D.Any, config: true
      x: 0, y: 12, width: 2, height: 1
    },
    {
      class: "label", x: 2, y: 12, width: 5, height: 1
      label: "of the X and Y offsets must change sign between subsequent line groups.",
    },
    {
      class: "label", label: "",
      x: 0, y: 13, width: 10, height: 1
    },
    {
      class: "label", label: "Random Number Generation",
      x: 0, y: 14, width: 10, height: 1
    },
    {
      class: "label", label: "Seed:",
      x: 0, y: 15, width: 1, height: 1
    },
    seed: {
      class:"intedit",
      value: os.time!,
      x: 1, y: 15, width: 2, height: 1
    },
    repeatPattern: {
      class: "checkbox", label: "Repeat pattern every",
      value: false, config: true,
      x: 0, y: 16, width: 1, height: 1
    },
    repeatInterval: {
      class:"intedit",
      value: 12, config: true,
      x: 1, y: 16, width: 1, height: 1
    },
    {
      class: "label", label: "line group(s)",
      x: 2, y: 16, width: 1, height: 1
    },
  },
  shakeScalarTag: {
    {
      class: "label", label: "Shaking Targets:",
      x: 0, y: 0, width: 6, height: 1
    },
    {
      class: "label", label: "Tag:",
      x: 0, y: 1, width: 1, height: 1
    },
    tag: {
      class: "dropdown",
      items: table.pluck table.filter(ASS.tagMap, (tag) -> tag.type == ASS.Number and not tag.props.global), "overrideName",
      value: "\\frz", config: true,
      x: 1, y: 1, width: 1, height: 1
    },
    LineBegin: {
      class: "checkbox", label: tagShakeTargets.LineBegin,
      value: true, config: true,
      x: 0, y: 2, width: 6, height: 1
    },
    ExistingTags: {
      class: "checkbox", label: tagShakeTargets.ExistingTags,
      value: false, config: true,
      x: 0, y: 3, width: 6, height: 1
    },
    TagSections: {
      class: "checkbox", label: tagShakeTargets.TagSections,
      value: false, config: true
      x: 0, y: 4, width: 6, height: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 5, width: 6, height: 1
    },
    {
      class: "label", label: "Shake offset limits (relative to original tag value): ",
      x: 0, y: 6, width: 6, height: 1,
    },
    absoluteOffsetMin: {
      class: "floatedit",
      value: 0, min: 0, step:1, config: true,
      x: 0, y: 7, width: 2, height: 1
    },
    {
      class: "label", label: "<  value  <",
      x: 2, y: 7, width: 1, height: 1
    },
    absoluteOffsetMax: {
      class: "floatedit",
      value: 10, min: 0, step: 1, config: true
      x: 3, y: 7, width: 2, height: 1,
    },
    {
      class: "label", label: "",
      x: 0, y: 8, width: 6, height: 1
    },
    groupLines: {
      class: "checkbox", label: "Group lines by:",
      value: true, config: true,
      x: 0, y: 9, width: 1, height: 1
    },
    groupLinesField: {
      class: "dropdown",
      items: {"start_time", "end_time", "layer", "effect", "actor"}, value: 'start_time', config: true,
      x: 1, y: 9, width: 1, height: 1
    },
    {
      class: "label", label: "Shake interval: every",
      x: 0, y: 10, width: 1, height: 1
    },
    interval: {
      class: "intedit",
      value: 1, min: 1, config: true,
      x: 1, y: 10, width: 1, height: 1
    },
    {
      class: "label", label: "line group(s)",
      x: 2, y: 10, width: 1, height: 1
    },
    {
      class: "label", label: "Offset difference range between subsequent line groups:",
      x: 0, y: 11, width: 6, height: 1
    },
    {
      class: "label", label: "Min:",
      x: 0, y: 12, width: 1, height: 1
    },
    groupOffsetMin: {
      class: "floatedit",
      value: 0, min: 0, step: 1, config: true,
      x: 1, y: 12, width: 2, height: 1
    },
    {
      class: "label", label: "    Max:",
      x: 3, y: 12, width: 1, height: 1
    },
    groupOffsetMax: {
      class: "floatedit",
      value: 10, min: 0, step: 1, config: true
      x: 4, y: 12, width: 2, height: 1,
    },
    {
      class: "label", label: "",
      x: 0, y: 13, width: 6, height: 1
    },
    {
      class: "label", label: "Shake offset constraints between subsequent line groups:",
      x: 0, y: 14, width: 6, height: 1
    },
    signChange: {
      class: "dropdown",
      items: table.values(signChangeModes1D), value: signChangeModes1D.Any, config: true,
      x: 0, y: 15, width: 2, height: 1
    },
    {
      class: "label", label: "sign change for tag offsets of subsequent lines.",
      x: 2, y: 15, width: 4, height: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 16, width: 6, height: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 17, width: 6, height: 1
    },
    {
      class: "label", label: "Random Number Generation",
      x: 0, y: 18, width: 10, height: 1
    },
    {
      class: "label", label: "Seed:",
      x: 0, y: 19, width: 1, height: 1
    },
    seed: {
      class:"intedit",
      value: os.time!,
      x: 1, y: 19, width: 2, height: 1
    },
    repeatPattern: {
      class: "checkbox", label: "Repeat pattern every",
      value: false, config: true,
      x: 0, y: 20, width: 1, height: 1
    },
    repeatInterval: {
      class:"intedit",
      value: 12, config: true,
      x: 1, y: 20, width: 1, height: 1
    },
    {
      class: "label", label: "line group(s)",
      x: 2, y: 20, width: 1, height: 1
    },
  }
}

hasLineRotation = (line) ->
  styleTags = line\getDefaultTags nil, false
  return true unless styleTags.tags.angle\equal 0
  line\modTags {"angle", "angle_x", "angle_y"}, (tag) -> true

groupLines = (lines, field, interval = 1) ->
  -- collect selected lines and group if desired
  groups = if field
    table.values list.groupBy(lines.lines, field), (grpA, grpB) -> grpA[1][field] < grpB[1][field]
  else [{line} for line in *lines]

  -- group fbf lines to get longer shake interval
  if interval > 1
    groups = [list.join unpack group for group in *list.chunk groups, interval]

  return groups

applyPositionShake = (lines, groups, offsets) ->
  aegisub.progress.task "Shaking..."
  groupCount = #groups

  for i, group in ipairs groups
    aegisub.progress.set 20 + 80 * (i-1) / groupCount
    aegisub.cancel! if aegisub.progress.is_cancelled!

    for line in *group
      data = ASS\parse line
      pos, align, org = data\getPosition!
      modifiedTags = {pos}

      if pos.class == ASS.Tag.Move
        pos\add offsets[i][1], offsets[i][2], offsets[i][1], offsets[i][2]
      else
        pos\add offsets[i][1], offsets[i][2]
        if hasLineRotation data
          modifiedTags[2] = org
          org\add offsets[i][1], offsets[i][2]

      data\replaceTags modifiedTags
      data\commit!

  lines\replaceLines!

collectTags = (lines, groups, tagName, targets) ->
  maxTagCountPerLine = 0
  groupCount = #groups

  tagsByGroupAndLine = for i, group in ipairs groups
    aegisub.progress.set 10 + 50 * (i-1) / groupCount
    aegisub.cancel! if aegisub.progress.is_cancelled!

    for line in *group
      tags = {}
      ass = line.ASS or ASS\parse line

      if targets.LineBegin
        -- get the tag section right at line begin, create one if it doesn't exist
        section = if #ass.sections > 0 and ass.sections[1].instanceOf[ASS.Section.Tag]
          ass.sections[1]
        else ass\insertSections(ASS.Section.Tag!, 1)[1]

        -- get the last matching override tag in that section, create one from style default if it doesn't exist
        tags[#tags+1] = section\getTags(tagName, -1, -1, true)[1] or section\insertDefaultTags tagName

      if targets.ExistingTags
        list.joinInto tags, ass\getTags tagName

      if targets.TagSections
        ass\callback (section,_,i) ->
          tags[#tags+1] = section\getTags(tagName, -1, -1, true)[1] or section\insertTags(
            section\getEffectiveTags(true).tags[tagName]),
          ASS.Section.Tag

      -- deduplicate tags we matched multiple times
      tags = table.keys list.makeSet tags
      -- sort tags by order of appearance in the line
      table.sort tags, (a, b) ->
        aSectionPosition = list.indexOf a.parent.parent.sections, a.parent
        bSectionPosition = list.indexOf b.parent.parent.sections, b.parent
        if aSectionPosition == bSectionPosition
          return list.indexOf(a.parent.tags, a) < list.indexOf b.parent.tags, b
        return  aSectionPosition < bSectionPosition

      maxTagCountPerLine = math.max maxTagCountPerLine, #tags
      tags

  return tagsByGroupAndLine, maxTagCountPerLine

getSingleSign = (mode, offPrev) ->
  ref = switch mode
    when signChangeModes1D.Prevent then offPrev
    when signChangeModes1D.Force then -offPrev
    else math.random! - 0.5
  return math.sign ref, true

makePositionOffsetGenerator = (res)  ->
  shakeRadius = math.vector2.distance 0, 0, res.offXMax, res.offYMax
  offXPrev, offYPrev, offX, offY = 0, 0
  -- allow user to replay a previous shake
  math.randomseed res.seed

  return (constrainAngle = true, rollLimit = 5000) ->
    for i = 1, rollLimit
      -- check if X sign change is subject to combined X/Y constraints
      xSign = if res.signChangeCmb == signChangeModes2D.One and res.signChangeY == signChangeModes1D.Force
        math.sign offXPrev, true
      elseif res.signChangeCmb == signChangeModes2D.Either and res.signChangeY == signChangeModes1D.Prevent
        math.sign -offXPrev, true
      -- otherwise use X-only constraints
      else getSingleSign res.signChangeX, offXPrev

      -- generate a new horizontal offset with the desired sign
      offX = xSign * math.randomFloat res.offXMin, res.offXMax
      xSignChanged = offX * offXPrev < 0

      -- check if Y sign change is subject to combined X/Y constraints
      ySign = if res.signChangeCmb == signChangeModes2D.Either and not xSignChanged
        math.sign -offYPrev, true
      elseif res.signChangeCmb == signChangeModes2D.One and xSignChanged
        math.sign offYPrev, true
      -- otherwise use Y-only constraints
      else getSingleSign res.signChangeY, offYPrev

      -- generate a new vertical offset with the desired sign
      offY = ySign * math.randomFloat res.offYMin, res.offYMax

      -- scale the current and previous offset vectors to the shake radius
      offXNorm, offYNorm = math.vector2.normalize offX, offY, shakeRadius
      offXPrevNorm, offYPrevNorm = math.vector2.normalize offXPrev, offYPrev, shakeRadius
      -- get the angle difference on the circle around the origin
      distance = math.vector2.distance offXPrevNorm, offYPrevNorm, offXNorm, offYNorm
      angle = math.degrees math.acos (2*shakeRadius^2 - distance^2) / (2 * shakeRadius^2)
      -- and check if is within the user-specified constraints
      if not constrainAngle or angle >= res.angleMin and angle <= res.angleMax
        offXPrev, offYPrev = offX, offY
        return {offX, offY}

    -- give up after so many rolls, because we're to lazy to actually do our maths
    -- and factor the constraints in when pulling our random numbers
    logger\error "Couldn't find offset that satifies chosen angle constraints (Min: #{res.angleMin}�, Max: #{res.angleMax}� for group #{i}. Aborting."

makeSimpleOffset = (prev, min, max, signChangeMode = signChangeModes1D.Any, minDiff = 0, maxDiff = math.huge, rollLimit = 5000) ->
  for i = 1, rollLimit
    sign = getSingleSign signChangeMode, prev
    off = sign * math.randomFloat min, max
    diffToPrev = math.abs off-prev
    if diffToPrev <= maxDiff and diffToPrev >= minDiff
      return off

  logger\error "Couldn't find offset that satifies constraints Min=#{minDiff} <= #{prev} <= Max=#{maxDiff}."


makeMultiOffsetGenerator = (res, count) ->
  -- this makes all initial offsets start with the same sign if sign change is enforced
  -- TODO: maybe offer an option to start with a random sign for every value
  offPrev = [0 for _ = 1, count]

  -- allow user to replay a previous shake
  math.randomseed res.seed

  return (applyConstraints = true, rollLimit) ->
    minPrevDiff, maxPrevDiff = if applyConstraints
      res.groupOffsetMin, res.groupOffsetMax
    else 0, math.huge

    offPrev = for i = 1, count
      makeSimpleOffset offPrev[i], res.absoluteOffsetMin, res.absoluteOffsetMax, res.signChange, minPrevDiff, maxPrevDiff, rollLimit
    return offPrev


calculateOffsets = (seriesCount, generator, seed, repeatInterval = math.huge, startProgress = 0, endProgress = 100) ->
  offsets = {}

  for i = 0, seriesCount - 1
    aegisub.progress.set startProgress + (endProgress-startProgress) * i / seriesCount
    aegsiub.cancel! if aegisub.progress.is_cancelled!
    offsets[1 + i] = if i < repeatInterval
      generator i != 0
    else offsets[1 + i%repeatInterval]

  return offsets

showDialog = (macro) ->
  options = ConfigHandler dialogs, depCtrl.configFile, false, script_version, depCtrl.configDir
  options\read!
  options\updateInterface macro
  btn, res = aegisub.dialog.display dialogs[macro]
  if btn
    options\updateConfiguration res, macro
    options\write!
    return res

shakePosition = (sub, sel) ->
  res = showDialog "shakePosition"
  return aegisub.cancel! unless res

  -- fix up some user errors
  if res.offXMax < res.offXMin
    res.offXMin, res.offXMax = res.offXMax, res.offXMin

  if res.offYMax < res.offYMin
    res.offYMin, res.offYMax = res.offYMax, res.offYMin

  if res.angleMax < res.angleMin
    res.angleMin, res.angleMax = res.angleMax, res.angleMin

  -- check for conflicting constraints
  err = {"You have provided conflicting constraints: "}
  if res.signChangeX == signChangeModes1D.Force and res.signChangeY == signChangeModes1D.Force
    if res.angleMax < 90
      err[#err+1] = "Forced sign inversion for X and Y offsets require a maxium angle of at least 90�."
    if res.signChangeCmb == signChangeModes2D.One
      err[#err+1] = "Can't limit signs to only one of the X and Y offsets because sign changes are separately enforced for both."

  elseif res.signChangeX == signChangeModes1D.Prevent and res.signChangeY == signChangeModes1D.Prevent
    if res.angleMin > 90
      err[#err+1] = "Can't prevent sign inversion for X and Y offsets when the minimum angle is larger than 90�."
    if res.signChangeCmb == signChangeModes2D.Either
      err[#err+1] = "Can't change signs of either X or Y offsets because they are prevented for both."

  logger\assert #err == 1, table.concat err, "\n"

  lines = LineCollection sub, sel

  aegisub.progress.task "Grouping lines..."
  groups = groupLines lines, res.groupLines and res.groupLinesField or nil, res.interval
  aegisub.progress.set 10
  aegisub.cancel! if aegisub.progress.is_cancelled!

  aegisub.progress.task "Rolling dice..."
  -- generate offsets for every line group, but don't apply them immediately in case the generator fails
  offsets = calculateOffsets #groups, makePositionOffsetGenerator(res),
    res.seed, res.repeatPattern and res.repeatInterval or math.huge, 10, 20

  -- apply the position offsets to all line groups
  aegisub.progress.task "Applying shake..."
  applyPositionShake lines, groups, offsets

shakeScalarTag = (sub, sel) ->
  res = showDialog "shakeScalarTag"
  return aegisub.cancel! unless res

  -- fix up some user errors
  if res.absoluteOffsetMax < res.absoluteOffsetMin
    res.absoluteOffsetMin, res.absoluteOffsetMax = res.absoluteOffsetMax, res.absoluteOffsetMin

  if res.groupOffsetMax < res.groupOffsetMin
    res.groupOffsetMin, res.groupOffsetMax = res.groupOffsetMax, res.groupOffsetMin

  lines = LineCollection sub, sel

  aegisub.progress.task "Grouping lines..."
  groups = groupLines lines, res.groupLines and res.groupLinesField or nil, res.interval
  groupCount = #groups
  aegisub.progress.set 10

  aegisub.progress.task "Collecting tags..."
  tagsByGroupAndLine, offsetCount = collectTags lines, groups, ASS.tagNames[res.tag][1], res

  aegisub.progress.task "Rolling dice..."
  offsets = calculateOffsets #groups, makeMultiOffsetGenerator(res, offsetCount),
    res.seed, res.repeatPattern and res.repeatInterval or math.huge, 60, 70

  aegisub.progress.task "Applying shake..."

  for g, group in ipairs groups
    aegisub.progress.set 70 + 30 * (g-1) / groupCount
    aegisub.cancel! if aegisub.progress.is_cancelled!

    for tagsByLine in *tagsByGroupAndLine[g]
      -- TODO: support tags w/ > 1 parameter
      tag\add offsets[g][t] for t, tag in ipairs tagsByLine

    line.ASS\commit! for line in *group

  lines\replaceLines!

depCtrl\registerMacros {
  {"Shake Position", "Applies randomized offsets to line positioning.", shakePosition},
  {"Shake Scalar Tag", "Applies randomized offsets to a specified scalar override tag.", shakeScalarTag},
}
