script_name="Move Along Path"
script_description="Moves text along a path specified in a \\clip. Currently only works on fbf lines."
script_version="0.1.4"
script_author="line0"
script_namespace="l0.MoveAlongPath"

local DependencyControl = require("l0.DependencyControl")
local version = DependencyControl{
    feed = "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        "aegisub.util",
        {"a-mo.LineCollection", version="1.1.1", url="https://github.com/torque/Aegisub-Motion",
         feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.Line", version="1.4.3", url="https://github.com/TypesettingTools/Aegisub-Motion",
         feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.Log", url="https://github.com/torque/Aegisub-Motion",
         feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version="0.2.9", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"l0.ASSFoundation.Common", version="0.2.0", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        "Yutils"
    }
}
local util, LineCollection, Line, Log, ASS, Common, Yutils = version:requireModules()

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
    if angle==A then return Yutils.math.distance(w,h)
    else
        local a,b = angle<A and w or h, angle<A and math.tan(angle)*w or h/math.tan(angle)
        return Yutils.math.distance(a,b)
    end
end

function process(sub,sel,res)
    aegisub.progress.task("Processing...")

    local lines, id = LineCollection(sub,sel), util.uuid()

    -- get total duration of the fbf lines
    local totalDuration = -lines.lines[1].duration
    lines:runCallback(function(lines, line)
        totalDuration = totalDuration + line.duration
    end)

    local startDist, metricsCache, path, posOff, angleOff, totalLength = 0, {}
    local linesToDelete, lineCnt, finalLineCnt, firstLineNum = {}, #lines.lines, 0
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
        if aegisub.progress.is_cancelled() then
            aegisub.cancel()
        end

        linesToDelete[i] = line
        local data, orgText = ASS:parse(line), line.text
        if i==1 then -- get path data and relative position/angle from first line
            path = data:getTags({"clip_vect","iclip_vect"})[1]
            assert(path,"Error: couldn't find \\clip containing path in first line, aborting.")
            data:removeTags({"clip_vect","iclip_vect"})
            angleOff, posOff = path:getAngleAtLength(0), path.contours[1].commands[1]:get()
            totalLength = path:getLength()
            firstLineNum = line.number
        end

        if res.reverseLine then data:reverse() end

        -- split line by characters
        local charLines, charOff = data:splitAtIntervals(1,4,false), 0
        for j=1,#charLines do
            local charData, length = charLines[j].ASS, startDist+charOff
            -- get font metrics
            local w = charData:getTextExtents()
            -- calculate new position and angle
            local targetPos, angle = path:getPositionAtLength(length,true), path:getAngleAtLength(length+w/2,true) or path:getAngleAtLength(length,true)
            -- stop processing this frame if he have reached the end of the path
            if not targetPos then
                break
            end
            -- get tags effective as of the first section (we know there won't be any tags after that)
            local effTags = charData.sections[1]:getEffectiveTags(true,true,false).tags

            -- calculate final rotation and write tags
            if res.aniFrz then
                charData:removeTags("angle")
                if res.flipFrz then angle:add(180) end
                charData:insertTags(angle,1)
            end

            -- calculate how much "space" the character takes up on the line
            -- and determine the distance offset for the next character
            -- this currently only uses horizontal metrics so it breaks if you disable rotation animation
            charOff = charOff + w

            if res.aniPos then
                local an = effTags.align:get()
                targetPos:add(alignOffset[an%3](w,angle.value), alignOffset[an%3](w,angle.value+90))
                if res.relPos then
                    targetPos:sub(posOff)
                    targetPos:add(effTags.position)
                end
                charData:removeTags("position")
                charData:insertTags(targetPos,1)
            end

            charData:commit()
            if charData:getLineBounds(true).w ~= 0 then
                local extra = {settings = res, id = id, orgLine = j==1 and orgText or nil}
                charLines[j]:setExtraData(version.namespace, extra)
                lines:addLine(charLines[j], nil, true, firstLineNum + finalLineCnt)
                finalLineCnt = finalLineCnt + 1
            end
        end

        local framePct = res.cfrMode and 1 or lineCnt*line.duration/totalDuration
        local time = (i^res.accel)/(lineCnt^res.accel)
        startDist = util.interpolate(time*framePct, 0, totalLength)
        aegisub.progress.set(i*100/lineCnt)
    end, true)
    lines:deleteLines(linesToDelete)
    lines:insertLines()
end

function hasClip(sub, sel, active)
    local firstLine = Line(sub[sel[1]])
    local data = ASS:parse(firstLine)
    if #data:getTags({"clip_vect","iclip_vect"}) <1 then
        return false, "No \\clip or \\iclip containing the path found in first line of the selection."
    else return true end
end

function hasUndoData(sub, sel, active)
    for i=1,#sel do
        if sub[sel[i]].extra and sub[sel[i]].extra[script_namespace] then
            return true
        end
    end
    return false
end

function undo(sub, sel)
    local ids, toDelete, j = {}, {}, 1
    for i=1,#sel do
        local extra = sub[sel[i]].extra and json.decode(sub[sel[i]].extra[script_namespace])
        ids[extra and extra.id] = true
    end
    sel = {}
    for i=1,#sub do
        local extra = sub[i].extra and json.decode(sub[i].extra[script_namespace] or "")
        if extra and ids[extra.id] then
            if extra.orgLine then
                sel[j], j = i, j+1
            else toDelete[#toDelete+1]=i end
        end
    end
    local lines = LineCollection(sub,sel)
    lines:runCallback(function(lines,line,i)
        line.text = line:getExtraData(script_namespace).orgLine
        line.extra[script_namespace]=nil
    end)
    lines:replaceLines()
    sub.delete(toDelete)
end

version:registerMacros{
    {script_name, nil, showDialog, hasClip},
    {"Undo", nil, undo, hasUndoData}
}