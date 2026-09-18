-- BookVault icon bootstrap.
-- Copies lightweight bundled PNG/SVG icons to KOReader's user icon directory.
-- No global UI/class monkey patches are performed here.

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local icon_dir = DataStorage:getDataDir() .. "/icons"
if lfs.attributes(icon_dir, "mode") ~= "directory" then
    pcall(lfs.mkdir, icon_dir)
end

local source = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local plugin_dir = source:match("^(.+)/[^/]+$")
local png_icons = {
    "bookvault-search.png",
    "bookvault-sort.png",
    "bookvault-sort-cat.png",
    "bookvault-cat.png",
    "bookvault-moon.png",
}
local svg_icons = {
    "bookvault-collections.svg",
    "bookvault-move.svg",
    "bookvault-copy.svg",
    "bookvault-trash.svg",
    "bookvault-more.svg",
    "bookvault-open.svg",
    "bookvault-info.svg",
    "bookvault-edit.svg",
    "bookvault-search-action.svg",
    "bookvault-folder.svg",
    "bookvault-check.svg",
    "bookvault-cancel.svg",
}

local function copyFile(name)
    if not plugin_dir or lfs.attributes(icon_dir, "mode") ~= "directory" then return end
    local input = io.open(plugin_dir .. "/icons/" .. name, "rb")
    if not input then return end
    local data = input:read("*a")
    input:close()
    if not data or #data == 0 then return end
    local output = io.open(icon_dir .. "/" .. name, "wb")
    if output then
        output:write(data)
        output:close()
    end
end

if plugin_dir and lfs.attributes(icon_dir, "mode") == "directory" then
    for _, name in ipairs(png_icons) do
        pcall(os.remove, icon_dir .. "/" .. name:gsub("%.png$", ".svg"))
        pcall(copyFile, name)
    end
    for _, name in ipairs(svg_icons) do
        pcall(copyFile, name)
    end
end

return true
