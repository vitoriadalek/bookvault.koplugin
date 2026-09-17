local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local icon_dir = DataStorage:getDataDir() .. "/icons"
if lfs.attributes(icon_dir, "mode") ~= "directory" then pcall(lfs.mkdir, icon_dir) end
if lfs.attributes(icon_dir, "mode") == "directory" then
    local icons = {
        ["bookvault-cat.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path d="M18 27 13 13l14 7c3-1 7-1 10 0l14-7-5 14c3 3 5 7 5 12 0 9-9 15-22 15S7 48 7 39c0-5 2-9 5-12z" fill="#000"/><path d="M20 38h.1M44 38h.1" stroke="#fff" stroke-width="4" stroke-linecap="round"/><path d="M29 44c2 2 4 2 6 0M32 42v3M32 7v5M26 10h12" fill="none" stroke="#000" stroke-width="3" stroke-linecap="round"/></svg>]],
        ["bookvault-sort.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><g fill="none" stroke="#000" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M18 14v36"/><path d="m10 22 8-8 8 8"/><path d="M38 50V14"/><path d="m30 42 8 8 8-8"/><path d="M50 14h6M50 26h6M50 38h6"/></g></svg>]],
        ["bookvault-sort-cat.svg"] = [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><g fill="none" stroke="#000" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M12 39V21l9 5c4-2 10-2 14 0l9-5v18c0 8-7 14-16 14S12 47 12 39z" fill="#000"/><path d="M20 38h.1M36 38h.1M25 44c2 2 4 2 6 0" stroke="#fff" stroke-width="3"/><path d="M49 12v36M43 18l6-6 6 6M43 42l6 6 6-6"/><path d="M2 18h6M2 30h6M2 42h6"/></g></svg>]],
    }
    for name, data in pairs(icons) do
        local path = icon_dir .. "/" .. name
        if lfs.attributes(path, "mode") ~= "file" then local f = io.open(path, "w"); if f then f:write(data); f:close() end end
    end
end
return true
