script_name="ASSWipe"
script_description="Cleans up tags."
script_version="0.0.1"
script_author="line0"

local LineCollection = require("a-mo.LineCollection")
local ASSTags = require("l0.ASSTags")
local Log = require("a-mo.Log")

function clean(sub,sel,res)
    
    aegisub.progress.task("Cleaning...") 
    local lines, cleanCnt, bytes = LineCollection(sub,sel), 0, 0
    local debugError, startTime, lineCnt = false, os.time(), #lines.lines

    lines:runCallback(function(lines, line, i)
        if aegisub.progress.is_cancelled() then
            aegisub.cancel()
        end

        local data, oldText = ASS.parse(line), line.text
        local oldBounds = data:getLineBounds(false)
        data:cleanTags(4)
        data:commit()
        local newBounds = data:getLineBounds(false)
        if oldText~=line.text then
            if not newBounds:equal(oldBounds) then
                debugError = true
                Log.warn("Cleaning affected output on line #%d, rolling back...", line.humanizedNumber)
                Log.warn("--- Before: %s\n--- After: %s\n--- Style: %s\n", oldText, line.text, line.styleRef.name)
                line.text = oldText
            else 
                cleanCnt, bytes = cleanCnt+1, bytes + #oldText - #line.text 
            end
            aegisub.progress.set(100*i/lineCnt)
        end
    end, true)
    lines:replaceLines()
    if debugError then Log.dump(lines.styles) end
    Log.warn("Done. Cleaned %d of %d lines in %d seconds, saved %.2f KB.", cleanCnt, lineCnt, os.time()-startTime, bytes/1000)
    if debugError then
        Log.warn([[However, ASSWipe possibly encountered bugs while cleaning. 
                   Affected lines have been rolled back to their previous state.
                   Please copy the whole log window contents and send them to line0.]])
    end
end

aegisub.register_macro(script_name, script_description, clean)
