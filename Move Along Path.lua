script_name="Move Along Path"
script_description=""
script_version="0.0.1"
script_author="line0"

local l0Common = require("l0.Common")
local LineCollection = require("a-mo.LineCollection")
local ASSTags = require("l0.ASSTags")
local Log = require("a-mo.Log")
local YUtils = require("YUtils")

function showDialog(sub, sel)
    local dlg = {
        {
            class="label",
            label="Select which tags are to be animated\nalong the path specified as a \\clip:",
            x=0, y=0, width=2, height=1,
        },
        {
            class="label",
            label="Tag                 ",
            x=0, y=1, width=1, height=1,
        },
        {
            class="label",
            label="Relative",
            x=1, y=1, width=1, height=1,
        },
        {
            class="checkbox",
            name="aniPos", label="\\pos",
            x=0, y=2, width=1, height=1, value=true
        },
        {
            class="checkbox",
            name="relPos", label="",
            x=1, y=2, width=1, height=1,
        },
        {
            class="checkbox",
            name="aniFrz", label="\\frz",
            x=0, y=3, width=1, height=1, value=true
        },
        {
            class="checkbox",
            name="relFrz", label="",
            x=1, y=3, width=1, height=1,
        }
    }

    local btn, res = aegisub.dialog.display(dlg)
    if btn then process(sub,sel,res) end
end

function getLengthWithinBox(w, h, angle)
    if w==0 or h==0 then return 0
    elseif angle==0 then return w end

    angle = math.rad(angle%90 or 0)
    local A = math.atan2(w,h)
    local a, b = angle<A and w or h, angle<A and math.tan(angle)*w or h/math.tan(angle)
    return math.sqrt(a^2 + b^2)
end

function process(sub,sel,res)
    aegisub.progress.task("Processing...")

    local lines = LineCollection(sub,sel)

    -- get total duration of the fbf lines
    local totalDuration = -lines.lines[1].duration
    lines:runCallback(function(lines, line)
        totalDuration = totalDuration + line.duration
    end)

    local startDist, path, posOff, angleOff, totalLength = 0
    local finalLines = LineCollection(sub)

    lines:runCallback(function(lines, line, i)
        data = ASS.parse(line)
        if i==1 then -- get path data and relative position/angle from first line
            path = data:getTags("clip_vect")[1]
            data:removeTags("clip_vect")
            angleOff, posOff = path:getAngleAtLength(0), path.commands[1]:get()
            totalLength = path:getLength()
        end

        -- split line by characters
        local charLines, charOff = data:splitAtIntervals(1,4,false), 0
        for i=1,#charLines do
            local charData = charLines[i].ASS
            -- calculate new position and angle
            local targetPos, angle = path:getPositionAtLength(startDist+charOff), path:getAngleAtLength(startDist+charOff)
            if not targetPos then
                break   -- stop if he have reached the end of the path
            end 
            local effTags = charData:getEffectiveTags(-1,true,true).tags

            if res.aniPos then
                local pos = effTags.position
                if res.relPos then
                    pos:add(targetPos:sub(posOff))
                else pos:set(targetPos) end
                charData:removeTags("position")
                charData:insertTags(pos,1)
            end

            if res.aniFrz then
                local frz = effTags.angle
                if res.relFrz then
                    frz:add(angle-angleOff)
                else frz:set(angle) end
                charData:removeTags("angle")
                charData:insertTags(frz,1)
            end

            -- calculate how much "space" the character takes up on the line
            -- and determine the distance offset for the next character
            local metrics = charData:getMetrics()
            charOff = charOff + getLengthWithinBox(metrics.width, metrics.box_height, angle)

            charData:commit()
            finalLines:addLine(charLines[i])
        end
        startDist = startDist + (totalLength * (line.duration/totalDuration))
        aegisub.progress.set(i*100/#lines.lines)
    end, true)
    lines:deleteLines()
    finalLines:insertLines()
end

aegisub.register_macro(script_name, script_description, showDialog)
    
    