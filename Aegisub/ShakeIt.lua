script_name="Shake It"
script_description="Lets you add a shaking effect to fbf typesets with configurable constraints."
script_version="0.0.3"
script_author="line0"

--[[REQUIRE lib-lyger.lua OF VERSION 1.1 OR HIGHER]]--
if pcall(require,"lib-lyger") and chkver("1.1") then
	local tinyPos = 0.0001
	
	function randomOffset(offMin,offMax,sign)
		if not sign or sign==0 then 
			sign = math.random(0,1) == 0 and -1 or 1 
		else sign = sign/math.abs(sign)
		end
		local off = sign*(offMin + math.random()*(offMax-offMin))
		return off
	end

	function distance(x1, y1, x2, y2)
		local dx, dy = x2-x1, y2-y1
		return math.sqrt(dx^2 + dy^2)
	end

	function normLength(x,y,rad)
		local norm = rad/distance(0,0,x,y)
		norm = norm == 1/0 and 1 or norm
		return x*norm, y*norm
	end

	function findInTable(table,prop,val,retIndex)
		for i=1,#table,1 do
			for p,v in pairs(table[i]) do
				if p==prop and v==val then
					return retIndex and i or true
				end
			end
		end
		return retIndex and 0 or false
	end

	function shakeIt(sub, sel)
		local dlg = {
			{
				class="label",
				label="Shaking Offset Limits (relative to original position): ",
				x=0, y=0, width=10, height=1,
			},
			{
				class="floatedit",
				name="offXMin",
				x=0, y=1, width=3, height=1,
				value=0, min=0, max=99999, step=1
			},
			{
				class="label",
				label="<  x  <",
				x=3, y=1, width=3, height=1,
			},
			{
				class="floatedit",
				name="offXMax",
				x=6, y=1, width=4, height=1,
				value=10, min=0, max=99999, step=1
			},
			{
				class="floatedit",
				name="offYMin",
				x=0, y=2, width=3, height=1,
				value=0, min=0, max=99999, step=1
			},
			{
				class="label",
				label="<  y  <",
				x=3, y=2, width=3, height=1,
			},
			{
				class="floatedit",
				name="offYMax",
				x=6, y=2, width=4, height=1,
				value=10, min=0, max=999999, step=1
			},
			{
				class="label",
				label="",
				x=0, y=3, width=10, height=1
			},
			{
				class="label",
				label="Angle between subsequent line offsets:",
				x=0, y=4, width=10, height=1,
			},
			{
				class="label",
				label="Min:",
				x=0, y=5, width=1, height=1,
			},
			{
				class="floatedit",
				name="angleMin",
				x=1, y=5, width=2, height=1,
				value=0, min=0, max=180, step=1
			},
			{
				class="label",
				label="°    Max:",
				x=3, y=5, width=3, height=1
			},
			{
				class="floatedit",
				name="angleMax",
				x=6, y=5, width=2, height=1,
				value=180, min=tinyPos, max=180, step=1
			},
			{
				class="label",
				label="°",
				x=8, y=5, width=2, height=1
			},
			{
				class="label",
				label="",
				x=0, y=6, width=10, height=1
			},
			{
				class="label",
				label="Constraints:",
				x=0, y=7, width=10, height=1
			},			
			{
				class="checkbox",
				name="fSignInvX", label="X offsets of subsequent lines must [",
				x=0, y=8, width=4, height=1
			},
			{
				class="checkbox",
				name="fSignInvXN", label="NOT  ] change sign.",
				x=4, y=8, width=6, height=1,
			},
			{
				class="checkbox",
				name="fSignInvY", label="Y offsets of subsequent lines must [",
				x=0, y=9, width=4, height=1
			},
			{
				class="checkbox",
				name="fSignInvYN", label="NOT  ] change sign.",
				x=4, y=9, width=6, height=1,
			},
			{
				class="checkbox",
				name="fSignInvEither", label="X or Y offsets of subsequent lines must change sign, ",
				x=0, y=10, width=7, height=1,
			},
			{
				class="checkbox",
				name="fSignInvNotBoth", label="but never both.",
				x=7, y=10, width=3, height=1,
			},
			{
				class="label",
				label="",
				x=0, y=11, width=10, height=1
			},
			{
				class="label",
				label="RNG Seed:",
				x=0, y=12, width=1, height=1,
			},
			{
				class="intedit",
				name="seed",
				x=1, y=12, width=2, height=1,
				value=os.time()
			},
		}

		local btn, res = aegisub.dialog.display(dlg)
		if btn then 
			--do some validation

			local err = {"The following errors occured: "}
			
			if res.offXMax < res.offXMin then
				err[#err+1] = "Mininum x offset ("..res.offXMin..") must not be bigger than maximum x offset ("..res.offXMax..")."
			end
			if res.offYMax < res.offYMin then
				err[#err+1] = "Mininum y offset ("..res.offYMin..") must not be bigger than maximum y offset ("..res.offYMax..")."
			end
			if res.angleMax < res.angleMin then
				err[#err+1] = "Mininum angle ("..res.angleMin..") must not be bigger than maximum angle ("..res.angleMax..")."
			end
			if  res.fSignInvX and not res.fSignInvXN 
			and res.fSignInvY and not res.fSignInvYN and res.angleMax < 90 then
				err[#err+1] = "Forced sign inversion for x and y require an angle of at least 90°."
			elseif res.fSignInvX and res.fSignInvXN 
			and     res.fSignInvY and res.fSignInvYN and res.angleMin > 90 then
				err[#err+1] = "No sign inversion for x and y requires an angle of at most 90°."
			end
			if res.fSignInvYN and res.fSignInvXN and res.fSignInvEither then
				err[#err+1] = "Can't change signs of either X or Y offsets because no sign changes are allowed."
			elseif res.fSignInvX and res.fSignInvY and res.fSignInvNotBoth then
				err[#err+1] = "Can't change signs of only X or Y offsets because sign changes are enforced for both."
			end

			if err[2] then aegisub.log(table.concat(err,"\n"))
			else shakeItProc(sub, sel, res) end
		end
	end

	function shakeItApply(sub, startTimes)
		aegisub.progress.task("Shaking...")
		for j,startTime in ipairs(startTimes) do
			aegisub.progress.set(50+50*j/#startTimes)
			for i=1,#startTime.lines,1 do
				local line=sub[startTime.lines[i]]
				
				--karaskel shenanigans
				local meta,styles = karaskel.collect_head(sub, false)
				karaskel.preproc_line(sub,meta,styles,line)
				local x,y = get_pos(line)
				-- aegisub.log("Line: " .. startTime.lines[i] .. " x: " .. x .. " y: " .. y .. "Offset x: " .. startTime.offX .. " y: " .. startTime.offY .."\n")
				line.text=line_exclude(line.text,{"pos"})
				line.text=line.text:gsub("^{", "{\\pos(".. float2str(x+startTime.offX)..",".. float2str(y+startTime.offY)..")")
				sub[startTime.lines[i]] = line
			end
		end
	end

	function shakeItProc(sub, sel, res)
		local startTimes = {}
		for i=1,#sel,1 do
			local line=sub[sel[i]]
			idx = findInTable(startTimes,"startTime", line.start_time,true)
			if idx==0 then table.insert(startTimes, {startTime=line.start_time, lines={sel[i]}})
			else table.insert(startTimes[idx].lines,sel[i]) end
		end
		table.sort(startTimes, function(a,b) return a.startTime<b.startTime end)

		math.randomseed(res.seed)
		local fSignInvX, fSignInvY = res.fSignInvXN and -1 or res.fSignInvX and 1 or 0, res.fSignInvYN and -1 or res.fSignInvY and 1 or 0
		local a = distance(0, 0, res.offXMax, res.offYMax) -- max circle radius
		local offXPrev, offYPrev = tinyPos, tinyPos

		aegisub.progress.task("Rolling...")
		for i=1,#startTimes,1 do
			aegisub.progress.set(50*i/#sel)
			
			local angle, isFirstLine, maxRolls = -1, false, 10000
			while not isFirstLine and (angle < res.angleMin or angle > res.angleMax) do 
				local xSign = res.fSignInvEither and res.fSignInvYN and -offXPrev or ((offXPrev+tinyPos)*-fSignInvX)
				offX = randomOffset(res.offXMin,res.offXMax, res.fSignInvNotBoth and res.fSignInvY and offXPrev or xSign)

				local xSignChng = offX*offXPrev < 0
				local ySign = res.fSignInvEither and not xSignChng and -offYPrev or ((offYPrev+tinyPos)*-fSignInvY)
				offY = randomOffset(res.offYMin,res.offYMax, res.fSignInvNotBoth and xSignChng and offYPrev or ySign)

				--aegisub.log("offX: " .. offX .. " offY: " .. offY .. "\n")

				local offXNorm, offYNorm = normLength(offX, offY, a)
				local offXPrevNorm, offYPrevNorm = normLength(offXPrev, offYPrev,a)
				local d = distance(offXPrevNorm, offYPrevNorm, normLength(offX, offY, a))

				angle=math.acos((2*a^2-math.abs(d)^2)/2/a^2)*180/math.pi
				--aegisub.log("Angle: " .. angle .. "\n")
				isFirstLine = i==1

				maxRolls = maxRolls - 1
				if maxRolls == 0 then error("ERROR: Couldn't find offset that satifies chosen angle constraints (Min: " .. 
											res.angleMin .. "°, Max: " .. res.angleMax .. "° for line" .. startTimes[i].lines[1] .. ". Aborting.") end
			end

			startTimes[i].offX, startTimes[i].offY = offX, offY
			offXPrev, offYPrev = offX, offY
		end
		shakeItApply(sub, startTimes)
	end

	aegisub.register_macro(script_name, script_description, shakeIt)


--[[HANDLING FOR lib-lyger.lua NOT FOUND CASE]]--
else
	require "clipboard"
	function lib_err()
		aegisub.dialog.display({{class="label",
			label="lib-lyger.lua is missing or out-of-date.\n"..
			"Please go to:\n\n"..
			"https://github.com/lyger/Aegisub_automation_scripts\n\n"..
			"and download the latest version of lib-lyger.lua.\n"..
			"(The URL will be copied to your clipboard once you click OK)",
			x=0,y=0,width=1,height=1}})
		clipboard.set("https://github.com/lyger/Aegisub_automation_scripts")
	end
	aegisub.register_macro(script_name,script_description,lib_err)
end