script_name="Shake It"
script_description="Lets you add a shaking effect to fbf typesets with configurable constraints."
script_version="0.0.1"
script_author="line0"

--[[REQUIRE lib-lyger.lua OF VERSION 1.1 OR HIGHER]]--
if pcall(require,"lib-lyger") and chkver("1.1") then
	local tinyPos = 0.0001
	
	function randomOffset(n,offMin,offMax,sign)
		if not sign or sign==0 then 
			sign = math.random(0,1) == 0 and -1 or 1 
		else sign = sign/math.abs(sign)
		end

		local off = math.random(offMin*sign,offMax*sign)
		return n+off, off
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

	function shakeIt(sub, sel)
		local dlg = {
			{
				class="label",
				label="Shaking Offset Limits (relative to original position): ",
				x=0, y=0, width=10, height=1,
			},
			{
				class="floatedit",
				name="xOffMin",
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
				name="xOffMax",
				x=6, y=1, width=4, height=1,
				value=10, min=0, max=99999, step=1
			},
			{
				class="floatedit",
				name="yOffMin",
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
				name="yOffMax",
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
			
			if res["xOffMax"] < res["xOffMin"] then
				err[#err+1] = "Mininum x offset ("..res["xOffMin"]..") must not be bigger than maximum x offset ("..res["xOffMax"]..")."
			end
			if res["yOffMax"] < res["yOffMin"] then
				err[#err+1] = "Mininum y offset ("..res["yOffMin"]..") must not be bigger than maximum y offset ("..res["yOffMax"]..")."
			end
			if res["angleMax"] < res["angleMin"] then
				err[#err+1] = "Mininum angle ("..res["angleMin"]..") must not be bigger than maximum angle ("..res["angleMax"]..")."
			end
			if  res["fSignInvX"] and not res["fSignInvXN"] 
			and res["fSignInvY"] and not res["fSignInvYN"] and res["angleMax"] < 90 then
				err[#err+1] = "Forced sign inversion for x and y require an angle of at least 90°."
			elseif res["fSignInvX"] and res["fSignInvXN"] 
			and     res["fSignInvY"] and res["fSignInvYN"] and res["angleMin"] > 90 then
				err[#err+1] = "No sign inversion for x and y requires an angle of at most 90°."
			end
			if res["fSignInvYN"] and res["fSignInvXN"] and res["fSignInvEither"] then
				err[#err+1] = "Can't change signs of either X or Y offsets because no sign changes are allowed."
			elseif res["fSignInvX"] and res["fSignInvY"] and res["fSignInvNotBoth"] then
				err[#err+1] = "Can't change signs of only X or Y offsets because sign changes are enforced for both."
			end

			if err[2] then aegisub.log(table.concat(err,"\n"))
			else shakeItProc(sub, sel, res) end
		end
	end

	function shakeItProc(sub, sel, res)
		math.randomseed(res["seed"])
		local fSignInvX, fSignInvY = res["fSignInvXN"] and -1 or res["fSignInvX"] and 1 or 0, res["fSignInvYN"] and -1 or res["fSignInvY"] and 1 or 0
		local a = distance(0, 0, res["xOffMax"], res["yOffMax"]) -- max circle radius
		local xOffPrev, yOffPrev = tinyPos, tinyPos

		aegisub.progress.task("Shaking...")

		for i=1,#sel,1 do
			local line=sub[sel[i]]
			local x,y = get_pos(line)

			aegisub.progress.set(100*i/#sel)

			-- aegisub.log("i: " .. i .. " x: " .. x .. " y: " .. y .. "\n")
			local angle, isFirstLine, maxRolls = -1, false, 10000
			while not isFirstLine and (angle < res["angleMin"] or angle > res["angleMax"]) do 
				local xSign = res["fSignInvEither"] and res["fSignInvYN"] and -xOffPrev or ((xOffPrev+tinyPos)*-fSignInvX)
				xNew, xOff = randomOffset(x,res["xOffMin"],res["xOffMax"], res["fSignInvNotBoth"] and res["fSignInvY"] and xOffPrev or xSign)

				local xSignChng = xOff*xOffPrev < 0
				local ySign = res["fSignInvEither"] and not xSignChng and -yOffPrev or ((yOffPrev+tinyPos)*-fSignInvY)
				yNew, yOff = randomOffset(y,res["yOffMin"],res["yOffMax"], res["fSignInvNotBoth"] and xSignChng and yOffPrev or ySign)

				--aegisub.log("xNew: " .. xNew .. " yNew: " .. yNew .. " xOff: " .. xOff .. " yOff: " .. yOff .. "\n")

				local xOffNorm, yOffNorm = normLength(xOff, yOff, a)
				local xOffPrevNorm, yOffPrevNorm = normLength(xOffPrev, yOffPrev,a)
				local d = distance(xOffPrevNorm, yOffPrevNorm, normLength(xOff, yOff, a))

				angle=math.acos((2*a^2-math.abs(d)^2)/2/a^2)*180/math.pi
				--aegisub.log("Angle: " .. angle .. "\n")
				isFirstLine = i==1

				maxRolls = maxRolls - 1
				if maxRolls == 0 then error("ERROR: Couldn't find offset that satifies chosen angle constraints (Min: " .. 
											res["angleMin"] .. "°, Max: " .. res["angleMax"] .. "° for line #" .. i .. ". Aborting.") end
			end

			line.text=line_exclude(line.text,{"pos"})
			line.text=line.text:gsub("^{", "{\\pos(".. float2str(xNew)..",".. float2str(yNew)..")")
			sub[sel[i]] = line

			xOffPrev, yOffPrev = xOff, yOff
		end
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