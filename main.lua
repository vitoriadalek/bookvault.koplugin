-- BookVault bootstrap kept intentionally tiny so KOReader can always discover the plugin.
-- The full implementation is loaded only after PluginLoader has accepted this module.
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")

local BookVault = WidgetContainer:extend{
    name = "bookvault",
    fullname = _("BookVault"),
    is_doc_only = false,
}

function BookVault:init()
    -- Loading the implementation is deliberately isolated from plugin discovery.
    -- Even if a helper/API is incompatible with a particular KOReader build,
    -- this module has already been returned to PluginLoader and remains visible
    -- in Tools/User Plugins.
    local ok, Core = pcall(require, "bookvault_core")
    if not ok or type(Core) ~= "table" then
        logger.err("BookVault: implementation failed to load", Core)
        return
    end

    -- Copy the implementation methods onto the real plugin class. The Core
    -- class is never instantiated, so its init() is intentionally not invoked.
    for name, value in pairs(Core) do
        if name ~= "init" and type(value) == "function" then
            BookVault[name] = value
        end
    end

    local ok_settings, err_settings = pcall(self.loadSettings, self)
    if not ok_settings then
        logger.err("BookVault: initial settings load failed", err_settings)
    end

    local ok_menu, err_menu = pcall(function()
        self.ui.menu:registerToMainMenu(self)
    end)
    if not ok_menu then
        logger.err("BookVault: main-menu registration failed", err_menu)
    end

    -- Actions are optional and must never affect plugin discovery.
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
end

return BookVault