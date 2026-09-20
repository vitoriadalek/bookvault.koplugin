local ButtonDialog = require("ui/widget/buttondialog")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local DataStorage = require("datastorage")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BookList = require("ui/widget/booklist")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local sha2 = require("ffi/sha2")
local logger = require("logger")
local _ = require("gettext")
local Screen = require("device").screen

local BookVault = WidgetContainer:extend{
    name = "bookvault", fullname = _("BookVault"), is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/bookvault.lua",
    settings = nil, unlocked = false,
}

local STATUS = {
    { key="all", label=_("Todos") },
    { key="reading", label=_("Lendo") },
    { key="abandoned", label=_("Em espera") },
    { key="complete", label=_("Concluídos") },
    { key="new", label=_("Não iniciados") },
}

local function normalize(path)
    if not path then return nil end
    local ok, real = pcall(ffiUtil.realpath, path)
    return ((ok and real) or path):gsub("/+$", "")
end

local function contains(parent, child)
    parent, child = normalize(parent), normalize(child)
    return parent and child and (child == parent or child:sub(1, #parent + 1) == parent .. "/")
end

local function addUnique(list, value)
    value = normalize(value)
    if not value then return end
    for _, p in ipairs(list) do if normalize(p) == value then return end end
    list[#list + 1] = value
end

local function copyItems(items)
    local result = {}
    for i, item in ipairs(items or {}) do result[i] = item end
    return result
end

local function safe(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        logger.err("BookVault:", err)
        UIManager:show(InfoMessage:new{ text = _("BookVault encontrou um erro e não conseguiu concluir a ação.") })
    end
end

function BookVault:loadSettings()
    if self.settings then return end
    local ok, s = pcall(LuaSettings.open, LuaSettings, self.settings_file)
    if ok and s then self.settings = s else
        logger.err("BookVault: settings error", s)
        self.settings = { data = {}, flush = function() end }
    end
    local d = self.settings.data
    d.protected_paths = d.protected_paths or {}
    d.private_paths = d.private_paths or {}
    d.custom_orders = d.custom_orders or {}
    d.sort_modes = d.sort_modes or {}
    d.sort_directions = d.sort_directions or {}
    d.grid = d.grid or {}
    d.appearance = d.appearance or {}
    if type(d.visible_statuses) ~= "table" then
        d.visible_statuses = { all=true, reading=true, abandoned=true, complete=true, new=true }
    else
        -- Older BookVault versions did not persist the complete category.
        -- Add it only when the key is genuinely absent; an explicit user choice
        -- to hide it is preserved.
        if d.visible_statuses.complete == nil then d.visible_statuses.complete = true end
    end
    if type(d.visible_collections) ~= "table" then d.visible_collections = {} end
    local visible = d.visible_statuses
    local count = 0
    for _, status in ipairs(STATUS) do if visible[status.key] then count = count + 1 end end
    if count == 0 then visible.all = true end
end

function BookVault:saveSettings()
    self:loadSettings()
    local ok, err = pcall(self.settings.flush, self.settings)
    if not ok then logger.err("BookVault: flush error", err) end
end

function BookVault:getRoot()
    self:loadSettings()
    local root = self.settings.data.root
    if root and lfs.attributes(root, "mode") == "directory" then return normalize(root) end
end

function BookVault:hasPassword()
    self:loadSettings()
    return self.settings.data.password_hash ~= nil and self.settings.data.password_salt ~= nil
end

function BookVault:hashPassword(password, salt) return sha2.sha256(salt .. password) end
function BookVault:verifyPassword(password)
    return self:hasPassword() and self:hashPassword(password, self.settings.data.password_salt) == self.settings.data.password_hash
end

function BookVault:askPassword(callback, title)
    if not self:hasPassword() then callback(false); return end
    local dialog
    dialog = InputDialog:new{
        title=title or _("Senha do BookVault"), input="", input_type="number", text_type="password",
        buttons={{
            {text=_("Cancelar"), callback=function() UIManager:close(dialog) end},
            {text=_("OK"), is_enter_default=true, callback=function()
                local password=dialog:getInputText(); UIManager:close(dialog)
                if self:verifyPassword(password) then safe(function() callback(true) end)
                else UIManager:show(InfoMessage:new{text=_("Senha incorreta.")}); callback(false) end
            end},
        }},
    }
    UIManager:show(dialog); pcall(dialog.onShowKeyboard, dialog)
end

function BookVault:saveNewPassword(password)
    local salt=table.concat({tostring(os.time()),tostring(math.random()),tostring(os.clock())},":")
    self.settings.data.password_salt=salt
    self.settings.data.password_hash=self:hashPassword(password,salt)
    self:saveSettings()
end

function BookVault:setPassword(on_saved)
    local function create()
        local first
        first=InputDialog:new{
            title=self:hasPassword() and _("Nova senha numérica") or _("Criar senha numérica"), input="", input_type="number", text_type="password",
            buttons={{
                {text=_("Cancelar"), callback=function() UIManager:close(first) end},
                {text=_("Continuar"), is_enter_default=true, callback=function()
                    local password=first:getInputText(); UIManager:close(first)
                    if not password:match("^%d+$") or #password<4 then UIManager:show(InfoMessage:new{text=_("Use pelo menos 4 dígitos.")}); return end
                    local second
                    second=InputDialog:new{
                        title=_("Confirmar senha"), input="", input_type="number", text_type="password",
                        buttons={{
                            {text=_("Cancelar"), callback=function() UIManager:close(second) end},
                            {text=_("Salvar"), is_enter_default=true, callback=function()
                                local confirmation=second:getInputText(); UIManager:close(second)
                                if confirmation~=password then UIManager:show(InfoMessage:new{text=_("As senhas não coincidem.")}); return end
                                self:saveNewPassword(password); UIManager:show(InfoMessage:new{text=_("Senha salva.")}); if on_saved then safe(on_saved) end
                            end},
                        }},
                    }; UIManager:show(second); pcall(second.onShowKeyboard, second)
                end},
            }},
        }; UIManager:show(first); pcall(first.onShowKeyboard, first)
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

function BookVault:invalidateLibraryCache()
    self._bookvault_scan_cache = nil
    self._bookvault_scan_cache_key = nil
    self._bookvault_status_index = nil
end

function BookVault:invalidateStatusCache(file)
    self._bookvault_status_cache = self._bookvault_status_cache or {}
    if file then
        self._bookvault_status_cache[normalize(file)] = nil
    else
        self._bookvault_status_cache = {}
    end
    self._bookvault_status_index = nil
end

function BookVault:getBookStatusCached(file)
    local key = normalize(file)
    if not key then return nil end
    self._bookvault_status_cache = self._bookvault_status_cache or {}
    local cached = self._bookvault_status_cache[key]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    local ok, status = pcall(BookList.getBookStatus, key)
    self._bookvault_status_cache[key] = ok and (status or false) or false
    return status
end

function BookVault:invalidateBookMetadataCache(file)
    if file then
        local key = normalize(file)
        if self._bookvault_metadata_cache and key then self._bookvault_metadata_cache[key] = nil end
    else
        self._bookvault_metadata_cache = {}
    end
end

function BookVault:makeBookItem(path)
    local normalized = normalize(path)
    if not normalized then return nil end
    local attr = lfs.attributes(normalized)
    if not attr or attr.mode ~= "file" then return nil end
    local ok, provider = pcall(DocumentRegistry.hasProvider, DocumentRegistry, normalized)
    if not ok or not provider then return nil end
    return {
        path = normalized,
        filepath = normalized,
        text = ffiUtil.basename(normalized) or normalized:match("[^/]+$") or normalized,
        attr = attr,
        is_file = true,
    }
end

function BookVault:updateMenuPath(menu, old_path, new_path, is_copy)
    if not menu or not new_path then return end
    local old_key = old_path and normalize(old_path) or nil
    local new_item = self:makeBookItem(new_path)
    local include_private = self.privacyIncludePrivate and self:privacyIncludePrivate() or false
    local root = self:getRoot()
    local visible = new_item and root and contains(root, new_item.path)
        and (include_private or not self:isPrivate(new_item.path))
    local view_status = menu._bookvault_view_key and menu._bookvault_view_key:match("^status:(.+)$") or nil
    if visible and view_status and view_status ~= "all" then
        visible = self:getBookStatusCached(new_item.path) == view_status
    end

    local function replace_path(list, key, replacement)
        if not list or not key then return false end
        for i, item in ipairs(list) do
            if item and normalize(item.path) == key then
                if replacement then
                    list[i] = replacement
                else
                    table.remove(list, i)
                end
                return true
            end
        end
        return false
    end

    local source = menu._bookvault_source_items
    local filtered = menu._bookvault_filtered_items
    local table_items = menu.item_table

    if old_key and not is_copy then
        replace_path(source, old_key, visible and new_item or nil)
        replace_path(filtered, old_key, visible and new_item or nil)
        replace_path(table_items, old_key, visible and new_item or nil)
    end

    if is_copy and visible and not filtered and source and table_items then
        source[#source + 1] = new_item
        table_items[#table_items + 1] = new_item
    end
end

function BookVault:scanBooks(include_private)
    local root=self:getRoot(); if not root then return {} end
    local cache_key = root .. "|" .. (include_private and "1" or "0")
    if self._bookvault_scan_cache_key == cache_key and type(self._bookvault_scan_cache) == "table" then
        return copyItems(self._bookvault_scan_cache)
    end
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
    table.sort(result,function(a,b) return (a.text or ""):lower()<(b.text or ""):lower() end)
    self._bookvault_scan_cache_key = cache_key
    self._bookvault_scan_cache = result
    return copyItems(result)
end

function BookVault:getStatusIndex(include_private)
    self:loadSettings()
    local root = self:getRoot()
    local scan_key = root and (root .. "|" .. (include_private and "1" or "0")) or nil
    local cache = self._bookvault_status_index
    if cache and cache.scan_key == scan_key and cache.scan_ref == self._bookvault_scan_cache then
        return cache.by_status
    end

    local by_status = { all = {}, reading = {}, abandoned = {}, complete = {}, new = {} }
    local all_items = self:scanBooks(include_private)
    by_status.all = all_items
    for _, item in ipairs(all_items) do
        local status = self:getBookStatusCached(item.path) or "new"
        if not by_status[status] then status = "new" end
        by_status[status][#by_status[status] + 1] = item
    end

    self._bookvault_status_index = {
        scan_key = scan_key,
        scan_ref = self._bookvault_scan_cache,
        by_status = by_status,
    }
    return by_status
end

function BookVault:getStatusLabel(status)
    for _,s in ipairs(STATUS) do if s.key==status then return s.label end end
    return STATUS[1].label
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
    table.sort(collections,function(a,b) if a.order==b.order then return a.name:lower()<b.name:lower() end return a.order<b.order end)
    return collections
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
            items[#items+1]={path=path,filepath=path,text=(item and item.text) or path:match("[^/]+$") or path,attr=lfs.attributes(path),is_file=true}
        end
    end
    table.sort(items,function(a,b) return (a.text or ""):lower()<(b.text or ""):lower() end)
    return items
end

function BookVault:getCustomOrder(view_key)
    self:loadSettings(); local order=self.settings.data.custom_orders[view_key]
    return type(order)=="table" and order or {}
end
function BookVault:applyCustomOrder(items,view_key)
    local order=self:getCustomOrder(view_key); local sorted=copyItems(items)
    table.sort(sorted,function(a,b)
        local pa,pb=tonumber(order[a.path]),tonumber(order[b.path])
        if pa and pb then if pa==pb then return (a.text or ""):lower()<(b.text or ""):lower() end return pa<pb end
        if pa then return true end if pb then return false end
        return (a.text or ""):lower()<(b.text or ""):lower()
    end)
    return sorted
end
function BookVault:saveCustomOrder(view_key,items)
    self:loadSettings(); local order={}
    for i,item in ipairs(items or {}) do order[item.path]=i end
    self.settings.data.custom_orders[view_key]=order; self:saveSettings()
end
function BookVault:moveCustomItem(view_key,items,index,target)
    if index<1 or index>#items or target<1 or target>#items or index==target then return end
    local item=table.remove(items,index); table.insert(items,target,item); self:saveCustomOrder(view_key,items)
end

function BookVault:showCustomOrderEditor(menu)
    local view_key=menu._bookvault_view_key; local working=copyItems(menu._bookvault_source_items); local dialog
    local function rebuild()
        if dialog then UIManager:close(dialog) end
        local buttons={}
        for i,item in ipairs(working) do
            local idx=i; local selected_item=item
            buttons[#buttons+1]={{text=string.format("%02d. %s",idx,selected_item.text or selected_item.path or ""),callback=function()
                local action
                local function refresh()
                    if action then UIManager:close(action) end
                    self:saveCustomOrder(view_key,working); rebuild()
                    menu._bookvault_filtered_items=nil; menu._bookvault_source_items=copyItems(working); menu.item_table=copyItems(working); menu.page=1; menu:updateItems()
                end
                action=ButtonDialog:new{title=_("Mover livro")..": "..(selected_item.text or ""),title_align="center",buttons={
                    {{text=_("↑ Mover para cima"),enabled=idx>1,callback=function() self:moveCustomItem(view_key,working,idx,idx-1); refresh() end}},
                    {{text=_("↓ Mover para baixo"),enabled=idx<#working,callback=function() self:moveCustomItem(view_key,working,idx,idx+1); refresh() end}},
                    {{text=_("⤒ Mover para o início"),enabled=idx>1,callback=function() self:moveCustomItem(view_key,working,idx,1); refresh() end}},
                    {{text=_("⤓ Mover para o fim"),enabled=idx<#working,callback=function() self:moveCustomItem(view_key,working,idx,#working); refresh() end}},
                    {{text=_("Cancelar"),callback=function() UIManager:close(action) end}},
                }}; UIManager:show(action)
            end}}
        end
        buttons[#buttons+1]={{text=_("Concluído"),callback=function() self:saveCustomOrder(view_key,working); UIManager:close(dialog); menu._bookvault_filtered_items=nil; menu._bookvault_source_items=copyItems(working); menu.item_table=copyItems(working); menu.page=1; menu:updateItems() end}}
        dialog=ButtonDialog:new{title=_("Ordem personalizada"),title_align="center",buttons=buttons}; UIManager:show(dialog)
    end
    rebuild()
end

function BookVault:getBookMetadata(item)
    if not item or not item.path then return {} end
    local path = normalize(item.path)
    if not path then return {} end
    self._bookvault_metadata_cache = self._bookvault_metadata_cache or {}

    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "file" then
        self._bookvault_metadata_cache[path] = nil
        return {}
    end
    local custom_file = nil
    local cover_file = nil
    pcall(function() custom_file = DocSettings.findCustomMetadataFile(path) end)
    pcall(function() cover_file = DocSettings.findCustomCoverFile(path) end)
    local custom_attr = custom_file and lfs.attributes(custom_file)
    local cover_attr = cover_file and lfs.attributes(cover_file)
    local fingerprint = table.concat({
        attr.modification or 0, attr.size or 0,
        custom_attr and custom_attr.modification or 0, custom_attr and custom_attr.size or 0,
        cover_attr and cover_attr.modification or 0, cover_attr and cover_attr.size or 0,
    }, ":")

    local cached = self._bookvault_metadata_cache[path]
    if cached and cached.fingerprint == fingerprint then
        local volatile = BookList.getBookInfo(path) or {}
        cached.info.status = self:getBookStatusCached(path)
        cached.info.progress = volatile.percent_finished
        cached.info.percent_finished = volatile.percent_finished
        cached.info.size = attr.size
        cached.info.location = path
        cached.info.cover = cover_file
        cached.info.tags = cached.info.tags or cached.info.keywords
        return cached.info
    end

    local bim=self:loadBookInfoManager()
    if not bim then return {} end
    local ok_info,info=pcall(bim.getBookInfo,bim,path,false)
    if not ok_info or type(info)~="table" then
        self._bookvault_metadata_cache[path] = { fingerprint = fingerprint, info = {} }
        return self._bookvault_metadata_cache[path].info
    end

    local volatile = BookList.getBookInfo(path) or {}
    info.status = self:getBookStatusCached(path)
    info.progress = volatile.percent_finished
    info.percent_finished = volatile.percent_finished
    info.size = attr.size
    info.location = path
    info.cover = cover_file
    info.tags = info.tags or info.keywords

    self._bookvault_metadata_cache[path] = { fingerprint = fingerprint, info = info }
    return info
end

function BookVault:sortBookVaultItems(menu,mode,direction)
    if not menu then return end
    self:loadSettings()
    local key=menu._bookvault_view_key
    local all_directions=self.settings.data.sort_directions
    if type(all_directions)~="table" then all_directions={} ; self.settings.data.sort_directions=all_directions end
    local directions=all_directions[key]
    if type(directions)~="table" then directions={} ; all_directions[key]=directions end
    direction=direction or directions[mode] or ((mode=="title" or mode=="author") and "asc" or "desc")
    self.settings.data.sort_modes[key]=mode
    directions[mode]=direction
    self:saveSettings()
    if mode=="custom" then self:showCustomOrderEditor(menu); return end
    local items=copyItems(menu._bookvault_filtered_items or menu._bookvault_source_items or menu.item_table or {})
    local function cmp(a,b) if a==b then return false end; return direction=="asc" and a<b or a>b end
    if mode=="recent" then
        table.sort(items,function(a,b) return cmp(a.attr and a.attr.access or 0,b.attr and b.attr.access or 0) end)
    elseif mode=="modified" then
        table.sort(items,function(a,b) return cmp(a.attr and a.attr.modification or 0,b.attr and b.attr.modification or 0) end)
    elseif mode=="size" then
        table.sort(items,function(a,b) return cmp(a.attr and a.attr.size or 0,b.attr and b.attr.size or 0) end)
    elseif mode=="author" or mode=="title" or mode=="pages" then
        local cache={}
        local function meta(item) if not cache[item.path] then cache[item.path]=self:getBookMetadata(item) end; return cache[item.path] end
        table.sort(items,function(a,b)
            local ma,mb=meta(a),meta(b)
            if mode=="author" then
                local aa=(ma.authors or a.author or ""):lower(); local ab=(mb.authors or b.author or ""):lower()
                if aa==ab then return cmp((ma.title or a.text or ""):lower(),(mb.title or b.text or ""):lower()) end
                return cmp(aa,ab)
            elseif mode=="pages" then
                local pa=tonumber(ma.pages or a.pages) or 0; local pb=tonumber(mb.pages or b.pages) or 0
                if pa==pb then return cmp((ma.title or a.text or ""):lower(),(mb.title or b.text or ""):lower()) end
                return cmp(pa,pb)
            end
            return cmp((ma.title or a.text or ""):lower(),(mb.title or b.text or ""):lower())
        end)
    else
        table.sort(items,function(a,b) return cmp((a.text or ""):lower(),(b.text or ""):lower()) end)
    end
    menu.item_table=items; menu.page=1
    if not menu._bookvault_filtered_items then menu._bookvault_source_items=items end
    if menu._bookvault_sort_dialog then UIManager:close(menu._bookvault_sort_dialog); menu._bookvault_sort_dialog=nil end
    local old_no_refresh = menu.no_refresh_covers
    menu.no_refresh_covers = true
    pcall(menu.updateItems, menu)
    menu.no_refresh_covers = old_no_refresh
end

function BookVault:sortDirectionLabel(mode,direction)
    local labels={title={"A → Z","Z → A"},author={"A → Z","Z → A"},recent={"novo → antigo","antigo → novo"},modified={"novo → antigo","antigo → novo"},size={"maior → menor","menor → maior"},pages={"mais → menos","menos → mais"}}
    local pair=labels[mode] or {"manual","manual"}
    return direction=="asc" and pair[1] or pair[2]
end

function BookVault:showSortDialog(menu)
    if not menu then return end
    self:loadSettings()
    local key=menu._bookvault_view_key
    local active=self.settings.data.sort_modes[key]
    local directions=self.settings.data.sort_directions[key] or {}
    local function current(mode) return directions[mode] or ((mode=="title" or mode=="author") and "asc" or "desc") end
    local function toggle(mode)
        local d=current(mode); d=(d=="asc") and "desc" or "asc"; self:sortBookVaultItems(menu,mode,d)
    end
    local function row(mode,label)
        local marker=active==mode and "✓ " or "  "
        return {{text=marker.._(label).."    "..self:sortDirectionLabel(mode,current(mode)),callback=function() toggle(mode) end}}
    end
    local buttons={
        row("title","Título"), row("author","Autor"), row("recent","Acessados recentemente"),
        row("modified","Modificados recentemente"), row("size","Tamanho"), row("pages","Páginas"),
        {{text="  ".._("Ordem personalizada").."    manual",callback=function() UIManager:close(menu._bookvault_sort_dialog); menu._bookvault_sort_dialog=nil; self:showCustomOrderEditor(menu) end}},
        {{text=_("Cancelar"),callback=function() UIManager:close(menu._bookvault_sort_dialog); menu._bookvault_sort_dialog=nil end}},
    }
    menu._bookvault_sort_dialog=ButtonDialog:new{title=_("Ordenar livros"),title_align="center",buttons=buttons}; UIManager:show(menu._bookvault_sort_dialog)
end

function BookVault:showSearchDialog(menu)
    if not menu then return end
    local dialog
    dialog=InputDialog:new{
        title=_("Buscar livros"),input="",input_type="text",
        buttons={{
            {text=_("Cancelar"),callback=function() UIManager:close(dialog) end},
            {text=_("Buscar"),is_enter_default=true,callback=function()
                local query=(dialog:getInputText() or ""):lower():gsub("^%s+",""):gsub("%s+$",""); UIManager:close(dialog)
                local filtered={}
                if query=="" then filtered=copyItems(menu._bookvault_source_items)
                else
                    for _,item in ipairs(menu._bookvault_source_items or {}) do
                        local text=(item.text or ""):lower()
                        if not text:find(query,1,true) then
                            local info=self:getBookMetadata(item)
                            text=((info.title or "").." "..(info.authors or "")):lower()
                        end
                        if text:find(query,1,true) then filtered[#filtered+1]=item end
                    end
                end
                menu._bookvault_filtered_items=filtered; menu.item_table=filtered; menu.page=1
                local old_no_refresh = menu.no_refresh_covers
                menu.no_refresh_covers = true
                pcall(menu.updateItems, menu)
                menu.no_refresh_covers = old_no_refresh
            end},
        }},
    }
    UIManager:show(dialog); pcall(dialog.onShowKeyboard,dialog)
end

function BookVault:loadVisualModules()
    local old_path=package.path
    package.path="plugins/coverbrowser.koplugin/?.lua;./plugins/coverbrowser.koplugin/?.lua;"..package.path
    local ok_bim,BookInfoManager=pcall(require,"bookinfomanager")
    local ok_cm,CoverMenu=pcall(require,"covermenu")
    local ok_mm,MosaicMenu=pcall(require,"mosaicmenu")
    package.path=old_path
    if not (ok_bim and ok_cm and ok_mm and BookInfoManager and CoverMenu and MosaicMenu) then
        logger.warn("BookVault: bundled CoverBrowser modules unavailable; using standard BookList")
        return nil
    end
    return BookInfoManager,CoverMenu,MosaicMenu
end

function BookVault:ensureBookVaultIcons()
    local icon_dir=DataStorage:getDataDir().."/icons"
    if lfs.attributes(icon_dir,"mode")~="directory" then pcall(lfs.mkdir,icon_dir) end
    if lfs.attributes(icon_dir,"mode")~="directory" then return false end
    local required={"bookvault-search.png","bookvault-sort.png","bookvault-sort-cat.png","bookvault-cat.png","bookvault-moon.png"}
    for _,name in ipairs(required) do
        if lfs.attributes(icon_dir.."/"..name,"mode")~="file" then return false end
    end
    return true
end

function BookVault:loadBookInfoManager()
    local old_path=package.path
    package.path="plugins/coverbrowser.koplugin/?.lua;./plugins/coverbrowser.koplugin/?.lua;"..package.path
    local ok,bim=pcall(require,"bookinfomanager")
    package.path=old_path
    if ok and bim then return bim end
    logger.warn("BookVault: BookInfoManager unavailable")
    return nil
end

function BookVault:showGridSettings(menu)
    self:loadSettings()
    local grid=self.settings.data.grid
    local visual=menu or {}
    local bim=self:loadVisualModules()
    if not bim then UIManager:show(InfoMessage:new{text=_("A grade visual do KOReader não está disponível nesta versão.")}); return end
    local function edit(landscape)
        local cols_key=landscape and "landscape_cols" or "portrait_cols"
        local rows_key=landscape and "landscape_rows" or "portrait_rows"
        local default_cols=landscape and 4 or 5
        local default_rows=landscape and 2 or 4
        local cols=grid[cols_key] or (landscape and visual.nb_cols_landscape or visual.nb_cols_portrait) or default_cols
        local rows=grid[rows_key] or (landscape and visual.nb_rows_landscape or visual.nb_rows_portrait) or default_rows
        local function apply()
            grid[cols_key]=cols; grid[rows_key]=rows; self:saveSettings()
            if menu and menu._bookvault_visual then
                if landscape then menu.nb_cols_landscape=cols; menu.nb_rows_landscape=rows
                else menu.nb_cols_portrait=cols; menu.nb_rows_portrait=rows end
                menu.no_refresh_covers=true
                if menu._recalculateDimen then pcall(menu._recalculateDimen,menu) end
                menu:updateItems()
                menu.no_refresh_covers=nil
            end
        end
        local widget=DoubleSpinWidget:new{
            title_text=landscape and _("Grade de capas · paisagem") or _("Grade de capas · retrato"),
            width_factor=0.72,left_text=_("Colunas"),left_value=cols,left_min=2,left_max=8,left_default=default_cols,left_precision="%01d",
            right_text=_("Linhas"),right_value=rows,right_min=2,right_max=8,right_default=default_rows,right_precision="%01d",
            keep_shown_on_apply=true,callback=function(a,b) cols=a; rows=b; apply() end,close_callback=apply,
        }
        UIManager:show(widget)
    end
    local dialog
    dialog=ButtonDialog:new{title=_("Grade de capas"),title_align="center",buttons={
        {{text=_("Retrato"),callback=function() UIManager:close(dialog); edit(false) end}},
        {{text=_("Paisagem"),callback=function() UIManager:close(dialog); edit(true) end}},
        {{text=_("Concluído"),callback=function() UIManager:close(dialog) end}},
    }}
    UIManager:show(dialog)
end

function BookVault:showAppearanceSettings(menu)
    self:loadSettings()
    local a=self.settings.data.appearance
    if a.show_cat == nil then a.show_cat=true end
    if a.show_moon == nil then a.show_moon=true end
    local function rebuild()
        local buttons={
            {{text=(a.show_cat and "☑ " or "☐ ").._("Identidade do BookVault"),callback=function() a.show_cat=not a.show_cat; self:saveSettings(); UIManager:close(self.appearance_dialog); rebuild() end}},
            {{text=(a.show_moon and "☑ " or "☐ ").._("Detalhe lunar"),callback=function() a.show_moon=not a.show_moon; self:saveSettings(); UIManager:close(self.appearance_dialog); rebuild() end}},
            {{text=_("Configurar grade de capas"),callback=function() UIManager:close(self.appearance_dialog); self:showGridSettings(menu) end}},
            {{text=_("Concluído"),callback=function() UIManager:close(self.appearance_dialog) end}},
        }
        self.appearance_dialog=ButtonDialog:new{title=_("Aparência do BookVault"),title_align="center",buttons=buttons}; UIManager:show(self.appearance_dialog)
    end
    rebuild()
end

function BookVault:showBookVaultSettings(menu)
    local dialog

    local function close()
        if dialog then UIManager:close(dialog) end
    end

    local function showSubmenu(title, buttons)
        local sub
        local rows = buttons or {}
        rows[#rows + 1] = {{text=_("Voltar"), callback=function() if sub then UIManager:close(sub) end end}}
        sub = ButtonDialog:new{title=title, title_align="center", buttons=rows}
        UIManager:show(sub)
    end

    dialog = ButtonDialog:new{
        title=_("BookVault"),
        title_align="center",
        buttons={
            {{text=_("Abrir biblioteca"), callback=function()
                close()
                self:showStatusChooser()
            end}},
            {{text_func=function()
                return self.unlocked and "◉ ".._("Ocultar conteúdo") or "◉ ".._("Revelar conteúdo")
            end, callback=function()
                close()
                self:togglePrivate()
            end}},
            {{text=_("Biblioteca"), callback=function()
                close()
                showSubmenu(_("Biblioteca"), {
                    {{text=_("Configurar pasta da biblioteca"), callback=function()
                        self:chooseRoot()
                    end}},
                    {{text=_("Categorias exibidas"), callback=function()
                        self:showStatusVisibilityChooser()
                    end}},
                    {{text=_("Coleções"), callback=function()
                        self:showCollectionChooser()
                    end}},
                    {{text=_("Coleções exibidas"), callback=function()
                        self:showCollectionVisibilityChooser()
                    end}},
                })
            }},
            {{text=_("Aparência"), callback=function()
                close()
                self:showAppearanceSettings(menu)
            end}},
            {{text=_("Segurança"), callback=function()
                close()
                showSubmenu(_("Segurança"), {
                    {{text=_("Criar/alterar senha"), callback=function() self:setPassword() end}},
                    {{text=_("Proteger uma pasta"), callback=function() self:chooseManagedPath(false) end}},
                    {{text=_("Gerenciar pastas protegidas"), callback=function() self:listManagedPaths(false) end}},
                })
            }},
            {{text=_("Privacidade"), callback=function()
                close()
                showSubmenu(_("Privacidade"), {
                    {{text=_("Tornar uma pasta privada"), callback=function() self:chooseManagedPath(true) end}},
                    {{text=_("Gerenciar conteúdo privado"), callback=function() self:listManagedPaths(true) end}},
                })
            }},
            {{text=_("Cancelar"), callback=close}},
        },
    }
    UIManager:show(dialog)
end

function BookVault:prepareVisualMenu(menu,source_items)
    menu._bookvault_source_items=source_items
    menu.sortBookVaultItems=function(instance,mode) self:sortBookVaultItems(instance,mode) end
    local BookInfoManager,CoverMenu,MosaicMenu=self:loadVisualModules()
    if not BookInfoManager then return false end
    self:loadSettings(); local grid=self.settings.data.grid
    menu.nb_cols_portrait=grid.portrait_cols or BookInfoManager:getSetting("nb_cols_portrait") or 3
    menu.nb_rows_portrait=grid.portrait_rows or BookInfoManager:getSetting("nb_rows_portrait") or 3
    menu.nb_cols_landscape=grid.landscape_cols or BookInfoManager:getSetting("nb_cols_landscape") or 4
    menu.nb_rows_landscape=grid.landscape_rows or BookInfoManager:getSetting("nb_rows_landscape") or 2
    menu.files_per_page=BookInfoManager:getSetting("files_per_page")
    menu.display_mode_type="mosaic"
    menu.updateItems=CoverMenu.updateItems
    menu.onCloseWidget=CoverMenu.onCloseWidget
    menu._recalculateDimen=MosaicMenu._recalculateDimen
    menu._updateItemsBuildUI=MosaicMenu._updateItemsBuildUI
    menu._do_cover_images=true
    menu._do_hint_opened=true
    menu._do_center_partial_rows=true
    menu._bookvault_visual=true
    return true
end

function BookVault:decorateTitleBar(menu, appearance, search_cb, sort_cb, settings_cb)
    -- Kept as a compatibility no-op: BookVault now uses BookVaultHeader.
end

function BookVault:changeCategory(menu, status)
    if not menu or not status then return end

    -- Reuse the already scanned library and the existing mosaic menu.
    -- Switching a status must not close/recreate the whole BookVault screen.
    local include_private = self.privacyIncludePrivate and self:privacyIncludePrivate() or false
    local by_status = self:getStatusIndex(include_private)
    local filtered = by_status[status] or by_status.all or {}

    local view_key = "status:" .. status
    menu._bookvault_view_key = view_key
    menu._bookvault_source_items = self:applyCustomOrder(filtered, view_key)
    menu._bookvault_filtered_items = nil
    menu.item_table = copyItems(menu._bookvault_source_items)
    menu.page = 1

    self:loadSettings()
    self.settings.data.last_status = status

    local header = menu._bookvault_header
    if header and header.setActiveStatus then
        header:setActiveStatus(status)
    end

    -- Avoid forcing a cover re-read when only the item table changed.
    menu.no_refresh_covers = true
    pcall(menu.updateItems, menu, 1, true)
    menu.no_refresh_covers = nil
end

function BookVault:makeBookMenu(name,title,items,view_key)
    local menu

    -- Visual dependencies are lazy-loaded so a problem in a UI helper can
    -- never make the BookVault plugin disappear from KOReader/Simple UI.
    local ok_bootstrap = pcall(require, "bookvault_icons_bootstrap")
    if not ok_bootstrap then
        logger.warn("BookVault: icon bootstrap unavailable")
    end
    local ok_header, BookVaultHeader = pcall(require, "bookvault_header")
    if not ok_header or not BookVaultHeader then
        UIManager:show(InfoMessage:new{
            text = _("BookVault não conseguiu carregar a interface visual. Verifique a instalação do plugin."),
        })
        return nil
    end

    self:ensureBookVaultIcons()
    self:loadSettings()
    local appearance=self.settings.data.appearance
    if appearance.show_cat == nil then appearance.show_cat=true end
    if appearance.show_moon == nil then appearance.show_moon=true end

    local active_status = "all"
    local prefix = view_key and view_key:match("^status:(.+)$")
    if prefix then active_status = prefix end

    local function search_cb() self:showSearchDialog(menu) end
    local function sort_cb() self:showSortDialog(menu) end
    local function settings_cb() self:showBookVaultSettings(menu) end
    local function status_cb(status) self:changeCategory(menu,status) end

    local header = BookVaultHeader:new{
        width=Screen:getWidth(),
        active_status=active_status,
        visible_statuses=self.settings.data.visible_statuses,
        show_cat=appearance.show_cat,
        show_moon=appearance.show_moon,
        on_status=status_cb,
        on_search=search_cb,
        on_sort=sort_cb,
        on_settings=settings_cb,
        on_close=function() if menu then self:closeBookVault(menu) end end,
        on_selection_collections=function()
            if menu and menu._bookvault_selected then self:showCollectionsForFiles(menu, menu._bookvault_selected) end
        end,
        on_selection_move=function()
            if menu and menu._bookvault_selected then self:copyOrMoveBookSelection(menu, true) end
        end,
        on_selection_copy=function()
            if menu and menu._bookvault_selected then self:copyOrMoveBookSelection(menu, false) end
        end,
        on_selection_delete=function()
            if menu and menu._bookvault_selected then self:deleteBooks(menu._bookvault_selected, menu) end
        end,
        on_selection_more=function()
            if menu then self:showSelectionMore(menu) end
        end,
        on_selection_exit=function()
            if menu then self:leaveSelection(menu) end
        end,
    }

    menu=BookList:new{
        name=name,title=title,item_table=items,covers_fullscreen=true,
        custom_title_bar=header,
        onMenuSelect=function(_,item) self:guard(item.path,function()
            if lfs.attributes(item.path,"mode")~="file" then
                UIManager:show(InfoMessage:new{text=_("O arquivo não existe mais.")})
                return
            end
            ReaderUI:showReader(item.path)
        end) end,
    }
    self._last_menu=menu
    menu._bookvault_view_key=view_key or name
    menu._bookvault_source_items=self:applyCustomOrder(items,menu._bookvault_view_key)
    menu.item_table=copyItems(menu._bookvault_source_items)
    menu._bookvault_header=header
    self:loadSettings()
    local saved_sort=self.settings.data.sort_modes[menu._bookvault_view_key]
    local saved_directions=self.settings.data.sort_directions
    if saved_sort and saved_sort ~= "custom" and type(saved_directions)=="table" and type(saved_directions[menu._bookvault_view_key])=="table" then
        local sd=saved_directions[menu._bookvault_view_key][saved_sort]
        if sd=="asc" or sd=="desc" then menu._bookvault_saved_sort={mode=saved_sort,direction=sd} end
    end
    local ok_visual=self:prepareVisualMenu(menu,menu._bookvault_source_items)
    if not ok_visual then menu._bookvault_source_items=items; menu.item_table=items end
    return menu
end

function BookVault:showCollection(collection_name)
    safe(function()
        local items=self:collectionItems(collection_name,self.privacyIncludePrivate and self:privacyIncludePrivate() or self.unlocked)
        local menu=self:makeBookMenu("bookvault_collection_"..collection_name,_("BookVault").." · "..collection_name,items,"collection:"..collection_name)
        UIManager:show(menu)
        if menu._bookvault_visual then
            local old_no_refresh = menu.no_refresh_covers
            menu.no_refresh_covers = true
            pcall(menu.updateItems, menu, 1, true)
            menu.no_refresh_covers = old_no_refresh
        else
            pcall(menu.updateItems, menu)
        end
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
        for _,collection in ipairs(collections) do local checked=self:isCollectionVisible(collection.name); buttons[#buttons+1]={{text=(checked and "☑ " or "☐ ")..collection.name,callback=function() self.settings.data.visible_collections[collection.name]=not checked; self:saveSettings(); UIManager:close(self.collection_visibility_dialog); rebuild() end}} end
        buttons[#buttons+1]={{text=_("Concluído"),callback=function() UIManager:close(self.collection_visibility_dialog) end}}
        self.collection_visibility_dialog=ButtonDialog:new{title=_("Coleções exibidas"),title_align="center",buttons=buttons}; UIManager:show(self.collection_visibility_dialog)
    end
    rebuild()
end
function BookVault:showLibrary(status,include_private)
    safe(function()
        local by_status = self:getStatusIndex(include_private)
        local items = by_status[status] or by_status.all or {}
        self.settings.data.last_status=status
        local menu=self:makeBookMenu("bookvault_library_"..status,_("BookVault"),items,"status:"..status)
        if not menu then return end
        UIManager:show(menu)
        -- CoverMenu/MosaicMenu performs its own initial layout. Calling it twice
        -- here caused unnecessary cover work on first open.
        if menu._bookvault_visual then
            pcall(menu.updateItems, menu, 1, true)
        else
            pcall(menu.updateItems, menu)
        end
    end)
end
function BookVault:showStatusChooser()
    self:loadSettings()
    local first = self.settings.data.last_status or "all"
    if not self:isStatusVisible(first) then first = "all" end
    if not self:isStatusVisible(first) then
        for _, status in ipairs(STATUS) do
            if self:isStatusVisible(status.key) then first=status.key; break end
        end
    end
    self:showLibrary(first, self.privacyIncludePrivate and self:privacyIncludePrivate() or false)
end

function BookVault:showStatusVisibilityChooser()
    self:loadSettings()
    local function rebuild()
        local buttons={}; local visible=self.settings.data.visible_statuses
        for _,status in ipairs(STATUS) do local checked=visible[status.key]==true; buttons[#buttons+1]={{text=(checked and "☑ " or "☐ ")..status.label,callback=function()
            if visible[status.key] then local count=0; for _,item in ipairs(STATUS) do if visible[item.key] then count=count+1 end end; if count<=1 then UIManager:show(InfoMessage:new{text=_("Mantenha pelo menos uma categoria visível.")}); return end end
            visible[status.key]=not visible[status.key]; self:saveSettings(); UIManager:close(self.status_visibility_dialog); rebuild()
        end}} end
        buttons[#buttons+1]={{text=_("Concluído"),callback=function() UIManager:close(self.status_visibility_dialog) end}}
        self.status_visibility_dialog=ButtonDialog:new{title=_("Categorias exibidas"),title_align="center",buttons=buttons}; UIManager:show(self.status_visibility_dialog)
    end
    rebuild()
end
function BookVault:chooseRoot()
    self:loadSettings(); UIManager:show(PathChooser:new{path=self:getRoot() or G_reader_settings:readSetting("home_dir"),select_directory=true,select_file=false,onConfirm=function(path) if path then self.settings.data.root=normalize(path); self:invalidateLibraryCache(); self:saveSettings(); UIManager:show(InfoMessage:new{text=_("Pasta da biblioteca salva.")}) end end})
end
function BookVault:chooseManagedPath(private)
    self:loadSettings(); UIManager:show(PathChooser:new{path=self:getRoot() or G_reader_settings:readSetting("home_dir"),select_directory=true,select_file=false,onConfirm=function(path) if not path then return end; local list=private and self.settings.data.private_paths or self.settings.data.protected_paths; addUnique(list,path); self:invalidateLibraryCache(); self:saveSettings(); UIManager:show(InfoMessage:new{text=private and _("Pasta tornada privada.") or _("Pasta protegida.")}) end})
end
function BookVault:listManagedPaths(private)
    self:loadSettings(); local list=private and self.settings.data.private_paths or self.settings.data.protected_paths
    local function showList()
        local buttons={}
        for i,path in ipairs(list) do local idx=i; buttons[#buttons+1]={{text=path,callback=function() table.remove(list,idx); self:saveSettings(); UIManager:close(self.path_dialog); showList() end}} end
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
        {text=_("Biblioteca"),separator=true,sub_item_table={
            {text=_("Configurar pasta da biblioteca"),callback=function() self:chooseRoot() end},
            {text=_("Categorias exibidas"),callback=function() self:showStatusVisibilityChooser() end},
            {text=_("Coleções"),callback=function() self:showCollectionChooser() end},
            {text=_("Coleções exibidas"),callback=function() self:showCollectionVisibilityChooser() end},
        }},
        {text=_("Aparência"),separator=true,sub_item_table={
            {text=_("Personalizar aparência"),callback=function() self:showAppearanceSettings(self._last_menu) end},
        }},
        {text=_("Segurança"),separator=true,sub_item_table={
            {text=_("Criar/alterar senha"),callback=function() self:setPassword() end},
            {text=_("Proteger uma pasta"),callback=function() self:chooseManagedPath(false) end},
            {text=_("Gerenciar pastas protegidas"),callback=function() self:listManagedPaths(false) end},
        }},
        {text=_("Privacidade"),separator=true,sub_item_table={
            {text=_("Tornar uma pasta privada"),callback=function() self:chooseManagedPath(true) end},
            {text=_("Gerenciar conteúdo privado"),callback=function() self:listManagedPaths(true) end},
        }},
    }}
end
function BookVault:show() self:showStatusChooser() end
function BookVault:onSuspend()
    self.unlocked=false
end
function BookVault:onResume()
    self.unlocked=false
    self:invalidateStatusCache()
    self:invalidateBookMetadataCache()
end
function BookVault:init()
    -- Keep registration alive even if a non-essential UI component fails on
    -- a particular KOReader build.
    safe(function()
        self:loadSettings()
        self.ui.menu:registerToMainMenu(self)
    end)
end

-- Install BookVault actions explicitly on the BookVault class.
-- This is intentionally done after the class is fully defined and never by
-- replacing WidgetContainer.extend/BookList.new globally.
local ok_actions, actions = pcall(require, "bookvault_actions")
if ok_actions and actions and actions.install then
    local ok_install, err = pcall(actions.install, BookVault)
    if not ok_install then logger.err("BookVault action layer install failed", err) end
else
    logger.err("BookVault action layer unavailable", actions)
end

return BookVault
