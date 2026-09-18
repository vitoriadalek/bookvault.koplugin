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
local svg_icons = {}

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


local generated_svg_icons = {
    ["bookvault-settings"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 8.2a3.8 3.8 0 1 0 0 7.6 3.8 3.8 0 0 0 0-7.6Z"/><path d="m19.2 13.7 1.1 1.8-1.8 1.8-1.8-1.1a7.5 7.5 0 0 1-1.8 1l-.3 2.1h-2.6l-.3-2.1a7.5 7.5 0 0 1-1.8-1L8.1 17.3l-1.8-1.8 1.1-1.8a7.5 7.5 0 0 1-1-1.8l-2.1-.3v-2.6l2.1-.3a7.5 7.5 0 0 1 1-1.8L6.3 5.1l1.8-1.8 1.8 1.1a7.5 7.5 0 0 1 1.8-1l.3-2.1h2.6l.3 2.1a7.5 7.5 0 0 1 1.8 1l1.8-1.1 1.8 1.8-1.1 1.8a7.5 7.5 0 0 1 1 1.8l2.1.3v2.6l-2.1.3a7.5 7.5 0 0 1-1 1.8Z"/></svg>]],
    ["bookvault-collections"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 4h12v16H6z"/><path d="M9 4v16"/><path d="M12 8h4M12 11h4M12 14h3"/></svg>]],
    ["bookvault-move"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h15"/><path d="m15 4 4 4-4 4"/><path d="M20 16H5"/><path d="m9 12-4 4 4 4"/></svg>]],
    ["bookvault-copy"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="8" y="7" width="11" height="13" rx="1"/><path d="M16 7V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h3"/></svg>]],
    ["bookvault-trash"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 7h14"/><path d="M9 7V4h6v3"/><path d="m8 7 .7 13h6.6L16 7"/><path d="M10 10v7M14 10v7"/></svg>]],
    ["bookvault-more"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><circle cx="12" cy="5" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="12" cy="19" r="1.5"/></svg>]],
    ["bookvault-check"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 4 4L19 6"/></svg>]],
}
if lfs.attributes(icon_dir, "mode") == "directory" then
    for name, data in pairs(generated_svg_icons) do
        local output = io.open(icon_dir .. "/" .. name .. ".svg", "wb")
        if output then
            output:write(data)
            output:close()
        end
    end
end

return true
