export script_name = "Split Lines"
export script_description = "Splits a line while maintaining appearance."
export script_version = "0.1.0"
export script_author = "line0"
export script_namespace = "l0.SplitLines"

DependencyControl = require "l0.DependencyControl"

rec = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.0.1", url: "https://github.com/torque/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.ConfigHandler", version: "1.1.1", url: "https://github.com/torque/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.2.4", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        "aegisub.re"
    }
}

LineCollection, ConfigHandler, ASS, re = rec\requireModules!
logger = rec\getLogger!

exampleExpr = [[step = n / 20
x = x > step and x-step or n/5
i + max(x, 2)]]

hints = {
    interval: "The line will be split after the specified amount of characters."
    indexes: [[Enter a comma-separated 1-based list indexes into the original line.
The line will be split before the characters at the specified indexes (1 is not a valid split index).]]
    expr: [[Enter the Lua function body that will determine the next index to split the line at. The function will run multiple times until the end of the original line
has been hit. The index returned must be a number larger than the previously returned index (fractional values will be rounded up).
A return statement will be prepended to the last line when none was found. Math library functions can be called without 'math.' prefix
]]
}

dlgs = {
  splitAtEvenInterval: {
    intervalLabel: class: "label",   x: 0, y: 0, width: 1,  height: 1, label: "Interval: "
    interval:      class: "intedit", x: 1, y: 0, width: 1,  height: 1, min: 1, value: 5, config: true, hint: hints.interval
  },
  splitAtIndexes: {
    indexesLabel:  class: "label",   x: 0, y: 0, width: 1,  height: 1, label: "Indexes:"
    indexes:       class: "textbox", x: 0, y: 1, width: 10, height: 3, value: "2, 4, 9, 17", config: true, hint: hints.indexes
  },
  splitAtCustomInterval: {
    varsLabel:     class: "label",   x: 0, y: 0, width: 5,  height: 1, label: "Available variables:"
    varIdxLabel:   class: "label",   x: 1, y: 1, width: 4,  height: 1, label: "i: current index into original line"
    varLenLabel:   class: "label",   x: 1, y: 2, width: 4,  height: 1, label: "n: length of original line in characters"
    varCntLabel:   class: "label",   x: 1, y: 3, width: 4,  height: 1, label: "s: current count of split lines"
    varNumLabel:   class: "label",   x: 1, y: 4, width: 4,  height: 1, label: "x: a number initialized to 0 for your convenience"
    exprLabel:     class: "label",   x: 0, y: 6, width: 5,  height: 1, label: "Expression:"
    expr:          class: "textbox", x: 0, y: 7, width: 10, height: 5, value: exampleExpr, config: true, hint: hints.expr
  }
}

showDialog = (macro) ->
    options = ConfigHandler dlgs, rec.configFile, false, script_version, rec.configDir
    options\read!
    options\updateInterface macro
    btn, res = aegisub.dialog.display dlgs[macro]
    if btn
        options\updateConfiguration res, macro
        options\write!
        return res


splitLines = (sub, sel, mode, arg) ->
    lines = LineCollection sub, sel
    lineCnt = #lines.lines
    toDelete = {}
    -- cleaning level, adjust \pos, write \org if required to maintain appearance
    config = {4, true, true}

    cb = (lines, line, i) ->
        aegisub.cancel! if aegisub.progress.is_cancelled!
        data = ASS\parse line
        splits = switch mode
            when "interval" then data\splitAtIntervals arg, unpack config
            when "tags" then data\splitAtTags unpack config
            when "indexes" then data\splitAtIndexes arg, unpack config

        lines\addLine split for split in *splits
        toDelete[#toDelete+1] = line
        aegisub.progress.set 100*i/lineCnt

    lines\runCallback cb, true
    -- TODO: check why line order is off by one when we do it the other way around
    lines\insertLines!
    lines\deleteLines toDelete


splitAtEvenInterval = (sub, sel) ->
    if res = showDialog "splitAtEvenInterval"
        splitLines sub, sel, "interval", res.interval

splitAtIndexes = (sub, sel) ->
    if res = showDialog "splitAtIndexes"
        indexes = [tonumber(i) for i in res.indexes\gmatch "(%d+)[%s\\n,;|/]*"]
        splitLines sub, sel, "indexes", indexes

splitByChars = (sub, sel) ->
    splitLines sub, sel, "interval", 1

splitAtCustomInterval = (sub, sel) ->
    res = showDialog "splitAtCustomInterval"
    return unless res

    -- initialize isolated environment for loaded expression
    env = setmetatable {s: 0, x: 0}, {__index: (tbl, k) -> _G[k] or math[k]}

    -- add missing return on last line and compile expression into a function
    pattern = re.compile "[ \t]*(return )?([^\n]+$)", re.NO_MOD_M
    expr = load pattern\sub(res.expr, "return $2"), nil, "t", env

    -- split lines
    splitLines sub, sel, "interval", (i, n) ->
        env.i, env.n = i, n
        env.s += 1
        expr!

rec\registerMacros{
    {"Split by Characters", "Turns every character into a separate line.", splitByChars},
    {"Split at Even Interval", "Splits a line after every N characters.", splitAtEvenInterval},
    {"Split at Custom Interval", "Specify an expression to determine split indexes.", splitAtCustomInterval},
    {"Split at Indexes", "Manually specify a list of indexes the line will be split at.", splitAtIndexes},
    {"Split at Tags", "Splits a line before every tag section.", (sub, sel) ->  splitLines sub, sel, "tags"},
}