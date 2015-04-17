script_name="Paste AI Lines"
script_description="Convenience macro for pasting full lines exported by AI2ASS."
script_version="0.1.2"
script_author="line0"
script_namespace="l0.PasteAILines"

local DependencyControl = require("l0.DependencyControl")
local version = DependencyControl{
    feed = "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        "aegisub.util", "aegisub.clipboard",
        {"a-mo.LineCollection", version="1.0.1", url="https://github.com/torque/Aegisub-Motion",
         feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.ConfigHandler", version="1.1.1", url="https://github.com/torque/Aegisub-Motion",
         feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.Log", url="https://github.com/torque/Aegisub-Motion",
         feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version="0.1.1", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"l0.ASSFoundation.Common", version="0.1.1", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"}
    }
}
local util, clipboard, LineCollection, ConfigHandler, Log, ASS, Common = version:requireModules()

local dlg = {
    main = {
        aiLinesRaw =        { class="textbox",  x=0, y=0,  width=4, height=5,
                              text=aiLinesRaw},
        trimDrawing =       { class="checkbox", x=0, y=5,  width=2, height=1, value=true,   config=true,
                              label="Trim drawings", hint="Makes drawings start at the top left point of their bounding box instead of at 0,0." },
        trimAlignLabel =    { class="label",    x=1, y=6,  width=1, height=1,
                              label="Alignment: "                                                     },
        trimAlign =         { class="dropdown", x=2, y=6,  width=1, height=1, value=5,      config=true,
                              items = {1,2,3,4,5,6,7,8,9}                                             },
        offsetLayers =      { class="checkbox", x=0, y=7,  width=2, height=1, value=true,   config=true,
                              label="Offset layers"                                                   },
        offsetModeLabel =   { class="label",    x=1, y=8,  width=1, height=1,
                              label="Mode: "                                                          },
        offsetMode =        { class="dropdown", x=2, y=8,  width=1, height=1, value="auto", config=true,
                              items={"auto","offset", "unique"}                                       },
        offsetValueLabel =  { class="label",    x=1, y=9,  width=1, height=1,
                              label="Offset: "                                                         },
        offsetValue =       { class="intedit",  x=2, y=9,  width=1, height=1, value=0,      config=true},
        setStyle =          { class="checkbox", x=0, y=10, width=2, height=1, value=false,  config=true,
                              label="Set Style"                                                       },
        styleNameLabel =    { class="label",    x=1, y=11, width=1, height=1,
                              label="Name: "                                                          },
        styleName =         { class="edit",     x=2, y=11, width=2, height=1, value="AI",   config=true},
        copyTimes =         { class="checkbox", x=0, y=12, width=2, height=1, value=true,   config=true,
                              label="Copy times from selection"                                       },
        removeActor =       { class="checkbox", x=0, y=13, width=3, height=1, value=false,  config=true,
                              label="Remove layer name from actor field."                             }
    }
}

function showDialog(sub, sel)
    local options = ConfigHandler(dlg, version.configFile, false, script_version, version.configDir)
    dlg.main.aiLinesRaw.text = clipboard:get()
    options:read()
    options:updateInterface("main")
    local btn, res = aegisub.dialog.display(dlg.main)
    if btn then
        options:updateConfiguration(res, "main")
        options:write()
        pasteAILines(sub, sel, res)
    end
end

function runSilently(sub, sel)
    local options = ConfigHandler(dlg, version.configFile, false, script_version, version.configDir)
    options:read()
    local res = options.configuration.main
    res.aiLinesRaw = clipboard:get()
    pasteAILines(sub, sel, res)
end

function pasteAILines(sub,sel,res)
    local lines, maxLayer, endTime, startTime = LineCollection(sub,sel), 0, 0
    if res.copyTimes or res.offsetLayers then
        lines:runCallback(function(_, line)
            endTime, startTime = math.max(endTime, line.end_time), math.min(startTime or line.start_time, line.start_time)
            if res.offsetMode=="auto" or res.offsetMode=="unique" then
                maxLayer = math.max(maxLayer, line.layer) end
        end, true)
    end

    local aiLinesRaw, aiLines = res.aiLinesRaw:split("\n"), LineCollection(sub)
    local firstSel, sel, lineCnt = sel[1], {}, #aiLinesRaw
    for i=1,lineCnt do
        local aiLine = ASS:createLine{aiLinesRaw[i], lines, number=firstSel+lineCnt-i+1,
                                      style=res.setStyle and res.styleName or nil,
                                      actor=res.removeActor and "" or nil,
                                      start_time=res.copyTimes and startTime or 0,
                                      end_time=res.copyTimes and endTime or 0}


        -- trim drawings by moving the top left coordinate of the bounding box to the drawing origin
        if res.trimDrawing then
            local off
            aiLine.ASS:callback(function(sect)
                off = sect:alignToOrigin(res.trimAlign)
            end, ASS.Section.Drawing)
            -- set alignment and position accordingly
            aiLine.ASS:replaceTags{ASS:createTag("align", res.trimAlign), ASS:createTag("position", off)}
            aiLine.ASS:commit()
        end

        aiLines:addLine(aiLine, nil, true, true)
    end

    -- process layer numbers
    if res.offsetLayers then
        local minAiLayer
        aiLines:runCallback(function(_, line, i)
            if res.offsetMode == "auto" then
                -- AI2ASS always exports from highest->lowest layer and we process them in reverse
                minAiLayer = minAiLayer or line.layer
                line.layer = line.layer - minAiLayer + res.offsetValue + maxLayer + 1
            elseif res.offsetMode =="unique" then
                line.layer = lineCnt-i + res.offsetValue + maxLayer + 1
            else line.layer = line.layer + res.offsetValue end
        end, true)
    end
    aiLines:insertLines()
    return aiLines:getSelection()
end

version:registerMacros{
    {"Open Menu", nil, showDialog},
    {"Paste from Clipboard", nil, runSilently}
}