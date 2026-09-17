-- BookVault icon bootstrap.
-- The small compatibility bridge below exists only to install BookVault's
-- action layer at class creation time; it restores WidgetContainer.extend
-- immediately after creating the BookVault class.
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local icon_dir = DataStorage:getDataDir() .. "/icons"
if lfs.attributes(icon_dir, "mode") ~= "directory" then pcall(lfs.mkdir, icon_dir) end
local source = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local plugin_dir = source:match("^(.+)/[^/]+$")
local icons = {
    ["bookvault-search.png"] = "bookvault-search.png",
    ["bookvault-sort.png"] = "bookvault-sort.png",
    ["bookvault-sort-cat.png"] = "bookvault-sort-cat.png",
    ["bookvault-cat.png"] = "bookvault-cat.png",
    ["bookvault-moon.png"] = "bookvault-moon.png",
}
if plugin_dir and lfs.attributes(icon_dir, "mode") == "directory" then
    for target_name, source_name in pairs(icons) do
        local stem = target_name:gsub("%.png$", "")
        pcall(os.remove, icon_dir .. "/" .. stem .. ".svg")
        local input = io.open(plugin_dir .. "/icons/" .. source_name, "rb")
        if input then
            local data = input:read("*a")
            input:close()
            if data and #data > 0 then
                local output = io.open(icon_dir .. "/" .. target_name, "wb")
                if output then output:write(data); output:close() end
            end
        end
    end
end

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local original_extend = WidgetContainer.extend
local installed = false
WidgetContainer.extend = function(base, props, ...)
    local cls = original_extend(base, props, ...)
    if not installed and props and props.name == "bookvault" then
        installed = true
        local ok, actions = pcall(require, "bookvault_actions")
        if ok and actions and actions.install then
            local ok_install, err = pcall(actions.install, cls)
            if not ok_install then
                pcall(require("logger").err, "BookVault action layer install failed", err)
            end
        else
            pcall(require("logger").err, "BookVault action layer unavailable", actions)
        end
        local ok_fix, fix = pcall(require, "bookvault_action_fix")
        if ok_fix and fix and fix.install then
            local ok_install, err = pcall(fix.install, cls)
            if not ok_install then
                pcall(require("logger").err, "BookVault action fix install failed", err)
            end
        else
            pcall(require("logger").err, "BookVault action fix unavailable", fix)
        end
        WidgetContainer.extend = original_extend
    end
    return cls
end
return true
