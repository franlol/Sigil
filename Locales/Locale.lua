-------------------------------------------------------------------------------
-- Sigil - Translations
--
-- The keys are the English texts: L["Some text"] returns that text in the
-- active language, or the key itself when there is no translation (English).
-------------------------------------------------------------------------------

local _, ns = ...

ns.translations = {}    -- [locale] = { [English text] = translated text }

local active

ns.L = setmetatable({}, {
    __index = function(_, key)
        return active and active[key] or key
    end,
})

-- lang: "enUS" or "esES" (anything else = English)
function ns.SetLanguage(lang)
    ns.language = ns.translations[lang] and lang or "enUS"
    active = ns.translations[lang]
end
