-- TODO: calc scale
script_name="Vertical Text"
script_description="Splits a line into vertical text."
script_version="0.1.2"
script_author="line0"
script_namespace="l0.VerticalText"

local DependencyControl = require("l0.DependencyControl")
local version = DependencyControl{
    feed = "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        {"a-mo.LineCollection", version="1.0.1", url="https://github.com/torque/Aegisub-Motion",
         feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.Log", url="https://github.com/torque/Aegisub-Motion",
         feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version="0.3.1", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"l0.ASSFoundation.Common", version="0.1.1", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        "Yutils"
    }
}
local LineCollection, Log, ASS, Common, Yutils = version:requireModules()

function showDialog(sub, sel)
    -- here be dialog
    process(sub,sel,res)
end


function process(sub,sel,res)
    aegisub.progress.task("Processing...")

    local lines = LineCollection(sub,sel)
    local finalLines = LineCollection(sub)

    function alignOffset(x, a)
        return math.abs(math.cos(math.rad(a))*x/2)
    end

    -- TODO: cache to disk
    local avgMetrics = {}

    lines:runCallback(function(lines, line, i)
        local data = ASS:parse(line)
        -- split line by characters
        local charLines, charOff = data:splitAtIntervals(1,4,false), 0
        for i=1,#charLines do
            local charData = charLines[i].ASS
            -- get tags effective as of the first section (we know there won't be any tags after that)
            local effTags = charData.sections[1]:getEffectiveTags(true,true).tags

            -- determine average width and height of glyphs for this font for vertical spacing generation
            local fontName = effTags.fontname:get()
            if not avgMetrics[fontName] then
                local start, end_, totalHeight, totalWidth, realCnt = 65, 122, 0, 0, 0
                local font = Yutils.decode.create_font(fontName, false, false, false, false, 100)
                for i=start,end_ do
                    x1,y1,x2,y2 = Yutils.shape.bounding(font.text_to_shape(string.char(i)))
                    if x1 then
                        totalHeight, totalWidth = totalHeight+y2-y1, totalWidth+x2-x1
                        realCnt = realCnt+1
                    end
                end
                avgMetrics[fontName] = {w=totalWidth/(realCnt), h=totalHeight/(realCnt)}
            end

            -- get font metrics
            local metrics = charData:getTextMetrics(true)

            -- since with \an5 the type is centered between ascender and baseline, we need to account
            -- for the descender and ascender separately
            local descender, ascender = math.max(metrics.bounds[4]-metrics.ascent,0), math.max(metrics.descent-metrics.bounds[2],0)

            -- calculate new position
            effTags.align:set(5)
            charData:removeTags("align")
            local an, frz = charData:insertTags(effTags.align,1):get(), effTags.angle:get()
            charOff = charOff + math.abs(math.cos(math.rad(frz)))*ascender

            effTags.position:add(0, charOff + alignOffset(metrics.bounds.h-math.max(metrics.bounds[2]-metrics.descent,0), frz)
                                            + alignOffset(metrics.width, frz+90))
            charData:removeTags("position")
            charData:insertTags(effTags.position,1)

            -- set position for the next character
            local spacing = 0.2*avgMetrics[fontName].h*effTags.fontsize:get()/100
            charOff = charOff + math.abs(math.cos(math.rad(frz)))*(metrics.bounds.h + spacing + descender)
                     + math.abs(math.sin(math.rad(frz)))*metrics.width

            charData:commit()
            finalLines:addLine(charLines[i])
        end
        aegisub.progress.set(i*100/#lines.lines)
    end, true)
    lines:deleteLines()
    finalLines:insertLines()
end

version:registerMacro(showDialog)