export script_name        = "Shake It"
export script_description = "Lets you add a shaking effect to fbf typesets with configurable constraints."
export script_version     = "0.1.0"
export script_author      = "line0"
export script_namespace   = "l0.ShakeIt"

DependencyControl = require "l0.DependencyControl"
dep = DependencyControl {
  feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
  {
    {"a-mo.LineCollection", version: "1.1.4", url: "https://github.com/torque/Aegisub-Motion",
     feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"l0.ASSFoundation", version:"0.3.3", url: "https://github.com/TypesettingTools/ASSFoundation",
     feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
    {"l0.Functional", version: "0.3.0", url: "https://github.com/TypesettingTools/Functional",
     feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"}
  }
}
LineCollection, ASS, functional = dep\requireModules!
{:list, :math, :string, :table, :unicode, :util, :re } = functional
logger = dep\getLogger!

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


hasLineRotation = (line) ->
  styleTags = line\getDefaultTags nil, false
  unless styleTags.tags.angle\equal 0
    return true
  line\modTags {"angle", "angle_x", "angle_y"}, (tag) ->
    return true

shakeItApply = (lines, groups) ->
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
        pos\add group.offX, group.offY, group.offX, group.offY
      else
        pos\add group.offX, group.offY
        if hasLineRotation data
          modifiedTags[2] = org
          org\add group.offX, group.offY

      data\replaceTags modifiedTags
      data\commit!

  lines\replaceLines!

getSingleSign = (mode, offPrev) ->
  ref = switch mode
    when signChgModesSingle.Prevent then offPrev
    when signChgModesSingle.Force then -offPrev
    else math.random! - 0.5
  return math.sign ref, true

makeOffsetGenerator = (res)  ->
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
        return offX, offY

    -- give up after so many rolls, because we're to lazy to actually do our maths
    -- and factor the constraints in when pulling our random numbers
    logger\error "ERROR: Couldn't find offset that satifies chosen angle constraints (Min: #{res.angleMin}°, Max: #{res.angleMax}° for group #{i}. Aborting."


shakeIt = (sub, sel) ->
  btn, res = aegisub.dialog.display {
    { class: "label",       x: 0, y: 0,  width: 10, height: 1,
      label: "Shaking Offset Limits (relative to original position): "
    },
    { class: "floatedit",   x: 0, y: 1,  width: 3,  height: 1,
      name:  "offXMin",     value: 0, min: 0, step:1
    },
    { class: "label",       x: 3, y: 1,  width: 3,  height: 1,
      label: "<  x  <"
    },
    { class: "floatedit",   x: 6, y: 1,  width: 4,  height: 1,
      name:  "offXMax",     value: 10, min: 0, step: 1
    },
    {
      class: "floatedit",   x: 0, y: 2,  width: 3,  height: 1,
      name:  "offYMin",     value: 0, min: 0, step: 1
    },
    { class: "label",       x: 3, y: 2,  width: 3,  height: 1,
      label: "<  y  <"
    },
    { class: "floatedit",   x: 6, y: 2,  width: 4,  height: 1
      name:  "offYMax",     value: 10, min: 0, step:1
    },
    { class: "label",       x: 0, y: 3,  width: 10, height: 1
      label: ""
    },
    { class: "label",       x: 0, y: 4,  width: 10, height: 1,
      label: "Angle between subsequent line offsets:",
    },
    { class: "label",       x: 0, y: 5,  width: 1,  height: 1,
      label: "Min:"
    },
    { class: "floatedit",   x: 1, y: 5,  width: 2,  height: 1,
      name:  "angleMin",    value: 0, min: 0, max: 180, step: 1
    },
    { class: "label",       x: 3, y: 5,  width: 3,  height: 1
      label: "°    Max:"
    },
    { class: "floatedit",   x: 6, y: 5,  width: 2,  height: 1,
      name:  "angleMax",    value: 180, min: 0, max: 180, step:1
    },
    { class: "label",       x: 8, y: 5,  width: 2, height: 1
      label: "°"
    },
    { class: "label",       x: 0, y: 6,  width: 10, height: 1
      label: ""
    },
    { class: "label",       x: 0, y: 7,  width: 10, height: 1
      label: "Constraints:"
    },
    { class: "dropdown",    x: 0, y: 8,  width: 2, height: 1,
      name:  "signChgX", items: table.values(signChgModesSingle), value: signChgModesSingle.Any
    },
    { class: "label",       x: 2, y: 8,  width: 5,  height: 1
      label: "sign change for X offsets of subsequent lines.",
    },
    { class: "dropdown",    x: 0, y: 9,  width: 2, height: 1,
      name:  "signChgY", items: table.values(signChgModesSingle), value: signChgModesSingle.Any
    },
    { class: "label",       x: 2, y: 9,  width: 5,  height: 1
      label: "sign change for Y offsets of subsequent lines.",
    },
    { class: "dropdown",    x: 0, y: 10, width: 2, height: 1,
      name:  "signChgCmb", items: table.values(signChgModesCmb), value: signChgModesCmb.Any
    },
    { class: "label",       x: 2, y: 10, width: 5,  height: 1
      label: "of the X and Y offsets must change sign between subsequent line.",
    },
    { class: "label",       x: 0, y: 11, width: 10, height: 1
      label: "",
    },
    { class: "label",       x: 0, y: 12, width: 1, height: 1,
      label: "RNG Seed:",
    },
    { class:"intedit",      x: 1, y: 12, width: 2, height: 1,
      name:"seed",          value:os.time()
    },
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

  -- collect selected lines and group by start time
  lines = LineCollection sub, sel
  lineCnt = #lines.lines
  groups = table.values list.groupBy(lines.lines, "start_time"), (grpA, grpB) ->
    return grpA[1].start_time < grpB[1].start_time

  -- generate offsets for every line group, but don't apply them immediately in case the generator fails
  generatePositionOffset = makeOffsetGenerator res
  aegisub.progress.task "Rolling..."
  for i, group in ipairs groups do
    aegisub.progress.set 50*i / #groups
    aegsiub.cancel! if aegisub.progress.is_cancelled!
    group.offX, group.offY = generatePositionOffset i != 1

  -- apply the position offsets to all line groups
  shakeItApply lines, groups

dep\registerMacro shakeIt