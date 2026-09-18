-- BookVault icon bootstrap.
-- Copies lightweight bundled PNGs to KOReader's user icon directory.
-- No global UI/class monkey patches are performed here.

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local icon_dir = DataStorage:getDataDir() .. "/icons"
if lfs.attributes(icon_dir, "mode") ~= "directory" then
    pcall(lfs.mkdir, icon_dir)
end

local source = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local plugin_dir = source:match("^(.+)/[^/]+$")
local icons = {
    "bookvault-search.png",
    "bookvault-sort.png",
    "bookvault-sort-cat.png",
    "bookvault-cat.png",
    "bookvault-moon.png",
}

if plugin_dir and lfs.attributes(icon_dir, "mode") == "directory" then
    for _, name in ipairs(icons) do
        pcall(os.remove, icon_dir .. "/" .. name:gsub("%.png$", ".svg"))
        local input = io.open(plugin_dir .. "/icons/" .. name, "rb")
        if input then
            local data = input:read("*a")
            input:close()
            if data and #data > 0 then
                local output = io.open(icon_dir .. "/" .. name, "wb")
                if output then
                    output:write(data)
                    output:close()
                end
            end
        end
    end
end

return true
