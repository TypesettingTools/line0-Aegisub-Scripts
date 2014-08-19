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

string.formatFancy = function(fmtStr,...)
    local i, args = 0, {...}
    local outStr=fmtStr:gsub("(%%[%+%- 0]*%d*.?%d*[hlLzjtI]*)([aAcedEfFgGcnNopiuAsuxX])", function(opts,type_)
        i=i+1
        if type_=="N" then
            return string.format(opts.."f",args[i]):gsub("%.(%d-)0+$","%.%1"):gsub("%.$",""), ""
        else return string.format(opts..type_,args[i]), "" end
    end)
    return outStr
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

table.find = function(tbl,findVal)
    for key,val in pairs(tbl) do
        if val==findVal then return key end
    end
    return nil
end

table.join = function(tbl1,tbl2)
    local tbl = {}
    for _,val in ipairs(tbl1) do table.insert(tbl,val) end
    for _,val in ipairs(tbl2) do table.insert(tbl,val) end
    return tbl
end

table.keys = function(tbl)
    local keys={}
    for key,_ in pairs(tbl) do
        table.insert(keys, key)
    end
    return keys
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

util.RGB_to_HSV = function(r,g,b)
    r,g,b = util.clamp(r,0,255), util.clamp(g,0,255), util.clamp(b,0,255)
    local min, max = math.min(r,g,b), math.max(r,g,b)
    local v, delta = max, max-min
    if delta==0 then 
        return 0,0,0
    else         
        local s,c = delta/max, (r==max and g-b) or (g==max and b-r+2) or (r-g+4)
        local h = 60*c/delta
        return h>0 and h or h+360, s, v
    end
end


