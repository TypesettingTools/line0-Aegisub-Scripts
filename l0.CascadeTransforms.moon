export script_name = "Cascade Transforms"
export script_description = "Changes transforms in a line to be transformed in a consecutive fashion, with the transform time being split evenly."
export script_version = "0.1.0"
export script_author = "line0"
export script_namespace = "l0.CascadeTransforms"

DependencyControl = require "l0.DependencyControl"

rec = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.0.1", url: "https://github.com/torque/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.2.2", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"}
    }
}

LineCollection, ASS = rec\requireModules!

cascadeTransforms = (sub, sel) ->
    lines = LineCollection sub, sel
    lines\runCallback (lines, line, i) ->
        data = ASS\parse line
        transforms = data\getTags "transform"
        return if #transforms == 0
        interval = line.duration / #transforms
        start = 0
        for t in *transforms
            t.startTime\set start
            start += interval
            t.endTime\set start
        data\commit!

    lines\replaceLines!

rec\registerMacro cascadeTransforms
