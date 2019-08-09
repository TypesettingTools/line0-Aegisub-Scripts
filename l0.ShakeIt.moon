export script_name = "Shake It"
export script_description = "Lets you add a shaking effect to fbf typesets with configurable constraints."
export script_version = "0.1.1"
export script_author = "line0"
export script_namespace = "l0.ShakeIt"

DependencyControl = require "l0.DependencyControl"
depCtrl = DependencyControl {
  feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
  {
    {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"l0.ASSFoundation", version:"0.4.0", url: "https://github.com/TypesettingTools/ASSFoundation",
      feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
    {"l0.Functional", version: "0.5.0", url: "https://github.com/TypesettingTools/Functional",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"}
  }
}
LineCollection, ASS, Functional = depCtrl\requireModules!
{:list, :math, :string, :table, :unicode, :util, :re } = Functional
logger = depCtrl\getLogger!

-- Enums used in dialog
signChgModesSingle = {
  Any: "Allow Any"
  Force: "Force"
  Prevent: "Prevent"
}

signChgModesCmb = {
  Any: "Any number"
  Either: "At least one"
  One: "Exactly one"
}

tagShakeTargets = {
  LineBegin: "Beginning of every line"
  ExistingTags: "Every existing override tag"
  TagSections: "Every tag section"
}

hasLineRotation = (line) ->
  styleTags = line\getDefaultTags nil, false
  return true unless styleTags.tags.angle\equal 0
  line\modTags {"angle", "angle_x", "angle_y"}, (tag) -> true

groupLines = (lines, interval = 1) ->
  -- collect selected lines and group by start time
  groups = table.values list.groupBy(lines.lines, "start_time"),
    (grpA, grpB) -> grpA[1].start_time < grpB[1].start_time

  -- group fbf lines to get longer shake interval
  if interval > 1
    groups = [list.join unpack group for group in *list.chunk groups, interval]

  return groups

applyPositionShake = (lines, groups, offsets) ->
  aegisub.progress.task "Shaking..."
  groupCnt = #groups

  for i, group in ipairs groups
    aegisub.progress.set 50 + 50 * i/groupCnt
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

  tagsByGroupAndLine = for i, group in ipairs groups
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

      maxTagCountPerLine = math.max maxTagCountPerLine, #tags
      tags

  return tagsByGroupAndLine, maxTagCountPerLine

getSingleSign = (mode, offPrev) ->
  ref = switch mode
    when signChgModesSingle.Prevent then offPrev
    when signChgModesSingle.Force then -offPrev
    else math.random! - 0.5
  return math.sign ref, true

makePositionOffsetGenerator = (res)  ->
  shakeRadius = math.vector2.distance 0, 0, res.offXMax, res.offYMax
  offXPrev, offYPrev, offX, offY = 0, 0
  -- allow user to replay a previous shake
  math.randomseed res.seed

  return (constrainAngle = true, rollLimit = 1000) ->
    for i = 1, rollLimit
      -- check if X sign change is subject to combined X/Y constraints
      xSign = if res.signChgCmb == signChgModesCmb.One and res.signChgY == signChgModesSingle.Force
        math.sign offXPrev, true
      elseif res.signChgCmb == signChgModesCmb.Either and res.signChgY == signChgModesSingle.Prevent
        math.sign -offXPrev, true
      -- otherwise use X-only constraints
      else getSingleSign res.signChgX, offXPrev

      -- generate a new horizontal offset with the desired sign
      offX = xSign * math.randomFloat res.offXMin, res.offXMax
      xSignChanged = offX * offXPrev < 0

      -- check if Y sign change is subject to combined X/Y constraints
      ySign = if res.signChgCmb == signChgModesCmb.Either and not xSignChanged
        math.sign -offYPrev, true
      elseif res.signChgCmb == signChgModesCmb.One and xSignChanged
        math.sign offYPrev, true
      -- otherwise use Y-only constraints
      else getSingleSign res.signChgY, offYPrev

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
    logger\error "Couldn't find offset that satifies chosen angle constraints (Min: #{res.angleMin}°, Max: #{res.angleMax}° for group #{i}. Aborting."

makeSimpleOffset = (prev, min, max, signChgMode = signChgModesSingle.Any, minDiff = 0, maxDiff = math.huge, rollLimit = 1000) ->
  for i = 1, rollLimit
    sign = getSingleSign signChgMode, prev
    off = sign * math.randomFloat min, max
    diffToPrev = math.abs off-prev
    if diffToPrev <= maxDiff and diffToPrev >= minDiff
      return off

  logger\error "Couldn't find offset that satifies chosen temporal offset constraints (Min: #{res.offTemporalMin}, Max: #{res.offTemporalMax} for group #{i}. Aborting."


makeMultiOffsetGenerator = (res, count) ->
  offPrev = [0 for _ = 1, count]

  -- allow user to replay a previous shake
  math.randomseed res.seed

  return (constrainTemporal = true, rollLimit) ->
    minPrevDiff, maxPrevDiff = if constrainTemporal
      res.offTemporalMin, res.offTemporalMax
    else 0, math.huge

    offPrev = for i = 1, count
      makeSimpleOffset offPrev[i], res.offTotalMin, res.offTotalMax, res.signChg, minPrevDiff, maxPrevDiff, rollLimit
    return offPrev


calculateOffsets = (seriesCount, generator) ->
  aegisub.progress.task "Rolling dice..."

  return for i = 1, seriesCount
    aegisub.progress.set 50 * i / seriesCount
    aegsiub.cancel! if aegisub.progress.is_cancelled!
    generator i != 1

shakePosition = (sub, sel) ->
  btn, res = aegisub.dialog.display {
    {
      class: "label", label: "Shaking Offset Limits (relative to original position): ",
      x: 0, y: 0, width: 10, height: 1,
    },
    {
      class: "floatedit", name: "offXMin",
      value: 0, min: 0, step:1,
      x: 0, y: 1, width: 3, height: 1
    },
    {
      class: "label", label: "<  x  <",
      x: 3, y: 1, width: 3, height: 1
    },
    {
      class: "floatedit", name: "offXMax",
      value: 10, min: 0, step: 1,
      x: 6, y: 1, width: 4, height: 1,
    },
    {
      class: "floatedit", name: "offYMin",
      value: 0, min: 0, step: 1,
      x: 0, y: 2, width: 3, height: 1
    },
    {
      class: "label", label: "<  y  <",
      x: 3, y: 2, width: 3, height: 1
    },
    {
      class: "floatedit", name: "offYMax",
      x: 6, y: 2, width: 4, height: 1,
      value: 10, min: 0, step: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 3, width: 10, height: 1
    },
    {
      class: "label", label: "Angle between subsequent line offsets:",
      x: 0, y: 4, width: 10, height: 1
    },
    {
      class: "label", label: "Min:",
      x: 0, y: 5, width: 1, height: 1
    },
    {
      class: "floatedit", name: "angleMin",
      value: 0, min: 0, max: 180, step: 1,
      x: 1, y: 5, width: 2, height: 1
    },
    {
      class: "label", label: "°    Max:",
      x: 3, y: 5, width: 3, height: 1
    },
    {
      class: "floatedit", name: "angleMax",
      value: 180, min: 0, max: 180, step: 1,
      x: 6, y: 5, width: 2, height: 1,
    },
    {
      class: "label", label: "°",
      x: 8, y: 5, width: 2, height: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 6, width: 10, height: 1
    },
    {
      class: "label", label: "Constraints:",
      x: 0, y: 7, width: 10, height: 1
    },
    {
      class: "dropdown", name: "signChgX",
      items: table.values(signChgModesSingle), value: signChgModesSingle.Any,
      x: 0, y: 8, width: 2, height: 1
    },
    {
      class: "label", label: "sign change for X offsets of subsequent lines.",
      x: 2, y: 8, width: 5, height: 1
    },
    {
      class: "dropdown", name: "signChgY",
      items: table.values(signChgModesSingle), value: signChgModesSingle.Any,
      x: 0, y: 9, width: 2, height: 1
    },
    {
      class: "label", label: "sign change for Y offsets of subsequent lines.",
      x: 2, y: 9, width: 5, height: 1
    },
    {
      class: "dropdown", name: "signChgCmb",
      items: table.values(signChgModesCmb), value: signChgModesCmb.Any,
      x: 0, y: 10, width: 2, height: 1
    },
    {
      class: "label", x: 2, y: 10, width: 5, height: 1
      label: "of the X and Y offsets must change sign between subsequent line.",
    },
    {
      class: "label", label: "",
      x: 0, y: 11, width: 10, height: 1
    },
    {
      class: "label", label: "Shake interval: every",
      x: 0, y: 12, width: 2, height: 1
    },
    {
      class:"intedit", name: "interval",
      value: 1, min: 1,
      x: 2, y: 12, width: 1, height: 1
    },
    {
      class: "label", label: "line(s)",
      x: 3, y: 12, width: 1, height: 1
    },
    {
      class: "label", label: "RNG Seed:",
      x: 0, y: 13, width: 1, height: 1
    },
    {
      class:"intedit", name: "seed",
      value: os.time!,
      x: 1, y: 13, width: 2, height: 1
    }
  }
  aegisub.cancel! unless btn

  -- fix up some user errors
  if res.offXMax < res.offXMin
    res.offXMin, res.offXMax = res.offXMax, res.offXMin

  if res.offYMax < res.offYMin
    res.offYMin, res.offYMax = res.offYMax, res.offYMin

  if res.angleMax < res.angleMin
    res.angleMin, res.angleMax = res.angleMax, res.angleMin

  -- check for conflicting constraints
  err = {"You have provided conflicting constraints: "}
  if res.signChgX == signChgModesSingle.Force and res.signChgY == signChgModesSingle.Force
    if res.angleMax < 90
      err[#err+1] = "Forced sign inversion for X and Y offsets require a maxium angle of at least 90°."
    if res.signChgCmb == signChgModesCmb.One
      err[#err+1] = "Can't limit signs to only one of the X and Y offsets because sign changes are separately enforced for both."

  elseif res.signChgX == signChgModesSingle.Prevent and res.signChgY == signChgModesSingle.Prevent
    if res.angleMin > 90
      err[#err+1] = "Can't prevent sign inversion for X and Y offsets when the minimum angle is larger than 90°."
    if res.signChgCmb == signChgModesCmb.Either
      err[#err+1] = "Can't change signs of either X or Y offsets because they are prevented for both."

  logger\assert #err == 1, table.concat err, "\n"

  lines = LineCollection sub, sel
  groups = groupLines lines, res.interval

  -- generate offsets for every line group, but don't apply them immediately in case the generator fails
  offsets = calculateOffsets #groups, makePositionOffsetGenerator res

  -- apply the position offsets to all line groups
  applyPositionShake lines, groups, offsets

shakeTag = (sub, sel) ->
  btn, res = aegisub.dialog.display {
    {
      class: "label", label: "Shaking Targets:",
      x: 0, y: 0, width: 6, height: 1
    },
    {
      class: "label", label: "Tag:",
      x: 0, y: 1, width: 1, height: 1
    },
    {
      class: "dropdown", name: "tag",
      items: table.pluck table.filter(ASS.tagMap, (tag) -> tag.type == ASS.Number and not tag.props.global), "overrideName"
      value: "\\frz",
      x: 1, y: 1, width: 1, height: 1
    },
    {
      class: "checkbox", name: 'LineBegin', label: tagShakeTargets.LineBegin,
      value: true,
      x: 0, y: 2, width: 6, height: 1
    },
    {
      class: "checkbox", name: 'ExistingTags', label: tagShakeTargets.ExistingTags,
      value: false,
      x: 0, y: 3, width: 6, height: 1
    },
    {
      class: "checkbox", name: 'TagSections', label: tagShakeTargets.TagSections,
      value: false,
      x: 0, y: 4, width: 6, height: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 5, width: 6, height: 1
    },
    {
      class: "label", label: "Shaking Offset Limits (relative to original tag value): ",
      x: 0, y: 6, width: 6, height: 1,
    },
    {
      class: "floatedit", name: "offTotalMin",
      value: 0, min: 0, step:1,
      x: 0, y: 7, width: 2, height: 1
    },
    {
      class: "label", label: "<  value  <",
      x: 2, y: 7, width: 1, height: 1
    },
    {
      class: "floatedit", name: "offTotalMax",
      value: 10, min: 0, step: 1,
      x: 3, y: 7, width: 2, height: 1,
    },
    {
      class: "label", label: "",
      x: 0, y: 8, width: 6, height: 1
    },
    {
      class: "label", label: "Change range between subsequent line group offsets:",
      x: 0, y: 9, width: 6, height: 1
    },
    {
      class: "label", label: "Min:",
      x: 0, y: 10, width: 1, height: 1
    },
    {
      class: "floatedit", name: "offTemporalMin",
      value: 0, min: 0, step: 1,
      x: 1, y: 10, width: 2, height: 1
    },
    {
      class: "label", label: "    Max:",
      x: 3, y: 10, width: 1, height: 1
    },
    {
      class: "floatedit", name: "offTemporalMax",
      value: 10, min: 0, step: 1,
      x: 4, y: 10, width: 2, height: 1,
    },
    {
      class: "label", label: "",
      x: 0, y: 11, width: 6, height: 1
    },
    {
      class: "label", label: "Constraints:",
      x: 0, y: 12, width: 6, height: 1
    },
    {
      class: "dropdown", name: "signChg",
      items: table.values(signChgModesSingle), value: signChgModesSingle.Any,
      x: 0, y: 13, width: 2, height: 1
    },
    {
      class: "label", label: "sign change for tag offsets of subsequent lines.",
      x: 2, y: 13, width: 4, height: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 14, width: 6, height: 1
    },
    {
      class: "label", label: "",
      x: 0, y: 15, width: 6, height: 1
    },
    {
      class: "label", label: "Shake interval: every",
      x: 0, y: 16, width: 1, height: 1
    },
    {
      class:"intedit", name: "interval",
      value: 1, min: 1,
      x: 1, y: 16, width: 2, height: 1
    },
    {
      class: "label", label: "group(s) / line(s)",
      x: 3, y: 16, width: 1, height: 1
    },
    {
      class: "label", label: "RNG Seed:",
      x: 0, y: 17, width: 1, height: 1
    },
    {
      class:"intedit", name: "seed",
      value: os.time!,
      x: 1, y: 17, width: 2, height: 1
    }
  }
  aegisub.cancel! unless btn

  -- fix up some user errors
  if res.offTotalMax < res.offTotalMin
    res.offTotalMin, res.offTotalMax = res.offTotalMax, res.offTotalMin

  if res.offTemporalMax < res.offTemporalMin
    res.offTemporalMin, res.offTemporalMax = res.offTemporalMax, res.offTemporalMin

  lines = LineCollection sub, sel
  groups = groupLines lines, res.interval
  groupCnt = #groups

  tagsByGroupAndLine, offsetCount = collectTags lines, groups, ASS.tagNames[res.tag][1], res
  offsets = calculateOffsets #groups, makeMultiOffsetGenerator res, offsetCount

  aegisub.progress.task "Shaking..."

  for g, group in ipairs groups
    aegisub.progress.set 50 + 50 * g/groupCnt
    aegisub.cancel! if aegisub.progress.is_cancelled!

    for tagsByLine in *tagsByGroupAndLine[g]
      -- TODO: support tags w/ > 1 parameter
      tag\add offsets[g][t] for t, tag in ipairs tagsByLine

    line.ASS\commit! for line in *group

  lines\replaceLines!


depCtrl\registerMacros {
  {"Shake Position", "Applies randomized offsets to line positioning.", shakePosition},
  {"Shake Tag", "Applies randomized offsets to a specified override tag.", shakeTag},
}
