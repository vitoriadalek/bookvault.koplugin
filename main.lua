local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local sha2 = require("ffi/sha2")
local logger = require("logger")
local _ = require("gettext")

local BookVault = WidgetContainer:extend{
    name = "bookvault", fullname = _("BookVault"), is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/bookvault.lua",
    settings = nil, unlocked = false,
}

local STATUS = {
    { key="all", label=_("Todos") }, { key="reading", label=_("Lendo") },
    { key="abandoned", label=_("Em espera") }, { key="complete", label=_("Concluídos") },
    { key="new", label=_("Não iniciados") },
}

local function normalize(path)
    if not path then return nil end
    local ok, real = pcall(ffiUtil.realpath, path)
    return ((ok and real) or path):gsub("/+$", "")
end
local function contains(parent, child)
    parent, child = normalize(parent), normalize(child)
    return parent and child and (child == parent or child:sub(1,#parent+1) == parent .. "/")
end
local function addUnique(list, value)
    value = normalize(value); if not value then return end
    for _, p in ipairs(list) do if normalize(p) == value then return end end
    list[#list+1] = value
end
local function safe(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        logger.err("BookVault:", err)
        UIManager:show(InfoMessage:new{ text=_("BookVault encontrou um erro e não conseguiu concluir a ação.") })
    end
end

function BookVault:loadSettings()
    if self.settings then return end
    local ok, s = pcall(LuaSettings.open, LuaSettings, self.settings_file)
    if ok and s then self.settings=s else
        logger.err("BookVault: settings error", s)
        self.settings={data={}, flush=function() end}
    end
    self.settings.data.protected_paths=self.settings.data.protected_paths or {}
    self.settings.data.private_paths=self.settings.data.private_paths or {}
    if type(self.settings.data.visible_statuses) ~= "table" then
        self.settings.data.visible_statuses={all=true,reading=true,abandoned=true,complete=true,new=true}
    end
    if type(self.settings.data.visible_collections) ~= "table" then
        self.settings.data.visible_collections={}
    end
    local visible=self.settings.data.visible_statuses
    local count=0
    for _,status in ipairs(STATUS) do if visible[status.key] then count=count+1 end end
    if count == 0 then visible.all=true end
end
function BookVault:saveSettings()
    self:loadSettings(); local ok,err=pcall(self.settings.flush,self.settings)
    if not ok then logger.err("BookVault: flush error",err) end
end
function BookVault:getRoot()
    self:loadSettings(); local root=self.settings.data.root
    if root and lfs.attributes(root,"mode")=="directory" then return normalize(root) end
end
function BookVault:hasPassword()
    self:loadSettings(); return self.settings.data.password_hash ~= nil and self.settings.data.password_salt ~= nil
end
function BookVault:hashPassword(password,salt) return sha2.sha256(salt..password) end
function BookVault:verifyPassword(password)
    return self:hasPassword() and self:hashPassword(password,self.settings.data.password_salt)==self.settings.data.password_hash
end
function BookVault:askPassword(callback,title)
    if not self:hasPassword() then callback(false); return end
    local dialog
    dialog=InputDialog:new{title=title or _("Senha do BookVault"),input="",input_type="number",text_type="password",buttons={{
        {text=_("Cancelar"),callback=function() UIManager:close(dialog) end},
        {text=_("OK"),is_enter_default=true,callback=function()
            local password=dialog:getInputText(); UIManager:close(dialog)
            if self:verifyPassword(password) then safe(function() callback(true) end)
            else UIManager:show(InfoMessage:new{text=_("Senha incorreta.")}); callback(false) end
        end},
    }}}
    UIManager:show(dialog); dialog:onShowKeyboard()
end
function BookVault:saveNewPassword(password)
    local salt=table.concat({tostring(os.time()),tostring(math.random()),tostring(os.clock())},":")
    self.settings.data.password_salt=salt; self.settings.data.password_hash=self:hashPassword(password,salt); self:saveSettings()
end
function BookVault:setPassword(on_saved)
    local function create()
        local first
        first=InputDialog:new{title=self:hasPassword() and _("Nova senha numérica") or _("Criar senha numérica"),input="",input_type="number",text_type="password",buttons={{
            {text=_("Cancelar"),callback=function() UIManager:close(first) end},
            {text=_("Continuar"),is_enter_default=true,callback=function()
                local password=first:getInputText(); UIManager:close(first)
                if not password:match("^%d+$") or #password<4 then UIManager:show(InfoMessage:new{text=_("Use pelo menos 4 dígitos.")}); return end
                local second
                second=InputDialog:new{title=_("Confirmar senha"),input="",input_type="number",text_type="password",buttons={{
                    {text=_("Cancelar"),callback=function() UIManager:close(second) end},
                    {text=_("Salvar"),is_enter_default=true,callback=function()
                        local confirmation=second:getInputText(); UIManager:close(second)
                        if confirmation~=password then UIManager:show(InfoMessage:new{text=_("As senhas não coincidem.")}); return end
                        self:saveNewPassword(password); UIManager:show(InfoMessage:new{text=_("Senha salva.")}); if on_saved then safe(on_saved) end
                    end},
                }}}; UIManager:show(second); second:onShowKeyboard()
            end},
        }}}; UIManager:show(first); first:onShowKeyboard()
    end
    if self:hasPassword() then self:askPassword(function(ok) if ok then create() end end,_("Senha atual")) else create() end
end
function BookVault:isProtected(path)
    self:loadSettings(); for _,p in ipairs(self.settings.data.protected_paths) do if contains(p,path) then return true end end; return false
end
function BookVault:isPrivate(path)
    self:loadSettings(); for _,p in ipairs(self.settings.data.private_paths) do if contains(p,path) then return true end end; return false
end
function BookVault:needsUnlock(path) return self:isProtected(path) or self:isPrivate(path) end
function BookVault:guard(path,callback)
    if not self:needsUnlock(path) or self.unlocked then callback(); return end
    self:askPassword(function(ok) if ok then self.unlocked=true; safe(callback) end end)
end
function BookVault:scanBooks(include_private)
    local root=self:getRoot(); if not root then return {} end
    local result,visited,pending={}, {}, {root}; local index=1
    while index<=#pending do
        local dir=normalize(pending[index]); index=index+1
        if dir and not visited[dir] then
            visited[dir]=true
            local ok,iter,obj=pcall(lfs.dir,dir)
            if ok and iter and obj then
                for name in iter,obj do
                    if name~="." and name~=".." then
                        local path=dir.."/"..name; local attr=lfs.attributes(path)
                        if attr and attr.mode=="directory" then
                            if include_private or not self:isPrivate(path) then pending[#pending+1]=path end
                        elseif attr and attr.mode=="file" and (include_private or not self:isPrivate(path)) then
                            local pok,provider=pcall(DocumentRegistry.hasProvider,DocumentRegistry,path)
                            if pok and provider then result[#result+1]={path=path,filepath=path,text=name,attr=attr,is_file=true} end
                        end
                    end
                end
            end
        end
    end
    table.sort(result,function(a,b) return a.text:lower()<b.text:lower() end); return result
end
function BookVault:getStatusLabel(status)
    for _,s in ipairs(STATUS) do if s.key==status then return s.label end end; return STATUS[1].label
end
function BookVault:isStatusVisible(status)
    self:loadSettings(); return self.settings.data.visible_statuses[status] == true
end
function BookVault:getCollections()
    local ok,ReadCollection=pcall(require,"readcollection")
    if not ok or not ReadCollection or type(ReadCollection.coll)~="table" then return {} end
    local collections={}
    for name,coll in pairs(ReadCollection.coll) do
        if type(name)=="string" and type(coll)=="table" then
            local settings=ReadCollection.coll_settings and ReadCollection.coll_settings[name] or {}
            collections[#collections+1]={name=name,order=tonumber(settings.order) or 999999,count=0}
            for file in pairs(coll) do if file then collections[#collections].count=collections[#collections].count+1 end end
        end
    end
    table.sort(collections,function(a,b) if a.order==b.order then return a.name:lower()<b.name:lower() end return a.order<b.order end); return collections
end
function BookVault:isCollectionVisible(name)
    self:loadSettings(); return self.settings.data.visible_collections[name] ~= false
end
function BookVault:collectionItems(collection_name,include_private)
    local root=self:getRoot(); if not root then return {} end
    local ok,ReadCollection=pcall(require,"readcollection")
    if not ok or not ReadCollection or type(ReadCollection.coll)~="table" then return {} end
    local coll=ReadCollection.coll[collection_name]; if type(coll)~="table" then return {} end
    local items={}
    for file,item in pairs(coll) do
        local path=normalize(file)
        if path and contains(root,path) and (include_private or not self:isPrivate(path)) and lfs.attributes(path,"mode")=="file" then
            items[#items+1]={path=path,filepath=path,text=item.text or path:match("[^/]+$"),attr=lfs.attributes(path),is_file=true}
        end
    end
    table.sort(items,function(a,b) return a.text:lower()<b.text:lower() end); return items
end

function BookVault:sortBookVaultItems(menu,mode)
    if not menu then return end
    local items=menu._bookvault_source_items or menu.item_table or {}; local sorted={}
    for i,item in ipairs(items) do sorted[i]=item end
    if mode=="recent" then
        table.sort(sorted,function(a,b) return (a.attr and a.attr.access or 0)>(b.attr and b.attr.access or 0) end)
    elseif mode=="modified" then
        table.sort(sorted,function(a,b) return (a.attr and a.attr.modification or 0)>(b.attr and b.attr.modification or 0) end)
    elseif mode=="size" then
        table.sort(sorted,function(a,b) return (a.attr and a.attr.size or 0)>(b.attr and b.attr.size or 0) end)
    else
        table.sort(sorted,function(a,b) return (a.text or ""):lower()<(b.text or ""):lower() end)
    end
    menu._bookvault_source_items=sorted; menu.item_table=sorted; menu.page=1
    if menu._bookvault_sort_dialog then UIManager:close(menu._bookvault_sort_dialog); menu._bookvault_sort_dialog=nil end
    menu:updateItems()
end

-- The visual layer is lazy and optional. No coverbrowser module is required while
-- KOReader is loading BookVault, so a missing/incompatible visual dependency can
-- never prevent the plugin from appearing in Tools/Plugins.
function BookVault:prepareVisualMenu(menu,source_items)
    menu._bookvault_source_items=source_items
    menu.sortBookVaultItems=function(instance,mode) self:sortBookVaultItems(instance,mode) end
    menu.title_bar_left_icon="search"
    menu.onLeftButtonTap=function(instance)
        local dialog
        dialog=InputDialog:new{title=_("Buscar na biblioteca"),input="",input_type="text",buttons={{
            {text=_("Cancelar"),callback=function() UIManager:close(dialog) end},
            {text=_("Buscar"),is_enter_default=true,callback=function()
                local query=(dialog:getInputText() or ""):lower():gsub("^%s+",""):gsub("%s+$",""); UIManager:close(dialog)
                if query=="" then instance.item_table=instance._bookvault_source_items else
                    local filtered={}
                    for _,item in ipairs(instance._bookvault_source_items) do if (item.text or ""):lower():find(query,1,true) then filtered[#filtered+1]=item end end
                    instance.item_table=filtered
                end
                instance.page=1; instance:updateItems()
            end},
        }}}; UIManager:show(dialog); dialog:onShowKeyboard()
    end
    menu.onLeftButtonHold=function(instance)
        local buttons={
            {{text=_("Título"),callback=function() instance:sortBookVaultItems("title") end}},
            {{text=_("Mais recentes"),callback=function() instance:sortBookVaultItems("recent") end}},
            {{text=_("Modificados recentemente"),callback=function() instance:sortBookVaultItems("modified") end}},
            {{text=_("Tamanho"),callback=function() instance:sortBookVaultItems("size") end}},
            {{text=_("Cancelar"),callback=function() UIManager:close(instance._bookvault_sort_dialog) end}},
        }
        instance._bookvault_sort_dialog=ButtonDialog:new{title=_("Ordenar livros"),title_align="center",buttons=buttons}; UIManager:show(instance._bookvault_sort_dialog)
    end

    local ok_cover,CoverBrowser=pcall(require,"coverbrowser")
    local ok_menu,CoverMenu=pcall(require,"covermenu")
    local ok_mosaic,MosaicMenu=pcall(require,"mosaicmenu")
    if not (ok_cover and ok_menu and ok_mosaic and CoverBrowser and CoverMenu and MosaicMenu) then
        logger.warn("BookVault: cover mosaic unavailable; using native BookList"); return false
    end
    local ok_grid,grid_err=pcall(CoverBrowser.initGrid,menu,"mosaic_image")
    if not ok_grid then logger.warn("BookVault: could not initialize mosaic:",grid_err); return false end

    -- MosaicMenuItem asks its parent menu for getBookInfo(); this is the same
    -- provider used by KOReader's CoverBrowser and does not modify global classes.
    menu.getBookInfo=CoverBrowser.getBookInfo
    menu.updateItems=CoverMenu.updateItems
    menu.onCloseWidget=CoverMenu.onCloseWidget
    menu._recalculateDimen=MosaicMenu._recalculateDimen
    menu._updateItemsBuildUI=MosaicMenu._updateItemsBuildUI
    menu._do_cover_images=true
    menu._do_hint_opened=true
    menu._do_center_partial_rows=true
    return true
end

function BookVault:showCollection(collection_name)
    safe(function()
        local items=self:collectionItems(collection_name,self.unlocked)
        local menu=BookList:new{name="bookvault_collection_"..collection_name,title=_("BookVault").." · "..collection_name,item_table=items,covers_fullscreen=true,
            onMenuSelect=function(_,item) self:guard(item.path,function()
                if lfs.attributes(item.path,"mode")~="file" then UIManager:show(InfoMessage:new{text=_("O arquivo não existe mais.")}); return end
                ReaderUI:showReader(item.path)
            end) end,
        }
        self._active_visual_menu=menu; self:prepareVisualMenu(menu,items); UIManager:show(menu); menu:updateItems()
    end)
end
function BookVault:showCollectionChooser()
    local collections=self:getCollections(); local buttons={}
    for _,collection in ipairs(collections) do if self:isCollectionVisible(collection.name) then buttons[#buttons+1]={{text=collection.name,callback=function() UIManager:close(self.collection_dialog); self:showCollection(collection.name) end}} end end
    if #buttons==0 then UIManager:show(InfoMessage:new{text=_("Nenhuma coleção está configurada para aparecer no BookVault.")}); return end
    buttons[#buttons+1]={{text=_("Voltar"),callback=function() UIManager:close(self.collection_dialog) end}}
    self.collection_dialog=ButtonDialog:new{title=_("Coleções"),title_align="center",buttons=buttons}; UIManager:show(self.collection_dialog)
end
function BookVault:showCollectionVisibilityChooser()
    self:loadSettings(); local collections=self:getCollections()
    if #collections==0 then UIManager:show(InfoMessage:new{text=_("Nenhuma coleção do KOReader foi encontrada.")}); return end
    local function rebuild()
        local buttons={}
        for _,collection in ipairs(collections) do
            local checked=self:isCollectionVisible(collection.name)
            buttons[#buttons+1]={{text=(checked and "☑ " or "☐ ")..collection.name,callback=function() self.settings.data.visible_collections[collection.name]=not checked; self:saveSettings(); UIManager:close(self.collection_visibility_dialog); rebuild() end}}
        end
        buttons[#buttons+1]={{text=_("Concluído"),callback=function() UIManager:close(self.collection_visibility_dialog) end}}
        self.collection_visibility_dialog=ButtonDialog:new{title=_("Coleções exibidas"),title_align="center",buttons=buttons}; UIManager:show(self.collection_visibility_dialog)
    end
    rebuild()
end
function BookVault:showLibrary(status,include_private)
    safe(function()
        local items={}
        for _,item in ipairs(self:scanBooks(include_private)) do if status=="all" or BookList.getBookStatus(item.path)==status then items[#items+1]=item end end
        local menu=BookList:new{name="bookvault_library",title=_("BookVault").." · "..self:getStatusLabel(status),item_table=items,covers_fullscreen=true,
            onMenuSelect=function(_,item) self:guard(item.path,function()
                if lfs.attributes(item.path,"mode")~="file" then UIManager:show(InfoMessage:new{text=_("O arquivo não existe mais.")}); return end
                ReaderUI:showReader(item.path)
            end) end,
        }
        self._active_visual_menu=menu; self:prepareVisualMenu(menu,items); UIManager:show(menu); menu:updateItems()
    end)
end
function BookVault:showStatusChooser()
    self:loadSettings(); local buttons={}
    for _,status in ipairs(STATUS) do if self:isStatusVisible(status.key) then buttons[#buttons+1]={{text=status.label,callback=function() UIManager:close(self.status_dialog); self:showLibrary(status.key,self.unlocked) end}} end end
    for _,collection in ipairs(self:getCollections()) do if self:isCollectionVisible(collection.name) then buttons[#buttons+1]={{text="▸ "..collection.name,callback=function() UIManager:close(self.status_dialog); self:showCollection(collection.name) end}} end end
    if #buttons==0 then self.settings.data.visible_statuses.all=true; self:saveSettings(); buttons={{{text=STATUS[1].label,callback=function() UIManager:close(self.status_dialog); self:showLibrary("all",self.unlocked) end}}} end
    self.status_dialog=ButtonDialog:new{title=_("BookVault"),title_align="center",buttons=buttons}; UIManager:show(self.status_dialog)
end
function BookVault:showStatusVisibilityChooser()
    self:loadSettings()
    local function rebuild()
        local buttons={}; local visible=self.settings.data.visible_statuses
        for _,status in ipairs(STATUS) do
            local checked=visible[status.key]==true
            buttons[#buttons+1]={{text=(checked and "☑ " or "☐ ")..status.label,callback=function()
                if visible[status.key] and (function() local count=0; for _,item in ipairs(STATUS) do if visible[item.key] then count=count+1 end end; return count<=1 end)() then UIManager:show(InfoMessage:new{text=_("Mantenha pelo menos uma categoria visível.")}); return end
                visible[status.key]=not visible[status.key]; self:saveSettings(); UIManager:close(self.status_visibility_dialog); rebuild()
            end}}
        end
        buttons[#buttons+1]={{text=_("Concluído"),callback=function() UIManager:close(self.status_visibility_dialog) end}}
        self.status_visibility_dialog=ButtonDialog:new{title=_("Categorias exibidas"),title_align="center",buttons=buttons}; UIManager:show(self.status_visibility_dialog)
    end
    rebuild()
end
function BookVault:chooseRoot()
    self:loadSettings(); UIManager:show(PathChooser:new{path=self:getRoot() or G_reader_settings:readSetting("home_dir"),select_directory=true,select_file=false,onConfirm=function(path) if path then self.settings.data.root=normalize(path); self:saveSettings(); UIManager:show(InfoMessage:new{text=_("Pasta da biblioteca salva.")}) end end})
end
function BookVault:chooseManagedPath(private)
    self:loadSettings(); UIManager:show(PathChooser:new{path=self:getRoot() or G_reader_settings:readSetting("home_dir"),select_directory=true,select_file=false,onConfirm=function(path) if not path then return end; local list=private and self.settings.data.private_paths or self.settings.data.protected_paths; addUnique(list,path); self:saveSettings(); UIManager:show(InfoMessage:new{text=private and _("Pasta tornada privada.") or _("Pasta protegida.")}) end})
end
function BookVault:listManagedPaths(private)
    self:loadSettings(); local list=private and self.settings.data.private_paths or self.settings.data.protected_paths
    local function showList()
        local buttons={}
        for i,path in ipairs(list) do buttons[#buttons+1]={{text=path,callback=function() table.remove(list,i); self:saveSettings(); UIManager:close(self.path_dialog); showList() end}} end
        buttons[#buttons+1]={{text=_("Cancelar"),callback=function() UIManager:close(self.path_dialog) end}}
        self.path_dialog=ButtonDialog:new{title=private and _("Conteúdo privado") or _("Pastas protegidas"),buttons=buttons}; UIManager:show(self.path_dialog)
    end
    if self:hasPassword() then self:askPassword(function(ok) if ok then showList() end end) else showList() end
end
function BookVault:togglePrivate()
    if self.unlocked then self.unlocked=false; self:showStatusChooser(); return end
    if not self:hasPassword() then self:setPassword(function() self.unlocked=true; self:showStatusChooser() end) else self:askPassword(function(ok) if ok then self.unlocked=true; self:showStatusChooser() end end,_("Revelar conteúdo")) end
end
function BookVault:addToMainMenu(menu_items)
    menu_items.bookvault={text=_("BookVault"),sorting_hint="more_tools",sub_item_table={
        {text=_("Abrir biblioteca"),callback=function() self:showStatusChooser() end},
        {text_func=function() return self.unlocked and "◉ ".._("Ocultar conteúdo") or "◉ ".._("Revelar conteúdo") end,callback=function() self:togglePrivate() end},
        {text=_("Biblioteca"),separator=true,sub_item_table={{text=_("Configurar pasta da biblioteca"),callback=function() self:chooseRoot() end},{text=_("Categorias exibidas"),callback=function() self:showStatusVisibilityChooser() end},{text=_("Coleções"),callback=function() self:showCollectionChooser() end},{text=_("Coleções exibidas"),callback=function() self:showCollectionVisibilityChooser() end}}},
        {text=_("Segurança"),separator=true,sub_item_table={{text=_("Criar/alterar senha"),callback=function() self:setPassword() end},{text=_("Proteger uma pasta"),callback=function() self:chooseManagedPath(false) end},{text=_("Gerenciar pastas protegidas"),callback=function() self:listManagedPaths(false) end}}},
        {text=_("Privacidade"),separator=true,sub_item_table={{text=_("Tornar uma pasta privada"),callback=function() self:chooseManagedPath(true) end},{text=_("Gerenciar conteúdo privado"),callback=function() self:listManagedPaths(true) end}}},
    }}
end
function BookVault:show() self:showStatusChooser() end
function BookVault:onSuspend() self.unlocked=false end
function BookVault:onResume() self.unlocked=false end
function BookVault:init() self:loadSettings(); self.ui.menu:registerToMainMenu(self) end
return BookVault
