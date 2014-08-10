script_name="Nudge"
script_description="Nudge, Nudge"
script_version="0.0.1"
script_author="line0"

json = require("json")
re = require("aegisub.re")
Line = require("a-mo.Line")
LineCollection = require("a-mo.LineCollection")

------ Why does lua suck so much? --------

math.isInt = function(var)
    return type(var) == "number" and a%1==0
end

math.toPrettyString = function(string, precision)
    -- stolen from liblyger, TODO: actually use it
    precision = precision or 3
    return string.format("%."..tostring(precision).."f",string):gsub("%.(%d-)0+$","%.%1"):gsub("%.$","") end

math.toStrings = function(...)
    strings={}
    for _,num in ipairs(table.pack(...)) do
        strings[#strings+1] = tostring(num)
    end
    return unpack(strings)
end

math.round = function(num,idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

string.patternEscape = function(str)
    return str:gsub("([%%%(%)%[%]%.%*%-%+%?%$%^])","%%%1")
end

string.toNumbers = function(...)
    numbers={}
    for _,string in ipairs(table.pack(...)) do
        numbers[#numbers+1] = tonumber(string)
    end
    return unpack(numbers)
end

table.isArray = function(tbl)
    local i = 0
    for _,_ in ipairs(tbl) do i=i+1 end
    return i==#tbl
end

table.filter = function(tbl, callback)
    local fltTbl = {}
    local tblIsArr = table.isArray(table)
    for key, value in pairs(tbl) do
        if callback(value,key,tbl) then 
            if tblIsArr then fltTbl[#fltTbl+1] = value
            else fltTbl[key] = value end
        end
    end
    return fltTbl
end

table.concatArray = function(tbl1,tbl2)
    local tbl = {}
    for _,val in ipairs(tbl1) do table.insert(tbl,val) end
    for _,val in ipairs(tbl2) do table.insert(tbl,val) end
    return tbl
end

------ Tag Classes ---------------------

function createClass(typeName)
  local cls = {}
  cls.__index = cls
  cls.instanceOf = {[cls] = true}
  cls.typeName = typeName
  cls.checkType = function(val, vType)
        if type(val) ~= vType then error("Error: " .. cls.typeName .. " must be a number, got " .. type(val) .. ".\n") end
  end
  setmetatable(cls, {
    __call = function (cls, ...)
    return cls.new(...)
  end})
  return cls
end

ASSNumber = createClass("ASSNumber")
function ASSNumber.new(val, constraints)
    local self = setmetatable({}, ASSNumber)
    self.value = tonumber(val) or 0
    self.constraints = constraints or {}
    return self
end

function ASSNumber:get(precision, coerceType)
    local val = math.round(tonumber(self.value),precision or 3)
    if coerceType then
        return self.constraints.positive and math.min(val,0) or val
    elseif type(self.value) ~= "number" then
        error("Error: ASSNumber must be a number, got " .. type(self.value) .. ".\n")
    elseif self.constraints.positive and self.value < 0 then
        error("Error: ASSNumber constraints do not permit numbers < 0.")
    else return val end
end

function ASSNumber:add(num)
    self.value = self.value + num
end

function ASSNumber:multiply(num)
    self.value = self.value * num
end

ASSPosition = createClass("ASSPosition")
function ASSPosition.new(valx, valy)
    local self = setmetatable({}, ASSPosition)
    if type(valx) == "string" then
        self.x, self.y = string.toNumbers(valx:match("([%-%d%.]+),([%-%d%.]+)"))
    else
        self.x = tonumber(valx) or 0
        self.y = tonumber(valy) or 0
    end 
    return self
end

function ASSPosition:add(x,y)
    self.x = x and (self.x + x) or self.x 
    self.y = y and (self.y + y) or self.y 
end

function ASSPosition:multiply(x,y)
    self.x = x and (self.x * x) or self.x 
    self.y = y and (self.y * y) or self.y 
end

function ASSPosition:get(precision, coerceType)
    precision = precision or 3
    local x = math.round(tonumber(self.x),precision)
    local y = math.round(tonumber(self.y),precision)
    if not coerceType then 
        self.checkType(self.x,"number")
        self.checkType(self.y,"number")
    end
    return x,y
end
------ Extend Line Object --------------

local meta = getmetatable(Line)
meta.__index.tagMap = {
    xscl = {friendlyName="\\fscx", type="ASSNumber", pattern="\\fscx([%d%.]+)", format="\\fscx%.3f"},
    yscl = {friendlyName="\\fscy", type="ASSNumber", pattern="\\fscy([%d%.]+)", format="\\fscy%.3f"},
    ali = {friendlyName="\\an", type="ASSAlign", pattern="\\an([1-9])"},
    zrot = {friendlyName="\\frz", type="ASSNumber", pattern="\\frz?([%-%d%.]+)"}, 
    yrot = {friendlyName="\\fry", type="ASSNumber", pattern="\\fry([%-%d%.]+)"}, 
    xrot = {friendlyName="\\frx", type="ASSNumber", pattern="\\frx([%-%d%.]+)"}, 
    bord = {friendlyName="\\bord", type="ASSNumber", constraints={positive=true}, pattern="\\bord([%d%.]+)", format="\\bord%.2f"}, 
    xbord = {friendlyName="\\xbord", type="ASSNumber", constraints={positive=true}, pattern="\\xbord([%d%.]+)", format="\\xbord%.2f"}, 
    ybord = {friendlyName="\\ybord", type="ASSNumber",constraints={positive=true}, pattern="\\ybord([%d%.]+)", format="\\ybord%.2f"}, 
    shad = {friendlyName="\\shad", type="ASSNumber", pattern="\\shad([%-%d%.]+)", format="\\shad%.2f"}, 
    xshad = {friendlyName="\\xshad", type="ASSNumber", pattern="\\xshad([%-%d%.]+)", format="\\xshad%.2f"}, 
    yshad = {friendlyName="\\yshad", type="ASSNumber", pattern="\\yshad([%-%d%.]+)", format="\\yshad%.2f"}, 
    reset = {friendlyName="\\r", type="ASSReset", pattern="\\r([^\\}]*)", format="\\r"}, 
    alpha = {friendlyName="\\alpha", type="ASSAlpha", pattern="\\alpha&H(%x%x)&"}, 
    l1a = {friendlyName="\\1a", type="ASSAlpha", pattern="\\1a&H(%x%x)&"}, 
    l2a = {friendlyName="\\2a", type="ASSAlpha", pattern="\\2a&H(%x%x)&"}, 
    l3a = {friendlyName="\\3a", type="ASSAlpha", pattern="\\3a&H(%x%x)&"}, 
    l4a = {friendlyName="\\4a", type="ASSAlpha", pattern="\\4a&H(%x%x)&"}, 
    l1c = {friendlyName="\\1c", type="ASSColor", pattern="\\1?c&H(%x+)&"}, 
    l2c = {friendlyName="\\2c", type="ASSColor", pattern="\\2c&H(%x+)&"}, 
    l3c = {friendlyName="\\3c", type="ASSColor", pattern="\\3c&H(%x+)&"}, 
    l4c = {friendlyName="\\4c", type="ASSColor", pattern="\\4c&H(%x+)&"}, 
    clip = {friendlyName="\\clip", type="ASSClip", pattern="\\clip%((.-)%)"}, 
    iclip = {friendlyName="\\iclip", type="ASSClip", pattern="\\iclip%((.-)%)"}, 
    be = {friendlyName="\\be", type="ASSNumber", constraints={positive=true}, pattern="\\be([%d%.]+)", format="\\be%.2f"}, 
    blur = {friendlyName="\\blur", type="ASSNumber", constraints={positive=true}, pattern="\\blur([%d%.]+)", format="\\blur%.2f"}, 
    fax = {friendlyName="\\fax", type="ASSNumber", pattern="\\fax([%-%d%.]+)", format="\\fax%.2f"}, 
    fay = {friendlyName="\\fay", type="ASSNumber", pattern="\\fay([%-%d%.]+)", format="\\fay%.2f"}, 
    bold = {friendlyName="\\b", type="ASSWeight", pattern="\\b(%d+)"}, 
    italic = {friendlyName="\\i", type="ASSToggle", pattern="\\i([10])"}, 
    underline = {friendlyName="\\u", type="ASSToggle", pattern="\\u([10])"},
    fsp = {friendlyName="\\fsp", type="ASSNumber", pattern="\\fsp([%-%d%.]+)", format="\\fsp%.2f"},
    kfill = {friendlyName="\\k", type="ASSDuration", pattern="\\k([%-%d]+)"},
    ksweep = {friendlyName="\\kf", type="ASSDuration", pattern="\\kf([%-%d]+)"},   -- because fuck \K and lua patterns
    kbord = {friendlyName="\\ko", type="ASSDuration", pattern="\\ko([%-%d]+)"},
    pos = {friendlyName="\\pos", type="ASSPosition", pattern="\\pos%(([%-%d%.]+,[%-%d%.]+)%)", format="\\pos(%.2f,%.2f)"},
    move = {friendlyName="\\move", type="ASSMove", pattern="\\move([%-%d%.]+,[%-%d%.]+,[%-%d%.]+,[%-%d%.]+)"},
    org = {friendlyName="\\org", type="ASSPosition", pattern="\\org([%-%d%.]+,[%-%d%.]+)"},
    wrap = {friendlyName="\\q", type="ASSWrapStyle", pattern="\\q(%d)"},
    fade = {friendlyName="\\fad", type="ASSFade", pattern="\\fade?%((.-)%)"},
    transform = {friendlyName="\\t", type="ASSTransform", pattern="\\t%((.-)%)"},
}


meta.__index.getDefaults = function()
    -- returns a table with Default values for the line (based on style, etc)
end

meta.__index.addDefault = function(tagName)
    -- adds override tag from Defaults to start of line if not present
end

meta.__index.getTagString = function(self,tagName,val)
    if type(val) == "table" then -- TODO: better check
        return self.tagMap[tagName].format:format(val:get())
    else
        return re.sub(self.tagMap[tagName].format,"(%.*?[A-Za-z],?)+","%s"):format(tostring(val))
    end
end

meta.__index.getTagVal = function(self,tagName,string)
    return _G[self.tagMap[tagName].type](string)
end

meta.__index.modTag = function(self, tagName, callback)
    local tags, tagsOrg = {},{} 
    for tag in self.text:gmatch("{.-" .. self.tagMap[tagName].pattern .. ".-}") do
        tags[#tags+1] = self:getTagVal(tagName, tag)
        tagsOrg[#tagsOrg+1] = tag
    end

    for i,tag in pairs(callback(tags)) do
        aegisub.log("Changed Tag: " .. self:getTagString(tagName, tagsOrg[i]) .. " to: " .. self:getTagString(tagName,tags[i]).. "\n")
        self.text = self.text:gsub(string.patternEscape(self:getTagString(tagName, tagsOrg[i])), self:getTagString(tagName,tags[i]), 1)
    end

    return #tags>0
end

setmetatable(Line, meta)

--------  Nudger Class -------------------
local Nudger = {}
Nudger.__index = Nudger

setmetatable(Nudger, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

function Nudger.new(params)
    -- https://gist.github.com/jrus/3197011
    local function uuid()
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
    self.tag = params.tag or "posx"
    self.action = params.action or "add"
    self.value = params.value or 1
    self.id = params.id or uuid()

    return self
end

function Nudger:nudge(sub, sel)
    local lines = LineCollection(sub,{},sel)
    lines:runCallback(function(lines, line)
        aegisub.log("BEFORE: " .. line.text .. "\n")
        line:modTag("pos", function(tags) -- hardcoded for my convenience
            for i=1,#tags,1 do
                tags[i]:add(self.value)
            end
            return tags
        end)
        aegisub.log("AFTER: " .. line.text .. "\n")
    end)
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
    aegisub.log("getNudger: looking for " .. uuid .. "\n")
    return table.filter(self.nudgers, function(nudger)
        return nudger.id == uuid end
    )[1]
end

function Configuration:getDialog()
    function mergeTable(tbl1,tbl2)
        for key,val in pairs(tbl2) do tbl1[key] = val end
        return tbl1
    end

    local dialog = {
        {class="label", label="Macro Name", x=0, y=0, width=1, height=1},
        {class="label", label="Override Tag", x=1, y=0, width=1, height=1},
        {class="label", label="Action", x=2, y=0, width=1, height=1},
        {class="label", label="Value", x=3, y=0, width=1, height=1},
        {class="label", label="Remove", x=4, y=0, width=1, height=1},
    }

    for i,nu in ipairs(self.nudgers) do
        dialog = table.concatArray(dialog, {
            {class="edit", name=uName.encode(nu.id,"name"), value=nu.name, x=0, y=i, width=1, height=1},
            {class="dropdown", name=uName.encode(nu.id,"tag"), items= {"posx","posy"}, value=nu.tag, x=1, y=i, width=1, height=1},
            {class="dropdown", name=uName.encode(nu.id,"action"), items= {"add","multiply"}, value=nu.action, x=2, y=i, width=1, height=1},
            {class="floatedit", name=uName.encode(nu.id,"value"), value=nu.value, step=0.5, x=3, y=i, width=1, height=1},
            {class="checkbox", name=uName.encode(nu.id,"remove"), value=false, x=4, y=i, width=1, height=1},
        })
    end
    return dialog
end

function Configuration:Update(res)
    for key,val in pairs(res) do
        local id,name = uName.decode(key)
        if name=="remove" and val==true then
            self:removeNudger(id)
        else
            local nudger = self:getNudger(id)
            if nudger then nudger[name] = val end
        end
    end
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