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

local function findSimpleUIBookVaultAction()
    local ok_store, store = pcall(require, "infra/sui_store")
    if not ok_store or not store then return nil, nil end
    local tabs = store:get("simpleui_bar_tabs")
    if type(tabs) ~= "table" then return nil, nil end
    for _, action_id in ipairs(tabs) do
        if type(action_id) == "string" and action_id:match("^custom_qa_%d+$") then
            local cfg = store:get("simpleui_qa_" .. action_id)
            if type(cfg) == "table" then
                local key = tostring(cfg.plugin_key or ""):lower()
                local label = tostring(cfg.label or ""):lower()
                if key:find("bookvault", 1, true) or label == "bookvault" then
                    return action_id, tabs
                end
            end
        elseif type(action_id) == "string" and action_id:match("^open_custom_screen:") then
            local ok_cs, CustomScreens = pcall(require, "infra/sui_custom_screens")
            if ok_cs and CustomScreens then
                local screen_id = action_id:match("^open_custom_screen:(.+)$")
                local screen = screen_id and CustomScreens.get(screen_id)
                local label = screen and tostring(screen.name or ""):lower() or ""
                if label:find("bookvault", 1, true) then
                    return action_id, tabs
                end
            end
        end
    end
    return nil, tabs
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
        local fm = require("apps/filemanager/filemanager").instance
        local rui = ReaderUI.instance
        local ui = (fm and fm.bookinfo and fm) or (rui and rui.bookinfo and rui)
        local bookinfo = ui and ui.bookinfo
        if not bookinfo then
            UIManager:show(InfoMessage:new{ text = _("As informações do livro não estão disponíveis nesta tela.") })
            return
        end
        safe(function()
            local file = item.path
            local book_props
            if fm and fm.coverbrowser and fm.coverbrowser.getBookInfo then
                book_props = fm.coverbrowser:getBookInfo(file)
            end
            local doc_settings_or_file = file
            if BookList.hasBookBeenOpened(file) then
                doc_settings_or_file = BookList.getDocSettings(file)
                if not book_props then
                    book_props = doc_settings_or_file:readSetting("doc_props")
                end
            end
            bookinfo:show(doc_settings_or_file, book_props and bookinfo.extendProps(book_props, file))

            -- Keep KOReader's native metadata page, but remove only the
            -- Rating/Review rows requested by BookVault. This is instance-scoped.
            local kvp = bookinfo.kvp_widget
            if kvp and type(kvp.kv_pairs) == "table" then
                local filtered = {}
                local function isRatingOrReviewRow(entry)
                    if type(entry) ~= "table" or type(entry[1]) ~= "string" then return false end
                    local label = entry[1]:lower():gsub("%s+", " ")
                    return label:find("rating", 1, true) ~= nil
                        or label:find("review", 1, true) ~= nil
                        or label:find("avalia", 1, true) ~= nil
                        or label:find("resenha", 1, true) ~= nil
                end
                for _, entry in ipairs(kvp.kv_pairs) do
                    if not isRatingOrReviewRow(entry) then
                        filtered[#filtered + 1] = entry
                    end
                end
                kvp.kv_pairs = filtered
                if kvp.items_per_page and kvp._populateItems then
                    kvp.pages = math.max(1, math.ceil(#filtered / kvp.items_per_page))
                    kvp.show_page = math.min(kvp.show_page or 1, kvp.pages)
                    kvp:_populateItems()
                    UIManager:setDirty(kvp, "ui", kvp.dimen)
                end
            end
        end)
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

    function BV:copyOrMoveSelected(menu, selected, move)
        copyOrMove(self, menu, selected or {}, move)
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

    function BV:copyOrMoveBookSelection(menu, move)
        local selected = menu and menu._bookvault_selected or {}
        if not next(selected or {}) then return end
        copyOrMove(self, menu, selected, move)
    end


    function BV:enterSelection(menu, item)
        menu._bookvault_selection_mode = true
        menu._bookvault_selected = {}
        if item and item.path then menu._bookvault_selected[item.path] = true end
        if menu._bookvault_header and menu._bookvault_header.setSelectionCount then
            menu._bookvault_header:setSelectionCount(count(menu._bookvault_selected))
        end
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
        local n = count(menu._bookvault_selected)
        if n == 0 then
            self:leaveSelection(menu)
            return
        end
        if menu._bookvault_header and menu._bookvault_header.setSelectionCount then
            menu._bookvault_header:setSelectionCount(n)
        end
        refresh(menu)
    end

    function BV:leaveSelection(menu)
        menu._bookvault_selection_mode = false
        menu._bookvault_selected = nil
        if menu._bookvault_header and menu._bookvault_header.setSelectionCount then
            menu._bookvault_header:setSelectionCount(0)
        end
        refresh(menu)
    end

    function BV:showSelectionMore(menu)
        local selected = menu and menu._bookvault_selected or {}
        local n = count(selected)
        if n == 0 then
            self:leaveSelection(menu)
            return
        end
        local dialog
        local first = next(selected)
        dialog = ButtonDialog:new{
            title = T(_("%1 selecionado(s)"), n),
            title_align = "center",
            buttons = {
                {{text = _("Status de leitura"), icon = "bookmark",
                    callback = function()
                        closeIf(dialog)
                        self:showStatusForFiles(menu, selected)
                    end}},
                {{text = _("Mais ações / plugins"), icon = "bookvault-more",
                    callback = function()
                        closeIf(dialog)
                        if first then self:showPluginActions(menu, {path=first}) end
                    end}},
                {{text = _("Sair da seleção"), icon = "bookvault-check",
                    callback = function()
                        closeIf(dialog)
                        self:leaveSelection(menu)
                    end}},
            },
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

    function BV:showMoreActions(menu, item)
        if not item or not item.path then return end
        local dialog
        dialog = ButtonDialog:new{
            title = item.text or basename(item.path),
            title_align = "center",
            buttons = {
                {{text = _("Copiar"), icon = "bookvault-copy", callback = function()
                    closeIf(dialog)
                    self:copyOrMoveBook(item, menu, false)
                end}},
                {{text = _("Mover"), icon = "bookvault-move", callback = function()
                    closeIf(dialog)
                    self:copyOrMoveBook(item, menu, true)
                end}},
                {{text = _("Mais ações / plugins"), icon = "bookvault-more", callback = function()
                    closeIf(dialog)
                    self:showPluginActions(menu, item)
                end}},
                {{text = _("Cancelar"), icon = "exit", callback = function() closeIf(dialog) end}},
            },
        }
        UIManager:show(dialog)
    end

    function BV:showBookActions(menu, item)
        if not item or not item.path or not item.is_file then return true end
        if menu._bookvault_selection_mode then
            self:toggleSelection(menu, item)
            return true
        end

        local dialog
        local buttons = {
            {{text = _("Abrir livro"), icon = "book.opened", callback = function()
                closeIf(dialog)
                self:guard(item.path, function()
                    if lfs.attributes(item.path,"mode") ~= "file" then
                        UIManager:show(InfoMessage:new{text=_("O arquivo não existe mais.")})
                        return
                    end
                    filemanagerutil.openFile(self.ui, item.path)
                end)
            end}},
            {{text = _("Informações do livro"), icon = "notice-info", callback = function()
                closeIf(dialog)
                self:showBookInfo(item)
            end}},
            {{text = _("Status de leitura"), icon = "bookmark", callback = function()
                closeIf(dialog)
                self:showStatusForFiles(menu, {[item.path] = true})
            end}},
            {{text = _("Coleções"), icon = "bookmark", callback = function()
                closeIf(dialog)
                self:showCollectionsForBook(item, menu)
            end}},
            {{text = _("Selecionar vários"), icon = "bookvault-check", callback = function()
                closeIf(dialog)
                self:enterSelection(menu, item)
            end}},
            {{text = _("Renomear"), icon = "edit", callback = function()
                closeIf(dialog)
                self:renameBook(item, menu)
            end}},
            {{text = _("Buscar capa"), icon = "search", callback = function()
                closeIf(dialog)
                self:searchBookCovers(item.path)
            end}},
            {{text = _("Abrir localização"), icon = "folder", callback = function()
                closeIf(dialog)
                local dir = item.path:match("^(.*)/[^/]+$")
                local fm = require("apps/filemanager/filemanager").instance
                if fm and fm.file_chooser and dir then
                    fm.file_chooser:changeToPath(dir, item.path)
                elseif self.ui and self.ui.file_chooser and dir then
                    self.ui.file_chooser:changeToPath(dir, item.path)
                end
            end}},
            {{text = _("Excluir"), icon = "bookvault-trash", callback = function()
                closeIf(dialog)
                self:deleteBooks({[item.path] = true}, menu)
            end}},
            {{text = _("Mais ações"), icon = "bookvault-more", callback = function()
                closeIf(dialog)
                self:showMoreActions(menu, item)
            end}},
            {{text = _("Cancelar"), icon = "exit", callback = function() closeIf(dialog) end}},
        }

        dialog = ButtonDialog:new{
            title = item.text or basename(item.path),
            title_align = "center",
            buttons = buttons,
            shrink_unneeded_width = true,
        }
        UIManager:show(dialog)
        return true
    end

    function BV:searchBookCovers(file)
    if not file then return end

    -- All network work is explicit and user-triggered. No background searches.
    local http = require("socket.http")
    local socketutil = require("socketutil")
    local urlmod = require("socket.url")
    local json = require("json")
    local mime = require("mime")
    local Screen = require("device").screen

    local https_ok, https = pcall(require, "ssl.https")
    local function request(req)
        if req.url and req.url:match("^https://") and https_ok then
            return https.request(req)
        end
        return http.request(req)
    end

    local props = getProps(self, file)
    local title = tostring(props.title or props.display_title or basename(file):gsub("%.[^%.]+$", ""))
    local authors = props.authors or props.author or ""
    if type(authors) == "table" then authors = table.concat(authors, " ") end
    authors = tostring(authors or "")
    local language = tostring(props.language or "")

    local function clean(value)
        return tostring(value or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end
    title, authors, language = clean(title), clean(authors), clean(language)
    if title == "" then
        UIManager:show(InfoMessage:new{text=_([=[Não foi possível determinar o título do livro.]=])})
        return
    end

    local isbns = {}
    local seen_isbn = {}
    local function addIsbn(value)
        if type(value) ~= "string" and type(value) ~= "number" then return end
        local raw = tostring(value):upper():gsub("[^0-9X]", "")
        for isbn in raw:gmatch("%d%d%d%d%d%d%d%d%d%d%d%d%d") do
            if not seen_isbn[isbn] then seen_isbn[isbn] = true; isbns[#isbns+1] = isbn end
        end
        for isbn in raw:gmatch("%d%d%d%d%d%d%d%d%d%d") do
            if not seen_isbn[isbn] then seen_isbn[isbn] = true; isbns[#isbns+1] = isbn end
        end
    end
    addIsbn(props.isbn)
    addIsbn(props.isbn13)
    addIsbn(props.isbn10)
    if type(props.identifiers) == "table" then
        local function walk(v)
            if type(v) == "table" then
                for k, value in pairs(v) do
                    if type(k) == "string" and k:lower():find("isbn", 1, true) then addIsbn(value) end
                    walk(value)
                end
            else
                addIsbn(v)
            end
        end
        walk(props.identifiers)
    else
        addIsbn(props.identifiers)
    end

    local candidates, seen = {}, {}
    local function normText(value)
        return clean(value):lower():gsub("[%p]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end
    local wanted_title = normText(title)
    local wanted_author = normText(authors)

    local function firstIsbn(list)
        if type(list) ~= "table" then return nil end
        for _, value in ipairs(list) do
            local s = tostring(value or ""):upper():gsub("[^0-9X]", "")
            if #s == 10 or #s == 13 then return s end
        end
    end

    local function addCandidate(item)
        if type(item) ~= "table" or type(item.original) ~= "string" then return end
        local original = item.original:gsub("^http://", "https://")
        local thumb = (item.thumb or original):gsub("^http://", "https://")
        if not original:match("^https?://") or #original > 4096 then return end
        if seen[original] then return end
        seen[original] = true
        item.original, item.thumb = original, thumb

        local ct = normText(item.title)
        local ca = normText(item.authors)
        local score = 0
        if item.isbn then
            for _, wanted in ipairs(isbns) do
                if item.isbn == wanted then score = score + 120; break end
            end
        end
        if ct ~= "" and ct == wanted_title then score = score + 80
        elseif ct ~= "" and (ct:find(wanted_title, 1, true) or wanted_title:find(ct, 1, true)) then score = score + 45 end
        if wanted_author ~= "" and ca ~= "" and (ca:find(wanted_author, 1, true) or wanted_author:find(ca, 1, true)) then score = score + 45 end
        if language ~= "" and item.language ~= "" and tostring(item.language):lower():sub(1,2) == language:lower():sub(1,2) then score = score + 10 end
        if item.source == "openlibrary" then score = score + 5 end
        item.score = score
        candidates[#candidates+1] = item
    end

    local function requestJson(target_url)
        local body = {}
        socketutil:set_timeout(8, 15)
        local ok, success, code = pcall(function()
            return request{
                url=target_url,
                method="GET",
                headers={
                    ["User-Agent"]="BookVault/3.4 KOReader plugin",
                    ["Accept"]="application/json",
                    ["Accept-Encoding"]="identity",
                },
                sink=require("ltn12").sink.table(body),
            }
        end)
        socketutil:reset_timeout()
        if not ok or success ~= 1 or tonumber(code) ~= 200 then return nil end
        local ok_decode, decoded = pcall(json.decode, table.concat(body))
        return ok_decode and decoded or nil
    end

    local function addOpenLibrary(data)
        if type(data) ~= "table" or type(data.docs) ~= "table" then return end
        for _, doc in ipairs(data.docs) do
            local cover_id = tonumber(doc.cover_i)
            if cover_id then
                local ids = doc.isbn
                addCandidate{
                    source="openlibrary",
                    title=doc.title,
                    authors=type(doc.author_name)=="table" and table.concat(doc.author_name," ") or doc.author_name,
                    language=type(doc.language)=="table" and doc.language[1] or doc.language,
                    isbn=firstIsbn(ids),
                    original="https://covers.openlibrary.org/b/id/"..cover_id.."-L.jpg",
                    thumb="https://covers.openlibrary.org/b/id/"..cover_id.."-M.jpg",
                }
            end
        end
    end

    local function addGoogle(data)
        if type(data) ~= "table" or type(data.items) ~= "table" then return end
        for _, volume in ipairs(data.items) do
            local info = volume.volumeInfo or {}
            local links = info.imageLinks or {}
            local ids = {}
            for _, ident in ipairs(info.industryIdentifiers or {}) do ids[#ids+1] = ident.identifier end
            local original = links.extraLarge or links.large or links.medium or links.small or links.thumbnail
            local thumb = links.thumbnail or links.smallThumbnail or original
            if original then
                addCandidate{
                    source="googlebooks",
                    title=info.title,
                    authors=type(info.authors)=="table" and table.concat(info.authors," ") or info.authors,
                    language=info.language,
                    isbn=firstIsbn(ids),
                    original=original,
                    thumb=thumb,
                }
            end
        end
    end

    local function queryBoth(stage)
        local ol_url, gb_url
        if stage == 1 and isbns[1] then
            local q = urlmod.escape(isbns[1])
            ol_url = "https://openlibrary.org/search.json?isbn="..q.."&limit=6"
            gb_url = "https://www.googleapis.com/books/v1/volumes?q=isbn:"..q.."&maxResults=6"
        elseif stage == 2 then
            local t = urlmod.escape(title)
            local a = authors ~= "" and urlmod.escape(authors) or nil
            ol_url = "https://openlibrary.org/search.json?title="..t..(a and "&author="..a or "").."&limit=6"
            gb_url = "https://www.googleapis.com/books/v1/volumes?q=intitle:"..t..(a and "+inauthor:"..a or "").."&maxResults=6"
        elseif stage == 3 then
            local t = urlmod.escape(title)
            local a = authors ~= "" and urlmod.escape(authors) or nil
            local lang = language ~= "" and urlmod.escape(language:sub(1,2)) or nil
            ol_url = "https://openlibrary.org/search.json?title="..t..(a and "&author="..a or "")..(lang and "&language="..lang or "").."&limit=6"
            gb_url = "https://www.googleapis.com/books/v1/volumes?q=intitle:"..t..(a and "+inauthor:"..a or "")..(lang and "&langRestrict="..lang or "").."&maxResults=6"
        else
            local t = urlmod.escape(title)
            ol_url = "https://openlibrary.org/search.json?title="..t.."&limit=6"
            gb_url = "https://www.googleapis.com/books/v1/volumes?q=intitle:"..t.."&maxResults=6"
        end
        local ol = requestJson(ol_url); if ol then addOpenLibrary(ol) end
        local gb = requestJson(gb_url); if gb then addGoogle(gb) end
    end

    UIManager:show(InfoMessage:new{text=_("Pesquisando capas…")})
    if #isbns > 0 then queryBoth(1) end
    if #candidates < 6 then queryBoth(2) end
    if #candidates < 6 then queryBoth(3) end
    if #candidates < 6 then queryBoth(4) end

    table.sort(candidates, function(a,b)
        if a.score == b.score then return (a.title or "") < (b.title or "") end
        return a.score > b.score
    end)
    if #candidates > 6 then
        while #candidates > 6 do table.remove(candidates) end
    end
    if #candidates == 0 then
        UIManager:show(InfoMessage:new{text=_("Nenhuma capa foi encontrada. Verifique a conexão ou os metadados do livro.")})
        return
    end

    local base = DataStorage:getDataDir() .. "/bookvault/covers"
    pcall(util.makePath, base)
    local temp_files = {}
    local nonce = tostring(os.time()) .. "_" .. tostring(math.random(1000,9999))
    local function cleanup()
        for _, path in ipairs(temp_files) do pcall(os.remove, path) end
        temp_files = {}
    end

    local function validateImage(path)
        local f = io.open(path, "rb")
        if not f then return false end
        local head = f:read(12) or ""
        f:close()
        return head:sub(1,3) == "\255\216\255"
            or head:sub(1,8) == "\137PNG\r\n\26\n"
            or head:sub(1,4) == "GIF8"
            or (head:sub(1,4) == "RIFF" and head:sub(9,12) == "WEBP")
    end

    local function downloadToFile(target_url, output, max_bytes)
        local f = io.open(output, "wb")
        if not f then return false end
        local total = 0
        local sink = function(chunk)
            if not chunk then f:close(); return 1 end
            total = total + #chunk
            if total > max_bytes then f:close(); return nil, "response too large" end
            if not f:write(chunk) then f:close(); return nil, "write failed" end
            return 1
        end
        socketutil:set_timeout(8, 15)
        local ok, success, code = pcall(function()
            return request{
                url=target_url,
                method="GET",
                headers={
                    ["User-Agent"]="BookVault/3.4 KOReader plugin",
                    ["Accept"]="image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
                    ["Accept-Encoding"]="identity",
                },
                sink=sink,
            }
        end)
        socketutil:reset_timeout()
        if not ok or success ~= 1 or tonumber(code) ~= 200 or total <= 0 or not validateImage(output) then
            pcall(os.remove, output)
            return false
        end
        temp_files[#temp_files+1] = output
        return true
    end

    local function makePreviewIcon(raw_path, index)
        local f = io.open(raw_path, "rb")
        if not f then return nil end
        local data = f:read("*a") or ""
        f:close()
        if #data == 0 then return nil end
        local mime_type
        if data:sub(1,3) == "\255\216\255" then mime_type="image/jpeg"
        elseif data:sub(1,8) == "\137PNG\r\n\26\n" then mime_type="image/png"
        elseif data:sub(1,4) == "GIF8" then mime_type="image/gif"
        elseif data:sub(1,4) == "RIFF" and data:sub(9,12) == "WEBP" then mime_type="image/webp" end
        if not mime_type then return nil end
        local encoded = mime.b64(data)
        local icon_name = "bookvault-cover-preview-"..nonce.."-"..index
        local icon_path = DataStorage:getDataDir().."/icons/"..icon_name..".svg"
        local svg = string.format('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="300" height="400" viewBox="0 0 300 400"><rect width="300" height="400" fill="white"/><image x="0" y="0" width="300" height="400" preserveAspectRatio="xMidYMid meet" href="data:%s;base64,%s" xlink:href="data:%s;base64,%s"/></svg>',mime_type,encoded,mime_type,encoded)
        local out=io.open(icon_path,"wb")
        if not out then return nil end
        out:write(svg); out:close()
        temp_files[#temp_files+1]=icon_path
        return icon_name
    end

    local found={}
    for i,result in ipairs(candidates) do
        local path=base.."/preview_"..nonce.."_"..i..".img"
        if downloadToFile(result.thumb,path,180*1024) then
            local icon=makePreviewIcon(path,i)
            if icon then found[#found+1]={candidate=result,icon=icon} end
        end
        if #found >= 6 then break end
    end
    if #found == 0 then
        cleanup()
        UIManager:show(InfoMessage:new{text=_("As capas foram encontradas, mas nenhuma prévia pôde ser carregada.")})
        return
    end

    local dialog
    local rows={}
    local current
    for i,result in ipairs(found) do
        if not current or #current >= 2 then current={}; rows[#rows+1]=current end
        current[#current+1]={
            text=tostring(i), icon=result.icon,
            icon_width=math.min(Screen:scaleBySize(150),math.floor(Screen:getWidth()/2)-Screen:scaleBySize(30)),
            icon_height=Screen:scaleBySize(200),
            callback=function()
                closeIf(dialog)
                local out=base.."/selected_"..nonce.."_"..i..".img"
                local ok_full=downloadToFile(result.candidate.original,out,6*1024*1024)
                if not ok_full then
                    cleanup(); UIManager:show(InfoMessage:new{text=_("Não foi possível baixar ou validar a capa escolhida.")}); return
                end
                local fm=require("apps/filemanager/filemanager").instance
                local rui=ReaderUI.instance
                local bookinfo=(fm and fm.bookinfo) or (rui and rui.bookinfo)
                if not bookinfo then
                    local FileManagerBookInfo=require("apps/filemanager/filemanagerbookinfo")
                    bookinfo=FileManagerBookInfo:new{ui=self.ui}
                end
                local applied=false
                if bookinfo and bookinfo.setCustomCoverFromImage then
                    local call_ok=pcall(bookinfo.setCustomCoverFromImage,bookinfo,file,out)
                    applied=call_ok and DocSettings.findCustomCoverFile(file) ~= nil
                end
                cleanup()
                if not applied then
                    UIManager:show(InfoMessage:new{text=_("Não foi possível aplicar esta capa nesta versão do KOReader.")}); return
                end
                if self.invalidateBookMetadataCache then self:invalidateBookMetadataCache(file) end
                UIManager:broadcastEvent(require("ui/event"):new("InvalidateMetadataCache",file))
                UIManager:broadcastEvent(require("ui/event"):new("BookMetadataChanged",file))
                if self._last_menu then refresh(self._last_menu) end
                UIManager:show(InfoMessage:new{text=_("Capa aplicada.")})
            end,
        }
    end
    rows[#rows+1]={{text=_("Cancelar"),icon="close",callback=function() closeIf(dialog); cleanup() end}}
    dialog=ButtonDialog:new{title=_("Buscar capa · escolher capa"),title_align="center",buttons=rows,shrink_unneeded_width=true}
    dialog.onCloseWidget=function() cleanup() end
    UIManager:show(dialog)
end

-- Compatibility for callers from older BookVault versions.
BV.searchGoogleImagesForCover = BV.searchBookCovers

function BV:markSimpleUIActive()
        if self._bookvault_sui_action then return true end
        local action_id, tabs = findSimpleUIBookVaultAction()
        if not action_id then return false end
        local fm = package.loaded["apps/filemanager/filemanager"]
        local fm_instance = fm and fm.instance
        local rui = package.loaded["apps/reader/readerui"]
        local sui = (fm_instance and fm_instance._simpleui_plugin)
            or (rui and rui.instance and rui.instance.simpleui)
        if not sui then return false end
        local ok_bb, BB = pcall(require, "screens/sui_bottombar")
        if not ok_bb or not BB then return false end

        self._bookvault_sui_action = action_id
        self._bookvault_sui_prev_action = sui.active_action
        self._bookvault_sui_plugin = sui

        local refreshed = false
        if BB.setActiveAndRefreshFM then
            refreshed = pcall(BB.setActiveAndRefreshFM, sui, action_id, tabs)
        end
        if not refreshed and BB.setTempTabActive then
            pcall(BB.setTempTabActive, sui, action_id, true, self._bookvault_sui_prev_action)
            refreshed = true
        end
        if refreshed then
            sui.active_action = action_id
            return true
        end
        self._bookvault_sui_action = nil
        self._bookvault_sui_prev_action = nil
        self._bookvault_sui_plugin = nil
        return false
    end

    function BV:restoreSimpleUIActive()
        local action_id = self._bookvault_sui_action
        local sui = self._bookvault_sui_plugin
        if not action_id or not sui then return end
        local prev = self._bookvault_sui_prev_action
        local tabs = select(2, findSimpleUIBookVaultAction())
        local ok_bb, BB = pcall(require, "screens/sui_bottombar")
        if ok_bb and BB then
            local restored = false
            if BB.setActiveAndRefreshFM and prev then
                restored = pcall(BB.setActiveAndRefreshFM, sui, prev, tabs)
            end
            if not restored and BB.setTempTabActive then
                pcall(BB.setTempTabActive, sui, action_id, false, prev)
                restored = true
            end
            if restored then sui.active_action = prev end
        end
        self._bookvault_sui_action = nil
        self._bookvault_sui_prev_action = nil
        self._bookvault_sui_plugin = nil
    end

    function BV:closeBookVault(menu)
        if menu then UIManager:close(menu) end
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

        self:markSimpleUIActive()
        local oldCloseWidget = menu.onCloseWidget
        menu.onCloseWidget = function(m, ...)
            self:restoreSimpleUIActive()
            if oldCloseWidget then
                return oldCloseWidget(m, ...)
            end
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
