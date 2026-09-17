local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local FileChooser = require("ui/widget/filechooser")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
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
    private_unlocked = false,
}

local STATUS = {
    { key = "all", label = _("Todos") },
    { key = "reading", label = _("Lendo") },
    { key = "abandoned", label = _("Em espera") },
    { key = "complete", label = _("Concluídos") },
    { key = "new", label = _("Não iniciados") },
}

local BOOK_EXTENSIONS = {
    epub = true, mobi = true, azw = true, azw3 = true, pdf = true,
    djvu = true, djv = true, cbz = true, cbr = true, cbt = true,
    fb2 = true, fbz = true, txt = true, html = true, htm = true,
    rtf = true, doc = true, docx = true, chm = true, xps = true,
}

local original_changeToPath
local original_openFile
local patches_installed = false

local function normalize(path)
    local real = ffiUtil.realpath(path)
    if real then
        return real:gsub("/+$", "")
    end
    return path and path:gsub("/+$", "") or path
end

local function contains(parent, child)
    parent, child = normalize(parent), normalize(child)
    if not parent or not child then return false end
    return child == parent or child:sub(1, #parent + 1) == parent .. "/"
end

local function extension(path)
    local name = path:match("([^/]+)$") or path
    return (name:match("%.([^%.]+)$") or ""):lower()
end

local function unique_insert(list, value)
    for _, v in ipairs(list) do
        if normalize(v) == normalize(value) then return end
    end
    table.insert(list, value)
end

function BookVault:loadSettings()
    if self.settings then return end
    self.settings = LuaSettings:open(self.settings_file)
    self.settings.data.protected_paths = self.settings.data.protected_paths or {}
    self.settings.data.private_paths = self.settings.data.private_paths or {}
    self.settings.data.root = self.settings.data.root
end

function BookVault:saveSettings()
    if self.settings then self.settings:flush() end
end

function BookVault:getRoot()
    self:loadSettings()
    local root = self.settings.data.root
    if root and lfs.attributes(root, "mode") == "directory" then
        return normalize(root)
    end
    return nil
end

function BookVault:hasPassword()
    self:loadSettings()
    return self.settings.data.password_hash ~= nil and self.settings.data.password_salt ~= nil
end

function BookVault:hashPassword(password, salt)
    local ok, result = pcall(function()
        return sha2.sha256(salt .. password)
    end)
    if ok and result then return result end
    return sha2.sha1(salt .. password)
end

function BookVault:verifyPassword(password)
    self:loadSettings()
    if not self:hasPassword() then return false end
    return self:hashPassword(password, self.settings.data.password_salt) == self.settings.data.password_hash
end

function BookVault:askPassword(callback, title)
    self:loadSettings()
    if not self:hasPassword() then
        callback(true)
        return
    end
    local dialog
    dialog = InputDialog:new{
        title = title or _("Senha do BookVault"),
        input = "",
        input_type = "number",
        text_type = "password",
        buttons = {
            {
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
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function BookVault:setPassword()
    self:loadSettings()
    local first
    first = InputDialog:new{
        title = _("Criar senha numérica"),
        input = "",
        input_type = "number",
        text_type = "password",
        buttons = {
            {
                { text = _("Cancelar"), callback = function() UIManager:close(first) end },
                { text = _("Continuar"), is_enter_default = true, callback = function()
                    local password = first:getInputText()
                    UIManager:close(first)
                    if not password or not password:match("^%d+$") or #password < 4 then
                        UIManager:show(InfoMessage:new{ text = _("Use pelo menos 4 dígitos.") })
                        return
                    end
                    local second
                    second = InputDialog:new{
                        title = _("Confirmar senha"),
                        input = "",
                        input_type = "number",
                        text_type = "password",
                        buttons = {
                            {
                                { text = _("Cancelar"), callback = function() UIManager:close(second) end },
                                { text = _("Salvar"), is_enter_default = true, callback = function()
                                    local confirmation = second:getInputText()
                                    UIManager:close(second)
                                    if confirmation ~= password then
                                        UIManager:show(InfoMessage:new{ text = _("As senhas não coincidem.") })
                                        return
                                    end
                                    local salt = tostring(os.time()) .. tostring(math.random()) .. tostring(password):reverse()
                                    self.settings.data.password_salt = salt
                                    self.settings.data.password_hash = self:hashPassword(password, salt)
                                    self:saveSettings()
                                    UIManager:show(InfoMessage:new{ text = _("Senha salva.") })
                                end },
                            },
                        },
                    }
                    UIManager:show(second)
                    second:onShowKeyboard()
                end },
            },
        },
    }
    UIManager:show(first)
    first:onShowKeyboard()
end

function BookVault:checkProtected(path)
    self:loadSettings()
    for _, protected in ipairs(self.settings.data.protected_paths) do
        if contains(protected, path) then
            return true
        end
    end
    return false
end

function BookVault:isPrivate(path)
    self:loadSettings()
    for _, private in ipairs(self.settings.data.private_paths) do
        if contains(private, path) then
            return true
        end
    end
    return false
end

function BookVault:isAccessible(path)
    if not self:isPrivate(path) and not self:checkProtected(path) then return true end
    return self.private_unlocked
end

function BookVault:unlockPrivate()
    if not self:hasPassword() then
        self:setPassword()
        return
    end
    self:askPassword(function(ok)
        if ok then
            self.private_unlocked = true
            self:showLibrary("all", true)
        end
    end, _("Acessar conteúdo privado"))
end

function BookVault:hidePrivate()
    self.private_unlocked = false
    self:showLibrary("all", false)
end

function BookVault:guardPath(path, proceed)
    if not self:checkProtected(path) and not self:isPrivate(path) then
        proceed()
        return true
    end
    if self.private_unlocked then
        proceed()
        return true
    end
    self:askPassword(function(ok)
        if ok then
            self.private_unlocked = true
            proceed()
        end
    end)
    return false
end

function BookVault:installPatches()
    if patches_installed then return end
    patches_installed = true

    original_changeToPath = FileChooser.changeToPath
    FileChooser.changeToPath = function(chooser, path, focused_path, ...)
        if self:checkProtected(path) or self:isPrivate(path) then
            if self.private_unlocked then
                return original_changeToPath(chooser, path, focused_path, ...)
            end
            self:askPassword(function(ok)
                if ok then
                    self.private_unlocked = true
                    original_changeToPath(chooser, path, focused_path, ...)
                end
            end)
            return
        end
        return original_changeToPath(chooser, path, focused_path, ...)
    end

    original_openFile = FileManager.openFile
    FileManager.openFile = function(manager, file, ...)
        if self:checkProtected(file) or self:isPrivate(file) then
            if self.private_unlocked then
                return original_openFile(manager, file, ...)
            end
            self:askPassword(function(ok)
                if ok then
                    self.private_unlocked = true
                    original_openFile(manager, file, ...)
                end
            end)
            return
        end
        return original_openFile(manager, file, ...)
    end
end

function BookVault:onSuspend()
    self.private_unlocked = false
end

function BookVault:onResume()
    self.private_unlocked = false
end

function BookVault:scanBooks(include_private)
    local root = self:getRoot()
    if not root then return {} end
    local result = {}
    local visited = {}

    local function scan(dir)
        dir = normalize(dir)
        if visited[dir] then return end
        visited[dir] = true
        if not include_private and not self:isAccessible(dir) then return end

        local good, iter, dir_obj = pcall(lfs.dir, dir)
        if not good or not iter or not dir_obj then return end
        for name in iter, dir_obj do
            if name ~= "." and name ~= ".." then
                local path = dir .. "/" .. name
                local attr = lfs.attributes(path)
                if attr then
                    if attr.mode == "directory" then
                        if include_private or self:isAccessible(path) then
                            scan(path)
                        end
                    elseif attr.mode == "file" then
                        if BOOK_EXTENSIONS[extension(path)] and DocumentRegistry:hasProvider(path) then
                            if include_private or self:isAccessible(path) then
                                table.insert(result, { path = path, text = name, attr = attr })
                            end
                        end
                    end
                end
            end
        end
    end

    scan(root)
    table.sort(result, function(a, b) return a.text:lower() < b.text:lower() end)
    return result
end

function BookVault:showStatusChooser()
    local buttons = {}
    for _, status in ipairs(STATUS) do
        table.insert(buttons, {
            text = status.label,
            callback = function()
                UIManager:close(self.status_dialog)
                self:showLibrary(status.key, self.private_unlocked)
            end,
        })
    end
    self.status_dialog = ButtonDialog:new{
        title = _("BookVault"),
        buttons = buttons,
    }
    UIManager:show(self.status_dialog)
end

function BookVault:showLibrary(status, include_private)
    local items = self:scanBooks(include_private)
    local filtered = {}
    for _, item in ipairs(items) do
        local book_status = BookList.getBookStatus(item.path)
        if status == "all" or book_status == status then
            table.insert(filtered, item)
        end
    end

    local BookInfoManager = select(2, pcall(require, "bookinfomanager"))
    local CoverMenu = select(2, pcall(require, "covermenu"))
    local MosaicMenu = select(2, pcall(require, "mosaicmenu"))

    local menu
    menu = BookList:new{
        title = _("BookVault"),
        item_table = filtered,
        covers_fullscreen = true,
        onMenuSelect = function(self_menu, item)
            self:guardPath(item.path, function()
                if self.ui and self.ui.openFile then
                    self.ui:openFile(item.path)
                else
                    local FileManagerInstance = require("apps/filemanager/filemanager").instance
                    if FileManagerInstance then FileManagerInstance:openFile(item.path) end
                end
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
    local chooser = PathChooser:new{
        path = self:getRoot() or G_reader_settings:readSetting("home_dir"),
        select_directory = true,
        select_file = false,
        onConfirm = function(path)
            self.settings.data.root = normalize(path)
            self:saveSettings()
            self:showLibrary("all", false)
        end,
    }
    UIManager:show(chooser)
end

function BookVault:chooseProtectedPath(is_private)
    self:loadSettings()
    local chooser = PathChooser:new{
        path = self:getRoot() or G_reader_settings:readSetting("home_dir"),
        select_directory = true,
        select_file = false,
        onConfirm = function(path)
            path = normalize(path)
            local list = is_private and self.settings.data.private_paths or self.settings.data.protected_paths
            unique_insert(list, path)
            self:saveSettings()
            UIManager:show(InfoMessage:new{ text = is_private and _("Pasta adicionada ao conteúdo privado.") or _("Pasta protegida.") })
        end,
    }
    UIManager:show(chooser)
end

function BookVault:listManagedPaths(is_private)
    self:loadSettings()
    local list = is_private and self.settings.data.private_paths or self.settings.data.protected_paths
    local buttons = {}
    for i, path in ipairs(list) do
        buttons[#buttons + 1] = {
            text = path,
            callback = function()
                table.remove(list, i)
                self:saveSettings()
                UIManager:close(self.path_dialog)
                self:listManagedPaths(is_private)
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

function BookVault:addToMainMenu(menu_items)
    menu_items.bookvault = {
        text = _("BookVault"),
        sub_item_table = {
            {
                text = _("Abrir biblioteca"),
                callback = function() self:showStatusChooser() end,
            },
            {
                text_func = function()
                    return self.private_unlocked and "◉ " .. _("Ocultar conteúdo") or "◉ " .. _("Acessar conteúdo")
                end,
                callback = function()
                    if self.private_unlocked then self:hidePrivate() else self:unlockPrivate() end
                end,
            },
            {
                text = _("Configurar pasta da biblioteca"),
                callback = function() self:chooseRoot() end,
            },
            {
                text = _("Criar/alterar senha"),
                callback = function() self:setPassword() end,
            },
            {
                text = _("Proteger uma pasta"),
                callback = function() self:chooseProtectedPath(false) end,
            },
            {
                text = _("Gerenciar pastas protegidas"),
                callback = function() self:listManagedPaths(false) end,
            },
            {
                text = _("Adicionar pasta ao conteúdo privado"),
                callback = function() self:chooseProtectedPath(true) end,
            },
            {
                text = _("Gerenciar conteúdo privado"),
                callback = function() self:listManagedPaths(true) end,
            },
        },
    }
end

function BookVault:onDispatcherRegisterActions()
    Dispatcher:registerAction("bookvault_open", {
        category = "none",
        event = "BookVaultOpen",
        title = _("BookVault: Abrir biblioteca"),
        general = true,
        separator = false,
    })
end

function BookVault:init()
    self:loadSettings()
    self:installPatches()
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function BookVault:onBookVaultOpen()
    self:showStatusChooser()
end

return BookVault
