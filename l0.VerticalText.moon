-- TODO: calc scale
export script_name = "Vertical Text"
export script_description = "Splits a line into vertical text."
export script_version = "0.2.0"
export script_author = "line0"
export script_namespace = "l0.VerticalText"

DependencyControl = require "l0.DependencyControl"
depCtrl = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/line0-Aegisub-Scripts/master/DependencyControl.json",
    {
      {"a-mo.LineCollection", version: "1.0.1", url: "https://github.com/TypesettingTools/Aegisub-Motion",
        feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
      {"l0.ASSFoundation", version: "0.4.0", url: "https://github.com/TypesettingTools/ASSFoundation",
        feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
      "Yutils"
    }
}
LineCollection, ASS, Yutils = depCtrl\requireModules!
logger = depCtrl\getLogger!

absCos = (a) -> math.abs math.cos math.rad a
absSin = (a) -> math.abs math.sin math.rad a
alignOffset = (x, a) -> math.abs x / 2 * math.cos math.rad a

averageGlyphMetricsByFont = {}
getAverageGlyphMetrics = (fontName) ->
  return averageGlyphMetricsByFont[fontName] if averageGlyphMetricsByFont[fontName]

  font = Yutils.decode.create_font fontName, false, false, false, false, 100
  startChar, endChar = 65, 122 -- character codes within [A-Za-z]
  totalHeight, totalWidth, nonEmptyGlyphCount = 0, 0, 0

  for c = startChar, endChar
    x1, y1, x2, y2 = Yutils.shape.bounding font.text_to_shape string.char c
    if x1
      totalHeight += y2 - y1
      totalWidth += x2 - x1
      nonEmptyGlyphCount += 1

  averageGlyphMetricsByFont[fontName] = {
    w: totalWidth/nonEmptyGlyphCount,
    h: totalHeight/nonEmptyGlyphCount
  }
  return averageGlyphMetricsByFont[fontName]

process = (sub, sel, res) ->
    aegisub.progress.task "Processing..."

    lines = LineCollection sub, sel
    finalLines = LineCollection sub

    cb = (lines, line, i) ->
      data = ASS\parse line
      -- split line by characters
      charLines = data\splitAtIntervals 1, 4, false
      charOffset = 0

      for charLine in *charLines
        logger\warn charLine.text
        charData = charLine.ASS
        -- get tags effective as of the first section (we know there won't be any tags after that)
        effTags = charData.sections[1]\getEffectiveTags(true,true).tags

        -- determine average width and height of glyphs for this font for vertical spacing generation
        averageGlyphMetrics = getAverageGlyphMetrics effTags.fontname.value
        -- with \an5 the type is centered between ascender and baseline,
        -- so we need to account for the descender and ascender separately
        metrics = charLine.ASS\getTextMetrics true
        charBounds = metrics.bounds
        descender = math.max charBounds[4] - metrics.ascent, 0
        ascender = math.max metrics.descent - charBounds[2], 0

        -- set \an5
        effTags.align.value = 5
        charData\removeTags "align"
        charData\insertTags effTags.align, 1

        -- calculate new position
        frz = effTags.angle.value
        charOffset += ascender * absCos frz
        logger\dump {metrics}
        effTags.position\add 0,
          charOffset + alignOffset(charBounds.h - math.max(charBounds[2]-metrics.descent, 0), frz) + alignOffset(metrics.width, frz+90)

        charData\removeTags "position"
        charData\insertTags effTags.position, 1

        -- set position for the next character
        spacing = 0.2 * averageGlyphMetrics.h * effTags.fontsize.value / 100
        charOffset += absCos(frz) * (charBounds.h + spacing + descender) + absSin(frz) * metrics.width

        charData\commit!
        finalLines\addLine charLine

      aegisub.progress.set i * 100 / #lines.lines
    lines\runCallback cb, true
    lines\deleteLines!
    finalLines\insertLines!

depCtrl\registerMacro process
