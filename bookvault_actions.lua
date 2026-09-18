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
local _source = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local PLUGIN_DIR = _source:match("^(.+)/[^/]+$") or "."
local function actionIcon(name) return PLUGIN_DIR .. "/icons/" .. name .. ".svg" end

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
        safe(function()
            local BookVaultBookInfo = require("bookvault_bookinfo")
            BookVaultBookInfo.show(self.ui or require("apps/filemanager/filemanager").instance, item.path)
        end)
    end

    local function collectionNames()    local function collectionNames()
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
        if menu._bookvault_header and menu._bookvault_header.setSelectionCount then
            menu._bookvault_header:setSelectionCount(count(menu._bookvault_selected))
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
                {{text = _("Mais ações / plugins"), icon = actionIcon("bookvault-more"),
                    callback = function()
                        closeIf(dialog)
                        if first then self:showPluginActions(menu, {path=first}) end
                    end}},
                {{text = _("Sair da seleção"), icon = actionIcon("bookvault-check"),
                    callback = function()
                        closeIf(dialog)
                        self:leaveSelection(menu)
                    end}},
            },
        }
        UIManager:show(dialog)
    end

    function BV:showStatusForFiles(menu, selected)    function BV:showStatusForFiles(menu, selected)
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
                {{text = _("Copiar"), icon = actionIcon("bookvault-copy"), callback = function()
                    closeIf(dialog)
                    self:copyOrMoveBook(item, menu, false)
                end}},
                {{text = _("Mover"), icon = actionIcon("bookvault-move"), callback = function()
                    closeIf(dialog)
                    self:copyOrMoveBook(item, menu, true)
                end}},
                {{text = _("Mais ações / plugins"), icon = actionIcon("bookvault-more"), callback = function()
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
            {{text = _("Abrir livro"), icon = actionIcon("bookvault-open"), callback = function()
                closeIf(dialog)
                self:guard(item.path, function()
                    if lfs.attributes(item.path,"mode") ~= "file" then
                        UIManager:show(InfoMessage:new{text=_("O arquivo não existe mais.")})
                        return
                    end
                    filemanagerutil.openFile(self.ui, item.path)
                end)
            end}},
            {{text = _("Informações do livro"), icon = actionIcon("bookvault-info"), callback = function()
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
            {{text = _("Selecionar vários"), icon = actionIcon("bookvault-check"), callback = function()
                closeIf(dialog)
                self:enterSelection(menu, item)
            end}},
            {{text = _("Renomear"), icon = actionIcon("bookvault-edit"), callback = function()
                closeIf(dialog)
                self:renameBook(item, menu)
            end}},
            {{text = _("Buscar capa no Google Imagens"), icon = actionIcon("bookvault-search-action"), callback = function()
                closeIf(dialog)
                self:searchGoogleImagesForCover(item.path)
            end}},
            {{text = _("Abrir localização"), icon = actionIcon("bookvault-folder"), callback = function()
                closeIf(dialog)
                local dir = item.path:match("^(.*)/[^/]+$")
                local fm = require("apps/filemanager/filemanager").instance
                if fm and fm.file_chooser and dir then
                    fm.file_chooser:changeToPath(dir, item.path)
                elseif self.ui and self.ui.file_chooser and dir then
                    self.ui.file_chooser:changeToPath(dir, item.path)
                end
            end}},
            {{text = _("Excluir"), icon = actionIcon("bookvault-trash"), callback = function()
                closeIf(dialog)
                self:deleteBooks({[item.path] = true}, menu)
            end}},
            {{text = _("Mais ações"), icon = actionIcon("bookvault-more"), callback = function()
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

    function BV:searchGoogleImagesForCover(file)
        local socket = require("socket")
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local socketutil = require("socketutil")
        local ImageWidget = require("ui/widget/imagewidget")
        local Button = require("ui/widget/button")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan = require("ui/widget/horizontalspan")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local FrameContainer = require("ui/widget/container/framecontainer")
        local Geom = require("ui/geometry")
        local Screen = require("device").screen
        local Size = require("ui/size")

        local props = getProps(self, file)
        local title = props.title or props.display_title or basename(file):gsub("%.[^%.]+$", "")
        local authors = props.authors or ""
        local query = (title .. " " .. authors):gsub("[^%w%s%-]", " "):gsub("%s+", " ")
        local encoded = query:gsub(" ", "+")
        local url = "https://www.google.com/search?tbm=isch&safe=active&q=" .. encoded

        local function decodeUrl(u)
            if not u then return nil end
            u = u:gsub("\\/", "/")
            u = u:gsub("\\u003d", "="):gsub("\\u0026", "&")
            u = u:gsub("\x3d", "="):gsub("\x26", "&")
            u = u:gsub("&amp;", "&")
            u = u:gsub("\"", """)
            return u
        end

        local function validImageUrl(u)
            if type(u) ~= "string" or u == "" then return false end
            if not u:match("^https?://") then return false end
            if u:find("google%.com/search", 1) then return false end
            if u:find("gstatic%.com/images", 1) then return false end
            return #u < 4096
        end

        local function requestToFile(target_url, output, max_bytes)
            local f = io.open(output, "wb")
            if not f then return false, _("Não foi possível criar o arquivo temporário.") end
            local total = 0
            local sink = function(chunk, err)
                if not chunk then
                    f:close()
                    return 1
                end
                total = total + #chunk
                if total > max_bytes then
                    f:close()
                    return nil, "response too large"
                end
                local ok_write = f:write(chunk)
                if not ok_write then
                    f:close()
                    return nil, "write failed"
                end
                return 1
            end

            socketutil:set_timeout(8, 15)
            local ok, success, code = pcall(function()
                return http.request{
                    url=target_url,
                    method="GET",
                    headers={
                        ["User-Agent"]="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124 Safari/537.36",
                        ["Accept"]="image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
                        ["Accept-Encoding"]="identity",
                    },
                    sink=sink,
                }
            end)
            socketutil:reset_timeout()
            if not ok or success ~= 1 or tonumber(code) ~= 200 then
                pcall(f.close, f)
                pcall(os.remove, output)
                return false, "http"
            end
            if total <= 0 then
                pcall(os.remove, output)
                return false, "empty"
            end
            return true
        end

        UIManager:show(InfoMessage:new{ text=_("Pesquisando capas…") })

        local html_parts = {}
        socketutil:set_timeout(8, 15)
        local ok, success, code = pcall(function()
            return http.request{
                url=url,
                method="GET",
                headers={
                    ["User-Agent"]="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124 Safari/537.36",
                    ["Accept"]="text/html,application/xhtml+xml",
                    ["Accept-Encoding"]="identity",
                    ["Accept-Language"]="pt-BR,pt;q=0.9,en;q=0.8",
                },
                sink=ltn12.sink.table(html_parts),
            }
        end)
        socketutil:reset_timeout()

        if not ok or success ~= 1 or tonumber(code) ~= 200 then
            UIManager:show(InfoMessage:new{ text=_("O Google Imagens não respondeu corretamente.") })
            return
        end

        local html = table.concat(html_parts)
        if html == "" or html:find("unusual traffic", 1, true) or html:find("consent.google.com", 1, true) then
            UIManager:show(InfoMessage:new{ text=_("O Google Imagens não disponibilizou resultados para esta pesquisa.") })
            return
        end

        local found, seen = {}, {}
        local function addResult(original, thumb)
            original, thumb = decodeUrl(original), decodeUrl(thumb)
            if not validImageUrl(original) then return end
            if not validImageUrl(thumb) then thumb = original end
            if seen[original] then return end
            seen[original] = true
            found[#found+1] = {original=original, thumb=thumb}
        end

        -- Google image results commonly expose original ("ou") and thumbnail
        -- ("tu") URLs inside JSON-like data. Accept both spacing variants.
        for ou, tu in html:gmatch('"ou"%s*:%s*"([^"]+)"%s*,%s*"tu"%s*:%s*"([^"]+)"') do
            addResult(ou, tu)
            if #found >= 6 then break end
        end
        if #found < 6 then
            for ou, tu in html:gmatch('"ou"%s*:%s*"([^"]+)"[^}]-"tu"%s*:%s*"([^"]+)"') do
                addResult(ou, tu)
                if #found >= 6 then break end
            end
        end
        if #found < 6 then
            for u in html:gmatch('https?://[^"\\<>%s]+') do
                u = decodeUrl(u)
                if validImageUrl(u) and not seen[u] then
                    local lower = u:lower()
                    if lower:find("%.jpg") or lower:find("%.jpeg") or lower:find("%.png") or lower:find("%.webp") then
                        addResult(u, u)
                    end
                end
                if #found >= 6 then break end
            end
        end

        if #found == 0 then
            UIManager:show(InfoMessage:new{
                text=_("Nenhuma capa utilizável foi encontrada. Tente novamente ou verifique a conexão."),
            })
            return
        end

        local base = DataStorage:getDataDir() .. "/bookvault/covers"
        pcall(util.makePath, base)
        local temp_files = {}
        local buttons = {}
        local cols = 2
        local thumb_w = math.min(Screen:scaleBySize(170), math.floor(Screen:getWidth() / 2) - Screen:scaleBySize(35))
        local thumb_h = Screen:scaleBySize(220)

        local dialog
        local function cleanup()
            for _, path in ipairs(temp_files) do pcall(os.remove, path) end
            temp_files = {}
        end

        for i, result in ipairs(found) do
            local thumb_path = base .. "/thumb_" .. tostring(os.time()) .. "_" .. tostring(i) .. ".img"
            local ok_thumb = requestToFile(result.thumb, thumb_path, 350 * 1024)
            if ok_thumb then
                temp_files[#temp_files+1] = thumb_path
                local button = {
                    icon=thumb_path,
                    icon_width=thumb_w,
                    icon_height=thumb_h,
                    text=tostring(i),
                    font_size=12,
                    callback=function()
                        if dialog then UIManager:close(dialog) end
                        cleanup()
                        local out = base .. "/cover_" .. tostring(os.time()) .. "_" .. tostring(i) .. ".img"
                        local ok_full = requestToFile(result.original, out, 8 * 1024 * 1024)
                        if not ok_full then
                            UIManager:show(InfoMessage:new{text=_("Não foi possível baixar a capa escolhida.")})
                            return
                        end
                        local ui = self.ui or ReaderUI.instance
                        local applied = false
                        if ui and ui.bookinfo and ui.bookinfo.setCustomCoverFromImage then
                            applied = pcall(ui.bookinfo.setCustomCoverFromImage, ui.bookinfo, file, out)
                        else
                            local ok_fm, fm_info = pcall(require, "apps/filemanager/filemanager").instance
                            if ok_fm and fm_info and fm_info.bookinfo and fm_info.bookinfo.setCustomCoverFromImage then
                                applied = pcall(fm_info.bookinfo.setCustomCoverFromImage, fm_info.bookinfo, file, out)
                            end
                        end
                        pcall(os.remove, out)
                        if applied then
                            UIManager:broadcastEvent(require("ui/event"):new("InvalidateMetadataCache", file))
                            if self._last_menu then refresh(self._last_menu) end
                            UIManager:show(InfoMessage:new{text=_("Capa aplicada.")})
                        else
                            UIManager:show(InfoMessage:new{text=_("Não foi possível aplicar esta capa nesta tela.")})
                        end
                    end,
                }
                if i % cols == 1 then
                    buttons[#buttons+1] = {button}
                else
                    buttons[#buttons] = buttons[#buttons] or {}
                    buttons[#buttons+1] = button
                end
            end
        end

        -- Fix row construction if an odd number of previews was downloaded.
        local normalized = {}
        for _, row in ipairs(buttons) do
            if row.text or row.icon then
                normalized[#normalized+1] = {row}
            else
                normalized[#normalized+1] = row
            end
        end

        if #normalized == 0 then
            cleanup()
            UIManager:show(InfoMessage:new{text=_("As prévias das capas não puderam ser carregadas.")})
            return
        end

        normalized[#normalized+1] = {{text=_("Cancelar"),icon="exit",callback=function()
            closeIf(dialog)
            cleanup()
        end}}

        dialog = ButtonDialog:new{
            title=_("Google Imagens · escolher capa"),
            title_align="center",
            buttons=normalized,
            shrink_unneeded_width=true,
        }
        dialog.onCloseWidget = function(self_dialog)
            cleanup()
        end
        UIManager:show(dialog)
    end


    function BV:markSimpleUIActive()
        if self._bookvault_sui_action then return true end
        local action_id, tabs = findSimpleUIBookVaultAction()
        if not action_id then return false end
        local fm = package.loaded["apps/filemanager/filemanager"]
        local fm_instance = fm and fm.instance
        local sui = fm_instance and fm_instance._simpleui_plugin
        if not sui then
            local rui = package.loaded["apps/reader/readerui"]
            sui = rui and rui.instance and rui.instance.simpleui
        end
        local ok_bb, BB = pcall(require, "screens/sui_bottombar")
        if not sui or not ok_bb or not BB or not BB.setTempTabActive then return false end
        self._bookvault_sui_action = action_id
        self._bookvault_sui_prev_action = sui.active_action
        self._bookvault_sui_plugin = sui
        pcall(BB.setTempTabActive, sui, action_id, true, self._bookvault_sui_prev_action)
        return true
    end

    function BV:restoreSimpleUIActive()
        local action_id = self._bookvault_sui_action
        local sui = self._bookvault_sui_plugin
        if not action_id or not sui then return end
        local prev = self._bookvault_sui_prev_action
        local ok_bb, BB = pcall(require, "screens/sui_bottombar")
        if ok_bb and BB and BB.setTempTabActive then
            pcall(BB.setTempTabActive, sui, action_id, false, prev)
        end
        self._bookvault_sui_action = nil
        self._bookvault_sui_prev_action = nil
        self._bookvault_sui_plugin = nil
    end

    function BV:closeBookVault(menu)
        if menu then UIManager:close(menu) end
    end

    -- Scope all interactions to the menu instance returned by BookVault.    -- Scope all interactions to the menu instance returned by BookVault.
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
