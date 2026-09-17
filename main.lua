local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local BookInfoManager = require("bookinfomanager")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local sha2 = require("ffi/sha2")
local logger = require("logger")
local _ = require("gettext")

local BookVault = WidgetContainer:extend{
    name = "bookvault",
    fullname = _("BookVault"),
    is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/bookvault.lua",
    settings = nil,
    unlocked = false,
    security_patched = false,
}

local STATUS = {
    { key = "all", label = _("Todos") },
    { key = "reading", label = _("Lendo") },
    { key = "abandoned", label = _("Em espera") },
    { key = "complete", label = _("Concluídos") },
    { key = "new", label = _("Não iniciados") },
}

local function normalize(path)
    if not path then return nil end
    local real = ffiUtil.realpath(path)
    return (real or path):gsub("/+$", "")
end

local function contains(parent, child)
    parent, child = normalize(parent), normalize(child)
    return parent and child and (child == parent or child:sub(1, #parent + 1) == parent .. "/")
end

local function addUnique(list, value)
    value = normalize(value)
    if not value then return end
    for _, existing in ipairs(list) do
        if normalize(existing) == value then return end
    end
    list[#list + 1] = value
end

function BookVault:loadSettings()
    if self.settings then return end
    self.settings = LuaSettings:open(self.settings_file)
    self.settings.data.protected_paths = self.settings.data.protected_paths or {}
    self.settings.data.private_paths = self.settings.data.private_paths or {}
end

function BookVault:saveSettings()
    self:loadSettings()
    self.settings:flush()
end

function BookVault:getRoot()
    self:loadSettings()
    local root = self.settings.data.root
    if root and lfs.attributes(root, "mode") == "directory" then
        return normalize(root)
    end
end

function BookVault:hasPassword()
    self:loadSettings()
    return self.settings.data.password_hash ~= nil and self.settings.data.password_salt ~= nil
end

function BookVault:hashPassword(password, salt)
    return sha2.sha256(salt .. password)
end

function BookVault:verifyPassword(password)
    if not self:hasPassword() then return false end
    return self:hashPassword(password, self.settings.data.password_salt) == self.settings.data.password_hash
end

function BookVault:askPassword(callback, title)
    if not self:hasPassword() then
        callback(false)
        return
    end
    local dialog
    dialog = InputDialog:new{
        title = title or _("Senha do BookVault"),
        input = "",
        input_type = "number",
        text_type = "password",
        buttons = {{
            { text = _("Cancelar"), callback = function() UIManager:close(dialog) end },
            { text = _("OK"), is_enter_default = true, callback = function()
                local password = dialog:getInputText()
                UIManager:close(dialog)
                if self:verifyPassword(password) then
                    callback(true)
                else
                    UIManager:show(InfoMessage:new{ text = _("Senha incorreta.") })
                    callback(false)
                end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function BookVault:saveNewPassword(password)
    local salt = table.concat({ tostring(os.time()), tostring(math.random()), tostring(os.clock()) }, ":")
    self.settings.data.password_salt = salt
    self.settings.data.password_hash = self:hashPassword(password, salt)
    self:saveSettings()
end

function BookVault:setPassword(on_saved)
    local function create()
        local first
        first = InputDialog:new{
            title = self:hasPassword() and _("Nova senha numérica") or _("Criar senha numérica"),
            input = "",
            input_type = "number",
            text_type = "password",
            buttons = {{
                { text = _("Cancelar"), callback = function() UIManager:close(first) end },
                { text = _("Continuar"), is_enter_default = true, callback = function()
                    local password = first:getInputText()
                    UIManager:close(first)
                    if not password:match("^%d+$") or #password < 4 then
                        UIManager:show(InfoMessage:new{ text = _("Use pelo menos 4 dígitos.") })
                        return
                    end
                    local second
                    second = InputDialog:new{
                        title = _("Confirmar senha"),
                        input = "",
                        input_type = "number",
                        text_type = "password",
                        buttons = {{
                            { text = _("Cancelar"), callback = function() UIManager:close(second) end },
                            { text = _("Salvar"), is_enter_default = true, callback = function()
                                local confirmation = second:getInputText()
                                UIManager:close(second)
                                if confirmation ~= password then
                                    UIManager:show(InfoMessage:new{ text = _("As senhas não coincidem.") })
                                    return
                                end
                                self:saveNewPassword(password)
                                UIManager:show(InfoMessage:new{ text = _("Senha salva.") })
                                if on_saved then on_saved() end
                            end },
                        }},
                    }
                    UIManager:show(second)
                    second:onShowKeyboard()
                end },
            }},
        }
        UIManager:show(first)
        first:onShowKeyboard()
    end
    if self:hasPassword() then
        self:askPassword(function(ok) if ok then create() end end, _("Senha atual"))
    else
        create()
    end
end

function BookVault:isProtected(path)
    self:loadSettings()
    for _, p in ipairs(self.settings.data.protected_paths) do
        if contains(p, path) then return true end
    end
    return false
end

function BookVault:isPrivate(path)
    self:loadSettings()
    for _, p in ipairs(self.settings.data.private_paths) do
        if contains(p, path) then return true end
    end
    return false
end

function BookVault:needsUnlock(path)
    return self:isProtected(path) or self:isPrivate(path)
end

function BookVault:guard(path, callback)
    if not self:needsUnlock(path) or self.unlocked then
        callback()
        return
    end
    self:askPassword(function(ok)
        if ok then
            self.unlocked = true
            callback()
        end
    end)
end

function BookVault:scanBooks(include_private)
    local root = self:getRoot()
    if not root then return {} end
    local result, visited = {}, {}
    local pending = { root }
    local index = 1
    while index <= #pending do
        local dir = normalize(pending[index])
        index = index + 1
        if not visited[dir] then
            visited[dir] = true
            local ok, iter, dir_obj = pcall(lfs.dir, dir)
            if ok and iter and dir_obj then
                for name in iter, dir_obj do
                    if name ~= "." and name ~= ".." then
                        local path = dir .. "/" .. name
                        local attr = lfs.attributes(path)
                        if attr and attr.mode == "directory" then
                            if include_private or not self:isPrivate(path) then
                                pending[#pending + 1] = path
                            end
                        elseif attr and attr.mode == "file" then
                            if include_private or not self:isPrivate(path) then
                                local provider_ok, has_provider = pcall(DocumentRegistry.hasProvider, DocumentRegistry, path)
                                if provider_ok and has_provider then
                                    result[#result + 1] = {
                                        path = path,
                                        filepath = path,
                                        text = name,
                                        attr = attr,
                                        is_file = true,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.text:lower() < b.text:lower() end)
    return result
end

function BookVault:loadCoverBrowserModules()
    if self.cover_modules then return self.cover_modules end
    local old_path = package.path
    local plugin_dir = DataStorage:getDataDir() .. "/plugins/coverbrowser.koplugin"
    package.path = plugin_dir .. "/?.lua;" .. old_path
    local ok_cover, CoverMenu = pcall(require, "covermenu")
    local ok_mosaic, MosaicMenu = pcall(require, "mosaicmenu")
    package.path = old_path
    if ok_cover and ok_mosaic then
        self.cover_modules = { CoverMenu = CoverMenu, MosaicMenu = MosaicMenu }
    end
    return self.cover_modules
end

function BookVault:configureCoverMosaic(menu)
    local modules = self:loadCoverBrowserModules()
    if not modules then return false end
    menu.nb_cols_portrait = BookInfoManager:getSetting("nb_cols_portrait") or 3
    menu.nb_rows_portrait = BookInfoManager:getSetting("nb_rows_portrait") or 3
    menu.nb_cols_landscape = BookInfoManager:getSetting("nb_cols_landscape") or 4
    menu.nb_rows_landscape = BookInfoManager:getSetting("nb_rows_landscape") or 2
    menu.files_per_page = BookInfoManager:getSetting("files_per_page")
    menu.display_mode_type = "mosaic"
    menu._do_cover_images = true
    menu._do_center_partial_rows = true
    menu._do_hint_opened = true
    menu.getBookInfo = function(_, file)
        return BookInfoManager:getBookInfo(file)
    end
    menu.updateItems = modules.CoverMenu.updateItems
    menu.onCloseWidget = modules.CoverMenu.onCloseWidget
    menu._recalculateDimen = modules.MosaicMenu._recalculateDimen
    menu._updateItemsBuildUI = modules.MosaicMenu._updateItemsBuildUI
    return true
end

function BookVault:showStatusChooser()
    local buttons = {}
    for _, status in ipairs(STATUS) do
        buttons[#buttons + 1] = {{
            text = status.label,
            callback = function()
                UIManager:close(self.status_dialog)
                self:showLibrary(status.key, self.unlocked)
            end,
        }}
    end
    self.status_dialog = ButtonDialog:new{
        title = _("BookVault"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.status_dialog)
end

function BookVault:showLibrary(status, include_private)
    local items = {}
    for _, item in ipairs(self:scanBooks(include_private)) do
        if status == "all" or BookList.getBookStatus(item.path) == status then
            items[#items + 1] = item
        end
    end
    local menu
    menu = BookList:new{
        name = "bookvault",
        title = _("BookVault") .. " · " .. (function()
            for _, s in ipairs(STATUS) do if s.key == status then return s.label end end
            return _("Todos")
        end)(),
        item_table = items,
        covers_fullscreen = true,
        onMenuSelect = function(_, item)
            self:guard(item.path, function()
                local filemanager = require("apps/filemanager/filemanager")
                local fm = filemanager.instance
                if fm then
                    fm:openFile(item.path)
                else
                    local reader = require("apps/reader/readerui").instance
                    if reader and reader.showFileManager then
                        reader:showFileManager(item.path)
                    end
                end
            end)
        end,
    }
    if not self:configureCoverMosaic(menu) then
        menu.covers_fullscreen = true
    end
    UIManager:show(menu)
    menu:updateItems()
end

function BookVault:chooseRoot()
    self:loadSettings()
    UIManager:show(PathChooser:new{
        path = self:getRoot() or G_reader_settings:readSetting("home_dir"),
        select_directory = true,
        select_file = false,
        onConfirm = function(path)
            self.settings.data.root = normalize(path)
            self:saveSettings()
            UIManager:show(InfoMessage:new{ text = _("Pasta da biblioteca salva.") })
        end,
    })
end

function BookVault:chooseManagedPath(private)
    self:loadSettings()
    UIManager:show(PathChooser:new{
        path = self:getRoot() or G_reader_settings:readSetting("home_dir"),
        select_directory = true,
        select_file = false,
        onConfirm = function(path)
            local list = private and self.settings.data.private_paths or self.settings.data.protected_paths
            addUnique(list, path)
            self:saveSettings()
            UIManager:show(InfoMessage:new{
                text = private and _("Pasta tornada privada.") or _("Pasta protegida."),
            })
        end,
    })
end

function BookVault:listManagedPaths(private)
    self:loadSettings()
    local list = private and self.settings.data.private_paths or self.settings.data.protected_paths
    local function showList()
        local buttons = {}
        for i, path in ipairs(list) do
            buttons[#buttons + 1] = {{
                text = path,
                callback = function()
                    table.remove(list, i)
                    self:saveSettings()
                    UIManager:close(self.path_dialog)
                    showList()
                end,
            }}
        end
        buttons[#buttons + 1] = {{ text = _("Cancelar"), callback = function() UIManager:close(self.path_dialog) end }}
        self.path_dialog = ButtonDialog:new{
            title = private and _("Conteúdo privado") or _("Pastas protegidas"),
            buttons = buttons,
        }
        UIManager:show(self.path_dialog)
    end
    if self:hasPassword() then
        self:askPassword(function(ok) if ok then showList() end end, _("Senha do BookVault"))
    else
        showList()
    end
end

function BookVault:togglePrivate()
    if self.unlocked then
        self.unlocked = false
        self:showStatusChooser()
        return
    end
    if not self:hasPassword() then
        self:setPassword(function()
            self.unlocked = true
            self:showStatusChooser()
        end)
        return
    end
    self:askPassword(function(ok)
        if ok then
            self.unlocked = true
            self:showStatusChooser()
        end
    end, _("Revelar conteúdo"))
end

function BookVault:patchSecurity()
    if self.security_patched then return end
    local ok, err = pcall(function()
        local FileChooser = require("ui/widget/filechooser")
        local FileManager = require("apps/filemanager/filemanager")
        local ReaderUI = require("apps/reader/readerui")

        local original_changeToPath = FileChooser.changeToPath
        FileChooser.changeToPath = function(chooser, path, focused_path)
            if self:isProtected(chooser.path) and not self:isProtected(path) then
                self.unlocked = false
            end
            if self:needsUnlock(path) and not self.unlocked then
                self:guard(path, function()
                    original_changeToPath(chooser, path, focused_path)
                end)
                return
            end
            return original_changeToPath(chooser, path, focused_path)
        end

        local original_genItemTableFromPath = FileChooser.genItemTableFromPath
        FileChooser.genItemTableFromPath = function(chooser, path)
            local items = original_genItemTableFromPath(chooser, path)
            if chooser.is_fm and not self.unlocked then
                local filtered = {}
                for _, item in ipairs(items) do
                    if not self:isPrivate(item.path) then
                        filtered[#filtered + 1] = item
                    end
                end
                return filtered
            end
            return items
        end

        local original_setupLayout = FileManager.setupLayout
        FileManager.setupLayout = function(filemanager, ...)
            local result = original_setupLayout(filemanager, ...)
            local chooser = filemanager.file_chooser
            if chooser and not chooser._bookvault_hold_patched then
                local original_onFileHold = chooser.onFileHold
                chooser.onFileHold = function(current_chooser, item)
                    if self:needsUnlock(item.path) and not self.unlocked then
                        self:guard(item.path, function() original_onFileHold(current_chooser, item) end)
                        return true
                    end
                    return original_onFileHold(current_chooser, item)
                end
                chooser._bookvault_hold_patched = true
            end
            return result
        end

        local original_openFile = FileManager.openFile
        FileManager.openFile = function(filemanager, file, provider, doc_caller_callback, aux_caller_callback, after_open_callback)
            if self:needsUnlock(file) and not self.unlocked then
                self:guard(file, function()
                    original_openFile(filemanager, file, provider, doc_caller_callback, aux_caller_callback, after_open_callback)
                end)
                return
            end
            return original_openFile(filemanager, file, provider, doc_caller_callback, aux_caller_callback, after_open_callback)
        end

        local original_showReader = ReaderUI.showReader
        ReaderUI.showReader = function(reader, file, provider, seamless, is_provider_forced, after_open_callback)
            if self:needsUnlock(file) and not self.unlocked then
                self:guard(file, function()
                    original_showReader(reader, file, provider, seamless, is_provider_forced, after_open_callback)
                end)
                return
            end
            return original_showReader(reader, file, provider, seamless, is_provider_forced, after_open_callback)
        end

        self.security_patched = true
    end)
    if not ok then
        logger.err("BookVault: security patch failed:", err)
    end
end

function BookVault:addToMainMenu(menu_items)
    menu_items.bookvault = {
        text = _("BookVault"),
        sorting_hint = "more_tools",
        sub_item_table = {
            { text = _("Abrir biblioteca"), callback = function() self:showStatusChooser() end },
            {
                text_func = function()
                    return self.unlocked and "◉ " .. _("Ocultar conteúdo") or "◉ " .. _("Revelar conteúdo")
                end,
                callback = function() self:togglePrivate() end,
            },
            {
                text = _("Biblioteca"),
                separator = true,
                sub_item_table = {
                    { text = _("Configurar pasta da biblioteca"), callback = function() self:chooseRoot() end },
                },
            },
            {
                text = _("Segurança"),
                separator = true,
                sub_item_table = {
                    { text = _("Criar/alterar senha"), callback = function() self:setPassword() end },
                    { text = _("Proteger uma pasta"), callback = function() self:chooseManagedPath(false) end },
                    { text = _("Gerenciar pastas protegidas"), callback = function() self:listManagedPaths(false) end },
                },
            },
            {
                text = _("Privacidade"),
                separator = true,
                sub_item_table = {
                    { text = _("Tornar uma pasta privada"), callback = function() self:chooseManagedPath(true) end },
                    { text = _("Gerenciar conteúdo privado"), callback = function() self:listManagedPaths(true) end },
                },
            },
        },
    }
end

function BookVault:onDispatcherRegisterActions()
    Dispatcher:registerAction(self.name, {
        category = "none",
        event = "BookVaultOpen",
        title = self.fullname,
        general = true,
    })
end

function BookVault:OpenBookVault()
    self:showStatusChooser()
end

function BookVault:onEvent(event)
    if event and event.name == "BookVaultOpen" then
        self:showStatusChooser()
        return true
    end
end

function BookVault:onSuspend()
    self.unlocked = false
end

function BookVault:onResume()
    self.unlocked = false
end

function BookVault:init()
    self:onDispatcherRegisterActions()
    self:loadSettings()
    self.ui.menu:registerToMainMenu(self)
    UIManager:nextTick(function() self:patchSecurity() end)
end

return BookVault
