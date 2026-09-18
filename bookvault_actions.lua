-- BookVault 3.x action and interaction layer.
-- Kept scoped to BookVault-created menus: no global KOReader monkey patches.

-- Keep this action layer out of the plugin bootstrap: load it only when
-- BookVault is actually used. This prevents a missing optional dependency
-- from hiding the whole plugin from KOReader.
local M = {}

local logger = require("logger")
local _ = require("gettext")

local function safeRequire(module_name)
    local ok, module = pcall(require, module_name)
    if ok and module then return module end
    logger.warn("BookVault: action dependency unavailable:", module_name, module)
    return nil
end

local ButtonDialog = safeRequire("ui/widget/buttondialog")
local ConfirmBox = safeRequire("ui/widget/confirmbox")
local InfoMessage = safeRequire("ui/widget/infomessage")
local InputDialog = safeRequire("ui/widget/inputdialog")
local PathChooser = safeRequire("ui/widget/pathchooser")
local UIManager = safeRequire("ui/uimanager")
local BookList = safeRequire("ui/widget/booklist")
local DocSettings = safeRequire("docsettings")
local ReadCollection = safeRequire("readcollection")
local DataStorage = safeRequire("datastorage")
local ffiUtil = safeRequire("ffi/util")
local lfs = safeRequire("libs/libkoreader-lfs")
local util = safeRequire("util")
local filemanagerutil = safeRequire("apps/filemanager/filemanagerutil")
local T = ffiUtil and ffiUtil.template
local N_ = _ .ngettext
local T = ffiUtil.template
local N_ = _.ngettext

local M = {}

local function getReaderUI()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok and ReaderUI then return ReaderUI end
    logger.warn("BookVault: ReaderUI unavailable for this action")
    return nil
