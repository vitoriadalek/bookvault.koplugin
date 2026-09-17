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
-- assets into KOReader's user icon directory. IconWidget accepts both SVG and PNG,
-- but uses SVG first, so these names intentionally end in '-png' to avoid any
-- stale SVG from an older BookVault installation taking precedence.
local source = debug.getinfo(1, "S").source or ""
source = source:gsub("^@", "")
local plugin_dir = source:match("^(.+)/[^/]+$")

local icons = {
    ["bookvault-search-png.png"] = "bookvault-search-png.png",
    ["bookvault-sort-png.png"] = "bookvault-sort-png.png",
    ["bookvault-sort-cat-png.png"] = "bookvault-sort-cat-png.png",
    ["bookvault-cat-png.png"] = "bookvault-cat-png.png",
    ["bookvault-moon-png.png"] = "bookvault-moon-png.png",
}

if plugin_dir and lfs.attributes(icon_dir, "mode") == "directory" then
    for target_name, source_name in pairs(icons) do
        local target = icon_dir .. "/" .. target_name
        -- Always refresh our tiny assets so an older/corrupt cached icon cannot
        -- survive an update. Binary mode is important for PNG files.
        local input = io.open(plugin_dir .. "/icons/" .. source_name, "rb")
        if input then
            local data = input:read("*a")
            input:close()
            if data and #data > 0 then
                local output = io.open(target, "wb")
                if output then
                    output:write(data)
                    output:close()
                end
            end
        end
    end
end

return true
