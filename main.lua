-- BookVault bootstrap.
-- Keep this file deliberately tiny: KOReader must be able to discover and
-- register the plugin even if a BookVault feature module has a compatibility
-- problem. The full implementation is loaded lazily from the BookVault menu.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")

local BookVault = WidgetContainer:extend{
    name = "bookvault",
    fullname = _("BookVault"),
    is_doc_only = false,
}

function BookVault:loadImplementation()
    if self._bookvault_implementation_loaded then
        return true
    end

    local ok, Core = pcall(require, "bookvault_core")
    if not ok or type(Core) ~= "table" then
        logger.err("BookVault: implementation failed to load", Core)
        return false
    end

    -- Copy implementation methods to the real plugin class. Do not copy init()
    -- or addToMainMenu(): both are owned by this minimal bootstrap.
    for name, value in pairs(Core) do
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

    if self.registerSimpleUIWithRetry then
        pcall(self.registerSimpleUIWithRetry, self)
    end

    return true
end

function BookVault:openBookVault()
    if not self:loadImplementation() then
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
        callback = function()
            self:openBookVault()
        end,
    }
end

function BookVault:init()
    -- Nothing optional is loaded here. This is intentional: plugin discovery
    -- and visibility in Tools/User Plugins must never depend on BookVault's
    -- feature modules, cover UI, Simple UI integration, or action layer.
    local ok, err = pcall(function()
        self.ui.menu:registerToMainMenu(self)
    end)
    if not ok then
        logger.err("BookVault: main-menu registration failed", err)
    end
end

return BookVault
