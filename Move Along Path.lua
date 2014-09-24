script_name="Move Along Path"
script_description="Moves text along a path specified in a \\clip. Currently only works on fbf lines."
script_version="0.1.0"
script_author="line0"

local l0Common = require("l0.Common")
local LineCollection = require("a-mo.LineCollection")
local ASSTags = require("l0.ASSTags")
local Log = require("a-mo.Log")
local YUtils = require("YUtils")
local util = require("aegisub.util")

function showDialog(sub, sel)
    local dlg = {
        {
            class="label", label="Select which tags are to be animated along the path specified as a \\clip:",
            x=0, y=0, width=8, height=1,
        },
        {
            class="checkbox", name="aniPos", label="Animate Position:",
            x=0, y=1, width=4, height=1, value=true
        },
        {
            class="label", label="Acceleration:",
            x=4, y=1, width=3, height=1,
        },
        {
            class="floatedit", name="accel", 
            x=7, y=1, width=1, height=1, value=1.0, step=0.1
        },
        {
            class="checkbox", name="relPos", label="Offset existing position",
            x=4, y=2, width=4, height=1, value=false
        },
        {
            class="checkbox", name="cfrMode", label="CFR mode (ignores frame timings)",
            x=4, y=3, width=4, height=1, value=true
        },
        {
            class="checkbox",
            name="aniFrz", label="Animate Rotation",
            x=0, y=5, width=4, height=1, value=true
        },
        {
            class="checkbox",
            name="flipFrz", label="Rotate final lines by 180°",
            x=4, y=5, width=4, height=1, value=false
        },
        {
            class="label", label="Options:",
            x=0, y=7, width=4, height=1, value=false
        },
        {
            class="checkbox", name="reverseLine", label="Reverse Line Contents",
            x=4, y=7, width=4, height=1, value=false
        }
    }

    local btn, res = aegisub.dialog.display(dlg)
    if btn then process(sub,sel,res) end
end

function getLengthWithinBox(w, h, angle)   -- currently unused because only horizontal metrics are being used
    angle = angle%180
    angle = math.rad(angle>90 and 180-angle or angle)

    if w==0 or h==0 then return 0
    elseif angle==0 then return w
    elseif angle==90 then return h end

    local A = math.atan2(h,w)
    if angle==A then return YUtils.math.distance(w,h)
    else
        local a,b = angle<A and w or h, angle<A and math.tan(angle)*w or h/math.tan(angle)
        return YUtils.math.distance(a,b)
    end
end

function process(sub,sel,res)
    aegisub.progress.task("Processing...")

    local lines = LineCollection(sub,sel)

    -- get total duration of the fbf lines
    local totalDuration = -lines.lines[1].duration
    lines:runCallback(function(lines, line)
        totalDuration = totalDuration + line.duration
    end)

    local startDist, metricsCache, path, posOff, angleOff, totalLength = 0, {}
    local finalLines, lineCnt = LineCollection(sub), #lines.lines
    local alignOffset = {
        [0] = function(w,a) return math.cos(math.rad(a))*w end,    -- right
        [1] = function() return 0 end,                             -- left
        [2] = function(w,a) return math.cos(math.rad(a))*w/2 end,  -- center
    }

    -- currently unused because gets too few hits in test case scenearios
    --[[
    local posAtLengthCache = {}
    function posAtLengthCache:insert(key, val)
        self[key] = val
        return val
    end
    ]]--

    lines:runCallback(function(lines, line, i)
        data = ASS.parse(line)
        if i==1 then -- get path data and relative position/angle from first line
            path = data:getTags({"clip_vect","iclip_vect"})[1]
            assert(path,"Error: couldn't find \\clip containing path in first line, aborting.")
            data:removeTags({"clip_vect","iclip_vect"})
            angleOff, posOff = path:getAngleAtLength(0), path.commands[1]:get()
            totalLength = path:getLength()
        end

        if res.reverseLine then data:reverse() end

        -- split line by characters
        local charLines, charOff = data:splitAtIntervals(1,4,false), 0
        for i=1,#charLines do
            local charData, length = charLines[i].ASS, startDist+charOff
            -- calculate new position and angle
            local targetPos, angle = path:getPositionAtLength(length,true), path:getAngleAtLength(length,true)
            -- stop processing this frame if he have reached the end of the path
            if not targetPos then
                break   
            end
            -- get tags effective as of the first section (we know there won't be any tags after that)
            local effTags = charData.sections[1]:getEffectiveTags(true,true).tags

            -- calculate final rotation and write tags
            if res.aniFrz then
                effTags.angle:set((angle + (res.flipFrz and 180 or 0)%360))
                charData:removeTags("angle")
                charData:insertTags(effTags.angle,1)
            end 

            -- get font metrics
            local w = charData:getTextExtents()

            -- calculate how much "space" the character takes up on the line
            -- and determine the distance offset for the next character
            -- this currently only uses horizontal metrics so it breaks if you disable rotation animation  
            charOff = charOff + w

            if res.aniPos then
                local an = effTags.align:get()
                targetPos:add(alignOffset[an%3](w,angle), alignOffset[an%3](w,angle+90))
                local pos = effTags.position
                if res.relPos then
                    pos:add(targetPos:sub(posOff))
                else pos:set(targetPos) end
                charData:removeTags("position")
                charData:insertTags(pos,1)
            end

            charData:commit()
            finalLines:addLine(charLines[i])
        end

        local framePct = res.cfrMode and 1 or lineCnt*line.duration/totalDuration
        local time = (i^res.accel)/(lineCnt^res.accel)
        startDist = util.interpolate(time*framePct, 0, totalLength)
        aegisub.progress.set(i*100/lineCnt)
    end, true)
    lines:deleteLines()
    finalLines:insertLines()
end

aegisub.register_macro(script_name, script_description, showDialog)
    
    