script_name="Insert Line Breaks"
script_description="Inserts hard line breaks after n characters, but tries to avoid breaking up words."
script_version="0.1.1"
script_author="line0"
script_namespace="l0.InsertLineBreaks"

local DependencyControl = require("l0.DependencyControl")
local version = DependencyControl{
    feed = "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        "aegisub.util", "aegisub.re", "aegisub.unicode",
        {"a-mo.LineCollection", version="1.0.1", url="https://github.com/torque/Aegisub-Motion",
         feed = "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version="0.1.1", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"l0.ASSFoundation.Common", version="0.1.1", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"}
    }
}
local util, re, unicode, LineCollection, ASS, Common = version:requireModules()

function showDialog(sub, sel)
    local dlg = {
        {
            class="label", label="Insert \\N after",
            x=0, y=0, width=1, height=1
        },
        {
            class="intedit", name="charLimit",
            x=1, y=0, width=1, height=1, value=35
        },
        {
            class="label", label="characters",
            x=2, y=0, width=1, height=1
        },
    }

    local btn, res = aegisub.dialog.display(dlg)
    if btn then insertLineBreaks(sub,sel,res) end
end

function insertLineBreaks(sub,sel,res)
    local lines = LineCollection(sub,sel)
    local curCnt, expr = res.charLimit, re.compile("\\s(?!.*\\s)")
    lines:runCallback(function(lines, line)
        local data = ASS:parse(line)
        data:callback(function(section)
            local j, n, len, split = 1, 1, unicode.len(section.value), {}
            while j<=len do
                local splitLen = math.min(curCnt,len-j+1)
                split[n], j = unicode.sub(section.value, j, j+splitLen-1), j+curCnt
                if splitLen-curCnt == 0 then
                    curCnt = res.charLimit
                    -- if the next character is a whitespace character, replace it with a line break
                    if re.match(unicode.sub(section.value,j,j), "\\s") then
                        j, split[n+1] = j+1, "\\N"
                    -- if it isn't, find the last whitespace character in our last <= n chars section
                    else
                        local matches = expr:find(split[n])
                        -- found one -> place the line break there and add the character count after that position
                        -- to the char count of the next section
                        if matches then
                            local pos = matches[1].last
                            split[n], split[n+1], split[n+2] = unicode.sub(split[n],1,pos-1), "\\N", unicode.sub(split[n],pos+1)
                            curCnt, n = curCnt-unicode.len(split[n+2]), n+1
                        -- no whitespace character found -> force the line break at n chars
                        else split[n+1] = "\\N" end
                    end
                    n=n+1
                end
                n=n+1
            end
            section.value = table.concat(split)
        end, ASS.Section.Text)
        data:commit()
    end)
    lines:replaceLines()
end
version:registerMacro(showDialog)