export script_name = "Merge Drawings"
export script_description = [[Moves all drawings found in all selected lines into the first line.
 Maintains positioning and converts scale as well as alignment.]]
export script_version = "0.2.0"
export script_author = "line0"
export script_namespace = "l0.MergeDrawings"

DependencyControl = require "l0.DependencyControl"

rec = DependencyControl{
  feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
  {
    {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"l0.ASSFoundation", version: "0.4.0", url: "https://github.com/TypesettingTools/ASSFoundation",
      feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"}
  }
}

LineCollection, ASS = rec\requireModules!
logger = rec\getLogger!

getScriptListDlg = (macros, modules) ->

mergeDrawings = (sub, sel, res, lines, lineCnt, targetLine) ->
  target = {name, ASS\createTag(name, value) for name, value in pairs res}
  mergedLines, targetSection = {}
  targetScaleX, targetScaleY = target.scale_x.value/100, target.scale_y.value/100

  lineCb = (lines, line, i) ->
    aegisub.cancel! if aegisub.progress.is_cancelled!
    aegisub.progress.task "Processed %d of %d lines..."\format i, lineCnt if i%10==0

    data = i==1 and targetLine or ASS\parse line
    pos, align = data\getPosition!
    tags = (data\getEffectiveTags -1, true, true, false).tags
    local haveTextSection

    data\callback (section) ->
      if section.class == ASS.Section.Drawing
        -- determine target drawing section to merge drawings into
        targetSection = section if i==1
        -- get a copy of the position tag which needs to be
        -- applied as an offset to the drawing
        off = pos.class == ASS.Tag.Move and pos.startPos\copy! or pos\copy!

        -- determine the top/left bounds of the drawing in order to make
        -- the drawing start at the coordinate origin
        bounds = section\getBounds!
        -- trim drawing in order to scale shapes without causing them to move
        section\sub bounds[1]
        -- add the scaled bounds to our offset
        scaleX, scaleY = tags.scale_x.value/100, tags.scale_y.value/100
        off\add bounds[1]\mul scaleX, scaleY
        facX, facY = scaleX / targetScaleX, scaleY / targetScaleY
        unless facX == 1 and facY == 1
          section\mul facX, facY
        -- now apply the position offset scaled by the target fscx/fscy values
        section\add off\div targetScaleX, targetScaleY

        -- set intermediate point of origin alignment
        unless align\equal 7
          ex = section\getExtremePoints true
          srcOff = align\getPositionOffset ex.w, ex.h
          section\sub srcOff

        if i > 1
          -- insert contours into first line, create a drawing section if none exists
          targetSection or= (targetLine\insertSections ASS.Section.Drawing!)[1]
          targetSection\insertContours section
          return false

      elseif section.class == ASS.Section.Text
        haveTextSection or= true

    if i > 1
      -- remove drawings from original lines and mark empty lines for deletion
      if haveTextSection then data\commit!
      else mergedLines[#mergedLines+1] = line

    aegisub.progress.set 100*i/lineCnt

  -- process all selected lines
  lines\runCallback lineCb, true

  -- update tags and aligment
  targetLine\replaceTags [tag for _,tag in pairs target]
  unless target.align\equal 7
    ex = targetSection\getExtremePoints true
    off = target.align\getPositionOffset ex.w, ex.h
    targetSection\add off

  pos, align = targetLine\getPosition!
  bounds = targetSection\getBounds!
  targetSection\sub bounds[1]
  if pos.class == ASS.Tag.Move
    pos.endPos\sub pos.startPos
    pos.endPos\add bounds[1]
    pos.startPos\set bounds[1].x, bounds[1].y
  else
    targetLine\replaceTags{ASS\createTag "position", bounds[1]}

  targetLine\commit!
  lines\replaceLines!
  lines\deleteLines mergedLines

showDialog = (sub, sel) ->
  lines = LineCollection sub, sel
  lineCnt = #lines.lines
  return if lineCnt == 0

  data = ASS\parse lines.lines[lineCnt] -- first line
  tags = (data\getEffectiveTags -1, true, true, false).tags
  scale_x, scale_y, align = tags.scale_x\get!, tags.scale_y\get!, tags.align\get!

  btn, res = aegisub.dialog.display {
    {
      class: "label", label: "Target Alignment: ",
      x: 0, y: 0, width: 1, height: 1
    },
    {
      class: "dropdown", name: "align",
      items: [i for i=1,9], value: align,
      x: 1, y: 0, width: 1, height: 1,
    },
    {
      class: "label", label: "Target Scale X: ",
      x: 0, y: 1, width: 1, height: 1
    },
    {
      class: "floatedit", name: "scale_x",
      min: 0.01, value: scale_x,
      x: 1, y: 1, width: 1, height: 1
    },
    {
      class: "label", label: "Target Scale Y: ",
      x: 0, y: 2, width: 1, height: 1
    },
    {
      class: "floatedit", name: "scale_y",
      min: 0.01, value: scale_y,
      x: 1, y: 2, width: 1, height: 1
    }
  }

  if btn
    mergeDrawings sub, sel, res, lines, lineCnt, data

rec\registerMacro showDialog
