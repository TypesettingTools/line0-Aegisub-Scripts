line0's Aegisub Scripts
=======================

 1. [Nudge](#nudge)
 2. [Shake It](#shake-it)

----------------------------------


Nudge
==========================

Nudge is an automation script for Aegisub that lets you **create your own hotkeyable macros for common tag modifications** like nudging a line up and down, increasing the brightness of signs or cycling through a predefined set of blur states.

Requirements
------------
- Aegisub 3.2.0+
- [LuaJSON](https://github.com/harningt/luajson)
* [Aegisub-Motion](https://github.com/torque/Aegisub-Motion/tree/lets-break-everything) (lets-break-everything branch)
- Includes from this repo: LineExtend, ASSTags, Common

Release Packages ship everything but Aegisub-Motion.

Installation
------------

 **From release package:**
1. Install Aegisub-Motion
2. Unpack the Nudge archive into your Aegisub automation directory
3. In Aegisub, rescan your automation folder or restart Aegisub

**From source repo:**
1. Install Aegisub-Motion
2. Clone the repository and copy the *autoload* and *include* folders into your Aegisub automation directory. You only need to take the *Nudge.lua* from the *autoload* folder, but all files from the *include* folder are required.
 

Usage
----
When you first load the Nudge script, it will create its own submenu in your automation menu. It also ships with a bunch of default macros to get you started.

To add, modify or remove Macros, run the *Configure Nudge* macro. Nudge will present you a list of all the existing macros, which you can then customize by adjusting their options:

 - **Macro Name:** Name of Macro. Because hotkeys are registered by command name, you need to update the commands of already hotkeyed macro after changing its name or the hotkey will stop working
 - **Override Tag:** The override tag(s) modified by the macro. The list contains all supported override tags as well as some "compound" tags (Colors, Shadows, ...) that will target multiple override tags at once (e.g. *Primary Color* modifies both \c and \1c)
 - **Action:** The operation that will be performed on matched override tags (first parameter) and user-supplied values (second parameter). Not all actions support every available tag (refer to the list below).
 - **Values:** Second parameter to the operation specified in the *Action* field. Values are separated by commas and usually match the position of the parameters to the specified override tags: *\blur#* takes only 1 parameter, while *\fad(#,#)* takes 2 parameters in tag order. **Exception: ** color tags take 3 base-10 parameters for *r,g,b* (e.g. *255,128,0* instead of *0080FF*). Some action take special set of parameters or ignore user-supplied values altogether (refer to the list below)
 - **Remove**: Check this checkbox if you want to remove a Macro and hit *Save*.

Use the *Add Macro* button to add a new Macro and the *Save* button to save the configuration to the disk. Since Aegisub only allows Macros to be registered when scripts are loaded, **you must reload your scripts** (in the automation menu, *click on Automation...* while holding down *Ctrl*) after adding macros, removing macros and changing macro names for the Automation menu to reflect the changes you just made. 

**Working with Macros:** Run the macro by hotkey or from the menu to make it process all selected lines according to its configuration. 

At this time the script processes all matching tags in a line and inserts style-based defaults for missing tags into the first tag block. If no tag block is found at the beginning of the line, Nudge will create one. Options to customize this behavior are planned.

Nudge will never output invalid tags (e.g. *\an10*, *\k15.5*) even if the user supplied values are of a bad type or the operation causes the result to be out of range. For your convenience, Nudge silently coerces the output values in order to output valid tags.
 
Operations
----------

 - **Add:** Adds the supplied values to the tag fields (Default: 0)
 - **Multiply:** Multiplies the tag fields with the supplied values (Default: 1)
 - **Power:** Exponentiates the tag fields with the supplied values (Default 1)
 - **Set:** Sets the tag fields to the supplied values (Defaults: tag/tag field dependent)
 - **Cycle:** Cycles through a defined set of values. Values must be in the format *[Set1],[Set2],[Set3]*, e.g. *[100,100],[500,500],[1000,1000]* for *\fad*
 - **Auto Cycle:** Cycles through the states of tags that only define a set amount of states (*\q*, *\an*). The *value* field is ignored.
 - **Set Default:** Sets the tag fields to their default values according to the style of the line. The *value* field is ignored.
 - **Toggle:** Switches on/off type tags (*\i*,*\u*...) between 1 and 0. The *value* field is ignored.
 - **Add HSV:** modifies RGB values of color tags in the HSV domain. Values must be supplied as *Hue,Saturation,Value*. Hue takes an angle, while Saturation and Value must be supplied in range 0..1. 
 - **Align Up/Down/Left/Right:** changes the alignment (*\an*) of a line stepwise in the specified direction. Example: *Align Up* changes *\an2* to *\an5*, *\an1* to *\an7*, but doesn't do anything for *\an8*.
 - **Append/Prepend:**: appends/prepends the specified string to string type tags (*\fs*, *\r*)
 - **Replace**: replaces in string type tags using regular expressions **(NOT lua expressions)**. First value is the string or pattern to match,  second value the replacement string.
 
Supported Operations by Tag
---------------------------

Tag        | Add/Mul/Pow | Set | Def | Cycle | ACycle | Toggle | Add HSV | Align | Rep/Append/Prepend 
-----------|-------------|-----|-----|-------|--------|--------|---------|-------|-------------------
\1a        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\2a        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\3a        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\4a        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\1c        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |    ✔    |       |
\2c        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |    ✔    |       |
\3c        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |    ✔    |       |
\4c        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |    ✔    |       |
\alpha     |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\an        |       ✔     |  ✔  |  ✔  |  ✔  |   ✔    |        |         |   ✔   |
\b         |       ✔     |  ✔  |  ✔  |  ✔  |        |   ✔    |         |       |
\be        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\blur      |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\bord      |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\c         |       ✔     |  ✔  |  ✔  |  ✔  |        |        |    ✔    |       |
\clip      |             |     |     |     |        |        |         |       |
\fad       |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\fade      |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\fax       |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\fay       |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\fe        |             |     |     |     |        |        |         |       |
\fn        |             |  ✔  |  ✔  |  ✔  |        |        |         |       |         ✔         
\frx       |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\fry       |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\frz       |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\fs        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\fscx      |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\fscy      |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\fsp       |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\k         |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\K         |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\kf        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\ko        |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\i         |             |  ✔  |  ✔  |     |        |   ✔    |         |       |
\iclip     |             |     |     |     |        |        |         |       |
\move      |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\org       |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\pos       |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\q         |             |  ✔  |  ✔  |  ✔  |   ✔    |        |         |   ✔   |
\r         |             |  ✔  |  ✔  |  ✔  |        |        |         |       |         ✔         
\t         |             |     |     |     |        |        |         |       |
\u         |             |  ✔  |  ✔  |     |        |   ✔    |         |       |
\xbord     |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\ybord     |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\xshad     |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
\yshad     |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
           |             |     |     |     |        |        |         |       |
Alphas     |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
Colors     |       ✔     |  ✔  |  ✔  |  ✔  |        |        |    ✔    |       |
Fades      |       ✔     |  ✔  |  ✔  |  ✔  |        |        |         |       |
Pri. Color |       ✔     |  ✔  |  ✔  |  ✔  |        |        |    ✔    |       |



-------------------------------

Shake It
==============================

tbd