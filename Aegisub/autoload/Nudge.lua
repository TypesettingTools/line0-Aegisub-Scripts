script_name="Nudge"
script_description="Nudge, Nudge"
script_version="0.0.1"
script_author="line0"

re = require("aegisub.re")
util = require("aegisub.util")
json = require("json")

Line = require("a-mo.Line")
LineCollection = require("a-mo.LineCollection")

l0Common = require("l0.Common")
ASSTags = require("l0.ASSTags")
LineExtend = require("l0.LineExtend")


--------  Nudger Class -------------------

local cmnOps = {"Add", "Multiply", "Power", "Cycle", "Set", "Set Default"}
local colorOps = table.join(cmnOps, {"Add HSV"})
local Nudger = {
    opList = {Add="add", Multiply="mul", Power="pow", Set="set", Up="up", Down="down", Left="left", Right="right", 
              Toggle="toggle", AutoCycle="cycle", Cycle=false, ["Set Default"]=false, ["Add HSV"]="addHSV"},
    supportedOps = {
        ["\\pos"]=cmnOps, ["\\be"]=cmnOps, ["\\fscx"]=cmnOps, ["\\fscy"]=cmnOps, 
        ["\\an"]=table.join(cmnOps,{"Up","Down","Left","Right","AutoCycle"}),
        ["\\frz"]=cmnOps, ["\\fry"]=cmnOps, ["\\frx"]=cmnOps, ["\\bord"]=cmnOps, ["\\xbord"]=cmnOps, ["\\ybord"]=cmnOps,
        ["\\shad"]=cmnOps, ["\\xshad"]=cmnOps, ["\\yshad"]=cmnOps, ["\\alpha"]=cmnOps, ["\\1a"]=cmnOps, 
        ["\\2a"]=cmnOps, ["\\3a"]=cmnOps, ["\\4a"]=cmnOps, ["\\c"]=colorOps, ["\\1c"]=colorOps, ["\\2c"]=colorOps, ["\\3c"]=colorOps, ["\\4c"]=colorOps,
        ["\\blur"]=cmnOps, ["\\fax"]=cmnOps, ["\\fay"]=cmnOps, ["\\b"]=table.join(cmnOps,{"Toggle"}), ["\\u"]={"Toggle","Set", "Set Default"},
        ["\\fsp"]=cmnOps, ["\\fs"]=cmnOps, ["\\k"]=cmnOps, ["\\K"]=cmnOps, ["\\kf"]=cmnOps, ["\\ko"]=cmnOps, ["\\move"]=cmnOps, ["\\org"]=cmnOps,
        ["\\q"]=table.join(cmnOps,{"AutoCycle"}), ["\\fad"]=cmnOps, ["\\fade"]=cmnOps, ["\\i"]={"Toggle","Set", "Set Default"},
        ["Colors"]=colorOps, ["Alphas"]=cmnOps, ["Primary Color"]=colorOps
    },
    compoundTags= {
        Colors = {"\\c","\\1c","\\2c","\\3c","\\4c"},
        ["Primary Color"] = {"\\c","\\1c"},
        Alphas = {"\\alpha", "\\1a", "\\2a", "\\3a", "\\4a"}
    }
}
Nudger.__index = Nudger

