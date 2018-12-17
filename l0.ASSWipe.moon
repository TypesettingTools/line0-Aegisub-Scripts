export script_name = "ASSWipe"
export script_description = "Performs script cleanup, removes unnecessary tags and lines."
export script_version = "0.3.3"
export script_author = "line0"
export script_namespace = "l0.ASSWipe"

DependencyControl = require "l0.DependencyControl"
version = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.0.1", url: "https://github.com/torque/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.ConfigHandler", version: "1.1.1", url: "https://github.com/torque/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.Log", url: "https://github.com/torque/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.2.4", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"l0.ASSFoundation.Common", version: "0.2.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"SubInspector.Inspector", version: "0.6.1", url: "https://github.com/TypesettingTools/SubInspector",
         feed: "https://raw.githubusercontent.com/TypesettingTools/SubInspector/master/DependencyControl.json"},
         "aegisub.util"
    }
}
LineCollection, ConfigHandler, ASS, Common, SubInspector, util = version\requireModules!
logger = version\getLogger!

reportMsg = [[
Done. Processed %d lines in %d seconds.
— Cleaned %d lines (%d%%)
— Removed %d invisible lines (%d%%)
— Combined %d consecutive identical lines (%d%%)
— Filtered %d clips and %d occurences of junk data
— Purged %d invisible contours (%d in drawings, %d in clips)
— Converted %d drawings/clips to floating-point
— Total space saved: %.2f KB
]]

hints = {
    cleanLevel: [[
0: no cleaning
1: remove empty tag sections
2: deduplicate tags inside sections
3: deduplicate tags globally,
4: remove tags matching the style defaults and otherwise ineffective tags]]
    tagsToKeep: "Don't remove these tags even if they match the style defaults for the line."
    filterClips: "Removes clips that don't affect the rendered output."
    removeInvisible: "Deletes lines that don't generate any visible output."
    combineLines: "Merges non-animated lines that render to an identical result and have consecutive times (without overlaps or gaps)."
    removeJunk: "Removes any 'in-line comments' and things not starting with a \\ from tag sections."
    scale2float: "Converts drawings and clips with a scale parameter to a floating-point representation."
    tagSortOrder: "Determines the order cleaned tags will be ordered inside a tag section. Resets always go first, transforms last."
    fixDrawings: "Removes extraneous ordinates from broken drawings to make them parseable. May or may not changed the rendered output."
    purgeContoursDraw: "Removes all contours of a drawing that are not visible on the canvas."
    purgeContoursClip: "Removes all contours of a clip that do not affect the appearance of the line."
}

defaultSortOrder = [[
\an, \pos, \move, \org, \fscx, \fscy, \frz, \fry, \frx, \fax, \fay, \fn, \fs, \fsp, \b, \i, \u, \s, \bord, \xbord, \ybord,
\shad, \xshad, \yshad, \1c, \2c, \3c, \4c, \alpha, \1a, \2a, \3a, \4a, \blur, \be, \fad, \fade, clip_rect, iclip_rect,
clip_vect, iclip_vect, \q, \p, \k, \kf, \K, \ko, junk, unknown
]]

-- to be moved into ASSFoundation.Functional
sortWithKeys = (tbl, comparator) ->
    -- shellsort written by Rici Lake
    -- c/p from http://lua-users.org/wiki/LuaSorting, with index argument added to comparator
    incs = { 1391376, 463792, 198768, 86961, 33936, 13776, 4592, 1968, 861, 336, 112, 48, 21, 7, 3, 1 }
    n = #tbl
    for h in *incs
        for i = h+1, n
            a = tbl[i]
            for j = i-h, 1, -h
                b = tbl[j]
                break unless comparator a, b, i, j
                tbl[i] = b
                i = j
            tbl[i] = a
    return tbl


-- returns if we can merge line b into a while still maintain b's layer order
isMergeable = (a, b, linesByFrame) ->
    for i = b.firstFrame, b.lastFrame
        group = linesByFrame[i]
        local pos

        unless group.sorted
            -- ensure line group is sorted by layer blending order
            sortWithKeys group, (x, y, i, j) ->
                pos or= i if x == b
                return x.layer < y.layer or x.layer == y.layer and i < j

            group.sorted = true

        -- get line position in blending order
        pos or= i for i, v in ipairs group when v == b

        -- as b is merged into a, it gets a's layer number
        -- so we can only merge if the new layer number does not change the blending order in any of the frames b is visible in
        lower = group[pos-1]
        return false unless (not lower or a.layer > lower.layer or a.layer == lower.layer and a.number > lower.number)

        higher = group[pos+1]
        return false unless (not higher or a.layer < higher.layer or a.layer == higher.layer and a.number < higher.number)

    return true

