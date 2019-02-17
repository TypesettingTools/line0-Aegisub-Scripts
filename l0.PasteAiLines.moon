export script_name = "Paste AI Lines"
export script_description = "Convenience macro for pasting full lines exported by AI2ASS."
export script_version = "0.2.0"
export script_author = "line0"
export script_namespace = "l0.PasteAILines"

DependencyControl = require "l0.DependencyControl"
depCtrl = DependencyControl {
  feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
  {
    "aegisub.clipboard",
    {"a-mo.LineCollection", version: "1.0.1", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"a-mo.ConfigHandler", version: "1.1.1", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"l0.ASSFoundation", version: "0.4.0", url: "https://github.com/TypesettingTools/ASSFoundation",
      feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
    {"l0.Functional", version: "0.5.0", url: "https://github.com/TypesettingTools/Functional",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"},
  }
}

clipboard, LineCollection, ConfigHandler, ASS, Functional = depCtrl\requireModules!
{:list, :math, :string, :table, :unicode, :util, :re } = Functional
logger = depCtrl\getLogger!

dlg = {
  main: {
    aiLinesRaw: {
      class: "textbox",
      text: aiLinesRaw,
      x: 0, y: 0, width: 4, height: 5
    },
    trimDrawing: {
      class: "checkbox", label: "Trim drawings", hint: "Makes drawings start at the top left point of their bounding box instead of at 0,0.",
      value: true, config: true, x: 0, y: 5, width: 2, height: 1,
    },
    trimAlignLabel: {
      class: "label", label: "Alignment: ",
      x: 1, y: 6,  width: 1, height: 1
    },
    trimAlign: {
      class: "dropdown",
      value: 5, config: true, items: {1,2,3,4,5,6,7,8,9},
      x: 2, y: 6,  width: 1, height: 1
    },
    offsetLayers: {
      class: "checkbox", label: "Offset layers",
      value: true, config: true,
      x: 0, y: 7,  width: 2, height: 1
    },
    offsetModeLabel: {
      class: "label", label: "Mode: "
      x: 1, y: 8,  width: 1, height: 1
    },
    offsetMode: {
      class: "dropdown",
      value: "auto", config: true, items: {"auto","offset", "unique"},
      x: 2, y: 8,  width: 1, height: 1
    },
    offsetValueLabel: {
      class: "label", label: "Offset:",
      x: 1, y: 9,  width: 1, height: 1
    },
    offsetValue: {
      class: "intedit",
      value: 0, config: true,
      x: 2, y: 9, width: 1, height: 1
    },
    setStyle: {
      class: "checkbox", label: "Set Style",
      value: false,  config: true,
      x: 0, y: 10, width: 2, height: 1
    },
    styleNameLabel: {
      class: "label", label: "Name: ",
      x: 1, y: 11, width: 1, height: 1
    },
    styleName: {
      class: "edit",
      value: "AI", config: true,
      x: 2, y: 11, width: 2, height: 1
    },
    copyTimes: {
      class: "checkbox", label: "Copy times from selection",
      value: true, config: true,
      x: 0, y: 12, width: 2, height: 1
    },
    removeActor: {
      class: "checkbox", label: "Remove layer name from actor field.",
      value: false,  config: true,
      x: 0, y: 13, width: 3, height: 1
    }
  }
}

pasteAILines = (sub,sel,res) ->
  lines = LineCollection(sub,sel)
  maxLayer, endTime, startTime = 0, 0

  if res.copyTimes or res.offsetLayers
    lines\runCallback (_, line) ->
        endTime = math.max endTime, line.end_time
        startTime = math.min startTime or line.start_time, line.start_time
        if res.offsetMode == "auto" or res.offsetMode == "unique"
          maxLayer = math.max maxLayer, line.layer,
      true

  aiLinesRaw = string.split res.aiLinesRaw, "\n"
  aiLines = LineCollection sub
  firstSel, sel, lineCnt = sel[1], {}, #aiLinesRaw
  for i = 1, lineCnt
    aiLine = ASS\createLine {
      aiLinesRaw[i], lines,
      number: firstSel + lineCnt-i+1,
      style: res.setStyle and res.styleName or nil,
      actor: res.removeActor and "" or nil,
      start_time: res.copyTimes and startTime or 0,
      end_time: res.copyTimes and endTime or 0
    }

    -- trim drawings by moving the top left coordinate of the bounding box to the drawing origin
    if res.trimDrawing
      local off
      aiLine.ASS\callback (sect) ->
          off = sect\alignToOrigin res.trimAlign,
        ASS.Section.Drawing

      -- set alignment and position accordingly
      aiLine.ASS\replaceTags {
        ASS\createTag "align", res.trimAlign,
        ASS\createTag "position", off
      }
      aiLine.ASS\commit!

    aiLines\addLine aiLine, nil, true, true

  -- process layer numbers
  if res.offsetLayers
    local minAiLayer
    aiLines\runCallback (_, line, i) ->
        line.layer = switch res.offsetMode
          when "auto"
            minAiLayer or= line.layer
            line.layer - minAiLayer + res.offsetValue + maxLayer + 1
          when "unique"
            lineCnt-i + res.offsetValue + maxLayer + 1
          else line.layer + res.offsetValue,
      true

  aiLines\insertLines!
  return aiLines\getSelection!

showDialog = (sub, sel) ->
  options = ConfigHandler dlg, depCtrl.configFile, false, script_version, depCtrl.configDir
  dlg.main.aiLinesRaw.text = clipboard\get!
  options\read!
  options\updateInterface "main"
  btn, res = aegisub.dialog.display dlg.main
  if btn
    options\updateConfiguration res, "main"
    options\write!
    pasteAILines sub, sel, res

runSilently = (sub, sel) ->
  options = ConfigHandler dlg, depCtrl.configFile, false, script_version, depCtrl.configDir
  options\read!
  res = options.configuration.main
  res.aiLinesRaw = clipboard\get!
  pasteAILines sub, sel, res

depCtrl\registerMacros {
  {"Open Menu", nil, showDialog},
  {"Paste from Clipboard", nil, runSilently}
}
