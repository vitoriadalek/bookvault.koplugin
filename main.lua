local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local _ = require("gettext")

local BookVault = WidgetContainer:extend{
    name = "bookvault",
    fullname = _("BookVault"),
    is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/bookvault.lua",
    settings = nil,
    unlocked = false,
}

function BookVault:init(...)
    local ok, core = pcall(require, "bookvault_core")
    if not ok or type(core) ~= "table" then
        logger.err("BookVault core failed to load:", core)
        UIManager:show(InfoMessage:new{
            text = _("BookVault não conseguiu carregar seu módulo principal.")
                .. "\n\n" .. tostring(core),
        })
        return
    end

    -- Keep the loader class deliberately tiny so a failure in the large
    -- implementation cannot make KOReader hide BookVault from User plugins.
    -- The real implementation remains the same class and its patched methods
    -- are copied onto this instance before initialization.
    for name, value in pairs(core) do
        if name ~= "new" and name ~= "init" then
            self[name] = value
        end
    end

    local ok_init, err = pcall(core.init, self, ...)
    if not ok_init then
        logger.err("BookVault core initialization failed:", err)
        UIManager:show(InfoMessage:new{
            text = _("BookVault encontrou um erro ao iniciar.")
                .. "\n\n" .. tostring(err),
        })
    end
end

return BookVault
