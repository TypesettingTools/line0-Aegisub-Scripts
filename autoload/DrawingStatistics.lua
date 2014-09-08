script_name="Drawing Statistics"
script_description="Counts drawing commands, anchors and coordinates."
script_version="0.0.1"
script_author="line0"

local l0Common = require("l0.Common")
local LineCollection = require("a-mo.LineCollection")
local LineExtend = require("l0.LineExtend")
local YUtils = require("YUtils")

local metrics = {
    b = {coords=6, points=1},
    l = {coords=2, points=1},
    m = {coords=2, points=2},
    n = {coords=2, points=2}
}

function count(vectors)
    local drawing=ASSClipVect({vectors},{})
    local cmdCnts,pts,coords={},0,0

    for _,cmd in ipairs(drawing.commands) do
        if not cmdCnts[cmd.__tag.name] then
            cmdCnts[cmd.__tag.name] = {commands=0, points=0, coords=0}
        end
        cmdCnts[cmd.__tag.name].commands = cmdCnts[cmd.__tag.name].commands + 1
    end

    for cmd,cnts in pairs(cmdCnts) do
        cnts.points, cnts.coords = cnts.commands*metrics[cmd].points, cnts.commands*metrics[cmd].coords
    end

    return cmdCnts
end

function process(sub,sel)
    local lines = LineCollection(sub,sel)
    lines:runCallback(function(lines, line)
        local _,linePos = line.text:find("{.-\\p%d.-}")
        if linePos then
            aegisub.log("Drawing statistics for line " .. tostring("X") .. ":\n")
            local vectors = line.text:sub(linePos+1):match("[^{}]+")
            cmdCnts = count(vectors)
            totalCmds, totalPts, totalCoords = 0,0,0
            for cmd,cnts in pairs(cmdCnts) do
                totalCmds, totalPts, totalCoords = totalCmds+cnts.commands, totalPts+cnts.points, totalCoords+cnts.coords
                aegisub.log(string.format("-- %s: %d (%d points, %d coordinates)\n",cmd,cnts.commands, cnts.points, cnts.coords))
            end
            aegisub.log(string.format("Line Total: %d commands, %d points, %d coordinates, %d Bytes\n",totalCmds,totalPts,totalCoords,vectors:len()))            
            
            local flattened = YUtils.shape.flatten(vectors)
            cmdCntsFlat = count(flattened)
            totalCmdsFlat, totalPtsFlat, totalCoordsFlat = 0,0,0
            for cmd,cnts in pairs(cmdCntsFlat) do
                totalCmdsFlat, totalPtsFlat, totalCoordsFlat = totalCmdsFlat+cnts.commands, totalPtsFlat+cnts.points, totalCoordsFlat+cnts.coords
            end
            aegisub.log(string.format("Flattened Total: %d commands, %d points, %d coordinates, %d Bytes\n\n",totalCmdsFlat,totalPtsFlat,totalCoordsFlat,flattened:len()))       
    end
    end)
end

aegisub.register_macro(script_name, script_description, process)
