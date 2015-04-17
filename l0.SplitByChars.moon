export script_name = "Split Line By Characters"
export script_description = "Splits a line into a separate line for every character while maintaining appearance."
export script_version = "0.1.0"
export script_author = "line0"
export script_namespace = "l0.SplitByChars"

DependencyControl = require "l0.DependencyControl"

rec = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.0.1", url: "https://github.com/torque/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/master/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.2.4", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"}
    }
}

LineCollection, ASS, Common = rec\requireModules!

splitByChars = (sub, sel) ->
    lines = LineCollection sub, sel
    lineCnt = #lines.lines
    toDelete = {}

    cb = (lines, line, i) ->
        aegisub.cancel! if aegisub.progress.is_cancelled!
        data = ASS\parse line
        lines\addLine splitLine for splitLine in *data\splitAtIntervals 1, 4
        toDelete[#toDelete+1] = line
        aegisub.progress.set 100*i/lineCnt

    lines\runCallback cb, true
    -- TODO: check why line order is off by one when we do it the other way around
    lines\insertLines!
    lines\deleteLines toDelete

rec\registerMacro splitByChars