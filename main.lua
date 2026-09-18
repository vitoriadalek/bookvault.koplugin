-- BookVault bootstrap.
-- Keep discovery completely independent from BookVault feature modules.
-- KOReader must be able to list this plugin even if a feature dependency is
-- unavailable on a particular firmware build.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local _ = require("gettext")
local logger = require("logger")

local BookVault = WidgetContainer:extend{
    name = "bookvault",
    fullname = _("BookVault"),
    is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/bookvault.lua",
    settings = nil,
    unlocked = false,
}

local function loadImplementation(self)
    if self._bookvault_implementation_loaded then
        return true
    end

    local ok, Impl = pcall(require, "bookvault_impl")
    if not ok or type(Impl) ~= "table" then
        logger.err("BookVault: implementation failed to load", Impl)
        return false
    end

    for name, value in pairs(Impl) do
        if name ~= "init" and name ~= "addToMainMenu" and type(value) == "function" then
            BookVault[name] = value
        end
    end

    self._bookvault_implementation_loaded = true

    local ok_actions, actions = pcall(require, "bookvault_actions")
    if ok_actions and actions and actions.install then
        local ok_install, err = pcall(actions.install, BookVault)
        if not ok_install then
            logger.err("BookVault action layer install failed", err)
        end
    else
        logger.err("BookVault action layer unavailable", actions)
    end

    return true
end

function BookVault:openBookVault()
    if not loadImplementation(self) then
        return
    end
    if self.show then
        local ok, err = pcall(self.show, self)
        if not ok then
            logger.err("BookVault: failed to open", err)
        end
    end
end

function BookVault:addToMainMenu(menu_items)
    menu_items.bookvault = {
        text = _("BookVault"),
        sorting_hint = "more_tools",
        callback = function() self:openBookVault() end,
    }
end

function BookVault:init()
    local ok, err = pcall(function()
        self.ui.menu:registerToMainMenu(self)
    end)
    if not ok then
        logger.err("BookVault: main-menu registration failed", err)
    end
end

return BookVault
