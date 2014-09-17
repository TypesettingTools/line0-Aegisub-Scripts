script_name="Nuke All Extradata"
script_description=""
script_version="0.0.1"
script_author="line0"

local l0Common = require("l0.Common")
local LineCollection = require("a-mo.LineCollection")

function process(sub,sel)
    local lines = LineCollection(sub,sel)
    lines:runCallback(function(lines, line)
        aegisub.log(string.format("Nuked %d sets of extradata from line %d\n",table.length(line.extra),line.humanizedNumber))
        line.extra={}
    end)
    lines:replaceLines()
end

aegisub.register_macro(script_name, script_description, process)
