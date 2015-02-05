script_name="ASSWipe"
script_description="Cleans up tags."
script_version="0.0.1"
script_author="line0"

local LineCollection = require("a-mo.LineCollection")
local ASSTags = require("l0.ASSTags")
local Log = require("a-mo.Log")
local ConfigHandler = require("a-mo.ConfigHandler")
local l0Common = require("l0.Common")

local reportMsg = [[
Done. Processed %d lines in %d seconds.
— Cleaned %d lines (%d%%)
— Removed %d invisible lines (%d%%)
— Combined %d consecutive identical lines (%d%%)
— Filtered %d clips and %d occurences of junk data
— Total space saved: %.2f KB
]]

local cleanLevelHint = [[
0: no cleaning
1: remove empty tag sections
2: deduplicate tags inside sections
3: deduplicate tags globally,
4: remove tags matching the style defaults and otherwise ineffective tags]]

local defaultSortOrder = [[
\an, \pos, \move, \org, \fscx, \fscy, \frz, \fry, \frx, \fax, \fay, \fn, \fs, \fsp, \b, \i, \u, \s, \bord, \xbord, \ybord,
\shad, \xshad, \yshad, \1c, \2c, \3c, \4c, \alpha, \1a, \2a, \3a, \4a, \blur, \be, \fad, \fade, clip_rect, iclip_rect,
clip_vect, iclip_vect, \q, \p, \k, \kf, \K, \ko, junk, unknown
]]

local function mergeLines(lines, start, cmbCnt, bytes)
    if lines[start].merged then
        return lines[start], cmbCnt+1, bytes + #lines[start].raw + 1
    end
    local merged = lines[start]
    for i=start+1,lines.n do
        if not lines[i].merged and lines[i].start_time==merged.end_time then
            lines[i].merged = true
            merged.end_time = lines[i].end_time
        end
    end
    return nil, cmbCnt, bytes
end

function showDialog(sub, sel, res)
    local dlg = {
        main = {
            cleanLevelLabel =   { class="label",    x=0, y=0, width=1, height=1, label="Tag cleanup level: "},
            cleanLevel =        { class="intedit",  x=1, y=0, width=1, height=1, min=0, max=4, value=4, config=true,
                                 hint=cleanLevelHint },
            tagsToKeepLabel =   { class="label",    x=4, y=0, width=1, height=1, label="Keep default tags: "},
            tagsToKeep =        { class="textbox",  x=4, y=1, width=10, height=2, value="\\pos", config=true,
                                  hint="Don't remove these tags even if they match the style defaults for the line."},
--          reorderGlobal =     { class="checkbox", x=0, y=1, width=2, height=1, value=true, config=true, label="Reorder global tags",
--                                hint="Moves global tags such as \\pos and \\fad to the front.", name="reorderGlobal" },
            filterClips =       { class="checkbox", x=0, y=1, width=2, height=1, value=true, config=true, label="Filter clips",
                                  hint="Removes clips that don't affect the rendered output." },
            removeInvisible =   { class="checkbox", x=0, y=2, width=2, height=1, value=true, config=true, label="Remove invisible lines",
                                  hint="Deletes lines that don't generate any visible output." },
            combineLines =      { class="checkbox", x=0, y=3, width=2, height=1, value=true, config=true, label="Combine consecutive identical lines",
                                  hint="Merges non-animated lines that render to an identical result and have consecutive times (without overlaps or gaps)." },
            tagSortOrderLabel = { class="label",    x=4, y=3, width=1, height=1, label="Tag sort order: "},
            removeJunk =        { class="checkbox", x=0, y=4, width=2, height=1, value=true, config=true, label="Remove junk from tag sections",
                                  hint="Removes any 'in-line comments' and things not starting with a \\ from tag sections." },
            tagSortOrder =      { class="textbox",  x=4, y=4, width=10, height=3, value=defaultSortOrder, config=true,
                                  hint="Determines the order cleaned tags will be ordered inside a tag section. Resets always go first, transforms last."}
        }
    }
    local options = ConfigHandler(dlg, "ASSWipe.json", false, script_version)
    options:read()
    options:updateInterface("main")
    local btn, res = aegisub.dialog.display(dlg.main)
    if btn then
        options:updateConfiguration(res, "main")
        options:write()
        process(sub, sel, res)
    end
