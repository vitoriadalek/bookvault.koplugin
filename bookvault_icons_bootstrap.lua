-- BookVault icon bootstrap.
-- Runs before TitleBar/IconWidget is loaded so the KOReader user icon directory
-- is present during IconWidget module initialization.
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local icon_dir = DataStorage:getDataDir() .. "/icons"
if lfs.attributes(icon_dir, "mode") ~= "directory" then
    pcall(lfs.mkdir, icon_dir)
end

-- Resolve the directory containing this plugin file, then copy the tiny PNG
-- assets into KOReader's user icon directory. PNG is supported by IconWidget.
-- We deliberately remove the old SVG variants first: IconWidget checks SVG
-- before PNG, and older BookVault versions may have left those SVGs cached.
local source = debug.getinfo(1, "S").source or ""
source = source:gsub("^@", "")
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
        -- Remove legacy BookVault SVGs so the lightweight PNG is selected.
        pcall(os.remove, icon_dir .. "/" .. stem .. ".svg")

        local input = io.open(plugin_dir .. "/icons/" .. source_name, "rb")
        if input then
            local data = input:read("*a")
            input:close()
            if data and #data > 0 then
                local output = io.open(icon_dir .. "/" .. target_name, "wb")
                if output then
                    output:write(data)
                    output:close()
                end
            end
        end
    end
end

return true
