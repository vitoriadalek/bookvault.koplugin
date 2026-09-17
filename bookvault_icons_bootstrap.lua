-- BookVault icon bootstrap.
-- The compatibility bridge is limited to BookVault class creation and is restored
-- immediately after the class is decorated.
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

        -- ButtonDialog's default outside-tap dismissal can steal the same touch
        -- sequence that opened the context menu on some KOReader mosaic builds.
        -- Keep the dialog non-dismissable so its buttons always receive the tap;
        -- every action has an explicit Cancel/close path.
        local ButtonDialog = require("ui/widget/buttondialog")
        local UIManager = require("ui/uimanager")
        local filemanagerutil = require("apps/filemanager/filemanagerutil")
        local _ = require("gettext")
        local old_show = cls.showBookActions
        if old_show then
            cls.showBookActions = function(self, menu, item)
                if menu._bookvault_selection_mode then
                    return self:toggleSelection(menu, item)
                end
                local dialog
                local function close()
                    if dialog then UIManager:close(dialog) end
                end
                local function showStatus()
                    local status_dialog
                    status_dialog=ButtonDialog:new{
                        title=_("Status de leitura"),
                        title_align="center",
                        dismissable=false,
                        buttons={
                            {filemanagerutil.genStatusButtonsRow(item.path,function() UIManager:close(status_dialog); if menu then menu:updateItems(1,true) end end)},
                            {{text=_("Cancelar"),callback=function() UIManager:close(status_dialog) end}},
                        },
                    }
                    UIManager:show(status_dialog)
                end
                local buttons = {
                    {{text=_("Abrir livro"), callback=function() close(); filemanagerutil.openFile(self.ui, item.path) end}},
                    {{text=_("Informações do livro"), callback=function() close(); self:showBookInfo(item) end}},
                    {{text=_("Status de leitura"), callback=function() close(); showStatus() end}},
                    {{text=_("Coleções"), callback=function() close(); self:showCollectionsForBook(item,menu) end}},
                    {{text=_("Editar capa/metadados"), callback=function() close(); self:showBookInfo(item) end}},
                    {{text=_("Buscar capa no Google Imagens"), callback=function() close(); self:searchGoogleImagesForCover(item.path) end}},
                    {{text=_("Selecionar vários"), callback=function() close(); self:enterSelection(menu,item) end}},
                    {{text=_("Renomear"), callback=function() close(); self:renameBook(item,menu) end}},
                    {{text=_("Copiar"), callback=function() close(); self:copyOrMoveBook(item,menu,false) end}},
                    {{text=_("Mover"), callback=function() close(); self:copyOrMoveBook(item,menu,true) end}},
                    {{text=_("Excluir"), callback=function() close(); self:deleteBooks({[item.path]=true},menu) end}},
                    {{text=_("Abrir localização"), callback=function()
                        close()
                        local dir=item.path:match("^(.*)/[^/]+$")
                        if self.ui and self.ui.file_chooser and dir then self.ui.file_chooser:changeToPath(dir,item.path) end
                    end}},
                    {{text=_("Ações de plugins"), callback=function() close(); self:showPluginActions(menu,item) end}},
                    {{text=_("Cancelar"), callback=function() close() end}},
                }
                dialog=ButtonDialog:new{
                    title=item.text or item.path,
                    title_align="center",
                    dismissable=false,
                    buttons=buttons,
                }
                UIManager:show(dialog)
                return true
            end
        end

        WidgetContainer.extend = original_extend
    end
    return cls
end
return true
