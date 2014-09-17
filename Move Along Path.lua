script_name="Move Along Path"
script_description=""
script_version="0.0.1"
script_author="line0"

local l0Common = require("l0.Common")
local LineCollection = require("a-mo.LineCollection")
local LineExtend = require("l0.LineExtend")
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

function process(sub,sel,res)
    local lines = LineCollection(sub,sel)
    -- get path and relative position from first line
    local firstLine = lines.lines[#lines.lines]
    local path = firstLine:getTags("clipVect")[1]
    firstLine:removeTag("clipVect")
    local posOff = path.commands[1]:get()
     
    local totalLength, totalDuration, currDistance, frzOff = path:getLength(), -lines.lines[1].duration, 0
    -- get total duration of the fbf lines
    lines:runCallback(function(lines, line)
        totalDuration = totalDuration + line.duration
    end)

    aegisub.progress.task("Processing...")
    lines:runCallback(function(lines, line, i)
        -- calculate new position and angle, TODO: only run when required
        local pos, frz = path:getPositionAtLength(currDistance), path:getAngleAtLength(currDistance)
        if i==1 then frzOff=frz end
        
        if res.aniPos then line:modTag("position", function(tags)
            if res.relPos then
                tags[1]:add(pos:sub(posOff))
            else tags[1]:set(pos) end
            return tags
        end, false) end

        if res.aniFrz then line:modTag("angleZ", function(tags)
            for _,tag in ipairs(tags) do
                if res.relFrz then
                    tag:add(frz-frzOff)
                else tag:set(frz) end
            end
            return tags
        end, false) end

        currDistance = currDistance + (totalLength * (line.duration/totalDuration))
        aegisub.progress.set(i*100/#lines.lines)
    end, true)
    lines:replaceLines()
end

aegisub.register_macro(script_name, script_description, showDialog)
    
    