script_name="Nudge"
script_description="Provides configurable and hotkeyable tag/line modification macros."
script_version="0.4.0"
script_author="line0"
script_namespace="l0.Nudge"

local DependencyControl = require "l0.DependencyControl"
local version = DependencyControl{
    feed = "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
        "aegisub.util", "aegisub.clipboard", "aegisub.re", "json",
        {"a-mo.LineCollection", version="1.0.1", url="https://github.com/torque/Aegisub-Motion"},
        {"a-mo.Log", url="https://github.com/torque/Aegisub-Motion"},
        {"l0.ASSFoundation", version="0.3.0", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"l0.ASSFoundation.Common", version="0.2.0", url="https://github.com/TypesettingTools/ASSFoundation",
         feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"}
    }
}

local util, clipboard, re, json, LineCollection, Log, ASS, Common = version:requireModules()

--------  Nudger Class -------------------

local cmnOps = {"Add", "Multiply", "Power", "Cycle", "Set", "Set Default", "Remove", "Copy", "Paste Over", "Paste Into"}
local colorOps, stringOps = table.join(cmnOps, {"Add HSV"}),  {"Append", "Prepend", "Replace", "Cycle", "Set", "Set Default", "Remove"}
local drawingOps = {"Add", "Multiply", "Power", "Remove", "Copy", "Paste Over", "Paste Into", "Expand", "Convert To Clip"}
local clipOpsVect = table.join(drawingOps, {"Invert Clip", "Convert To Drawing", "Set Default"})
local clipOptsRect = table.join(cmnOps,{"Invert Clip", "Convert To Drawing"})
local Nudger = {
    operations = {Add="add", Multiply="mul", Power="pow", Set="set", ["Align Up"]=false, ["Align Down"]=false, ["Align Left"]=false, ["Align Right"]=false,
              Toggle="toggle", ["Auto Cycle"]="cycle", Cycle=false, ["Set Default"]=false, ["Add HSV"]="addHSV", Replace="replace", Append="append", Prepend="prepend",
              ["Invert Clip"]="toggleInverse", Remove = false, ["Convert To Drawing"]=false, ["Set Comment"]=false, ["Unset Comment"]=false, ["Toggle Comment"]=false,
              ["Copy"]=false, ["Paste Over"]=false, ["Paste Into"]=false, Expand=false, ["Convert To Clip"]=false},
    targets = {
        tags = { position=cmnOps, blur_edges=cmnOps, scale_x=cmnOps, scale_y=cmnOps,
            align={"Align Up", "Align Down", "Align Left", "Align Right", "Auto Cycle", "Set", "Set Default", "Cycle"},
            angle=cmnOps, angle_y=cmnOps, angle_x=cmnOps, outline=cmnOps, outline_x=cmnOps, outline_y=cmnOps,
            shadow=cmnOps, shadow_x=cmnOps, shadow_y=cmnOps, alpha=cmnOps, alpha1=cmnOps,
            alpha2=cmnOps, alpha3=cmnOps, alpha4=cmnOps, color1=colorOps, color2=colorOps, color3=colorOps, color4=colorOps,
            blur=cmnOps, shear_x=cmnOps, shear_y=cmnOps, bold=table.join(cmnOps,{"Toggle"}), underline={"Toggle","Set", "Set Default"},
            spacing=cmnOps, fontsize=cmnOps, k_fill=cmnOps, k_sweep_alt=cmnOps, k_sweep=cmnOps, k_bord=cmnOps, move=cmnOps, move_simple=cmnOps, origin=cmnOps,
            wrapstyle={"Auto Cycle","Cycle", "Set", "Set Default"}, fade_simple=cmnOps, fade=cmnOps, italic={"Toggle","Set", "Set Default"},
            reset=stringOps, fontname=stringOps, clip_vect=clipOpsVect, iclip_vect=clipOpsVect, clip_rect=clipOptsRect, iclip_rect=clipOptsRect,
            unknown={"Remove"}, junk={"Remove"}, ["Clips (Vect)"]=clipOpsVect, ["Clips (Rect)"]=clipOptsRect, Clips=clipOpsVect, ["Any Tag"]={"Remove", "Copy", "Paste Over", "Paste Into"},
            ["Colors"]=colorOps, ["Alphas"]=cmnOps, ["Primary Color"]=colorOps, ["Fades"]=cmnOps, Comment={"Remove"}, ["Comments/Junk"]={"Remove"},
        },
        line = {Line={"Set Comment", "Unset Comment", "Toggle Comment"}, Text={"Convert To Drawing", "Expand", "Convert To Clip"},
                Drawing=drawingOps, Contents={"Convert To Drawing", "Expand"}}
    },
    compoundTargets = {
        Colors = {"color1","color2","color3","color4"},
        Alphas = {"alpha", "alpha1", "alpha2", "alpha3", "alpha4"},
        Fades = {"fade_simple", "fade"},
        Clips = {"clip_vect", "clip_rect", "iclip_vect", "iclip_rect"},
        ["Clips (Vect)"] = {"clip_vect", "iclip_vect"},
        ["Clips (Rect)"] = {"clip_rect", "iclip_rect"},
        ["\\move"] = {"move", "move_simple"},
        ["Any Tag"] = ASS.tagNames.all,
        Contents = {"Text", "Drawing"}
    }
}

