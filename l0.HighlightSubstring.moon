export script_name = "Highlight Substring"
export script_description = "Highlights a substring at a given index in a line by underlaying a colored rectangle."
export script_version = "0.1.0"
export script_author = "line0"
export script_namespace = "l0.highlightSubstring"

DependencyControl = require "l0.DependencyControl"

rec = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingCartel/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.0.1", url: "https://github.com/torque/Aegisub-Motion"},
        {"l0.ASSFoundation", version: "0.1.2", url: "https://github.com/TypesettingCartel/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingCartel/ASSFoundation/master/DependencyControl.json"}
    }
}

LineCollection, ASS = rec\requireModules!

highlightSubstring = (sub, sel, res) ->
    lines = LineCollection sub, sel
    lines\runCallback (lines, line, i) ->
        -- outline should be below original, line must be at least at layer 1
        line.layer = math.min line.layer, 1
        data = ASS\parse line

        local splitLine
        if res.start <= 1
            -- can't split a line at position <= 1
            splitLine = (data\splitAtIndexes res.end+1)[1]
        else
            splitLine = (data\splitAtIndexes {res.start, res.end+1})[2]

        bounds = splitLine.ASS\getLineBounds!
        box, tags = ASS.Section.Drawing!, ASS.Section.Tag {
            ASS\createTag("position", 0, 0),
            ASS\createTag("align", 7),
            ASS\createTag("color", 0, 0, 255),
            ASS\createTag("alpha", 127),
            ASS\createTag("outline", 0),
            ASS\createTag("shadow", 0)
        }
        box\drawRect bounds[1], bounds[2]
        lines\addLine ASS\createLine{{tags, box}, data, layer: line.layer - 1}

    lines\replaceLines!
    lines\insertLines!

showDialog = (sub, sel) ->
    btn, res = aegisub.dialog.display {
        {class: "label",   label:"Start Index:", x: 0, y: 0, width: 1, height: 1},
        {class: "intedit", name: "start",        x: 1, y: 0, width: 1, height: 1, value: 1, min: 0},
        {class: "label",   label:"End Index:",   x: 0, y: 1, width: 1, height: 1},
        {class: "intedit", name: "end",          x: 1, y: 1, width: 1, height: 1, value: 1, min: 0}
    }

    -- idiot validation
    res.end = math.max(res.start, res.end)

    highlightSubstring sub, sel, res if btn


rec\registerMacro showDialog
