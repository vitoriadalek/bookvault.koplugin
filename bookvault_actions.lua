-- BookVault 3.x action and interaction layer.
-- Kept scoped to BookVault-created menus: no global KOReader monkey patches.

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local BookList = require("ui/widget/booklist")
local DocSettings = require("docsettings")
local ReadCollection = require("readcollection")
local DataStorage = require("datastorage")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local ReaderUI = require("apps/reader/readerui")
local _ = require("gettext")
local logger = require("logger")
local T = ffiUtil.template
local N_ = _.ngettext

local M = {}

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function basename(path)
    return ffiUtil.basename(path) or path or ""
end

local function safe(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        logger.err("BookVault:", err)
        UIManager:show(InfoMessage:new{
            text = _("BookVault encontrou um erro e não conseguiu concluir a ação."),
        })
    end
    return ok
end

local function refresh(menu)
    if not menu then return end
    pcall(function()
        if menu.updateItems then menu:updateItems(1, true) end
    end)
end

local function closeIf(widget)
    if widget then pcall(UIManager.close, UIManager, widget) end
end

local function selectedList(selected)
    local list = {}
    for path in pairs(selected or {}) do list[#list + 1] = path end
    table.sort(list)
    return list
end

local function getBookInfo(file)
    local ok, info = pcall(BookList.getBookInfo, file)
    return ok and info or {}
end

local function getProps(owner, file)
    if owner and owner.ui and owner.ui.bookinfo and owner.ui.bookinfo.getDocProps then
        local ok, props = pcall(owner.ui.bookinfo.getDocProps, owner.ui.bookinfo, file)
        if ok and type(props) == "table" then return props end
    end
    return {}
end

local function hasCover(owner, file)
    local props = getProps(owner, file)
    if props.has_cover ~= nil then return props.has_cover end
    local ok, custom = pcall(DocSettings.findCustomCoverFile, file)
    if ok and custom then return true end
    return false
end

function M.install(BV)
    if BV._bookvault_actions_installed then return end
    BV._bookvault_actions_installed = true

    -- Privacy is deliberately independent from folder protection.
    local oldLoad = BV.loadSettings
    BV.loadSettings = function(self, ...)
        oldLoad(self, ...)
        local d = self.settings.data
        if d.privacy_enabled == nil then d.privacy_enabled = true end
        d.protected_paths = d.protected_paths or {}
        d.private_paths = d.private_paths or {}
    end

    function BV:isPrivacyOn()
        self:loadSettings()
        return self.settings.data.privacy_enabled ~= false
    end

    function BV:privacyIncludePrivate()
        return not self:isPrivacyOn() and self.unlocked
    end

    function BV:setPrivacy(on, reveal)
        self:loadSettings()
        self.settings.data.privacy_enabled = on and true or false
        self.unlocked = reveal and true or false
        self:saveSettings()
    end

    function BV:togglePrivacy()
        if self:isPrivacyOn() then
            local reveal = function(ok)
                if ok then
                    self:setPrivacy(false, true)
                    self:showStatusChooser()
                end
            end
            if self:hasPassword() then
                self:askPassword(reveal, _("Revelar conteúdo privado"))
            else
                self:setPassword(function()
                    self:askPassword(reveal, _("Revelar conteúdo privado"))
                end)
            end
        else
            self:setPrivacy(true, false)
            self:showStatusChooser()
        end
    end

    -- Open the native KOReader Book Information screen from BookVault.
    -- This preserves native metadata editing (hold a metadata row), progress,
    -- cover handling and compatibility across KOReader versions.
    function BV:showBookInfo(item)
        if not item or not item.path then return end
        local ui = self.ui or ReaderUI.instance
        if ui and ui.bookinfo and ui.bookinfo.show then
            local file = item.path
            safe(function()
                local props = ui.bookinfo:getDocProps(file)
                ui.bookinfo:show(file, ui.bookinfo.extendProps(props, file))
            end)
            return
        end
        UIManager:show(InfoMessage:new{ text = _("As informações do livro não estão disponíveis nesta tela.") })
    end

    local function collectionNames()
        local names = {}
        for name in pairs(ReadCollection.coll or {}) do
            if type(name) == "string" then names[#names + 1] = name end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        return names
    end

    local function createCollection(owner, callback)
        local dialog
        dialog = InputDialog:new{
            title = _("Nova coleção"),
            input = "",
            buttons = {{
                { text = _("Cancelar"), callback = function() closeIf(dialog) end },
                { text = _("Criar"), is_enter_default = true, callback = function()
                    local name = (dialog:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    closeIf(dialog)
                    if name == "" then return end
                    if ReadCollection.coll[name] then
                        UIManager:show(InfoMessage:new{ text = _("Essa coleção já existe.") })
                        return
                    end
                    local ok = pcall(ReadCollection.addCollection, ReadCollection, name)
                    if ok then
                        pcall(ReadCollection.write, ReadCollection)
                        if callback then callback(name) end
                    else
                        UIManager:show(InfoMessage:new{ text = _("Não foi possível criar a coleção.") })
                    end
                end },
            }},
        }
        UIManager:show(dialog)
        pcall(dialog.onShowKeyboard, dialog)
    end

    function BV:showCollectionsForFiles(menu, selected)
        local files = {}
        for path in pairs(selected or {}) do files[path] = true end
        if not next(files) then return end

        local dialog
        local function rebuild()
            closeIf(dialog)
            local names = collectionNames()
            local buttons = {}

            for _, name in ipairs(names) do
                local allChecked = true
                local anyChecked = false
                for path in pairs(files) do
                    local checked = false
                    local ok = pcall(function()
                        checked = ReadCollection:isFileInCollection(path, name)
                    end)
                    if ok and checked then anyChecked = true else allChecked = false end
                end
                local prefix = allChecked and "☑ " or (anyChecked and "◩ " or "☐ ")
                buttons[#buttons + 1] = {{
                    text = prefix .. name,
                    callback = function()
                        local target = not allChecked
                        for path in pairs(files) do
                            local map = {}
                            for _, n in ipairs(names) do
                                map[n] = ReadCollection:isFileInCollection(path, n)
                            end
                            map[name] = target
                            pcall(ReadCollection.addRemoveItemMultiple, ReadCollection, path, map)
                        end
                        pcall(ReadCollection.write, ReadCollection)
                        rebuild()
                        refresh(menu)
                    end,
                }}
            end

            buttons[#buttons + 1] = {{
                text = _("＋ Criar nova coleção"),
                callback = function()
                    createCollection(self, function(name)
                        for path in pairs(files) do
                            local map = {}
                            for _, n in ipairs(collectionNames()) do
                                map[n] = ReadCollection:isFileInCollection(path, n)
                            end
                            map[name] = true
                            pcall(ReadCollection.addRemoveItemMultiple, ReadCollection, path, map)
                        end
                        pcall(ReadCollection.write, ReadCollection)
                        rebuild()
                        refresh(menu)
                    end)
                end,
            }}
            buttons[#buttons + 1] = {{
                text = _("Concluído"),
                callback = function() closeIf(dialog); refresh(menu) end,
            }}

            dialog = ButtonDialog:new{
                title = T(_("Coleções · %1 selecionado(s)"), count(files)),
                title_align = "center",
                buttons = buttons,
            }
            UIManager:show(dialog)
        end
        rebuild()
    end

    function BV:showCollectionsForBook(item, menu)
        self:showCollectionsForFiles(menu, {[item.path] = true})
    end

    function BV:renameBook(item, menu)
        local file = item and item.path
        if not file then return end
        local dialog
        dialog = InputDialog:new{
            title = _("Renomear livro"),
            input = basename(file),
            buttons = {{
                { text = _("Cancelar"), callback = function() closeIf(dialog) end },
                { text = _("Salvar"), is_enter_default = true, callback = function()
                    local name = (dialog:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    closeIf(dialog)
                    if name == "" then return end
                    if name:find("/") or name:find("\\") then
                        UIManager:show(InfoMessage:new{ text = _("O nome não pode conter barras.") })
                        return
                    end
                    local dir = file:match("^(.*)/[^/]+$") or "."
                    local dest = dir .. "/" .. name
                    if lfs.attributes(dest) then
                        UIManager:show(InfoMessage:new{ text = _("Já existe um arquivo com esse nome.") })
                        return
                    end
                    if os.rename(file, dest) then
                        pcall(DocSettings.updateLocation, file, dest)
                        pcall(function() require("readhistory"):updateItem(file, dest) end)
                        BookList.resetBookInfoCache(file)
                        item.path, item.filepath, item.text = dest, dest, name
                        refresh(menu)
                    else
                        UIManager:show(InfoMessage:new{ text = _("Não foi possível renomear o arquivo.") })
                    end
                end },
            }},
        }
        UIManager:show(dialog)
        pcall(dialog.onShowKeyboard, dialog)
    end

    local function copyOrMove(owner, menu, selected, move)
        local paths = selectedList(selected)
        if #paths == 0 then return end
        local chooser = PathChooser:new{
            select_directory = true,
            select_file = false,
            onConfirm = function(dir)
                if not dir then return end
                local failed = 0
                local changed = 0
                for _, file in ipairs(paths) do
                    local dest = ffiUtil.joinPath(dir, basename(file))
                    if lfs.attributes(dest) then
                        failed = failed + 1
                    else
                        local ok
                        if move then
                            ok = os.rename(file, dest)
                            if ok then
                                pcall(DocSettings.updateLocation, file, dest)
                                pcall(function() require("readhistory"):updateItem(file, dest) end)
                            end
                        else
                            ok = ffiUtil.copyFile(file, dest)
                            if ok then pcall(DocSettings.updateLocation, file, dest, true) end
                        end
                        if ok then changed = changed + 1 else failed = failed + 1 end
                    end
                end
                if failed > 0 then
                    UIManager:show(InfoMessage:new{
                        text = T(_("%1 arquivo(s) não puderam ser processados."), failed),
                    })
                end
                if move and changed > 0 then owner:leaveSelection(menu) end
                refresh(menu)
            end,
        }
        UIManager:show(chooser)
    end

    function BV:copyOrMoveBook(item, menu, move)
        copyOrMove(self, menu, {[item.path] = true}, move)
    end

    function BV:deleteBooks(selected, menu)
        local files = {}
        for path in pairs(selected or {}) do files[path] = true end
        local n = count(files)
        if n == 0 then return end

        UIManager:show(ConfirmBox:new{
            text = T(N_("Excluir %1 livro?\nEssa ação não pode ser desfeita.",
                        "Excluir %1 livros?\nEssa ação não pode ser desfeita.", n), n),
            ok_text = _("Excluir"),
            ok_callback = function()
                local failed = 0
                for file in pairs(files) do
                    if lfs.attributes(file, "mode") == "file" then
                        -- Let KOReader remove sidecar/custom metadata consistently.
                        pcall(DocSettings.updateLocation, file)
                        if not os.remove(file) then failed = failed + 1 end
                    end
                    pcall(ReadCollection.removeItem, ReadCollection, file, nil, true)
                    BookList.resetBookInfoCache(file)
                end
                pcall(ReadCollection.write, ReadCollection)
                pcall(function() require("readhistory"):clearMissing() end)
                if failed > 0 then
                    UIManager:show(InfoMessage:new{
                        text = T(_("%1 arquivo(s) não puderam ser excluídos."), failed),
                    })
                end
                if menu then
                    self:leaveSelection(menu)
                    menu._bookvault_source_items = self:scanBooks(self:privacyIncludePrivate())
                    menu.item_table = menu._bookvault_source_items
                    refresh(menu)
                end
            end,
        })
    end

    function BV:enterSelection(menu, item)
        menu._bookvault_selection_mode = true
        menu._bookvault_selected = {}
        if item and item.path then menu._bookvault_selected[item.path] = true end
        refresh(menu)
    end

    function BV:toggleSelection(menu, item)
        if not item or not item.path then return end
        menu._bookvault_selected = menu._bookvault_selected or {}
        if menu._bookvault_selected[item.path] then
            menu._bookvault_selected[item.path] = nil
        else
            menu._bookvault_selected[item.path] = true
        end
        refresh(menu)
    end

    function BV:leaveSelection(menu)
        menu._bookvault_selection_mode = false
        menu._bookvault_selected = nil
        refresh(menu)
    end

    function BV:showSelectionActions(menu)
        local selected = menu._bookvault_selected or {}
        local n = count(selected)
        if n == 0 then
            self:leaveSelection(menu)
            return
        end

        local dialog
        local buttons = {
            {{ text = _("Abrir primeiro selecionado"), callback = function()
                local path = next(selected)
                closeIf(dialog)
                if path then filemanagerutil.openFile(self.ui, path) end
            end }},
            {{ text = _("Status de leitura"), callback = function()
                closeIf(dialog)
                self:showStatusForFiles(menu, selected)
            end }},
            {{ text = _("Coleções"), callback = function()
                closeIf(dialog)
                self:showCollectionsForFiles(menu, selected)
            end }},
            {{ text = T(_("Mover %1"), n), callback = function()
                closeIf(dialog)
                copyOrMove(self, menu, selected, true)
            end }},
            {{ text = T(_("Copiar %1"), n), callback = function()
                closeIf(dialog)
                copyOrMove(self, menu, selected, false)
            end }},
            {{ text = T(_("Excluir %1"), n), callback = function()
                closeIf(dialog)
                self:deleteBooks(selected, menu)
            end }},
            {{ text = _("Sair da seleção"), callback = function()
                closeIf(dialog)
                self:leaveSelection(menu)
            end }},
        }
        dialog = ButtonDialog:new{
            title = T(_("%1 selecionado(s)"), n),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(dialog)
    end

    function BV:showStatusForFiles(menu, selected)
        local files = selected or {}
        local first = next(files)
        if not first then return end

        local doc_settings_or_file
        if count(files) == 1 then
            doc_settings_or_file = first
        else
            doc_settings_or_file = first
        end

        local row = filemanagerutil.genStatusButtonsRow(doc_settings_or_file, function()
            refresh(menu)
        end)
        local dialog
        dialog = ButtonDialog:new{
            title = count(files) == 1 and _("Status de leitura") or T(_("Status de %1 livros"), count(files)),
            title_align = "center",
            buttons = {
                row,
                {{
                    text = _("Aplicar aos selecionados"),
                    callback = function()
                        local selected_status = nil
                        -- Status row's callbacks already write the first item, so for
                        -- multi-selection use the native summary API explicitly below.
                        closeIf(dialog)
                        local choose
                        local statuses = {
                            { "reading", _("Lendo") },
                            { "abandoned", _("Em espera") },
                            { "complete", _("Concluídos") },
                        }
                        choose = ButtonDialog:new{
                            title = _("Aplicar status"),
                            buttons = {
                                {{ text = statuses[1][2], callback = function()
                                    closeIf(choose)
                                    self:setStatusForFiles(files, "reading", menu)
                                end }},
                                {{ text = statuses[2][2], callback = function()
                                    closeIf(choose)
                                    self:setStatusForFiles(files, "abandoned", menu)
                                end }},
                                {{ text = statuses[3][2], callback = function()
                                    closeIf(choose)
                                    self:setStatusForFiles(files, "complete", menu)
                                end }},
                            },
                        }
                        UIManager:show(choose)
                    end,
                }},
                {{ text = _("Cancelar"), callback = function() closeIf(dialog) end }},
            },
        }
        UIManager:show(dialog)
    end

    function BV:setStatusForFiles(files, status, menu)
        for file in pairs(files or {}) do
            local ds = BookList.getDocSettings(file)
            local summary = ds:readSetting("summary") or {}
            summary.status = status
            local saved = filemanagerutil.saveSummary(ds, summary)
            BookList.setBookInfoCacheProperty(file, "status", status)
            if saved then ds = saved end
        end
        refresh(menu)
    end

    function BV:showPluginActions(menu, item)
        local fm = require("apps/filemanager/filemanager").instance
        if fm and fm.file_chooser and fm.file_chooser.showFileDialog then
            local ok = pcall(fm.file_chooser.showFileDialog, fm.file_chooser, {
                path = item.path,
                is_file = true,
                is_go_up = false,
            })
            if ok then return end
        end
        UIManager:show(InfoMessage:new{
            text = _("As ações de plugins compatíveis não estão disponíveis nesta tela."),
        })
    end

    function BV:showBookActions(menu, item)
        if not item or not item.path or not item.is_file then return true end
        if menu._bookvault_selection_mode then
            self:toggleSelection(menu, item)
            return true
        end

        local coverLabel = hasCover(self, item.path) and _("Alterar capa") or _("Adicionar capa")
        local dialog
        local buttons = {
            {{ text = _("Abrir livro"), callback = function()
                closeIf(dialog)
                self:guard(item.path, function() filemanagerutil.openFile(self.ui, item.path) end)
            end }},
            {{ text = _("Informações do livro"), callback = function()
                closeIf(dialog); self:showBookInfo(item)
            end }},
            {{ text = _("Status de leitura"), callback = function()
                closeIf(dialog); self:showStatusForFiles(menu, {[item.path] = true})
            end }},
            {{ text = _("Coleções"), callback = function()
                closeIf(dialog); self:showCollectionsForBook(item, menu)
            end }},
            {{ text = coverLabel .. " / metadados", callback = function()
                closeIf(dialog); self:showBookInfo(item)
            end }},
            {{ text = _("Buscar capa no Google Imagens"), callback = function()
                closeIf(dialog); self:searchGoogleImagesForCover(item.path)
            end }},
            {},
            {{ text = _("Selecionar vários"), callback = function()
                closeIf(dialog); self:enterSelection(menu, item)
            end }},
            {{ text = _("Renomear"), callback = function()
                closeIf(dialog); self:renameBook(item, menu)
            end }},
            {{ text = _("Copiar"), callback = function()
                closeIf(dialog); self:copyOrMoveBook(item, menu, false)
            end }},
            {{ text = _("Mover"), callback = function()
                closeIf(dialog); self:copyOrMoveBook(item, menu, true)
            end }},
            {{ text = _("Abrir localização"), callback = function()
                closeIf(dialog)
                local dir = item.path:match("^(.*)/[^/]+$")
                local fm = require("apps/filemanager/filemanager").instance
                if fm and fm.file_chooser and dir then
                    fm.file_chooser:changeToPath(dir, item.path)
                elseif self.ui and self.ui.file_chooser and dir then
                    self.ui.file_chooser:changeToPath(dir, item.path)
                end
            end }},
            {{ text = _("Excluir"), callback = function()
                closeIf(dialog); self:deleteBooks({[item.path] = true}, menu)
            end }},
            {{ text = _("Mais ações / plugins"), callback = function()
                closeIf(dialog); self:showPluginActions(menu, item)
            end }},
            {},
            {{ text = _("Cancelar"), callback = function() closeIf(dialog) end }},
        }

        dialog = ButtonDialog:new{
            title = item.text or basename(item.path),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(dialog)
        return true
    end

    function BV:searchGoogleImagesForCover(file)
        local socket = require("socket")
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local socketutil = require("socketutil")
        local props = getProps(self, file)
        local title = props.title or props.display_title or basename(file):gsub("%.[^%.]+$", "")
        local authors = props.authors or ""
        local q = (title .. " " .. authors):gsub("[^%w%s%-]", ""):gsub("%s+", "+")
        local url = "https://www.google.com/search?tbm=isch&q=" .. q

        UIManager:show(InfoMessage:new{ text = _("Pesquisando capas…") })
        local sink = {}
        socketutil:set_timeout(10, 20)
        local ok = pcall(function()
            socket.skip(1, http.request{
                url = url,
                headers = {
                    ["User-Agent"] = "Mozilla/5.0",
                    ["Accept-Encoding"] = "identity",
                },
                sink = ltn12.sink.table(sink),
            })
        end)
        socketutil:reset_timeout()
        if not ok then
            UIManager:show(InfoMessage:new{ text = _("Não foi possível acessar a pesquisa de imagens.") })
            return
        end

        local html = table.concat(sink)
        local found, seen = {}, {}
        for u in html:gmatch('https?://[^"\\<> ]+') do
            u = u:gsub("\\u003d", "="):gsub("\\u0026", "&")
            if (u:match("%.[Jj][Pp][Gg]") or u:match("%.[Jj][Pp][Ee][Gg]") or
                u:match("%.[Pp][Nn][Gg]") or u:match("%.[Ww][Ee][Bb][Pp]")) and not seen[u] then
                seen[u] = true
                found[#found + 1] = u
                if #found >= 6 then break end
            end
        end

        if #found == 0 then
            UIManager:show(InfoMessage:new{
                text = _("O Google Imagens não retornou capas utilizáveis."),
            })
            return
        end

        local dialog
        local buttons = {}
        for i, imageUrl in ipairs(found) do
            local index = i
            buttons[#buttons + 1] = {{
                text = T(_("Capa %1 · baixar e aplicar"), index),
                callback = function()
                    closeIf(dialog)
                    local base = DataStorage:getDataDir() .. "/bookvault/covers"
                    pcall(util.makePath, base)
                    local ext = imageUrl:match("%.([A-Za-z0-9]+)(?:%?|$)") or "jpg"
                    if ext:lower() ~= "jpg" and ext:lower() ~= "jpeg" and ext:lower() ~= "png" then ext = "jpg" end
                    local out = base .. "/cover_" .. tostring(os.time()) .. "_" .. tostring(index) .. "." .. ext
                    local f = io.open(out, "wb")
                    if not f then
                        UIManager:show(InfoMessage:new{ text = _("Não foi possível preparar a capa.") })
                        return
                    end
                    socketutil:set_timeout(10, 20)
                    local ok2 = pcall(function()
                        socket.skip(1, http.request{
                            url = imageUrl,
                            headers = { ["User-Agent"] = "Mozilla/5.0" },
                            sink = ltn12.sink.file(f),
                        })
                    end)
                    socketutil:reset_timeout()
                    pcall(f.close, f)
                    if not ok2 or lfs.attributes(out, "mode") ~= "file" then
                        UIManager:show(InfoMessage:new{ text = _("Não foi possível baixar esta capa.") })
                        return
                    end

                    local ui = self.ui or ReaderUI.instance
                    if ui and ui.bookinfo and ui.bookinfo.setCustomCoverFromImage then
                        local ok_apply = pcall(ui.bookinfo.setCustomCoverFromImage, ui.bookinfo, file, out)
                        if ok_apply then
                            pcall(os.remove, out)
                            UIManager:broadcastEvent(require("ui/event"):new("InvalidateMetadataCache", file))
                            if self._last_menu then refresh(self._last_menu) end
                            UIManager:show(InfoMessage:new{ text = _("Capa aplicada.") })
                        else
                            UIManager:show(InfoMessage:new{ text = _("Não foi possível aplicar esta capa.") })
                        end
                    else
                        UIManager:show(InfoMessage:new{ text = _("A edição de capa nativa não está disponível nesta tela.") })
                    end
                end,
            }}
        end
        buttons[#buttons + 1] = {{
            text = _("Cancelar"),
            callback = function() closeIf(dialog) end,
        }}
        dialog = ButtonDialog:new{
            title = _("Google Imagens · escolher capa"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(dialog)
    end

    -- Scope all interactions to the menu instance returned by BookVault.
    local oldMake = BV.makeBookMenu
    BV.makeBookMenu = function(self, ...)
        local menu = oldMake(self, ...)
        if not menu then return menu end

        local oldSelect = menu.onMenuSelect
        menu.onMenuSelect = function(m, item, pos)
            if m._bookvault_selection_mode then
                self:toggleSelection(m, item)
                return true
            end
            return oldSelect and oldSelect(m, item, pos) or true
        end

        menu.onMenuHold = function(m, item, pos)
            return self:showBookActions(m, item)
        end

        menu._bookvault_action_owner = self
        return menu
    end

    -- Make the native File Browser protection apply only to the active FileManager
    -- chooser when BookVault is initialized there. No global class override.
    local oldInit = BV.init
    BV.init = function(self, ...)
        local result = oldInit(self, ...)
        local ui = self.ui
        local fc = ui and ui.file_chooser
        if fc and not fc._bookvault_guard then
            fc._bookvault_guard = true
            local oldSelect = fc.onMenuSelect
            local oldHold = fc.onMenuHold
            local oldChange = fc.changeToPath
            local function guarded(path, callback)
                if not path or not self:isProtected(path) or self.unlocked then
                    return callback()
                end
                self:askPassword(function(ok)
                    if ok then self.unlocked = true; safe(callback) end
                end, _("Pasta protegida"))
                return true
            end
            fc.onMenuSelect = function(f, item)
                local path = item and item.path
                if path and self:isProtected(path) and not self.unlocked then
                    return guarded(path, function() return oldSelect(f, item) end)
                end
                return oldSelect(f, item)
            end
            fc.onMenuHold = function(f, item)
                local path = item and item.path
                if path and self:isProtected(path) and not self.unlocked then
                    return guarded(path, function() return oldHold(f, item) end)
                end
                return oldHold(f, item)
            end
            fc.changeToPath = function(f, path, focused)
                if path and self:isProtected(path) and not self.unlocked then
                    return guarded(path, function() return oldChange(f, path, focused) end)
                end
                return oldChange(f, path, focused)
            end
        end
        return result
    end
end

return M
