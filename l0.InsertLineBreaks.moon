export script_name = "Insert Line Breaks"
export script_description = "Inserts hard line breaks after n characters, but tries to avoid breaking up words."
export script_version = "0.2.0"
export script_author = "line0"
export script_namespace = "l0.InsertLineBreaks"

DependencyControl = require "l0.DependencyControl"
depCtrl = DependencyControl {
  feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
  {
    {"a-mo.LineCollection", version: "1.0.1", url: "https://github.com/TypesettingTools/Aegisub-Motion",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    {"l0.ASSFoundation", version: "0.4.0", url: "https://github.com/TypesettingTools/ASSFoundation",
      feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
    {"l0.Functional", version: "0.5.0", url: "https://github.com/TypesettingTools/Functional",
      feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"},
  }
}
LineCollection, ASS, Functional = depCtrl\requireModules!
{:list, :math, :string, :table, :unicode, :util, :re } = Functional
logger = depCtrl\getLogger!

insertLineBreaks = (sub, sel, res) ->
  lines = LineCollection sub, sel
  curCnt, expr = res.charLimit, re.compile "\\s(?!.*\\s)"
  lines\runCallback (lines, line) ->
    data = ASS\parse line
    textSectionCb = (section) ->
      j, n, len, split = 1, 1, unicode.len(section.value), {}
      while j <= len
        splitLen = math.min curCnt, len-j+1
        split[n] = unicode.sub section.value, j, j+splitLen-1
        j += curCnt
        if splitLen - curCnt == 0
          curCnt = res.charLimit
          -- if the next character is a whitespace character, replace it with a line break
          if re.match unicode.sub(section.value, j, j), "\\s"
            j += 1
            split[n+1] = "\\N"
          -- if it isn't, find the last whitespace character in our last <= n chars section
          else
            matches = expr\find split[n]
            -- found one -> place the line break there and add the character count after that position
            -- to the char count of the next section
            if matches
              pos = matches[1].last
              split[n], split[n+1], split[n+2] = unicode.sub(split[n], 1, pos-1), "\\N", unicode.sub split[n], pos+1
              curCnt -= unicode.len split[n+2]
              n += 1
            -- no whitespace character found -> force the line break at n chars
            else split[n+1] = "\\N"
          n += 1
        n += 1
      section.value = table.concat split

    data\callback textSectionCb, ASS.Section.Text
    data\commit!
  lines\replaceLines!

showDialog = (sub, sel) ->
  dlg = {
    {
      class: "label", label: "Insert \\N after",
      x: 0, y: 0, width: 1, height: 1
    },
    {
      class: "intedit", name: "charLimit",
      x: 1, y: 0, width: 1, height: 1, value: 35
    },
    {
      class: "label", label: "characters",
      x: 2, y: 0, width: 1, height: 1
    },
  }

  btn, res = aegisub.dialog.display dlg
  insertLineBreaks sub, sel, res if btn

depCtrl\registerMacro showDialog
