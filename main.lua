local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local FileChooser = require("ui/widget/filechooser")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local sha2 = require("ffi/sha2")
local _ = require("gettext")

local BookVault = WidgetContainer:extend{
    name = "bookvault",
    fullname = _("BookVault"),
    is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/bookvault.lua",
    settings = nil,
    unlocked = false,
}

local STATUS = {
    { key = "all", label = _("Todos") },
    { key = "reading", label = _("Lendo") },
    { key = "abandoned", label = _("Em espera") },
    { key = "complete", label = _("Concluídos") },
    { key = "new", label = _("Não iniciados") },
}

local BOOK_EXTENSIONS = {
    epub=true, epub3=true, mobi=true, azw=true, azw3=true, pdf=true,
    djvu=true, djv=true, cbz=true, cbr=true, cbt=true, fb2=true, fbz=true,
    txt=true, html=true, htm=true, rtf=true, doc=true, docx=true, chm=true,
    xps=true,
}

local original_changeToPath
local original_openFile
local patches_installed = false

local function normalize(path)
    if not path then return nil end
    local real = ffiUtil.realpath(path)
    return (real or path):gsub("/+$", "")
end

local function contains(parent, child)
    parent, child = normalize(parent), normalize(child)
    return parent and child and (child == parent or child:sub(1, #parent + 1) == parent .. "/")
end

local function extension(path)
    return ((path:match("([^/]+)$") or path):match("%.([^%.]+)$") or ""):lower()
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
    if self.settings then self.settings:flush() end
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

function BookVault:setPassword()
    local begin = function()
        local first
        first = InputDialog:new{
            title = self:hasPassword() and _("Nova senha numérica") or _("Criar senha numérica"),
            input = "", input_type = "number", text_type = "password",
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
                        title = _("Confirmar senha"), input = "", input_type = "number", text_type = "password",
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
        self:askPassword(function(ok) if ok then begin() end end, _("Senha atual"))
    else
        begin()
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
        return true
    end
    self:askPassword(function(ok)
        if ok then
            self.unlocked = true
            callback()
        end
    end)
    return false
end

function BookVault:installPatches()
    if patches_installed then return end
    patches_installed = true

    original_changeToPath = FileChooser.changeToPath
    FileChooser.changeToPath = function(chooser, path, focused_path, ...)
        local old_path = chooser.path
        if old_path and self:needsUnlock(old_path) and not contains(old_path, path) then
            self.unlocked = false
        end
        if not self:needsUnlock(path) or self.unlocked then
            return original_changeToPath(chooser, path, focused_path, ...)
        end
        self:askPassword(function(ok)
            if ok then
                self.unlocked = true
                original_changeToPath(chooser, path, focused_path, ...)
            end
        end)
    end

    -- FileManager routes normal book opening through this helper. Wrapping it
    -- gives BookVault the same password gate for files opened from the browser,
    -- search/history and other standard FileManager entry points.
    original_openFile = filemanagerutil.openFile
    filemanagerutil.openFile = function(ui, file, caller_pre_callback, no_dialog, after_open_callback, ...)
        if not self:needsUnlock(file) or self.unlocked then
            return original_openFile(ui, file, caller_pre_callback, no_dialog, after_open_callback, ...)
        end
        self:askPassword(function(ok)
            if ok then
                self.unlocked = true
                original_openFile(ui, file, caller_pre_callback, no_dialog, after_open_callback, ...)
            end
        end)
    end
end

function BookVault:onSuspend()
    self.unlocked = false
end

function BookVault:onResume()
    self.unlocked = false
end

function BookVault:scanBooks(include_private)
    local root = self:getRoot()
    if not root then return {} end
    local result, visited = {}, {}

    local function scan(dir)
        dir = normalize(dir)
        if visited[dir] then return end
        visited[dir] = true
        local ok, iter, dir_obj = pcall(lfs.dir, dir)
        if not ok or not iter or not dir_obj then return end
        for name in iter, dir_obj do
            if name ~= "." and name ~= ".." then
                local path = dir .. "/" .. name
                local attr = lfs.attributes(path)
                if attr and attr.mode == "directory" then
                    if include_private or not self:isPrivate(path) then scan(path) end
                elseif attr and attr.mode == "file"
                    and BOOK_EXTENSIONS[extension(path)]
                    and DocumentRegistry:hasProvider(path)
                    and (include_private or not self:isPrivate(path)) then
                    result[#result + 1] = { path = path, filepath = path, text = name, attr = attr }
                end
            end
        end
    end

    scan(root)
    table.sort(result, function(a, b) return a.text:lower() < b.text:lower() end)
    return result
end

function BookVault:loadCoverBrowserModules()
    -- PluginLoader adds every loaded plugin directory to package.path. Keep a
    -- fallback for KOReader variants where CoverBrowser is not yet on it.
    local old_path = package.path
    local data = DataStorage:getDataDir()
    package.path = data .. "/plugins/coverbrowser.koplugin/?.lua;" .. old_path
    local ok1, bim = pcall(require, "bookinfomanager")
    local ok2, cm = pcall(require, "covermenu")
    local ok3, mm = pcall(require, "mosaicmenu")
    package.path = old_path
    if ok1 and ok2 and ok3 then return bim, cm, mm end
end

function BookVault:showStatusChooser()
    local buttons = {}
    for _, status in ipairs(STATUS) do
        buttons[#buttons + 1] = {
            text = status.label,
            callback = function()
                UIManager:close(self.status_dialog)
                self:showLibrary(status.key, self.unlocked)
            end,
        }
    end
    self.status_dialog = ButtonDialog:new{ title = _("BookVault"), buttons = buttons }
    UIManager:show(self.status_dialog)
end

function BookVault:showLibrary(status, include_private)
    local items = {}
    for _, item in ipairs(self:scanBooks(include_private)) do
        if status == "all" or BookList.getBookStatus(item.path) == status then
            items[#items + 1] = item
        end
    end

    local BookInfoManager, CoverMenu, MosaicMenu = self:loadCoverBrowserModules()
    local menu
    menu = BookList:new{
        title = _("BookVault"),
        item_table = items,
        covers_fullscreen = true,
        onMenuSelect = function(_, item)
            self:guard(item.path, function()
                local fm = require("apps/filemanager/filemanager").instance
                if fm then fm:openFile(item.path) end
            end)
        end,
        onLeftButtonTap = function()
            UIManager:close(menu)
            self:showStatusChooser()
        end,
    }

    if BookInfoManager and CoverMenu and MosaicMenu then
        BookInfoManager:openDbConnection()
        menu.nb_cols_portrait = BookInfoManager:getSetting("nb_cols_portrait") or 3
        menu.nb_rows_portrait = BookInfoManager:getSetting("nb_rows_portrait") or 3
        menu.nb_cols_landscape = BookInfoManager:getSetting("nb_cols_landscape") or 4
        menu.nb_rows_landscape = BookInfoManager:getSetting("nb_rows_landscape") or 2
        menu.files_per_page = BookInfoManager:getSetting("files_per_page")
        menu.display_mode_type = "mosaic"
        menu._do_cover_images = true
        menu._do_center_partial_rows = true
        menu._do_hint_opened = true
        menu.getBookInfo = function(_, file) return BookInfoManager:getBookInfo(file) end
        menu.getDocProps = function(_, file) return BookInfoManager:getDocProps(file) end
        menu.updateItems = CoverMenu.updateItems
        menu.onCloseWidget = CoverMenu.onCloseWidget
        menu._recalculateDimen = MosaicMenu._recalculateDimen
        menu._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
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

function BookVault:chooseManagedPath(is_private)
    self:loadSettings()
    UIManager:show(PathChooser:new{
        path = self:getRoot() or G_reader_settings:readSetting("home_dir"),
        select_directory = true,
        select_file = false,
        onConfirm = function(path)
            local list = is_private and self.settings.data.private_paths or self.settings.data.protected_paths
            addUnique(list, path)
            self:saveSettings()
            UIManager:show(InfoMessage:new{
                text = is_private and _("Pasta adicionada ao conteúdo privado.") or _("Pasta protegida."),
            })
        end,
    })
end

function BookVault:listManagedPaths(is_private)
    self:loadSettings()
    local list = is_private and self.settings.data.private_paths or self.settings.data.protected_paths
    local function showList()
        local buttons = {}
        for i, path in ipairs(list) do
            buttons[#buttons + 1] = {
                text = path,
                callback = function()
                    table.remove(list, i)
                    self:saveSettings()
                    UIManager:close(self.path_dialog)
                    showList()
                end,
            }
        end
        buttons[#buttons + 1] = { text = _("Cancelar"), callback = function() UIManager:close(self.path_dialog) end }
        self.path_dialog = ButtonDialog:new{
            title = is_private and _("Conteúdo privado") or _("Pastas protegidas"),
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

function BookVault:addToMainMenu(menu_items)
    menu_items.bookvault = {
        text = _("BookVault"),
        sub_item_table = {
            { text = _("Abrir biblioteca"), callback = function() self:showStatusChooser() end },
            {
                text_func = function()
                    return self.unlocked and "◉ " .. _("Ocultar conteúdo") or "◉ " .. _("Acessar conteúdo")
                end,
                callback = function()
                    if self.unlocked then
                        self.unlocked = false
                        self:showStatusChooser()
                    elseif not self:hasPassword() then
                        self:setPassword()
                    else
                        self:askPassword(function(ok)
                            if ok then
                                self.unlocked = true
                                self:showStatusChooser()
                            end
                        end, _("Acessar conteúdo privado"))
                    end
                end,
            },
            { text = _("Configurar pasta da biblioteca"), callback = function() self:chooseRoot() end },
            { text = _("Criar/alterar senha"), callback = function() self:setPassword() end },
            { text = _("Proteger uma pasta"), callback = function() self:chooseManagedPath(false) end },
            { text = _("Gerenciar pastas protegidas"), callback = function() self:listManagedPaths(false) end },
            { text = _("Adicionar pasta ao conteúdo privado"), callback = function() self:chooseManagedPath(true) end },
            { text = _("Gerenciar conteúdo privado"), callback = function() self:listManagedPaths(true) end },
        },
    }
end

function BookVault:onDispatcherRegisterActions()
    Dispatcher:registerAction("bookvault_open", {
        category = "none", event = "BookVaultOpen", title = _("BookVault: Abrir biblioteca"),
        general = true, separator = false,
    })
end

function BookVault:init()
    -- Do not scan books or load cover data during plugin initialization.
    -- This keeps AppStore/plugin loading lightweight and prevents one bad
    -- library entry from making the plugin disappear from Tools.
    self:loadSettings()
    self:installPatches()
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function BookVault:onBookVaultOpen()
    self:showStatusChooser()
end

return BookVault