mergeLines = (lines, start, cmbCnt, bytes, linesByFrame) ->
    -- queue merged lines for deletion and collect statistics
    if lines[start].merged
        return lines[start], cmbCnt+1, bytes + #lines[start].raw + 1

    -- merge applicable lines into first mergeable by extending its end time
    -- then mark all merged lines
    merged = lines[start]
    for i=start+1,lines.n
        line = lines[i]
        break if line.merged or line.start_time != merged.end_time or not isMergeable merged, line, linesByFrame
        lines[i].merged = true
        merged.end_time = lines[i].end_time

        -- update lines by frame index
        for f = line.firstFrame, line.lastFrame
            group = linesByFrame[f]
            pos = i for i, v in ipairs group when v == line
            group[pos] = merged

    return nil, cmbCnt, bytes

process = (sub, sel, res) ->
    ASS.config.fixDrawings = res.fixDrawings
    lines = LineCollection sub,sel
    linesToDelete, delCnt, linesToCombine, cmbCnt, lineCnt, debugError = {}, 0, {}, 0, #lines.lines, false
    tagNames = res.filterClips and util.copy(ASS.tagNames.clips) or {}
    tagNames[#tagNames+1] = res.removeJunk and "junk"
    stats = { bytes: 0, junk: 0, clips: 0, start: os.time!, cleaned: 0,
              scale2float: 0, contoursDraw: 0, contoursClip: 0 }
    linesByFrame = {}

    -- create proper tag name lists from user input which may be override tag names or mixed
    res.tagsToKeep = ASS\getTagNames res.tagsToKeep\split ",%s"
    res.tagSortOrder = ASS\getTagNames res.tagSortOrder\split ",%s"

    callback = (lines, line, i) ->
        aegisub.cancel! if aegisub.progress.is_cancelled!
        aegisub.progress.task "Cleaning %d of %d lines..."\format i, lineCnt if i%10==0
        aegisub.progress.set 100*i/lineCnt

        unless line.styleRef
            logger\warn "WARNING: Line #%d is using undefined style '%s', skipping...\n— %s", i, line.style, line.text
            return

        success, data = pcall ASS\parse, line
        unless success
            logger\warn "Couldn't parse line #%d: %s", i, data
            return

        -- it is essential to run SubInspector on a ASSFoundation-built line (rather than the original)
        -- because ASSFoundation rounds tag values to a sane precision, which is not visible but
        -- will produce a hash mismatch compared to the original line. However we must avoid that to
        -- not trigger the ASSWipe bug detection
        orgText, oldBounds = line.text, data\getLineBounds false
        orgTextParsed = oldBounds.rawText

        removeInvisibleContour = (contour) ->
            contour.disabled = true
            if oldBounds\equal data\getLineBounds!
                if contour.parent.class == ASS.Section.Drawing
                    stats.contoursDraw += 1
                else stats.contoursClip += 1
                return false
            contour.disabled = false

        -- remove invisible lines
        if res.removeInvisible and oldBounds.w == 0
            stats.bytes += #line.raw + 1
            delCnt += 1
            linesToDelete[delCnt], line.ASS = line
            return

        if res.purgeContoursDraw or res.scale2float
            cb = (section) ->
                -- remove invisible contours from drawings
                if res.purgeContoursDraw
                    section\callback removeInvisibleContour
                -- un-scale drawings
                if res.scale2float and section.scale > 1
                    section.scale\set 1
                    stats.scale2float += 1

            data\callback cb, ASS.Section.Drawing


        -- pogressively build a table of visible lines by frame
        -- which is required to check mergeability of consecutive identical lines
        if res.combineLines
            line.firstFrame = aegisub.frame_from_ms line.start_time
            line.lastFrame = -1 + aegisub.frame_from_ms line.end_time
            for i = line.firstFrame, line.lastFrame
                if linesByFrame[i]
                    linesByFrame[i][linesByFrame[i].n+1] = line
                    linesByFrame[i].n += 1
                else
                    linesByFrame[i] = {line, n: 1}

            -- collect lines to combine
            unless oldBounds.animated
                hash = oldBounds.firstHash
                if linesToCombine[hash]
                    linesToCombine[hash][linesToCombine[hash].n+1] = line
                    linesToCombine[hash].n = linesToCombine[hash].n+1
                else
                    linesToCombine[hash] = {line, n: 1}

        -- clean tags
        data\cleanTags res.cleanLevel, true, res.tagsToKeep, res.tagSortOrder
        newBounds = data\getLineBounds!

        if res.filterClips or res.removeJunk
            data\modTags tagNames, (tag) ->
                -- remove junk
                if tag.instanceOf[ASS.Tag.Unknown]
                    stats.junk += 1
                    return false

                if tag.instanceOf[ASS.Tag.ClipVect]
                    -- un-scale clips
                    if res.scale2float and tag.scale>1
                        tag.scale\set 1
                        stats.scale2float += 1
                    -- purge ineffective contours from clips
                    if res.purgeContoursClip
                        tag\callback removeInvisibleContour

                -- filter clips
                tag.disabled = true
                if data\getLineBounds!\equal newBounds
                    stats.clips += 1
                    return false
                tag.disabled = false

        data\commit!
        line.ASS = nil

        if orgText != line.text
            if not newBounds\equal oldBounds
                debugError = true
                logger\warn "Cleaning affected output on line #%d, rolling back...", line.humanizedNumber
                logger\warn "—— Before: %s\n—— Parsed: %s\n—— After: %s\n—— Style: %s", orgText, orgTextParsed, line.text, line.styleRef.name
                line.text = orgText
            elseif #line.text < #orgText
                stats.cleaned += 1
                stats.bytes += #orgText - #line.text

    lines\runCallback callback, true

    -- sort lines which are to be combined by time
    sortFunc = (a, b) ->
        return true if a.start_time < b.start_time
        return false if a.start_time > b.start_time
        return true if a.layer < b.layer
        return false if a.layer > b.layer
        return true if a.number < b.number
        return false

    linesToCombineSorted, l = {}, 1
    for _, group in pairs linesToCombine
        continue if group.n < 2
        table.sort group, sortFunc
        linesToCombineSorted[l] = group
        l += 1
    table.sort linesToCombineSorted, (a, b) -> sortFunc a[1], b[1]

    -- combine lines
    for group in *linesToCombineSorted
        for j=1, group.n
            linesToDelete[delCnt+cmbCnt+1], cmbCnt, stats.bytes = mergeLines group, j, cmbCnt, stats.bytes, linesByFrame

    lines\replaceLines!
    lines\deleteLines linesToDelete

    logger\warn json.encode {Styles: lines.styles, Configuration: res} if debugError
    logger\warn reportMsg, lineCnt, os.time!-stats.start, stats.cleaned, 100*stats.cleaned/lineCnt,
             delCnt, 100*delCnt/lineCnt, cmbCnt, 100*cmbCnt/lineCnt, stats.clips, stats.junk,
             stats.contoursClip+stats.contoursDraw, stats.contoursDraw, stats.contoursClip,
             stats.scale2float, stats.bytes/1000

    if debugError
        logger\warn [[However, ASSWipe possibly encountered bugs while cleaning.
                    Affected lines have been rolled back to their previous state, so your script is most likely fine.
                    Please copy the whole log window contents and send them to line0.]]


    return lines\getSelection!


showDialog = (sub, sel, res) ->
    dlg = {
        main: {
            cleanLevelLabel:    class: "label",    x: 0, y: 0, width: 1,  height: 1, label: "Tag cleanup level: "
            cleanLevel:         class: "intedit",  x: 1, y: 0, width: 1,  height: 1, min: 0, max: 4, value: 4, config: true, hint: hints.cleanLevel
            tagsToKeepLabel:    class: "label",    x: 4, y: 0, width: 1,  height: 1, label: "Keep default tags: "
            tagsToKeep:         class: "textbox",  x: 4, y: 1, width: 10, height: 2, value: "\\pos", config:true, hint: hints.tagsToKeep
            filterClips:        class: "checkbox", x: 0, y: 1, width: 2,  height: 1, value: true, config: true, label: "Filter clips", hint: hints.filterClips
            removeInvisible:    class: "checkbox", x: 0, y: 2, width: 2,  height: 1, value: true, config: true, label: "Remove invisible lines", hint: hints.removeInvisible
            combineLines:       class: "checkbox", x: 0, y: 3, width: 2,  height: 1, value: true, config: true, label: "Combine consecutive identical lines", hint: hints.combineLines
            tagSortOrderLabel:  class: "label",    x: 4, y: 3, width: 1,  height: 1, label: "Tag sort order: "
            removeJunk:         class: "checkbox", x: 0, y: 4, width: 2,  height: 1, value: true, config: true, label: "Remove junk from tag sections", hint: hints.removeJunk
            scale2float:        class: "checkbox", x: 0, y: 5, width: 2,  height: 1, value: true, config: true, label: "Un-scale drawings and clips", hint: hints.scale2float
            tagSortOrder:       class: "textbox",  x: 4, y: 4, width: 10, height: 3, value: defaultSortOrder, config: true, hint: hints.tagSortOrder
            fixDrawings:        class: "checkbox", x: 0, y: 6, width: 2,  height: 1, value: false, config: true, label: "Try to fix broken drawings", hint: hints.fixDrawings
            purgeContoursLabel: class: "label",    x: 0, y: 8, width: 2,  height: 1, label: "Purge invisible contours: "
            purgeContoursDraw:  class: "checkbox", x: 4, y: 8, width: 3,  height: 1, value: false, config: true, label: "from drawings", hint: hints.purgeContoursDraw
            purgeContoursClip:  class: "checkbox", x: 7, y: 8, width: 6,  height: 1, value: false, config: true, label: "from clips", hint: hints.purgeContoursClip
        }
    }
    options = ConfigHandler dlg, version.configFile, false, script_version, version.configDir
    options\read!
    options\updateInterface "main"
    btn, res = aegisub.dialog.display dlg.main
    if btn
        options\updateConfiguration res, "main"
        options\write!
        process sub, sel, res

version\registerMacro showDialog, ->
    if aegisub.project_properties!.video_file == ""
        return false, "A video must be loaded to run #{script_name}."
    else return true, script_description