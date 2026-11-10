-------------------------------------------------------------------------------
-- Sigil - Options look: a LibFlatyUI-1.0 instance with the Sigil color
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local UI = LibStub("LibFlatyUI-1.0"):New({ accent = { 0.71, 0.55, 1 } })
ns.UI = UI

UI.OnChange = function() UI.RefreshAll() end

-- Texts the library shows on its own, in the active language
local STRINGS = {
    confirm = "Click again to confirm",
    search = "Search...",
    accept = "Accept",
    cancel = "Cancel",
}
UI.strings = setmetatable({}, { __index = function(_, key) return L[STRINGS[key]] end })
