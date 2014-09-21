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
    angle = angle%180
    angle =  math.rad(angle>90 and 180-angle or angle)

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
    local finalLines = LineCollection(sub)
    local alignOffset = {
        [0] = function(w) return w end,    -- right
        [1] = function() return 0 end,                       -- left
        [2] = function(w) return w/2 end -- center
    }

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
            local __atLength = startDist+charOff
            local targetPos, angle = path:getPositionAtLength(startDist+charOff), path:getAngleAtLength(startDist+charOff)
            if not targetPos then
                break   -- stop if he have reached the end of the path
            end

            -- get tags effective as of the first section (we know there won't be any tags after that)
            local effTags = charData.sections[1]:getEffectiveTags(true,true).tags

            -- calculate final rotation first, because the metrics depend on it
            local frz
            if res.aniFrz then
                frz = effTags.angle
                if res.relFrz then
                    frz:add(angle-angleOff)
                else frz:set(angle) end
                charData:removeTags("angle")
                charData:insertTags(frz,1)
            end 

            -- get font metrics and cache them
            local metricsCacheKey = table.concat({charData.sections[2].value, effTags.fontname:get(),effTags.fontsize:get(), effTags.bold:getTagParams(),
                 effTags.italic:getTagParams(), effTags.underline:getTagParams(), effTags.strikeout:getTagParams(), effTags.fontsize:get(), 
                 effTags.scale_x:get(), effTags.scale_y:get(), effTags.spacing:get(), res.aniFrz and math.round(frz:get(),0) or nil})

            local metrics = metricsCache[metricsCacheKey]
            if not metrics then
                metrics = charData:getMetrics()
                metricsCache[metricsCacheKey] = metrics
            end

            -- calculate how much "space" the character takes up on the line
            -- and determine the distance offset for the next character
            local w, h = metrics.box_width, metrics.box_height  -- TODO: use horizontal metrics (.width) and make up some good vertical metrics
            charOff = charOff + getLengthWithinBox(w, h, angle)

            if res.aniPos then
                targetPos:add(alignOffset[effTags.align:get()%3](w),0)
                local pos = effTags.position
                if res.relPos then
                    pos:add(targetPos:sub(posOff))
                else pos:set(targetPos) end
                charData:removeTags("position")
                charData:insertTags(pos,1)
            end

            charData:commit()

            -- debug logging
            charData:insertSections(ASSLineCommentSection(string.format("BoxW: %d BoxH: %d Angle: %d charOffAfter: %d atLength: %d shape: %s",
            metrics.box_width, metrics.box_height, angle, charOff, __atLength, metrics.shape)))
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
    
    