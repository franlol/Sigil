-------------------------------------------------------------------------------
-- Sigil - Bar textures and fonts
-- The game's ones are always there; if another addon loads
-- LibSharedMedia-3.0, all of its ones are added too.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

ns.FLAT = "Interface\\Buttons\\WHITE8X8"

local FONTS = {
    { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
    { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\skurri.ttf" },
    { "Morpheus", "Fonts\\MORPHEUS.ttf" },
}

local TEXTURES = {
    { "Flat", ns.FLAT },
    { "Blizzard", "Interface\\TargetingFrame\\UI-StatusBar" },
    { "Blizzard (raid)", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { "Gloss", "Interface\\TargetingFrame\\BarFill2" },
    { "Smooth", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- { value, label } lists for the dropdowns
local function Merge(base, mediaType)
    local out, seen = {}, {}
    for _, e in ipairs(base) do
        out[#out + 1] = { e[2], L[e[1]] }
        seen[e[2]:lower()] = true
    end
    local lsm = LSM()
    if lsm then
        local extra = {}
        for name, path in pairs(lsm:HashTable(mediaType)) do
            if type(path) == "string" and not seen[path:lower()] then
                seen[path:lower()] = true
                extra[#extra + 1] = { path, name }
            end
        end
        table.sort(extra, function(a, b) return a[2] < b[2] end)
        for _, e in ipairs(extra) do out[#out + 1] = e end
    end
    return out
end

function ns.FontList() return Merge(FONTS, "font") end
function ns.TextureList() return Merge(TEXTURES, "statusbar") end

function ns.Texture()
    return ns.P and ns.P.media and ns.P.media.texture or ns.FLAT
end

function ns.Font()
    return ns.P and ns.P.media and ns.P.media.font or STANDARD_TEXT_FONT or FONTS[1][2]
end

function ns.Outline()
    return ns.P and ns.P.media and ns.P.media.outline or "OUTLINE"
end

-- Sets a font; if the file fails, falls back to the game's one
function ns.SetFont(fs, size)
    if not fs:SetFont(ns.Font(), size, ns.Outline()) then
        fs:SetFont(STANDARD_TEXT_FONT or FONTS[1][2], size, ns.Outline())
    end
end
