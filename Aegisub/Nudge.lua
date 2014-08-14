script_name="Nudge"
script_description="Nudge, Nudge"
script_version="0.0.1"
script_author="line0"

json = require("json")
re = require("aegisub.re")
util = require("aegisub.util")
Line = require("a-mo.Line")
LineCollection = require("a-mo.LineCollection")

------ Why does lua suck so much? --------

math.isInt = function(val)
    return type(val) == "number" and val%1==0
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

string.toNumbers = function(base, ...)
    numbers={}
    for _,string in ipairs(table.pack(...)) do
        numbers[#numbers+1] = tonumber(string, base)
    end
    return unpack(numbers)
end

table.length = function(tbl) -- currently unused
    local res=0
    for _,_ in pairs(tbl) do res=res+1 end
    return res
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

table.merge = function(tbl1,tbl2)
    local tbl = {}
    for key,val in pairs(tbl1) do tbl[key] = val end
    for key,val in pairs(tbl2) do tbl[key] = val end
    return tbl
end

table.sliceArray = function(tbl, istart, iend)
    local arr={}
    for i=istart,iend,1 do arr[#arr+1]=tbl[i] end
    return arr
end

------ Tag Classes ---------------------

function createClass(typeName,baseClass,props)
  local cls, baseClass = {}, baseClass or {}
  for key, val in pairs(baseClass) do
    cls[key] = val
  end

  cls.__index = cls
  cls.instanceOf = {[cls] = true}
  cls.typeName = typeName
  cls.props = props or {}

  setmetatable(cls, {
    __call = function (cls, ...)
        local self = setmetatable({}, cls)
        self:new(...)
        return self
    end})
  return cls
end

ASSBase = createClass("ASSBase")
function ASSBase:checkType(type_, ...)
    for _,val in ipairs({...}) do
        result = (type_=="integer" and math.isInt(val)) or type(val)==type_
        assert(result, "Error: " .. self.typeName .. " must be a " .. type_ .. ", got " .. type(val) .. ".\n")
    end
end

function ASSBase:checkPositive(...)
    self:checkType("number",...)
    for _,val in ipairs({...}) do
        assert(val >= 0, "Error: " .. self.typeName .. " props do not permit numbers < 0, got " ..  tostring(val) .. ".\n")
    end
end

function ASSBase:checkRange(min,max,...)
    self:checkType("number",...)
    for _,val in ipairs({...}) do
        assert(val >= min and val <= max, "Error: " .. self.typeName .. " must be a in range " .. min .. "-" .. max .. ", got " .. tostring(val) .. ".\n")
    end
end

function ASSBase:getArgs(args, default, ...)
    assert(type(args)=="table", "Error: first argument to getArgs must be a table of packed arguments, got " .. type(args) ..".\n")
    if #args == 1 and type(args[1]) == "table" and args[1].typeName then
        local res = false
        for _,class in ipairs(table.concatArray(table.pack(...),{cls})) do
            res = args[1].instanceOf[class] and true or res
        end
        args = assert(res, self.typeName .. " does not accept instances of class " .. args[1].typeName .. " as argument.") and args[1].__values__
    end
    for i=1,#self.__order__,1 do
        args[i] = type(args[i])=="nil" and default or args[i]
    end
    self:typeCheck(unpack(args))
    return unpack(args)
end

function ASSBase:typeCheck(...)
    local vals, valNames, valTypes, j, args = self.__values__, self.__order__, self.__types__, 1, {...}
    --assert(#valNames >= #args, string.format("Error: too many arguments. Expected %d, got %d.\n",#valNames,#args))
    for i,valName in ipairs(valNames) do
        if type(valTypes[i])=="table" and valTypes[i].instanceOf then
            if type(args[j])=="table" and args[j].instanceOf then
                vals[valName]:typeCheck(args[j])
                j=j+1
            else
                local subCnt = #vals[valName].__order__
                vals[valName]:typeCheck(unpack(table.sliceArray(args,j,j+subCnt-1)))
                j=j+subCnt
            end
        else       
            assert(type(args[i])==valTypes[i] or type(args[i])=="nil" or valTypes[i]=="nil", 
                   string.format("Error: bad type for argument %d (%s). Expected %s, got %s.\n", i,valName,type(vals[valName]),type(args[i]))) 
        end
    end
end

function ASSBase:get()
    local vals = {}
    for _,val in pairs(self.__values__) do
        if type(val)=="table" and val.instanceOf then
            for _,cval in pairs({val:get()}) do vals[#vals+1]=cval end
        else 
            vals[#vals+1] = val
        end
    end
end

function ASSBase:commonOp(method, callback, default, ...)
    local args = {self:getArgs({...}, default)}
    local j,vals = 1, self.__values__
    for _,valName in ipairs(self.__order__) do
        if type(vals[valName])=="table" and vals[valName].instanceOf then
            local subCnt = #vals[valName].__values__.__order__
            vals[valName][method](vals[valName],unpack(table.sliceArray(args,j,j+subCnt-1)))
            j=j+subCnt
        else 
            vals[valName]=callback(vals[valName],args[j])
            j=j+1
        end
    end
end

function ASSBase:add(...)
    self:commonOp("add", function(a,b) return a+b end, 0, ...)
end

function ASSBase:mul(...)
    self:commonOp("mul", function(a,b) return a*b end, 1, ...)
end

function ASSBase:pow(...)
    self:commonOp("pow", function(a,b) return a^b end, 1, ...)
end

function ASSBase:set(...)
    self:commonOp("set", function(a,b) return b end, nil, ...)
end

function ASSBase:mod(callback, ...)
    self:set(callback(self:get(...)))
end

function ASSBase:readProps(props)
    for key, val in pairs(props or {}) do
        self[key] = val
    end
end


ASSNumber = createClass("ASSNumber", ASSBase)
function ASSNumber:new(val, props)
    self:readProps(props)
    self.__values__ = {
        value = type(val)=="string" and tonumber(val) or val or 0,
        __order__ = {"value"},
        __types__ = {"number"}
    }
    setmetatable(self,{__index=setmetatable(self.__values__,getmetatable(self))})
    self:checkType("number",self.value)    
    return self
end

function ASSNumber:getTag(coerceType, precision)
    local val = math.round(tonumber(self.value),precision or 3)
    if coerceType then
        return self.props.positive and math.max(val,0) or val
    else
        self:checkType("number",self.value)
        if self.props.positive then self:checkPositive(self.value) end
        return val
    end
end


ASSPosition = createClass("ASSPosition", ASSBase)
function ASSPosition:new(valx, valy, props)
    if type(valx) == "string" then
        props = valy
        valx, valy = string.toNumbers(10,valx:match("([%-%d%.]+),([%-%d%.]+)"))
    end
    self:readProps(props)
    self.__values__ = {
        x = valx or 0,
        y = valy or 0,
        __order__ = {"x","y"},
        __types__ = {"number", "number"}
    }
    setmetatable(self,{__index=setmetatable(self.__values__,getmetatable(self))})
    self:checkType("number", self.x, self.y)
    return self
end


function ASSPosition:getTag(coerceType, precision)
    precision = precision or 3
    local x = math.round(tonumber(self.x),precision)
    local y = math.round(tonumber(self.y),precision)
    if not coerceType then 
        self:checkType("number", self.x, self.y)
    end
    return x,y
end

ASSTime = createClass("ASSTime", ASSBase)
function ASSTime:new(val, props)
    self:readProps(props)
    self.scale = self.scale or 1
    self.__values__ = {
        value = type(val) == "string" and tonumber(val) or val or 0,
        __order__ = {"value"},
        __types__ = {"number"}
    }
    setmetatable(self,{__index=setmetatable(self.__values__,getmetatable(self))})
    self:checkType("number", self.value)   -- not sure if it's better to check for integer instead
    self.value = self.value*self.scale
    return self
     -- TODO: implement adding by framecount
end

function ASSTime:getTag(coerceType, precision)
    local val = tonumber(self.value)/self.scale
    precision = precision or 0
    if coerceType then
        precision = math.min(precision,0)
        val = self.positive and math.max(val,0)
    else
        assert(precision <= 0, "Error: " .. self.typeName .." doesn't support floating point precision")
        self:checkType("number", self.value)
        if self.positive then self:checkPositive(self.value) end
    end
    return math.round(val,precision)
end

ASSDuration = createClass("ASSDuration", ASSTime, {positive=true})

ASSHex = createClass("ASSHex", ASSBase)
function ASSHex:new(val, props)
    self:readProps(props)
    self.__values__ = {
        value = type(val) == "string" and tonumber(val,16) or val,
        __order__ = {"value"},
        __types__ = {"number"}
    }
    setmetatable(self,{__index=setmetatable(self.__values__,getmetatable(self))})
    self:checkRange(0,255,self.value)
    return self
end

function ASSHex:getTag(coerceType)
    if not coerceType then self.checkRange(self.value,0,255) end
    return util.clamp(math.round(tonumber(self.value),0),0,255)
end

ASSColor = createClass("ASSColor", ASSBase)
function ASSColor:new(r,g,b, props)
    if type(r) == "string" then
        props = g
        r,g,b = string.toNumbers(16, r:match("(%x%x)(%x%x)(%x%x)"))    
    end 
    self:readProps(props)
    self.__values__ = {
        r = ASSHex(r),
        g = ASSHex(g),
        b = ASSHex(b),
        __order__ = {"r","g","b"},
        __types__ = {ASSHex,ASSHex,ASSHex}
    }
    setmetatable(self,{__index=setmetatable(self.__values__,getmetatable(self))})
    return self
end

function ASSColor:getTag(coerceType)
    return self.b:getTag(coerceType), self.g:getTag(coerceType), self.r:getTag(coerceType)
end

ASSFade = createClass("ASSFade", ASSBase)
function ASSFade:new(startDuration,endDuration,startTime,endTime,startAlpha,midAlpha,endAlpha,props)
    if type(startDuration) == "string" then
        props = endDuration or {}
        prms={}
        for prm in startDuration:gmatch("([^,]+)") do
            prms[#prms+1] = tonumber(prm)
        end
        if #prms == 2 then 
            startDuration, endDuration = unpack(prms)
            props.simple = true
        elseif #prms == 7 then
            startDuration, endDuration, startTime, endTime = prms[5]-prms[4], prms[7]-prms[6], prms[4], prms[7] 
        end
    end 
    self:readProps(props)
    self.__values__ = {
        startDuration = ASSDuration(startDuration), endDuration = ASSDuration(endDuration),
        startTime = self.simple and ASSTime(0) or ASSTime(startTime),
        endTime = self.simple and nil or ASSTime(endTime),
        startAlpha = self.simple and ASSHex(0) or ASSHex(startAlpha),
        midAlpha = self.simple and ASSHex(255) or ASSHex(midAlpha),
        endAlpha = self.simple and ASSHex(0) or ASSHex(endAlpha),
        __order__ = {"startDuration", "endDuration", "startTime", "endTime", "startAlpha", "midAlpha", "endAlpha"},
        __types__ = {ASSDuration,ASSDuration,ASSTime,ASSTime,ASSHex,ASSHex,ASSHex}
    }
    setmetatable(self,{__index=setmetatable(self.__values__,getmetatable(self))})
    return self
end

function ASSFade:getTag(coerceType)
    if self.simple then
        return self.startDuration:getTag(coerceType), self.endDuration:getTag(coerceType)
    else
        local t1, t4 = self.startTime:getTag(coerceType), self.endTime:getTag(coerceType)
        local t2 = t1 + self.startDuration:getTag(coerceType)
        local t3 = t4 - self.endDuration:getTag(coerceType)
        if not coerceType then
             self:checkPositive(t2,t3)
             assert(t1<=t2 and t2<=t3 and t3<=t4, string.format("Error: fade times must evaluate to t1<=t2<=t3<=t4, got %d<=%d<=%d<=%d", t1,t2,t3,t4))
        end
        return self.startAlpha, self.midAlpha, self.endAlpha, math.min(t1,t2), util.clamp(t2,t1,t3), math.clamp(t3,t2,t4), math.max(t4,t3) 
    end
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
    bord = {friendlyName="\\bord", type="ASSNumber", props={positive=true}, pattern="\\bord([%d%.]+)", format="\\bord%.2f"}, 
    xbord = {friendlyName="\\xbord", type="ASSNumber", props={positive=true}, pattern="\\xbord([%d%.]+)", format="\\xbord%.2f"}, 
    ybord = {friendlyName="\\ybord", type="ASSNumber",props={positive=true}, pattern="\\ybord([%d%.]+)", format="\\ybord%.2f"}, 
    shad = {friendlyName="\\shad", type="ASSNumber", pattern="\\shad([%-%d%.]+)", format="\\shad%.2f"}, 
    xshad = {friendlyName="\\xshad", type="ASSNumber", pattern="\\xshad([%-%d%.]+)", format="\\xshad%.2f"}, 
    yshad = {friendlyName="\\yshad", type="ASSNumber", pattern="\\yshad([%-%d%.]+)", format="\\yshad%.2f"}, 
    reset = {friendlyName="\\r", type="ASSReset", pattern="\\r([^\\}]*)", format="\\r"}, 
    alpha = {friendlyName="\\alpha", type="ASSHex", pattern="\\alpha&H(%x%x)&", format="\\alpha&H%02X&"}, 
    l1a = {friendlyName="\\1a", type="ASSHex", pattern="\\1a&H(%x%x)&", format="\\alpha&H%02X&"}, 
    l2a = {friendlyName="\\2a", type="ASSHex", pattern="\\2a&H(%x%x)&", format="\\alpha&H%02X&"}, 
    l3a = {friendlyName="\\3a", type="ASSHex", pattern="\\3a&H(%x%x)&", format="\\alpha&H%02X&"}, 
    l4a = {friendlyName="\\4a", type="ASSHex", pattern="\\4a&H(%x%x)&", format="\\alpha&H%02X&"}, 
    l1c = {friendlyName="\\1c", type="ASSColor", pattern="\\1?c&H(%x+)&", format="\\1c&H%02X%02X%02X&"}, 
    l2c = {friendlyName="\\2c", type="ASSColor", pattern="\\2c&H(%x+)&", format="\\2c&H%02X%02X%02X&"}, 
    l3c = {friendlyName="\\3c", type="ASSColor", pattern="\\3c&H(%x+)&", format="\\3c&H%02X%02X%02X&"}, 
    l4c = {friendlyName="\\4c", type="ASSColor", pattern="\\4c&H(%x+)&", format="\\4c&H%02X%02X%02X&"}, 
    clip = {friendlyName="\\clip", type="ASSClip", pattern="\\clip%((.-)%)"}, 
    iclip = {friendlyName="\\iclip", type="ASSClip", pattern="\\iclip%((.-)%)"}, 
    be = {friendlyName="\\be", type="ASSNumber", props={positive=true}, pattern="\\be([%d%.]+)", format="\\be%.2f"}, 
    blur = {friendlyName="\\blur", type="ASSNumber", props={positive=true}, pattern="\\blur([%d%.]+)", format="\\blur%.2f"}, 
    fax = {friendlyName="\\fax", type="ASSNumber", pattern="\\fax([%-%d%.]+)", format="\\fax%.2f"}, 
    fay = {friendlyName="\\fay", type="ASSNumber", pattern="\\fay([%-%d%.]+)", format="\\fay%.2f"}, 
    bold = {friendlyName="\\b", type="ASSWeight", pattern="\\b(%d+)"}, 
    italic = {friendlyName="\\i", type="ASSToggle", pattern="\\i([10])"}, 
    underline = {friendlyName="\\u", type="ASSToggle", pattern="\\u([10])"},
    fsp = {friendlyName="\\fsp", type="ASSNumber", pattern="\\fsp([%-%d%.]+)", format="\\fsp%.2f"},
    fs = {friendlyName="\\fs", type="ASSNumber", props={positive=true}, pattern="\\fs([%d%.]+)", format="\\fsp%.2f"},
    kfill = {friendlyName="\\k", type="ASSDuration", props={scale=10}, pattern="\\k([%d]+)", format="\\k%d"},
    ksweep = {friendlyName="\\kf", type="ASSDuration", props={scale=10}, pattern="\\kf([%d]+)", format="\\kf%d"},   -- because fuck \K and lua patterns
    kbord = {friendlyName="\\ko", type="ASSDuration", props={scale=10}, pattern="\\ko([%d]+)", format="\\ko%d"},
    pos = {friendlyName="\\pos", type="ASSPosition", pattern="\\pos%(([%-%d%.]+,[%-%d%.]+)%)", format="\\pos(%.2f,%.2f)"},
    move = {friendlyName="\\move", type="ASSMove", pattern="\\move([%-%d%.]+,[%-%d%.]+,[%-%d%.]+,[%-%d%.]+)"},
    org = {friendlyName="\\org", type="ASSPosition", pattern="\\org([%-%d%.]+,[%-%d%.]+)"},
    wrap = {friendlyName="\\q", type="ASSWrapStyle", pattern="\\q(%d)"},
    smplfade = {friendlyName="\\fad", type="ASSFade", props={simple=true}, pattern="\\fad%((%d+,%d+)%)", format="\\fad(%d,%d)"},
    fade = {friendlyName="\\fade", type="ASSFade", pattern="\\fade?%((.-)%)", format="\\fade(%d,%d,%d,%d,%d,%d,%d)"},
    transform = {friendlyName="\\t", type="ASSTransform", pattern="\\t%((.-)%)"},
}


meta.__index.getDefault = function(self,tag)
    -- returns an object with the default values for a tag in this line
end

meta.__index.addTag = function(self, tagName, val, pos)
    -- adds override tag from Defaults to start of line if not present
    -- pos: +n:n-th override tag; 0:first override tag and after resets -n: position in line
end

meta.__index.getTagString = function(self,tagName,val)
    if type(val) == "table" then -- TODO: better check
        return self.tagMap[tagName].format:format(val:getTag())
    else
        return re.sub(self.tagMap[tagName].format,"(%.*?[A-Za-z],?)+","%s"):format(tostring(val))
    end
end

meta.__index.getTagVal = function(self,tagName,string)
    return _G[self.tagMap[tagName].type](string,self.tagMap[tagName].props)
end

meta.__index.modTag = function(self, tagName, callback)
    local tags, tagsOrg = {},{}
    assert(self.tagMap[tagName], string.format("Error: can't find tag %s.\n",tagName))
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
        line:modTag("smplfade", function(tags) -- hardcoded for my convenience
            for i=1,#tags,1 do
                --tags[i]:add(self.value,10)
                tags[i]:add(10,20)
                --tags[i]:mul(self.value,5)
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
