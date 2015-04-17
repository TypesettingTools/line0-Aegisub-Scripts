export script_name = "ASSWipe"
export script_description = "Performs script cleanup, removes unnecessary tags and lines."
export script_version = "0.3.1"
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
LineCollection, ConfigHandler, Log, ASS, Common, SubInspector, util = version\requireModules!

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

mergeLines = (lines, start, cmbCnt, bytes) ->
    if lines[start].merged
        return lines[start], cmbCnt+1, bytes + #lines[start].raw + 1

    merged = lines[start]
    for i=start+1,lines.n
        if not lines[i].merged and lines[i].start_time==merged.end_time
            lines[i].merged = true
            merged.end_time = lines[i].end_time
    return nil, cmbCnt, bytes

process = (sub, sel, res) ->
    ASS.config.fixDrawings = res.fixDrawings
    lines = LineCollection sub,sel
    linesToDelete, delCnt, linesToCombine, cmbCnt, lineCnt, debugError = {}, 0, {}, 0, #lines.lines, false
    tagNames = res.filterClips and util.copy(ASS.tagNames.clips) or {}
    tagNames[#tagNames+1] = res.removeJunk and "junk"
    stats = { bytes: 0, junk: 0, clips: 0, start: os.time!, cleaned: 0,
              scale2float: 0, contoursDraw: 0, contoursClip: 0 }

    -- create proper tag name lists from user input which may be override tag names or mixed
    res.tagsToKeep = ASS\getTagNames res.tagsToKeep\split ",%s"
    res.tagSortOrder = ASS\getTagNames res.tagSortOrder\split ",%s"

    callback = (lines, line, i) ->
        aegisub.cancel! if aegisub.progress.is_cancelled!
        aegisub.progress.task "Cleaning %d of %d lines..."\format i, lineCnt if i%10==0
        aegisub.progress.set 100*i/lineCnt

        unless line.styleRef
            Log.warn "WARNING: Line #%d is using undefined style '%s', skipping...\n— %s", i, line.style, line.text
            return

        success, data = pcall ASS\parse, line
        unless success
            Log.warn "Couldn't parse line #%d: %s", i, data
            return

        -- it is essential to run SubInspector on a ASSFoundation-built line (rather than the original)
        -- because ASSFoundation rounds tag values to a sane precision, which is not visible but
        -- will produce a hash mismatch compared to the original line. However we must avoid that to
        -- not trigger the ASSWipe bug detection
        oldText, oldBounds = line.text, data\getLineBounds false

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

        -- collect lines to combine
        if res.combineLines and not oldBounds.animated
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

        if oldText != line.text
            if not newBounds\equal oldBounds
                debugError = true
                Log.warn "Cleaning affected output on line #%d, rolling back...", line.humanizedNumber
                Log.warn "—— Before: %s\n—— After: %s\n—— Style: %s\n", oldText, line.text, line.styleRef.name
                line.text = oldText
            elseif #line.text < #oldText
                stats.cleaned += 1
                stats.bytes += #oldText - #line.text

    lines\runCallback callback, true

    for hash, lines in pairs linesToCombine
        continue if lines.n < 2
        table.sort lines, (a,b) -> a.start_time < b.start_time
        for j=1,lines.n
            linesToDelete[delCnt+cmbCnt+1], cmbCnt, stats.bytes = mergeLines lines, j, cmbCnt, stats.bytes

    lines\replaceLines!
    lines\deleteLines linesToDelete

    Log.dump{"Styles:", lines.styles, "Configuration:", res} if debugError
    Log.warn reportMsg, lineCnt, os.time!-stats.start, stats.cleaned, 100*stats.cleaned/lineCnt,
             delCnt, 100*delCnt/lineCnt, cmbCnt, 100*cmbCnt/lineCnt, stats.clips, stats.junk,
             stats.contoursClip+stats.contoursDraw, stats.contoursDraw, stats.contoursClip,
             stats.scale2float, stats.bytes/1000

    if debugError
        Log.warn([[However, ASSWipe possibly encountered bugs while cleaning.
                   Affected lines have been rolled back to their previous state.
                   Please copy the whole log window contents and send them to line0.]])

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