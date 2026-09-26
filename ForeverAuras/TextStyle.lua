-- Shared font setup for addon-owned text, including native aura text bindings.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local fontObjects = setmetatable({}, {__mode = "k"})
local fontObjectCounter = 0

function Private.ApplyTextFont(text, fontObject, fontPath, size, flags, shadowColor, shadowX, shadowY)
  -- Native aura FontStrings are pooled: retain one font object per string rather
  -- than creating a global font for every slider change or appearance refresh.
  if not fontObject then
    fontObject = fontObjects[text]
    if not fontObject then
      fontObjectCounter = fontObjectCounter + 1
      fontObject = CreateFont("ForeverAuras-NativeText-Font" .. fontObjectCounter)
      fontObjects[text] = fontObject
    end
  end

  -- Forever renders inherited shadows. Configure a complete font object BEFORE
  -- attaching it, then apply the chosen face to the string. Direct FontString
  -- shadow setters do not reliably render here. Reattach on edits/pool reuse so
  -- changes to offsets, opacity and the outline mode reach existing text too.
  fontObject:SetFont(STANDARD_TEXT_FONT, size, flags)
  fontObject:SetShadowColor(unpack(shadowColor))
  if flags == "OUTLINE|SLUG" or flags == "THICKOUTLINE|SLUG" then
    -- Preserve the existing outlined-SLUG limitation without changing saved offsets.
    fontObject:SetShadowOffset(0, 0)
  else
    fontObject:SetShadowOffset(shadowX, shadowY)
  end
  text:SetFontObject(fontObject)
  text:SetFont(fontPath, size, flags)

  -- Retain the font-loading retry and fallback without rewriting the saved font.
  if not text:GetFont() and fontPath then
    fontObject:SetFont(fontPath, size, flags)
    text:SetFontObject(fontObject)
  end
  if not text:GetFont() then
    text:SetFont(STANDARD_TEXT_FONT, size, flags)
  end
end
