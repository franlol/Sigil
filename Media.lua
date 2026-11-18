-------------------------------------------------------------------------------
-- Sigil - Bar textures and fonts
-- From LibFlatyUI: its own ("Flaty: ..."), the game's, and LibSharedMedia's
-- when another addon loads it.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local Flaty = LibStub("LibFlatyUI-1.0")

ns.FLAT = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"

-- { value, label, font, texture } lists for the dropdowns; the game's names
-- are translated here (the lib's are brand names)
local function Translated(list)
    for _, o in ipairs(list) do
        if not o[2]:find("^Flaty: ") then o[2] = L[o[2]] end
    end
    return list
end
function ns.FontList() return Translated(Flaty.MediaList("font")) end
function ns.TextureList() return Translated(Flaty.MediaList("statusbar")) end

-- A saved path ready to use (nil: its addon is not loaded)
ns.ResolveMedia = Flaty.ResolveMedia

-- For dropdown getters: the saved value as the list knows it
function ns.MediaGetter(get)
    return function()
        local v = get()
        return v and Flaty.ResolveMedia(v) or v
    end
end

function ns.Texture()
    local p = ns.P and ns.P.media and ns.P.media.texture
    return Flaty.ResolveMedia(p) or ns.FLAT
end

function ns.Font()
    local p = ns.P and ns.P.media and ns.P.media.font
    return Flaty.ResolveMedia(p) or STANDARD_TEXT_FONT or FONT
end

function ns.Outline()
    return ns.P and ns.P.media and ns.P.media.outline or "OUTLINE"
end

-- Sets a font; if the file fails, falls back to the game's one
function ns.SetFont(fs, size)
    if not fs:SetFont(ns.Font(), size, ns.Outline()) then
        fs:SetFont(STANDARD_TEXT_FONT or FONT, size, ns.Outline())
    end
end