setmetatable(Nudger, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

function Nudger.new(params)
    local function uuid()
        -- https://gist.github.com/jrus/3197011
        math.randomseed(os.time())
        local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return string.gsub(template, '[xy]', function (c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end)
    end

    local self = setmetatable({}, Nudger)
    params = params or {}
    self.name = params.name or "Unnamed Nudger"
    self.tag = params.tag or "\\pos"
    self.operation = params.operation or "Add"
    self.value = params.value or {}
    self.id = params.id or uuid()
    self:validate()
    return self
end

function Nudger:validate()
    -- do we need to check the other values?
    assert(table.find(self.supportedOps[self.tag],self.operation), string.format("Error: Operation %s not supported for tag %s.\n",self.operation,self.tag))
end

function Nudger:nudge(sub, sel)
    local tags = self.tag:sub(1,1)=="\\" and {self.tag} or self.compoundTags[self.tag]
    local lines = LineCollection(sub,sel)

    lines:runCallback(function(lines, line)
        for _,tag in ipairs(tags) do
            if self.opList[self.operation] then
                line:modTag(tag, function(tags)
                    for i=1,#tags,1 do
                        tags[i][self.opList[self.operation]](tags[i],unpack(self.value))
                    end
                    return tags
                end)

            elseif self.operation=="Cycle" then
                line:modTag(tag, function(tags)
                    local edField = "l0.Nudge.cycleState"
                    local ed = line:getExtraData(edField)
                    if type(ed)=="table" then
                        ed[self.id] = ed[self.id] and ed[self.id]<#self.value and ed[self.id]+1 or 1
                    else ed={[self.id]=1} end
                    line:setExtraData(edField,ed)

                    for i=1,#tags,1 do
                        tags[i]:set(unpack(self.value[ed[self.id]]))
                    end
                    return tags
                end)   
            elseif self.operation=="Set Default" then
                line:modTag(tag, function(tags)
                    for i=1,#tags,1 do
                        tags[i]:set(line:getDefaultTag(self.tag))
                    end
                    return tags
                end)
            end
        end
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

local Configuration = {}
Configuration.__index = Configuration

setmetatable(Configuration, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

function Configuration.new(fileName)
  local self = setmetatable({}, Configuration)
  self.fileName = aegisub.decode_path('?user/' .. fileName)
  self.nudgers = {}
  self:load()
  return self
end

function Configuration:load()
  local fileHandle = io.open(self.fileName)
  local data = json.decode(fileHandle:read('*a'))

  self.nudgers = {}
  for _,val in ipairs(data.nudgers) do
    self:addNudger(val)
  end
end

function Configuration:save()
  local data = json.encode({nudgers=self.nudgers, __version=script_version})
  local fileHandle = io.open(self.fileName,'w')
  fileHandle:write(data)
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
    return table.filter(self.nudgers, function(nudger)
        return nudger.id == uuid end
    )[1]
end

function Configuration:getDialog()
    local dialog = {
        {class="label", label="Macro Name", x=0, y=0, width=1, height=1},
        {class="label", label="Override Tag", x=1, y=0, width=1, height=1},
        {class="label", label="Action", x=2, y=0, width=1, height=1},
        {class="label", label="Value", x=3, y=0, width=1, height=1},
        {class="label", label="Remove", x=4, y=0, width=1, height=1},
    }

    local function getUnwrappedJson(arr)
        local json = json.encode(arr)
        return json:sub(2,json:len()-1)
    end

    for i,nu in ipairs(self.nudgers) do
        dialog = table.join(dialog, {
            {class="edit", name=uName.encode(nu.id,"name"), value=nu.name, x=0, y=i, width=1, height=1},
            {class="dropdown", name=uName.encode(nu.id,"tag"), items=table.keys(Nudger.supportedOps), value=nu.tag, x=1, y=i, width=1, height=1},
            {class="dropdown", name=uName.encode(nu.id,"operation"), items= table.keys(Nudger.opList), value=nu.operation, x=2, y=i, width=1, height=1},
            {class="edit", name=uName.encode(nu.id,"value"), value=getUnwrappedJson(nu.value), step=0.5, x=3, y=i, width=1, height=1},
            {class="checkbox", name=uName.encode(nu.id,"remove"), value=false, x=4, y=i, width=1, height=1},
        })
    end
    return dialog
end

function Configuration:Update(res)
    for key,val in pairs(res) do
        local id,name = uName.decode(key)
        if name=="value" then val=json.decode("["..val.."]") end
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
    if not noReload then self:load() else noReload=false end
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

local config = Configuration("nudge.json")

aegisub.register_macro(script_name .. "/Configure Nudge", script_description, function(_,_,_) 
    config:run()
end)
config:registerMacros()