returnAll = function(...) -- blame lua
    local arr={}
    for _,results in ipairs({...}) do
        for _,result in ipairs(results) do
            arr[#arr+1] = result
        end
    end
    return unpack(arr)
end
------ Tag Classes ---------------------

function createASSClass(typeName,baseClass,order,types,tagProps)
  local cls, baseClass = {}, baseClass or {}
  for key, val in pairs(baseClass) do
    cls[key] = val
  end

  cls.__index = cls
  cls.instanceOf = {[cls] = true}
  cls.typeName = typeName
  cls.__meta__ = { 
       order = order,
       types = types
  }
  cls.__defProps = table.merge(cls.__defProps or {},tagProps or {})

  setmetatable(cls, {
    __call = function (cls, ...)
        local self = setmetatable({__tag = util.copy(cls.__defProps)}, cls)
        self:new(...)
        return self
    end})
  return cls
end

ASSBase = createASSClass("ASSBase")
function ASSBase:checkType(type_, ...) --TODO: get rid of
    for _,val in ipairs({...}) do
        result = (type_=="integer" and math.isInt(val)) or type(val)==type_
        assert(result, string.format("Error: %s must be a %s, got %s.\n",self.typeName,type_,type(val)))
    end
end

function ASSBase:checkPositive(...)
    self:checkType("number",...)
    for _,val in ipairs({...}) do
        assert(val >= 0, string.format("Error: %s tagProps do not permit numbers < 0, got %d.\n", self.typeName,val))
    end
end

function ASSBase:checkRange(min,max,...)
    self:checkType("number",...)
    for _,val in ipairs({...}) do
        assert(val >= min and val <= max, string.format("Error: %s must be in range %d-%d, got %d.\n",self.typeName,min,max,val))
    end
end

function ASSBase:CoerceNumber(num, default)
    num = tonumber(num)
    if not num then num=default or 0 end
    if self.__tag.positive then num=math.max(num,0) end
    if self.__tag.range then num=util.clamp(num,self.__tag.range[1], self.__tag.range[2]) end
    return num 
end

function ASSBase:getArgs(args, default, coerce, ...)
    assert(type(args)=="table", "Error: first argument to getArgs must be a table of packed arguments, got " .. type(args) ..".\n")
    -- check if first arg is a compatible ASSTag and dump into args 
    if #args == 1 and type(args[1]) == "table" and args[1].typeName then
        local res, selfClasses = false, {}
        for key,val in pairs(self.instanceOf) do
            if val then table.insert(selfClasses,key) end
        end
        for _,class in ipairs(table.join(table.pack(...),selfClasses)) do
            res = args[1].instanceOf[class] and true or res
        end
        assert(res, string.format("%s does not accept instances of class %s as argument.\n", self.typeName, args[1].typeName))
        args=table.pack(args[1]:get())
    end

    local valTypes, j, outArgs = self.__meta__.types, 1, {}
    for i,valName in ipairs(self.__meta__.order) do
        -- write defaults
        args[j] = type(args[j])=="nil" and default or args[j]

        if type(valTypes[i])=="table" and valTypes[i].instanceOf then
            local subCnt = #valTypes[i].__meta__.order
            outArgs = table.join(outArgs, {valTypes[i]:getArgs(table.sliceArray(args,j,j+subCnt-1), default, coerce)})
            j=j+subCnt-1

        elseif coerce then
            local tagProps = self.__tag or self.__defProps
            local map = {
                number = function() return tonumber(args[j],tagProps.base or 10)*(tagProps.scale or 1) end,
                string = function() return tostring(args[j]) end,
                boolean = function() return not (args[j] == 0 or not args[j]) end
            }
            table.insert(outArgs, args[j]~= nil and map[valTypes[i]]() or nil)
        else table.insert(outArgs, args[j]) end

        j=j+1
    end
    --self:typeCheck(unpack(outArgs))
    return unpack(outArgs)
end

function ASSBase:typeCheck(...)
    local valTypes, j, args = self.__meta__.types, 1, {...}
    --assert(#valNames >= #args, string.format("Error: too many arguments. Expected %d, got %d.\n",#valNames,#args))
    for i,valName in ipairs(self.__meta__.order) do
        if type(valTypes[i])=="table" and valTypes[i].instanceOf then
            if type(args[j])=="table" and args[j].instanceOf then
                self[valName]:typeCheck(args[j])
                j=j+1
            else
                local subCnt = #valTypes[i].__meta__.order
                valTypes[i]:typeCheck(unpack(table.sliceArray(args,j,j+subCnt-1)))
                j=j+subCnt
            end
        else    
            assert(type(args[i])==valTypes[i] or type(args[i])=="nil" or valTypes[i]=="nil",
                   string.format("Error: bad type for argument %d (%s). Expected %s, got %s.\n", i,valName,type(self[valName]),type(args[i]))) 
        end
    end
end

function ASSBase:get()
    local vals = {}
    for _,valName in ipairs(self.__meta__.order) do
        if type(self[valName])=="table" and self[valName].instanceOf then
            for _,cval in pairs({self[valName]:get()}) do vals[#vals+1]=cval end
        else 
            vals[#vals+1] = self[valName]
        end
    end
    return unpack(vals)
end

function ASSBase:commonOp(method, callback, default, ...)
    local args = {self:getArgs({...}, default, false)}
    local j, res = 1, {}
    for _,valName in ipairs(self.__meta__.order) do
        if type(self[valName])=="table" and self[valName].instanceOf then
            local subCnt = #self[valName].__meta__.order
            res=table.join(res,{self[valName][method](self[valName],unpack(table.sliceArray(args,j,j+subCnt-1)))})
            j=j+subCnt
        else 
            self[valName]=callback(self[valName],args[j])
            j=j+1
            table.insert(res,self[valName])
        end
    end
    return unpack(res)
end

function ASSBase:add(...)
    return self:commonOp("add", function(a,b) return a+b end, 0, ...)
end

function ASSBase:mul(...)
    return self:commonOp("mul", function(a,b) return a*b end, 1, ...)
end

function ASSBase:pow(...)
    return self:commonOp("pow", function(a,b) return a^b end, 1, ...)
end

function ASSBase:set(...)
    return self:commonOp("set", function(a,b) return b end, nil, ...)
end

function ASSBase:mod(callback, ...)
    return self:set(callback(self:get(...)))
end

function ASSBase:readProps(tagProps)
    for key, val in pairs(tagProps or {}) do
        self.__tag[key] = val
    end
end


ASSNumber = createASSClass("ASSNumber", ASSBase, {"value"}, {"number"}, {base=10, precision=3, scale=1})

function ASSNumber:new(val, tagProps)
    self:readProps(tagProps)
    self.value = type(val)=="table" and self:getArgs(val,0,true) or val or 0
    self:typeCheck(self.value)
    if self.__tag.positive then self:checkPositive(self.value) end
    if self.__tag.range then self:checkRange(self.__tag.range[1], self.__tag.range[2], self.value) end
    return self
end

function ASSNumber:getTag(coerce, precision)
    self:readProps(tagProps)
    precision = precision or self.__tag.precision
    local val = self.value
    if coerce then
        self:CoerceNumber(val,0)
    else
        assert(precision <= self.__tag.precision, string.format("Error: output wih precision %d is not supported for %s (maximum: %d).\n", 
               precision,self.typeName,self.__tag.precision))
        self:typeCheck(self.value)
        if self.__tag.positive then self:checkPositive(val) end
        if self.__tag.range then self:checkRange(self.__tag.range[1], self.__tag.range[2],val) end
    end
    return math.round(val,self.__tag.precision)
end


ASSPosition = createASSClass("ASSPosition", ASSBase, {"x","y"}, {"number", "number"})
function ASSPosition:new(valx, valy, tagProps)
    if type(valx) == "table" then
        tagProps = valy
        valx, valy = self:getArgs(valx,0,true)
    end
    self:readProps(tagProps)
    self:typeCheck(valx, valy)
    self.x, self.y = valx, valy
    return self
end


function ASSPosition:getTag(coerce, precision)
    local x,y = self.x, self.y
    if coerce then
        x,y = self:CoerceNumber(x,0), self:CoerceNumber(y,0)
    else 
        self:checkType("number", x, y)
    end
    precision = precision or 3
    local x = math.round(x,precision)
    local y = math.round(y,precision)
    return x,y
end
-- TODO: ASSPosition:move(ASSPosition) -> return \move tag

ASSTime = createASSClass("ASSTime", ASSNumber, {"value"}, {"number"}, {precision=0})
-- TODO: implement adding by framecount

function ASSTime:getTag(coerce, precision)
    precision = precision or 0
    local val = self.value
    if coerce then
        precision = math.min(precision,0)
        val = self:CoerceNumber(0)
    else
        assert(precision <= 0, "Error: " .. self.typeName .." doesn't support floating point precision")
        self:checkType("number", self.value)
        if self.__tag.positive then self:checkPositive(self.value) end
    end
    val = val/self.__tag.scale
    return math.round(val,precision)
end

ASSDuration = createASSClass("ASSDuration", ASSTime, {"value"}, {"number"}, {positive=true})
ASSHex = createASSClass("ASSHex", ASSNumber, {"value"}, {"number"}, {range={0,255}, base=16, precision=0})

ASSColor = createASSClass("ASSColor", ASSBase, {"r","g","b"}, {ASSHex,ASSHex,ASSHex})   
function ASSColor:new(r,g,b, tagProps)
    if type(r) == "table" then
        tagProps = g
        r,g,b = self:getArgs({r[1]:match("(%x%x)(%x%x)(%x%x)")},0,true)
    end 
    self:readProps(tagProps)
    self.r, self.g, self.b = ASSHex(r), ASSHex(g), ASSHex(b)
    return self
end

function ASSColor:addHSV(h,s,v)
    local ho,so,vo = util.RGB_to_HSV(self.r:get(),self.g:get(),self.b:get())
    local r,g,b = util.HSV_to_RGB(ho+h,util.clamp(so+s,0,1),util.clamp(vo+v,0,1))
    return self:set(r,g,b)
end

function ASSColor:getTag(coerce)
    return self.b:getTag(coerce), self.g:getTag(coerce), self.r:getTag(coerce)
end

ASSFade = createASSClass("ASSFade", ASSBase,
    {"startDuration", "endDuration", "startTime", "endTime", "startAlpha", "midAlpha", "endAlpha"},
    {ASSDuration,ASSDuration,ASSTime,ASSTime,ASSHex,ASSHex,ASSHex}
)
function ASSFade:new(startDuration,endDuration,startTime,endTime,startAlpha,midAlpha,endAlpha,tagProps)
    if type(startDuration) == "table" then
        tagProps = endDuration or {}
        prms={self:getArgs(startDuration,nil,true)}
        if #prms == 2 then 
            startDuration, endDuration = unpack(prms)
            tagProps.simple = true
        elseif #prms == 7 then
            startDuration, endDuration, startTime, endTime = prms[5]-prms[4], prms[7]-prms[6], prms[4], prms[7] 
        end
    end 
    self:readProps(tagProps)

    self.startDuration, self.endDuration = ASSDuration(startDuration), ASSDuration(endDuration)
    self.startTime = self.__tag.simple and ASSTime(0) or ASSTime(startTime)
    self.endTime = self.__tag.simple and nil or ASSTime(endTime)
    self.startAlpha = self.__tag.simple and ASSHex(0) or ASSHex(startAlpha)
    self.midAlpha = self.__tag.simple and ASSHex(255) or ASSHex(midAlpha)
    self.endAlpha = self.__tag.simple and ASSHex(0) or ASSHex(endAlpha)
    return self
end

function ASSFade:getTag(coerce)
    if self.__tag.simple then
        return self.startDuration:getTag(coerce), self.endDuration:getTag(coerce)
    else
        local t1, t4 = self.startTime:getTag(coerce), self.endTime:getTag(coerce)
        local t2 = t1 + self.startDuration:getTag(coerce)
        local t3 = t4 - self.endDuration:getTag(coerce)
        if not coerce then
             self:checkPositive(t2,t3)
             assert(t1<=t2 and t2<=t3 and t3<=t4, string.format("Error: fade times must evaluate to t1<=t2<=t3<=t4, got %d<=%d<=%d<=%d", t1,t2,t3,t4))
        end
        return self.startAlpha, self.midAlpha, self.endAlpha, math.min(t1,t2), util.clamp(t2,t1,t3), math.clamp(t3,t2,t4), math.max(t4,t3) 
    end
end

ASSMove = createASSClass("ASSMove", ASSBase,
    {"startPos", "endPos", "startTime", "endTime"},
    {ASSPosition,ASSPosition,ASSTime,ASSTime}
)
function ASSMove:new(startPosX,startPosY,endPosX,endPosY,startTime,endTime,tagProps)
    if type(startPosX) == "table" then
        tagProps = startPosY
        startPosX,startPosY,endPosX,endPosY,startTime,endTime = self:getArgs(startPosX, nil, true)
    end
    self:readProps(tagProps)
    assert((startTime==endTime and self.__tag.simple~=false) or (startTime and endTime), "Error: creating a complex move requires both start and end time.\n")
    
    if startTime==nil or endTime==nil or (startTime==0 and endTime==0) then
        self.__tag.simple = true
        self.__tag.name = "moveSmpl"
    else self.__tag.simple = false end

    self.startPos = ASSPosition(startPosX,startPosY)
    self.endPos = ASSPosition(endPosX,endPosY)
    self.startTime = ASSTime(startTime)
    self.endTime = ASSTime(endTime)
    return self
end

function ASSMove:getTag(coerce)
    if self.__tag.simple or self.__tag.name=="moveSmpl" then
        return returnAll({self.startPos:getTag(coerce)}, {self.endPos:getTag(coerce)})
    else
        if not coerce then
             assert(startTime<=endTime, string.format("Error: move times must evaluate to t1<=t2, got %d<=%d.\n", startTime,endTime))
        end
        local t1,t2 = self.startTime:getTag(coerce), self.endTime:getTag(coerce)
        return returnAll({self.startPos:getTag(coerce)}, {self.endPos:getTag(coerce)},
               {math.min(t1,t2)}, {math.max(t2,t1)}) 
    end
end

ASSToggle = createASSClass("ASSToggle", ASSBase, {"value"}, {"boolean"})
function ASSToggle:new(val, tagProps)
    self:readProps(tagProps)
    if type(val) == "table" then
        self.value = self:getArgs(val,false,true)
    else 
        self.value = val or false 
    end
    self:typeCheck(self.value)
    return self
end

function ASSToggle:toggle(state)
    assert(type(state)=="boolean" or type(state)=="nil", "Error: state argument to toggle must be true, false or nil.\n")
    self.value = state==nil and not self.value or state
    return self.value
end

function ASSToggle:getTag(coerce)
    if not coerce then self:typeCheck(self.value) end
    return self.value and 1 or 0
end

ASSIndexed = createASSClass("ASSIndexed", ASSNumber, {"value"}, {"number"}, {precision=0, positive=true})
function ASSIndexed:cycle(down)
    local min, max = self.__tag.range[1], self.__tag.range[2]
    if down then
        return self.value<=min and self:set(max) or self:add(-1)
    else
        return self.value>=max and self:set(min) or self:add(1)
    end
end

ASSAlign = createASSClass("ASSAlign", ASSIndexed, {"value"}, {"number"}, {range={1,9}, default=5})

function ASSAlign:up()
    if self.value<7 then return self:add(3)
    else return false end
end

function ASSAlign:down()
    if self.value>3 then return self:add(-3)
    else return false end
end

function ASSAlign:left()
    if self.value%3~=1 then return self:add(-1)
    else return false end
end

function ASSAlign:right()
    if self.value%3~=0 then return self:add(1)
    else return false end
end

ASSWeight = createASSClass("ASSWeight", ASSBase, {"weightClass","bold"}, {ASSNumber,ASSToggle})
function ASSWeight:new(val, tagProps)
    if type(val) == "table" then
        local val = self:getArgs(val,0,true)
        self.bold = (val==1 and true) or (val==0 and false)
        self.weightClass = val>1 and true or 0
    elseif type(val) == "boolean" then
        self.bold, self.weightClass = val, 0
    else self.weightClass = val
    end
    self:readProps(tagProps)
    self.bold = ASSToggle(self.bold)
    self.weightClass = ASSNumber(self.weightClass,{positive=true,precision=0})
    return self
end

function ASSWeight:getTag(coerce)
    if self.weightClass.value >0 then
        return self.weightClass:getTag(coerce)
    else
        return self.bold:getTag(coerce)
    end
end

function ASSWeight:setBold(state)
    self.bold:set(type(state)=="nil" and true or state)
    self.weightClass.value = 0
end

function ASSWeight:toggleBold()
    self.bold:toggle()
end

function ASSWeight:setWeight(weightClass)
    self.bold:set(false)
    self.weightClass:set(weightClass or 400)
end

ASSWrapStyle = createASSClass("ASSWrapStyle", ASSIndexed, {"value"}, {"number"}, {range={0,3}, default=0})

------ Extend Line Object --------------

local meta = getmetatable(Line)
meta.__index.mapTag = function(self, tagName)
    local function getStyleRef(tag)
        if tag:find("alpha") then 
            local alpha = true
            tag = tag:gsub("alpha", "color")
        end
        if tag:find("color") then
            return alpha and {self.styleref[tag]:sub(3,4)} or {self.styleref[tag]:sub(5,10)}
        else return  {self.styleref[tag]} end
    end

    if not  self.tagMap then
        self:extraMetrics(self.styleref)
        self.tagMap = {
            scaleX= {friendlyName="\\fscx", type="ASSNumber", pattern="\\fscx([%d%.]+)", format="\\fscx%.3N", default=getStyleRef("scale_x")},
            scaleY = {friendlyName="\\fscy", type="ASSNumber", pattern="\\fscy([%d%.]+)", format="\\fscy%.3N", default=getStyleRef("scale_y")},
            align = {friendlyName="\\an", type="ASSAlign", pattern="\\an([1-9])", format="\\an%d", default=getStyleRef("align")},
            angleZ = {friendlyName="\\frz", type="ASSNumber", pattern="\\frz?([%-%d%.]+)", format="\\frz%.3N", default=getStyleRef("angle")}, 
            angleY = {friendlyName="\\fry", type="ASSNumber", pattern="\\fry([%-%d%.]+)", format="\\frz%.3N", default=0},
            angleX = {friendlyName="\\frx", type="ASSNumber", pattern="\\frx([%-%d%.]+)", format="\\frz%.3N", default=0}, 
            outline = {friendlyName="\\bord", type="ASSNumber", props={positive=true}, pattern="\\bord([%d%.]+)", format="\\bord%.2N", default=getStyleRef("outline")}, 
            outlineX = {friendlyName="\\xbord", type="ASSNumber", props={positive=true}, pattern="\\xbord([%d%.]+)", format="\\xbord%.2N", default=getStyleRef("outline")}, 
            outlineY = {friendlyName="\\ybord", type="ASSNumber",props={positive=true}, pattern="\\ybord([%d%.]+)", format="\\ybord%.2N", default=getStyleRef("outline")}, 
            shadow = {friendlyName="\\shad", type="ASSNumber", pattern="\\shad([%-%d%.]+)", format="\\shad%.2N", default=getStyleRef("shadow")}, 
            shadowX = {friendlyName="\\xshad", type="ASSNumber", pattern="\\xshad([%-%d%.]+)", format="\\xshad%.2N", default=getStyleRef("shadow")}, 
            shadowY = {friendlyName="\\yshad", type="ASSNumber", pattern="\\yshad([%-%d%.]+)", format="\\yshad%.2N", default=getStyleRef("shadow")}, 
            reset = {friendlyName="\\r", type="ASSReset", pattern="\\r([^\\}]*)", format="\\r"}, 
            alpha = {friendlyName="\\alpha", type="ASSHex", pattern="\\alpha&H(%x%x)&", format="\\alpha&H%02X&", default=0}, 
            alpha1 = {friendlyName="\\1a", type="ASSHex", pattern="\\1a&H(%x%x)&", format="\\alpha&H%02X&", default=getStyleRef("alpha1")}, 
            alpha2 = {friendlyName="\\2a", type="ASSHex", pattern="\\2a&H(%x%x)&", format="\\alpha&H%02X&", default=getStyleRef("alpha2")}, 
            alpha3 = {friendlyName="\\3a", type="ASSHex", pattern="\\3a&H(%x%x)&", format="\\alpha&H%02X&", default=getStyleRef("alpha3")}, 
            alpha4 = {friendlyName="\\4a", type="ASSHex", pattern="\\4a&H(%x%x)&", format="\\alpha&H%02X&", default=getStyleRef("alpha4")}, 
            color = {friendlyName="\\c", type="ASSColor", pattern="\\c&H(%x+)&", format="\\c&H%02X%02X%02X&", default=getStyleRef("color1")}, 
            color1 = {friendlyName="\\1c", type="ASSColor", pattern="\\1c&H(%x+)&", format="\\1c&H%02X%02X%02X&", default=getStyleRef("color1")}, 
            color2 = {friendlyName="\\2c", type="ASSColor", pattern="\\2c&H(%x+)&", format="\\2c&H%02X%02X%02X&", default=getStyleRef("color2")}, 
            color3 = {friendlyName="\\3c", type="ASSColor", pattern="\\3c&H(%x+)&", format="\\3c&H%02X%02X%02X&", default=getStyleRef("color3")}, 
            color4 = {friendlyName="\\4c", type="ASSColor", pattern="\\4c&H(%x+)&", format="\\4c&H%02X%02X%02X&", default=getStyleRef("color4")}, 
            clip = {friendlyName="\\clip", type="ASSClip", pattern="\\clip%((.-)%)"}, 
            iclip = {friendlyName="\\iclip", type="ASSClip", pattern="\\iclip%((.-)%)"}, 
            be = {friendlyName="\\be", type="ASSNumber", props={positive=true}, pattern="\\be([%d%.]+)", format="\\be%.2N", default=0}, 
            blur = {friendlyName="\\blur", type="ASSNumber", props={positive=true}, pattern="\\blur([%d%.]+)", format="\\blur%.2N", default=0}, 
            fax = {friendlyName="\\fax", type="ASSNumber", pattern="\\fax([%-%d%.]+)", format="\\fax%.2N", default=0}, 
            fay = {friendlyName="\\fay", type="ASSNumber", pattern="\\fay([%-%d%.]+)", format="\\fay%.2N", default=0}, 
            bold = {friendlyName="\\b", type="ASSWeight", pattern="\\b(%d+)", format="\\b%d", default=getStyleRef("bold")}, 
            italic = {friendlyName="\\i", type="ASSToggle", pattern="\\i([10])", format="\\i%d", default=getStyleRef("italic")}, 
            underline = {friendlyName="\\u", type="ASSToggle", pattern="\\u([10])", format="\\u%d", default=getStyleRef("underline")},
            spacing = {friendlyName="\\fsp", type="ASSNumber", pattern="\\fsp([%-%d%.]+)", format="\\fsp%.2N", default=getStyleRef("spacing")},
            fontsize = {friendlyName="\\fs", type="ASSNumber", props={positive=true}, pattern="\\fs([%d%.]+)", format="\\fsp%.2N", default=getStyleRef("fontsize")},
            kFill = {friendlyName="\\k", type="ASSDuration", props={scale=10}, pattern="\\k([%d]+)", format="\\k%d", default=0},
            kSweep = {friendlyName="\\kf", type="ASSDuration", props={scale=10}, pattern="\\kf([%d]+)", format="\\kf%d", default=0},
            kSweepAlt = {friendlyName="\\K", type="ASSDuration", props={scale=10}, pattern="\\K([%d]+)", format="\\K%d", default=0},
            kBord = {friendlyName="\\ko", type="ASSDuration", props={scale=10}, pattern="\\ko([%d]+)", format="\\ko%d", default=0},
            position = {friendlyName="\\pos", type="ASSPosition", pattern="\\pos%(([%-%d%.]+,[%-%d%.]+)%)", format="\\pos(%.2N,%.2N)", default={self:getDefaultPosition(self.styleref)}},
            moveSmpl = {friendlyName=nil, type="ASSMove", props={simple=true}, format="\\move(%.2N,%.2N,%.2N,%.2N)", default={self.xPosition, self.yPosition, self.xPosition, self.yPosition}}, -- only for output formatting
            move = {friendlyName="\\move", type="ASSMove", pattern="\\move%(([%-%d%.,]+)%)", format="\\move(%.2N,%.2N,%.2N,%.2N,%.2N,%.2N)", default={self.xPosition, self.yPosition, self.xPosition, self.yPosition}},
            org = {friendlyName="\\org", type="ASSPosition", pattern="\\org([%-%d%.]+,[%-%d%.]+)", format="\\org(%.2N,%.2N)", default={self.xPosition, self.yPosition}},
            wrap = {friendlyName="\\q", type="ASSWrapStyle", pattern="\\q(%d)", format="\\q%d", default=0},
            fadeSmpl = {friendlyName="\\fad", type="ASSFade", props={simple=true}, pattern="\\fad%((%d+,%d+)%)", format="\\fad(%d,%d)", default={0,0}},
            fade = {friendlyName="\\fade", type="ASSFade", pattern="\\fade?%((.-)%)", format="\\fade(%d,%d,%d,%d,%d,%d,%d)", default={255,0,255,0,0,0,0}},
            transform = {friendlyName="\\t", type="ASSTransform", pattern="\\t%((.-)%)"},
        }
    end

    if not self.tagMap[tagName] then 
        for key,val in pairs(self.tagMap) do
            if val.friendlyName == tagName then 
                tagName = key
            break end
        end
    end

    assert(self.tagMap[tagName], string.format("Error: can't find tag %s.\n",tagName))
    return self.tagMap[tagName], tagName
end

meta.__index.getDefaultTag = function (self,tagName)
    local tagData, tagName = self:mapTag(tagName)  -- make sure to not pass friendlyNames into ASSTypes
    return _G[tagData.type](tagData.default, table.merge(tagData.props or {},{name=tagName}))
end

meta.__index.addTag = function(self,tagName,val,pos)
    if type(val) == "table" and val.instanceOf then
        tagName = tagName or val.__tag.name
    else
        local tagData = self:mapTag(tagName)
        if val==nil then val=self:getDefaultTag(tagName) end
    end

    local _,linePos = self.text:find("{.-}")
    if linePos then 
        self.text = self.text:sub(0,linePos-1)..self:getTagString(nil,val)..self.text:sub(linePos,self.text:len())
    else
        self.text = string.format("{%s}%s", self:getTagString(tagName,val), self.text)
    end

    return val
    -- TODO: pos: +n:n-th override tag; 0:first override tag and after resets -n: position in line
end

meta.__index.getTagString = function(self,tagName,val)
    if type(val) == "table" and val.instanceOf then
        tagName = tagName or val.__tag.name
        return self:mapTag(tagName).format:formatFancy(val:getTag(true))
    else
        return re.sub(self:mapTag(tagName).format,"(%.*?[A-Za-z],?)+","%s"):formatFancy(tostring(val))
    end
end

meta.__index.getTags = function(self,tagName,asStrings)
    local tagData, tagName = self:mapTag(tagName) -- make sure to not pass friendlyNames into ASSTypes
    local tags={}
    for tag in self.text:gmatch("{.-" .. tagData.pattern .. ".-}") do
        prms={}
        for prm in tag:gmatch("([^,]+)") do prms[#prms+1] = prm end
        tags[#tags+1] = asStrings and self:getTagString(tagName,tag) or
                        _G[tagData.type](prms,table.merge(tagData.props or {},{name=tagName}))
    end
    return tags
end

meta.__index.modTag = function(self, tagName, callback)
    local tags, orgStrings = self:getTags(tagName), self:getTags(tagName, true)

    if #orgStrings==0 then
        local newTag = self:addTag(tagName,nil)
        tags, orgStrings = {newTag}, {self:getTagString(nil,newTag)}
    end
    
    for i,tag in pairs(callback(tags)) do
        self.text = self.text:gsub(string.patternEscape(orgStrings[i]), self:getTagString(nil,tags[i]), 1)
    end

    return #tags>0
end

setmetatable(Line, meta)

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