Nudger.targetList = table.keys(Nudger.targets.line)
for name,ops in pairs(Nudger.targets.tags) do
    Nudger.targetList[#Nudger.targetList+1] = ASS.toFriendlyName[name] or name
end
table.sort(Nudger.targetList)


Nudger.__index = Nudger
setmetatable(Nudger, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

function Nudger.new(params)
    local self = setmetatable({}, Nudger)
    params = params or {}
    self.name = params.name or "Unnamed Nudger"
    self.tag = params.tag or "position"
    self.operation = params.operation or "Add"
    self.value = params.value or {}
    self.id = params.id or util.uuid()
    self.noDefault = params.noDefault or false
    self.targetValue = params.targetValue or 0
    self.targetName = params.targetName or "Tag Section"
    self:validate()
    return self
end

function Nudger:validate()
    -- do we need to check the other values?
    local ops = self.targets.tags[self.tag] or self.targets.line[self.tag]
    assertEx(table.find(ops, self.operation), "Operation %s not supported for tag %s.", self.operation, self.tag)
end

function Nudger:nudgeTags(lineData, lines, line, targets)
    local tagSect = self.targetValue~=0 and self.targetValue or nil
    local relative, builtinOp = self.targetName=="Matched Tag", self.operations[self.operation]

    local foundTags = lineData:getTags(targets, tagSect, tagSect, relative)
    local foundCnt = #foundTags

    -- insert default tags if no matching tags are present
    if foundCnt==0 and not self.noDefault and not relative and self.operation~="Remove" then
        lineData:insertDefaultTags(targets, tagSect)
    end

    if builtinOp then
        lineData:modTags(targets, function(tag)
            tag[builtinOp](tag,unpack(self.value))
        end, tagSect, tagSect, relative)

    elseif self.operation=="Copy" then
        local tagStr = {}
        lineData:modTags(targets, function(tag)
            tagStr[#tagStr+1] = tag:getTagString()
        end, tagSect, tagSect, relative)
        clipboard.set(table.concat(tagStr))

    elseif self.operation=="Paste Over" then
        local pasteTags = ASS.TagList(ASS.Section.Tag(clipboard.get())):filterTags(targets)
        lineData:replaceTags(pasteTags, tagSect, tagSect, relative)

    elseif self.operation=="Paste Into" then
        local pasteTags = ASS.TagList(ASS.Section.Tag(clipboard.get()))
        local global, normal = pasteTags:filterTags(targets, {global=true})
        lineData:insertTags(normal, tagSect, -1, not relative)
        lineData:replaceTags(global)

    elseif self.operation=="Cycle" then
        local edField = "l0.Nudge.cycleState"
        local ed = line:getExtraData(edField)
        if type(ed)=="table" then
            ed[self.id] = ed[self.id] and ed[self.id]<#self.value and ed[self.id]+1 or 1
        else ed={[self.id]=1} end
        line:setExtraData(edField,ed)

        lineData:modTags(targets, function(tag)
            tag:set(unpack(self.value[ed[self.id]]))
        end, tagSect, tagSect, relative)

    elseif self.operation=="Set Default" and foundCnt>0 then
        local defaults = lineData:getStyleDefaultTags()
        lineData:modTags(targets, function(tag)
            tag:set(defaults.tags[tag.__tag.name]:get())
        end, tagSect, tagSect, relative)

    elseif self.operation=="Remove" then
        if targets=="Comments/Junk" then
            lineData:stripComments()
            lineData:removeTags("junk", tagSect, tagSect, relative)
        elseif targets=="Comment" then
            lineData:stripComments()
        else lineData:removeTags(targets, tagSect, tagSect, relative) end
        lineData:cleanTags(1,false)

    elseif self.operation=="Expand" then
        lineData:modTags(targets, function(tag)
            tag:expand(self.value[1], self.value[2])
        end, tagSect, tagSect, relative)

    elseif self.operation=="Convert To Drawing" then
            local keepPos, drawing, pos = not self.value[2]
            lineData:modTags(targets, function(tag)
                drawing, pos = tag:getDrawing(keepPos)
                return self.value[1]==true
            end, tagSect, tagSect, relative)

            lineData:insertSections(drawing)
            if pos then lineData:replaceTags(pos) end

    else
        local opAlign = re.match(self.operation, "Align (Up|Down|Left|Right)")
        if opAlign then
            local pos, align, org= lineData:getPosition()
            local newAlign = align:copy()
            newAlign[string.lower(opAlign[2].str)](newAlign)

            if self.value[1] == true then
                local haveDrawings, haveRotation, w, h = false, false
                lineData:callback(function(section,sections,i)
                    haveDrawings = true
                end, ASS.Section.Drawing)

                -- While text uses type metrics for positioning and alignment
                -- vector drawings use a straight bounding box
                -- TODO: make this work for lines that have both drawings AND text
                if haveDrawings then
                    local bounds = lineData:getLineBounds()
                    w, h = bounds.w, bounds.h
                else
                    local metrics = lineData:getTextMetrics(true)
                    w, h = metrics.width, metrics.height
                end
                pos:add(newAlign:getPositionOffset(w, h, align))

                -- add origin if any rotation is applied to the line
                local effTags = lineData:getEffectiveTags(-1, true, true, false)
                trans, tags = effTags:checkTransformed(), effTags.tags
                Log.dump{tags.angle:modEq(0, 360)}
                if tags.angle:modEq(0, 360) and tags.angle_x:modEq(0, 360) and tags.angle_y:modEq(0, 360)
                and not (trans.angle or trans.angle_x or trans.angle_y) then
                    org = nil
                end
            end
            lineData:replaceTags{newAlign,org}
        end

    end
end

function Nudger:nudgeLines(lineData, lines, line, targets)
    local op, relative, tagSect  = self.operation, self.targetName=="Matched Tag", self.targetValue~=0 and self.targetValue or nil

    if targets["Line"] then
        if op=="Unset Comment" then line.comment=false
        elseif op=="Set Comment" then line.comment=true
        elseif op=="Toggle Comment" then line.comment = not line.comment end
    end

    if targets["Text"] then
        if op=="Convert To Clip" then
            local toConvert
            lineData:callback(function(sect)
                toConvert = sect:convertToDrawing()
                return false
            end, ASS.Section.Text, 1, 1, true)
            if toConvert then
                lineData:replaceTags(toConvert:getClip())
            end
        else
            lineData:callback(function(sect)
                if op=="Convert To Drawing" then sect:convertToDrawing()
                elseif op=="Expand" then sect:expand(self.value[1], self.value[2]) end
            end, ASS.Section.Text, tagSect, tagSect, relative)
        end
    end

    if targets["Drawing"] or targets["Text"] then
        local targetSections = {targets["Drawing"] and ASS.Section.Drawing, targets["Text"] and ASS.Section.Text}
        if op=="Copy" then
            local sectStr = {}
            lineData:callback(function(sect)
                sectStr[#sectStr+1] = sect:getString()
            end, targetSections, tagSect, tagSect, relative)
            clipboard.set(table.concat(sect))
        elseif op=="Paste Over" then
            local sectStr = clipboard.get()
            lineData:callback(function(sect)
                if sect.class == ASS.Section.Text then
                    sect.value = sectStr
                else return ASS.Section.Drawing{str=sectStr} end
            end, targetSections, tagSect, tagSect, relative)
        elseif op=="Paste Into" then
            local sectStr = clipboard.get()
            if targets["Drawing"] and sectStr:match("m%s+[%-%d%.]+%s+[%-%d%.]+") then
                lineData:insertSections(ASS.Section.Drawing{str=sectStr})
            elseif targets["Text"] then
                lineData:insertSections(ASS.Section.Text(sectStr))
            end
        elseif op=="Convert To Clip" then
            local clip
            lineData:callback(function(sect)
                if clip then
                    clip:insertContours(sect:getClip())
                else
                    clip = sect:getClip()
                end
                return false
            end, ASS.Section.Drawing, tagSect, tagSect, relative)
            if clip then
                lineData:replaceTags(clip)
            end
        end
    end

    if targets["Drawing"] then
        local builtinOp = self.operations[self.operation]
        lineData:callback(function(sect)
            if builtinOp then
                sect[builtinOp](sect,unpack(self.value))
            elseif op=="Expand" then
                sect:expand(self.value[1], self.value[2])
            end
        end, ASS.Section.Drawing, tagSect, tagSect, relative)
    end

end

function Nudger:nudge(sub, sel)
    local targets, tagTargets, lineTargets = self.compoundTargets[self.tag], {}, {}
    if targets then
        for i=1,#targets do
            if ASS.tagMap[targets[i]] then tagTargets[#tagTargets+1]=targets[i]
            else
                lineTargets[#lineTargets+1]=targets[i]
                lineTargets[targets[i]]=true
            end
        end
    elseif ASS.tagMap[self.tag]
        then tagTargets[1] = self.tag
    else
        lineTargets[1], lineTargets[self.tag] = self.tag, true
    end

    local lines = LineCollection(sub, sel, function() return true end)
        lines:runCallback(function(lines, line)
        local lineData = ASS:parse(line)
        if #tagTargets>0 then self:nudgeTags(lineData, lines, line, tagTargets) end
        if #lineTargets>0 then self:nudgeLines(lineData, lines, line, lineTargets) end

        lineData:commit()
    end)
    lines:replaceLines()
end
-------Dialog Resource Name Encoding---------

local uName = {
    encode = function(id,name)
        return id .. "." .. name
    end,
    decode = function(un)
        return un:match("([^%.]+)%.(.+)")
    end
}

-----  Configuration Class ----------------

local Configuration = {
    default = {__version=script_version ,nudgers = {
        {operation="Add", value={1,0}, id="d0dad24e-515e-40ab-a120-7b8d24ecbad0", name="Position Right (+1)", tag="position"},
        {operation="Add", value={-1,0}, id="0c6ff644-ef9c-405a-bb12-032694d432c0", name="Position Left (-1)", tag="position"},
        {operation="Add", value={0,-1}, id="cb2ec6c1-a8c1-48b8-8a13-cafadf55ffdd", name="Position Up (-1)", tag="position"},
        {operation="Add", value={0,1}, id="cb9c1a5b-6910-4fb2-b457-a9c72a392d90", name="Position Down (+1)", tag="position"},
        {operation="Cycle", value={{0.6},{0.8},{1},{1.2},{1.5},{2},{3},{4},{5},{8}}, id="c900ef51-88dd-413d-8380-cebb7a59c793", name="Cycle Blur", tag="blur"},
        {operation="Cycle", value={{255},{0},{16},{48},{96},{128},{160},{192},{224}}, id="d338cbca-1575-4795-9b80-3680130cce62", name="Cycle Alpha", tag="alpha"},
        {operation="Toggle", value={}, id="974c3af9-ef51-45f5-a992-4850cb006743", name="Toggle Bold", tag="bold"},
        {operation="Auto Cycle", value={}, id="aa74461a-477b-47de-bbf4-16ef1ee568f5", name="Cycle Wrap Styles", tag="wrapstyle"},
        {operation="Align Up", value={}, id="254bf380-22bc-457b-abb7-3d1f85b90eef", name="Align Up", tag="align"},
        {operation="Align Down", value={}, id="260318dc-5bdd-4975-9feb-8c95b41e7b5b", name="Align Down", tag="align"},
        {operation="Align Left", value={}, id="e6aeca35-d4e0-4ff4-81ac-8d3a853d5a9c", name="Align Left", tag="align"},
        {operation="Align Right", value={}, id="dd80e1c5-7c07-478c-bc90-7c473c3abe49", name="Align Right", tag="align"},
        {operation="Set", value={1}, id="18a27245-5306-4990-865c-ae7f0062083a", name="Add Edgeblur", tag="blur_edges"},
        {operation="Set Default", value={1}, id="bb4967a7-fb8a-4907-b5e8-395ea67c0a52", name="Default Origin", tag="origin"},
        {operation="Add HSV", value={0,0,0.1}, id="015cd09b-3c2b-458e-a65a-80b80bb951b1", name="Brightness Up", tag="Colors"},
        {operation="Add HSV", value={0,0,-0.1}, id="93f07885-c3f7-41bb-b319-0542e6fd52d7", name="Brightness Down", tag="Colors"},
        {operation="Invert Clip", value={}, id="e719120a-e45a-44d4-b76a-62943f47d2c5", name="Invert First Clip", tag="Clips",
         noDefault=true, targetName="Matched Tag", targetValue="1"},
        {operation="Remove", value={}, id="4dfc33fd-3090-498b-8922-7e1eb4515257", name="Remove Comments & Junk", tag="Comments/Junk", noDefault=true},
        {operation="Remove", value={}, id="bc642b90-8ebf-45e8-a160-98b4658721bd", name="Strip Tags", tag="Any Tag", noDefault=true},
        {operation="Convert To Drawing", value={false, false}, id="9cf44e64-9ce9-402e-8097-9e189014c9c1", name="Clips -> Drawing", tag="Clips", noDefault=true},
    }}
}
Configuration.__index = Configuration

setmetatable(Configuration, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

function Configuration.new(fileName)
  local self = setmetatable({}, Configuration)
  self.fileName = aegisub.decode_path(fileName)
  self.nudgers = {}
  self:load()
  return self
end

function Configuration:load()
  local fileHandle = io.open(self.fileName)
  local data
  if fileHandle then
    data = json.decode(fileHandle:read('*a'))
    fileHandle:close()
  else
    data = self.default
  end

  -- version checking
  assert(tonumber(data.__version:sub(3,3))>=3, string.format(
         [[Error: your configuration file version (%s) is incompatible with %s %s
         and I'm too lazy to add update routines for the 2 people that have been using the script so far.
         Please delete %s and reload your scripts.]]
  , data.__version, script_name, script_version, self.fileName))

  self.nudgers = {}
  for _,val in ipairs(data.nudgers) do
    self:addNudger(val)
  end

  if not fileHandle then self:save() end
end

function Configuration:save()
  local data = json.encode({nudgers=self.nudgers, __version=script_version})
  local fileHandle = io.open(self.fileName,'w')
  fileHandle:write(data)
  fileHandle:close()
end

function Configuration:addNudger(params)
    self.nudgers[#self.nudgers+1] = Nudger(params)
end

function Configuration:removeNudger(uuid)
    self.nudgers = table.filter(self.nudgers, function(nudger)
        return nudger.id ~= uuid end
    )
end

function Configuration:getNudger(uuid)
    return table.reduce(table.filter(self.nudgers, function(nudger)
        return nudger.id == uuid end
    ))[1]
end

function Configuration:getDialog()
    local dialog = {
        {class="label", label="Macro Name", x=0, y=0, width=1, height=1},
        {class="label", label="Override Tag", x=1, y=0, width=1, height=1},
        {class="label", label="Action", x=2, y=0, width=1, height=1},
        {class="label", label="Value", x=3, y=0, width=1, height=1},
        {class="label", label="Target", x=4, y=0, width=1, height=1},
        {class="label", label="Target #", x=5, y=0, width=1, height=1},
        {class="label", label="No Default", x=6, y=0, width=1, height=1},
        {class="label", label="Remove", x=7, y=0, width=1, height=1},
    }

    local function getUnwrappedJson(arr)
        local json = json.encode(arr)
        return json:sub(2,json:len()-1)
    end

    local tags, operations = Nudger.targetList, table.keys(Nudger.operations)
    table.sort(operations)

    for i,nu in ipairs(self.nudgers) do
        dialog = table.join(dialog, {
            {class="edit", name=uName.encode(nu.id,"name"), value=nu.name, x=0, y=i, width=1, height=1},
            {class="dropdown", name=uName.encode(nu.id,"tag"), items=tags, value=ASS.toFriendlyName[nu.tag] or nu.tag,
             x=1, y=i, width=1, height=1},
            {class="dropdown", name=uName.encode(nu.id,"operation"), items=operations, value=nu.operation, x=2, y=i, width=1, height=1},
            {class="edit", name=uName.encode(nu.id,"value"), value=getUnwrappedJson(nu.value), step=0.5, x=3, y=i, width=1, height=1},
            {class="dropdown", name=uName.encode(nu.id,"targetName"), items={"Tag Section", "Matched Tag"}, value=nu.targetName, x=4, y=i, width=1, height=1},
            {class="intedit", name=uName.encode(nu.id,"targetValue"), value=nu.targetValue, x=5, y=i, width=1, height=1},
            {class="checkbox", name=uName.encode(nu.id,"noDefault"), value=nu.noDefault, x=6, y=i, width=1, height=1},
            {class="checkbox", name=uName.encode(nu.id,"remove"), value=false, x=7, y=i, width=1, height=1}
        })
    end
    return dialog
end

function Configuration:Update(res)
    for key,val in pairs(res) do
        local id,name = uName.decode(key)
        if name=="value" then val=json.decode("["..val.."]")
        elseif name=="tag" then val=ASS.toTagName[val] or val end

        if name=="remove" and val==true then
            self:removeNudger(id)
        else
            local nudger = self:getNudger(id)
            if nudger then nudger[name] = val end
        end
    end
    for _,nudger in ipairs(self.nudgers) do
        nudger:validate()
    end
    self:registerMacros()
end

function Configuration:registerMacros()
    for i,nudger in ipairs(self.nudgers) do
        aegisub.register_macro(script_name.."/"..nudger.name, script_description, function(sub, sel)
            nudger:nudge(sub, sel)
        end)
    end
end

function Configuration:run(noReload)
    if not noReload then self:load() end
    local btn, res = aegisub.dialog.display(self:getDialog(),{"Save","Cancel","Add Nudger"},{save="Save",cancel="Cancel", close="Save"})
    if btn=="Add Nudger" then
        self:addNudger()
        self:run(true)
    elseif btn=="Save" then
        self:Update(res)
        self:save()
    else self:load()
    end
end
-------------------------------------------

local config = Configuration(version:getConfigFileName())

aegisub.register_macro(script_name .. "/Configure Nudge", script_description, function()
    config:run()
end)
config:registerMacros()