end

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
    -- Native BookVault Quick Action registered through Simple UI's public
    -- registry. It avoids the context-sensitive plugin-key lookup used by
    -- older persisted custom actions.
    local ok_qa, QA = pcall(require, "features/sui_quickactions")
    if ok_qa and QA and type(QA.getEntry) == "function" then
        for _, action_id in ipairs(tabs) do
            if action_id == "bookvault" then
                local entry = QA.getEntry("bookvault")
                if entry and entry.label == "BookVault" then
                    return "bookvault", tabs
                end
            end
        end
    end
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

    -- Simple UI registration is performed from the live plugin instance
    -- (not from the class table). This matters on Homescreen: the action
    -- must capture the same BookVault instance that owns the live UI.
    function BV:registerSimpleUIAction()
        if self._bookvault_sui_registered then return true end

        local ok_qa, QA = pcall(require, "features/sui_quickactions")
        if not ok_qa or type(QA) ~= "table" or type(QA.register) ~= "function" then
            return false
        end

        pcall(require, "bookvault_icons_bootstrap")
        local descriptor = {
            id = "bookvault",
            label = _("BookVault"),
            icon = "bookvault-cat",
            is_in_place = false,
            execute = function()
                self:showStatusChooser()
            end,
        }
        local ok, err = pcall(QA.register, descriptor)
        if not ok then
            logger.warn("BookVault: Simple UI action registration failed", err)
            return false
        end

        self._bookvault_sui_registered = true
        -- Only migrate the old persisted action after the native action is
        -- actually registered. This prevents an unavailable native action
        -- from deleting the only working legacy entry.
        pcall(self.migrateLegacySimpleUIActions, self)
        return true
    end

    function BV:registerSimpleUIWithRetry()
        if self:registerSimpleUIAction() then return true end
        if self._bookvault_sui_retry then return false end

        self._bookvault_sui_retry = true
        local attempts = 0
        local function retry()
            self._bookvault_sui_retry = false
            attempts = attempts + 1
            if self:registerSimpleUIAction() or attempts >= 5 then return end
            self._bookvault_sui_retry = true
            UIManager:scheduleIn(2, retry)
        end
        UIManager:scheduleIn(0, retry)
        return false
    end

    -- Migrate the old persisted Simple UI "plugin_key=bookvault" action to
    -- the native registered action. Keep its position in the bottom bar and
    -- Homescreen QA slots so the user does not have to recreate the action.
    -- Only entries that explicitly target BookVault are touched.
    function BV:migrateLegacySimpleUIActions()
        local ok_qa, QA = pcall(require, "features/sui_quickactions")
        if not ok_qa or type(QA) ~= "table" or type(QA.getCustomQAList) ~= "function"
                or type(QA.getCustomQAConfig) ~= "function"
                or type(QA.deleteCustomQA) ~= "function" then
            return false
        end

        local ok_store, Store = pcall(require, "infra/sui_store")
        if not ok_store or not Store or type(Store.get) ~= "function"
                or type(Store.set) ~= "function" then
            return false
        end

        local legacy_ids = {}
        for _, id in ipairs(QA.getCustomQAList() or {}) do
            local cfg = QA.getCustomQAConfig(id)
            local key = tostring(cfg.plugin_key or ""):lower()
            local label = tostring(cfg.label or ""):lower()
            if key == "bookvault" or key:match("bookvault") or label == "bookvault" then
                legacy_ids[#legacy_ids + 1] = id
            end
        end
        if #legacy_ids == 0 then return false end

        local changed = false
        local legacy = {}
        for _, id in ipairs(legacy_ids) do legacy[id] = true end

        local function replace_ids(list)
            if type(list) ~= "table" then return list, false end
            local out, did_change = {}, false
            local native_seen = false
            for _, id in ipairs(list) do
                if legacy[id] then
                    if not native_seen then
                        out[#out + 1] = "bookvault"
                        native_seen = true
                    end
                    did_change = true
                elseif id == "bookvault" then
                    if not native_seen then
                        out[#out + 1] = id
                        native_seen = true
                    else
                        did_change = true
                    end
                else
                    out[#out + 1] = id
                end
            end
            return out, did_change
        end

        local tabs = Store:get("simpleui_bar_tabs")
        local new_tabs, tabs_changed = replace_ids(tabs)
        if tabs_changed then Store:set("simpleui_bar_tabs", new_tabs); changed = true end

        for slot = 1, 3 do
            local key = "simpleui_hs_qa_" .. slot .. "_items"
            local items = Store:get(key)
            local new_items, items_changed = replace_ids(items)
            if items_changed then Store:set(key, new_items); changed = true end
        end

        -- Replace legacy IDs inside Quick Action groups before deleting them.
        for _, group_id in ipairs(QA.getCustomQAList() or {}) do
            local items = QA.getQAFolderItems and QA.getQAFolderItems(group_id)
            local new_items, items_changed = replace_ids(items)
            if items_changed and QA.saveQAFolderItems then
                QA.saveQAFolderItems(group_id, new_items)
                changed = true
            end
        end

        for _, id in ipairs(legacy_ids) do
            pcall(QA.deleteCustomQA, id)
            changed = true
        end

        if changed then
            local mqa = package.loaded["modules/module_quick_actions"]
            if mqa and mqa.invalidateCustomQACache then pcall(mqa.invalidateCustomQACache) end
            local plugin = package.loaded["screens/sui_homescreen"]
            if plugin and plugin._rebuildAllNavbars then pcall(plugin._rebuildAllNavbars, plugin) end
            local ok_engine, ScreenEngine = pcall(require, "engines/sui_screen_engine")
            if ok_engine and ScreenEngine and ScreenEngine.refreshAllLiveImmediate then
                pcall(ScreenEngine.refreshAllLiveImmediate, false)
            end
        end
        return changed
    end

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
        local ReaderUI = getReaderUI()
        local rui = ReaderUI and ReaderUI.instance
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
                        if self.invalidateLibraryCache then self:invalidateLibraryCache() end
                        if self.invalidateBookMetadataCache then self:invalidateBookMetadataCache(file); self:invalidateBookMetadataCache(dest) end
                        if self.invalidateStatusCache then self:invalidateStatusCache(file); self:invalidateStatusCache(dest) end
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
                if changed > 0 and owner.invalidateLibraryCache then
                    owner:invalidateLibraryCache()
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
                    if self.invalidateBookMetadataCache then self:invalidateBookMetadataCache(file) end
                    if self.invalidateStatusCache then self:invalidateStatusCache(file) end
                end
                pcall(ReadCollection.write, ReadCollection)
                pcall(function() require("readhistory"):clearMissing() end)
                if failed > 0 then
                    UIManager:show(InfoMessage:new{
                        text = T(_("%1 arquivo(s) não puderam ser excluídos."), failed),
                    })
                end
                if menu then
                    self:invalidateLibraryCache()
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
            if self.invalidateStatusCache then self:invalidateStatusCache(first) end
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
            self._bookvault_status_cache = self._bookvault_status_cache or {}
            self._bookvault_status_cache[file] = status
            if saved then ds = saved end
        end
        -- Batch status changes invalidate the derived category index once,
        -- rather than forcing every selected file to rebuild it.
        self._bookvault_status_index = nil
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
        -- "Mais ações" is intentionally a direct gateway to plugin actions.
        -- Copy/Move remain primary batch actions and are not duplicated here.
        self:showPluginActions(menu, item)
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
                self:searchGoogleImagesForCover(item.path)
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
        -- Explicit, user-triggered cover search. No background scans.
        -- Uses structured book APIs instead of scraping Google Images HTML.
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local socketutil = require("socketutil")
        local urlmod = require("socket.url")
        local JSON = require("json")
        local mime = require("mime")
        local Screen = require("device").screen
        local Event = require("ui/event")

        local https_ok, https = pcall(require, "ssl.https")
        local function request(req)
            if req.url and req.url:match("^https://") and https_ok then
                return https.request(req)
            end
            return http.request(req)
        end

        local props = getProps(self, file)
        local title = props.title or props.display_title or basename(file):gsub("%.[^%.]+$", "")
        local authors = props.authors or props.author or ""
        if type(authors) == "table" then
            local names = {}
            for _, author in ipairs(authors) do
                if type(author) == "string" and author ~= "" then names[#names + 1] = author end
            end
            authors = table.concat(names, " ")
        end
        title = tostring(title or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        authors = tostring(authors or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

        local function firstIdentifier(value)
            if type(value) == "string" then
                local cleaned = value:gsub("[^%dXx]", "")
                if #cleaned >= 10 then return cleaned end
            elseif type(value) == "table" then
                for _, v in ipairs(value) do
                    local found = firstIdentifier(v)
                    if found then return found end
                end
                for _, v in pairs(value) do
                    local found = firstIdentifier(v)
                    if found then return found end
                end
            end
            return nil
        end

        local isbn = firstIdentifier(props.isbn13)
            or firstIdentifier(props.isbn_13)
            or firstIdentifier(props.isbn10)
            or firstIdentifier(props.isbn_10)
            or firstIdentifier(props.isbn)
        if not isbn and type(props.identifiers) == "table" then
            isbn = firstIdentifier(props.identifiers.isbn13)
                or firstIdentifier(props.identifiers.isbn_13)
                or firstIdentifier(props.identifiers.isbn10)
                or firstIdentifier(props.identifiers.isbn_10)
                or firstIdentifier(props.identifiers.isbn)
        end

        if title == "" then
            UIManager:show(InfoMessage:new{ text = _("Não foi possível determinar o título do livro.") })
            return
        end

        local language = props.language
        if type(language) == "table" then language = language[1] end
        language = type(language) == "string" and language:lower() or nil

        local function normalizeText(value)
            return tostring(value or ""):lower()
                :gsub("[^%w%s]", " ")
                :gsub("%s+", " ")
                :gsub("^%s+", "")
                :gsub("%s+$", "")
        end

        local wanted_title = normalizeText(title)
        local wanted_author = normalizeText(authors)
        local wanted_isbn = isbn and isbn:gsub("[^%dXx]", "") or nil

        local function scoreCandidate(candidate)
            local score = 0
            local candidate_title = normalizeText(candidate.title)
            local candidate_authors = normalizeText(candidate.authors)
            local candidate_isbn = candidate.isbn and candidate.isbn:gsub("[^%dXx]", "") or nil

            if wanted_isbn and candidate_isbn and wanted_isbn == candidate_isbn then
                score = score + 120
            end
            if candidate_title ~= "" and candidate_title == wanted_title then
                score = score + 80
            elseif candidate_title ~= "" and wanted_title ~= "" then
                if candidate_title:find(wanted_title, 1, true) or wanted_title:find(candidate_title, 1, true) then
                    score = score + 45
                end
            end
            if wanted_author ~= "" and candidate_authors ~= "" then
                if candidate_authors:find(wanted_author, 1, true) or wanted_author:find(candidate_authors, 1, true) then
                    score = score + 45
                end
            end
            if language and candidate.language and candidate.language:lower():find(language, 1, true) then
                score = score + 10
            end
            if candidate.source == "openlibrary" then score = score + 5 end
            return score
        end

        local function requestJSON(endpoint)
            local sink = {}
            socketutil:set_timeout(5, 12)
            local ok, success, code, headers, status = pcall(function()
                return request{
                    url = endpoint,
                    method = "GET",
                    headers = {
                        ["User-Agent"] = "BookVault/3.4 (KOReader)",
                        ["Accept"] = "application/json",
                        ["Accept-Encoding"] = "identity",
                    },
                    sink = ltn12.sink.table(sink),
                }
            end)
            socketutil:reset_timeout()
            if not ok or success ~= 1 or tonumber(code) ~= 200 then
                return nil
            end
            local body = table.concat(sink)
            if body == "" or #body > 700 * 1024 then return nil end
            local decoded_ok, data = pcall(JSON.decode, body)
            if decoded_ok and type(data) == "table" then return data end
            return nil
        end

        local candidates, seen = {}, {}
        local function addCandidate(candidate)
            if type(candidate) ~= "table" or type(candidate.preview) ~= "string" or candidate.preview == "" then
                return
            end
            candidate.original = candidate.original or candidate.preview
            candidate.key = candidate.key or candidate.preview
            if seen[candidate.key] then return end
            candidate.score = scoreCandidate(candidate)
            seen[candidate.key] = true
            candidates[#candidates + 1] = candidate
        end

        local ol_query
        if isbn then
            ol_query = "isbn:" .. isbn
        else
            ol_query = title
            if authors ~= "" then ol_query = ol_query .. " " .. authors end
        end
        local ol_url = "https://openlibrary.org/search.json?q=" .. urlmod.escape(ol_query)
            .. "&limit=10&fields=key,title,author_name,cover_i,isbn,language,edition_key"

        local ol_data = requestJSON(ol_url)
        if ol_data and type(ol_data.docs) == "table" then
            for _, doc in ipairs(ol_data.docs) do
                if type(doc) == "table" and doc.cover_i then
                    local doc_isbn = firstIdentifier(doc.isbn)
                    local cover_id = tostring(doc.cover_i)
                    addCandidate{
                        source = "openlibrary",
                        title = doc.title,
                        authors = type(doc.author_name) == "table" and table.concat(doc.author_name, " ") or doc.author_name,
                        language = type(doc.language) == "table" and doc.language[1] or doc.language,
                        isbn = doc_isbn,
                        preview = "https://covers.openlibrary.org/b/id/" .. cover_id .. "-M.jpg?default=false",
                        original = "https://covers.openlibrary.org/b/id/" .. cover_id .. "-L.jpg?default=false",
                        key = "ol:" .. cover_id,
                    }
                end
            end
        end

        local gb_query
        if isbn then
            gb_query = "isbn:" .. isbn
        else
            gb_query = "intitle:" .. title
            if authors ~= "" then gb_query = gb_query .. " inauthor:" .. authors end
        end
        local gb_url = "https://www.googleapis.com/books/v1/volumes?q=" .. urlmod.escape(gb_query)
            .. "&maxResults=10&printType=books"

        local gb_data = requestJSON(gb_url)
        if gb_data and type(gb_data.items) == "table" then
            for _, item in ipairs(gb_data.items) do
                local info = type(item) == "table" and item.volumeInfo or nil
                local images = info and info.imageLinks or nil
                if type(info) == "table" and type(images) == "table" then
                    local preview = images.smallThumbnail or images.thumbnail or images.small or images.medium
                    local original = images.extraLarge or images.large or images.medium or images.small or images.thumbnail
                    if preview and original then
                        local identifiers = {}
                        for _, identifier in ipairs(info.industryIdentifiers or {}) do
                            if type(identifier) == "table" and identifier.identifier then
                                identifiers[#identifiers + 1] = identifier.identifier
                            end
                        end
                        addCandidate{
                            source = "googlebooks",
                            title = info.title,
                            authors = type(info.authors) == "table" and table.concat(info.authors, " ") or info.authors,
                            language = info.language,
                            isbn = firstIdentifier(identifiers),
                            preview = preview,
                            original = original,
                            key = "gb:" .. tostring(item.id or preview),
                        }
                    end
                end
            end
        end

        table.sort(candidates, function(a, b)
            if a.score == b.score then
                return (a.source or "") < (b.source or "")
            end
            return a.score > b.score
        end)

        local found_candidates = {}
        for _, candidate in ipairs(candidates) do
            found_candidates[#found_candidates + 1] = candidate
            if #found_candidates >= 6 then break end
        end

        if #found_candidates == 0 then
            UIManager:show(InfoMessage:new{
                text = _("Nenhuma capa foi encontrada. Verifique a conexão e tente novamente."),
            })
            return
        end

        local base = DataStorage:getDataDir() .. "/bookvault/covers"
        pcall(util.makePath, base)
        local temp_files = {}

        local function cleanup()
            for _, path in ipairs(temp_files) do pcall(os.remove, path) end
            temp_files = {}
        end

        local function requestToFile(target_url, output, max_bytes)
            if type(target_url) ~= "string" or not target_url:match("^https?://") then return false end
            local f = io.open(output, "wb")
            if not f then return false end
            local total = 0
            local sink = function(chunk)
                if not chunk then
                    f:close()
                    return 1
                end
                total = total + #chunk
                if total > max_bytes then
                    f:close()
                    return nil, "response too large"
                end
                if not f:write(chunk) then
                    f:close()
                    return nil, "write failed"
                end
                return 1
            end
            socketutil:set_timeout(5, 12)
            local ok, success, code = pcall(function()
                return request{
                    url = target_url,
                    method = "GET",
                    headers = {
                        ["User-Agent"] = "BookVault/3.4 (KOReader)",
                        ["Accept"] = "image/jpeg,image/png,image/webp,image/*;q=0.8,*/*;q=0.5",
                        ["Accept-Encoding"] = "identity",
                    },
                    sink = sink,
                }
            end)
            socketutil:reset_timeout()
            pcall(f.close, f)
            if not ok or success ~= 1 or tonumber(code) ~= 200 or total <= 0 then
                pcall(os.remove, output)
                return false
            end
            return true
        end

        local function makePreviewIcon(raw_path, index)
            local f = io.open(raw_path, "rb")
            if not f then return nil end
            local data = f:read("*a")
            f:close()
            if not data or #data == 0 or #data > 180 * 1024 then return nil end

            local mime_type
            if data:sub(1, 3) == "\255\216\255" then
                mime_type = "image/jpeg"
            elseif data:sub(1, 8) == "\137PNG\r\n\26\n" then
                mime_type = "image/png"
            elseif data:sub(1, 4) == "GIF8" then
                mime_type = "image/gif"
            elseif data:sub(1, 12):sub(9, 12) == "WEBP" and data:sub(1, 4) == "RIFF" then
                mime_type = "image/webp"
            end
            if not mime_type then return nil end

            local encoded = mime.b64(data)
            local icon_name = "bookvault-cover-preview-" .. tostring(os.time()) .. "-" .. tostring(index)
            local icon_path = DataStorage:getDataDir() .. "/icons/" .. icon_name .. ".svg"
            local svg = string.format(
                '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="300" height="400" viewBox="0 0 300 400"><rect width="300" height="400" fill="white"/><image x="0" y="0" width="300" height="400" preserveAspectRatio="xMidYMid meet" href="data:%s;base64,%s" xlink:href="data:%s;base64,%s"/></svg>',
                mime_type, encoded, mime_type, encoded)
            local out = io.open(icon_path, "wb")
            if not out then return nil end
            out:write(svg)
            out:close()
            pcall(os.remove, raw_path)
            temp_files[#temp_files + 1] = icon_path
            return icon_name
        end

        local found = {}
        for i, candidate in ipairs(found_candidates) do
            if #found >= 6 then break end
            local thumb_path = base .. "/preview_" .. tostring(os.time()) .. "_" .. tostring(i) .. ".img"
            if requestToFile(candidate.preview, thumb_path, 140 * 1024) then
                local icon_name = makePreviewIcon(thumb_path, i)
                if icon_name then
                    found[#found + 1] = {candidate = candidate, icon = icon_name}
                else
                    pcall(os.remove, thumb_path)
                end
            end
        end

        if #found == 0 then
            cleanup()
            UIManager:show(InfoMessage:new{
                text = _("As capas foram encontradas, mas nenhuma prévia pôde ser carregada."),
            })
            return
        end

        local dialog
        local rows = {}
        local current_row
        for i, result in ipairs(found) do
            if not current_row or #current_row >= 2 then
                current_row = {}
                rows[#rows + 1] = current_row
            end
            current_row[#current_row + 1] = {
                text = tostring(i),
                icon = result.icon,
                icon_width = math.min(Screen:scaleBySize(150), math.floor(Screen:getWidth() / 2) - Screen:scaleBySize(30)),
                icon_height = Screen:scaleBySize(200),
                callback = function()
                    closeIf(dialog)
                    cleanup()

                    local selected = result.candidate
                    local out = base .. "/selected_" .. tostring(os.time()) .. "_" .. tostring(i) .. ".img"
                    local ok_full = requestToFile(selected.original, out, 6 * 1024 * 1024)
                    if not ok_full then
                        UIManager:show(InfoMessage:new{ text = _("Não foi possível baixar a capa escolhida.") })
                        return
                    end

                    local fm = require("apps/filemanager/filemanager").instance
                    local rui = ReaderUI.instance
                    local bookinfo = (fm and fm.bookinfo) or (rui and rui.bookinfo)
                    local applied = false
                    if bookinfo and bookinfo.setCustomCoverFromImage then
                        local call_ok = pcall(bookinfo.setCustomCoverFromImage, bookinfo, file, out)
                        applied = call_ok and DocSettings:findCustomCoverFile(file) ~= nil
                    end
                    pcall(os.remove, out)

                    if not applied then
                        UIManager:show(InfoMessage:new{ text = _("Não foi possível aplicar esta capa nesta tela.") })
                        return
                    end

                    if self.invalidateBookMetadataCache then self:invalidateBookMetadataCache(file) end
                    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
                    UIManager:broadcastEvent(Event:new("BookMetadataChanged", file))
                    if self._last_menu then refresh(self._last_menu) end
                    UIManager:show(InfoMessage:new{ text = _("Capa aplicada.") })
                end,
            }
        end

        rows[#rows + 1] = {{
            text = _("Cancelar"),
            icon = "close",
            callback = function()
                closeIf(dialog)
                cleanup()
            end,
        }}

        dialog = ButtonDialog:new{
            title = _("Escolher capa"),
            title_align = "center",
            buttons = rows,
            shrink_unneeded_width = true,
        }
        dialog.onCloseWidget = function()
            cleanup()
        end
        UIManager:show(dialog)
    end

    -- Keep the old entry point as a compatibility alias for any existing
    -- menu or saved callback that still refers to its previous name.
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