end

function process(sub, sel, res)
    local lines, linesToDelete, delCnt, linesToCombine, cmbCnt = LineCollection(sub,sel), {}, 0, {}, 0
    local debugError, lineCnt = false, #lines.lines
    local tagNames = table.insert(res.filterClips and ASS.tagNames.clips or {},
                                  res.removeJunk and "junk")
    local stats = {bytes=0, junk=0, clips=0, start=os.time(), cleaned=0}

    -- create proper tag name lists from user input which may be override tag names or mixed
    res.tagsToKeep, res.tagSortOrder = ASS:getTagNames(res.tagsToKeep:split(",%s")),
                                       ASS:getTagNames(res.tagSortOrder:split(",%s"))

    lines:runCallback(function(lines, line, i)
        if aegisub.progress.is_cancelled() then
            aegisub.cancel()
        end

        if i%10==0 then
            aegisub.progress.task(string.format("Cleaning %d of %d lines...", i, lineCnt))
        end

        local data, oldText = ASS.parse(line), line.text
        local oldBounds = data:getLineBounds(false)

        if res.removeInvisible and oldBounds.w == 0 then
            -- remove invisible lines
            linesToDelete[delCnt+1], delCnt = line, delCnt + 1
            stats.bytes = stats.bytes + #line.raw + 1
        else
            if res.combineLines and not oldBounds.animated then
                local hash = oldBounds.firstHash
                if not linesToCombine[hash] then
                    linesToCombine[hash] = {line, n=1}
                else
                    linesToCombine[hash][linesToCombine[hash].n+1] = line
                    linesToCombine[hash].n = linesToCombine[hash].n+1
                end
            end

            -- clean tags
            data:cleanTags(res.cleanLevel, true, res.tagsToKeep, res.tagSortOrder)
            local newBounds = data:getLineBounds()

            if res.filterClips or res.removeJunk then
                data:modTags(tagNames, function(tag)
                    -- remove junk
                    if tag.instanceOf[ASSUnknown] then
                        stats.junk = stats.junk + 1
                        return false
                    end

                    -- filter clips
                    tag.disabled = true
                    if data:getLineBounds():equal(newBounds) then
                        stats.clips = stats.clips + 1
                        return false
                    else tag.disabled = false end
                end)
            end

            data:commit()

            if oldText~=line.text then
                if not newBounds:equal(oldBounds) then
                    debugError = true
                    Log.warn("Cleaning affected output on line #%d, rolling back...", line.humanizedNumber)
                    Log.warn("—— Before: %s\n—— After: %s\n—— Style: %s\n", oldText, line.text, line.styleRef.name)
                    line.text = oldText
                elseif #line.text < #oldText then
                    stats.cleaned, stats.bytes = stats.cleaned+1, stats.bytes + #oldText - #line.text
                end
                aegisub.progress.set(100*i/lineCnt)
            end
        end
    end, true)

    for hash, lines in pairs(linesToCombine) do
        if lines.n > 1 then
            table.sort(lines, function(a,b) return a.start_time < b.start_time end)
            for j=1,lines.n do
                linesToDelete[delCnt+cmbCnt+1], cmbCnt, stats.bytes = mergeLines(lines, j, cmbCnt, stats.bytes)
            end
        end
    end

    lines:replaceLines()
    lines:deleteLines(linesToDelete)

    if debugError then Log.dump{"Styles:", lines.styles, "Configuration:", res} end
    Log.warn(reportMsg, lineCnt, os.time()-stats.start, stats.cleaned, 100*stats.cleaned/lineCnt,
             delCnt, 100*delCnt/lineCnt, cmbCnt, 100*cmbCnt/lineCnt, stats.clips, stats.junk, stats.bytes/1000)

    if debugError then
        Log.warn([[However, ASSWipe possibly encountered bugs while cleaning.
                   Affected lines have been rolled back to their previous state.
                   Please copy the whole log window contents and send them to line0.]])
    end

    return lines:getSelection()
end

aegisub.register_macro(script_name, script_description, showDialog)