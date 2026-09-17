-- BookVault action fix layer.
-- Attaches to BookVault-created BookList instances only.
-- The constructor bridge is deliberately scoped by the BookVault UI instance.

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local PathChooser = require("ui/widget/pathchooser")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local BookList = require("ui/widget/booklist")
local DocSettings = require("docsettings")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local ReadCollection = require("readcollection")
local _ = require("gettext")
local logger = require("logger")

local M = {}

local function safe(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        logger.err("BookVault action fix:", err)
        UIManager:show(InfoMessage:new{ text = _("BookVault encontrou um erro e não conseguiu concluir a ação.") })
    end
    return ok
end

local function basename(path)
    return ffiUtil.basename(path) or path or ""
end

local function sizeOf(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function refresh(menu)
    if not menu then return end
    if menu.updateItems then pcall(menu.updateItems, menu, 1, true) end
end

local function getProps(item)
    local file = item and item.path
    if not file then return {} end
    local ui = item._bookvault_ui
    if ui and ui.bookinfo and ui.bookinfo.getDocProps then
        local ok, props = pcall(ui.bookinfo.getDocProps, ui.bookinfo, file)
        if ok and type(props) == "table" then return props end
    end
    return {}
end

local function getInfo(file)
    local info = BookList.getBookInfo(file) or {}
    local doc = {}
    if DocSettings:hasSidecarFile(file) then
        local ok, ds = pcall(DocSettings.open, DocSettings, file)
        if ok and ds then
            doc = ds:readSetting("summary") or {}
            info.pages = info.pages or ds:readSetting("doc_pages")
        end
    end
    return info, doc
end

function M.showBookInfo(owner, menu, item)
    local ui = owner.ui
    local file = item.path
    local props = getProps(setmetatable({ _bookvault_ui = ui }, { __index = item }))
    local info, summary = getInfo(file)

    -- Use KOReader's native BookInfo screen when available: it already knows how
    -- to render cover, metadata and progress safely for the running KOReader build.
    if ui and ui.bookinfo and ui.bookinfo.show then
        local ok = pcall(function()
            ui.bookinfo:show(DocSettings:hasSidecarFile(file) and DocSettings:open(file) or file,
                next(props) and ui.bookinfo.extendProps(props) or nil)
        end)
        if ok then return end
    end

    local attr = lfs.attributes(file) or {}
    local ext = util.getFileNameSuffix(file) or ""
    local title = props.display_title or props.title or item.text or basename(file)
    local authors = props.authors or props.author or _("Não informado")
    local series = props.series or _("Não informado")
    local series_index = props.series_index and tostring(props.series_index) or _("Não informado")
    local genre = props.genre or props.subject or _("Não informado")
    local language = props.language or _("Não informado")
    local tags = props.keywords or props.tags or _("Não informado")
    local pages = info.pages or props.pages or _("Não informado")
    local progress = info.percent_finished and string.format("%.0f%%", info.percent_finished * 100) or _("Não iniciado")
    local status = BookList.getBookStatusString(info.status or "new", true) or _("Não iniciado")
    local added = attr.creation and os.date("%d/%m/%Y %H:%M", attr.creation) or _("Não informado")
    local modified = attr.modification and os.date("%d/%m/%Y %H:%M", attr.modification) or _("Não informado")
    local accessed = attr.access and os.date("%d/%m/%Y %H:%M", attr.access) or _("Não informado")
    local text = table.concat({
        _("Título: ") .. tostring(title),
        _("Autor: ") .. tostring(authors),
        _("Série: ") .. tostring(series),
        _("Número da série: ") .. tostring(series_index),
        _("Gênero: ") .. tostring(genre),
        _("Idioma: ") .. tostring(language),
        _("Tags: ") .. tostring(tags),
        _("Status: ") .. tostring(status),
        _("Progresso: ") .. tostring(progress),
        _("Página atual/total: ") .. tostring(info.pages_read or _("Não informado")) .. " / " .. tostring(pages),
        _("Tamanho: ") .. util.getFriendlySize(attr.size or 0),
        _("Formato: ") .. string.upper(ext),
        _("Data: ") .. tostring(added),
        _("Modificado: ") .. tostring(modified),
        _("Último acesso: ") .. tostring(accessed),
        _("Pasta/localização: ") .. tostring(file),
    }, "\n")
    UIManager:show(TextViewer:new{ title = _("Informações do livro"), text = text })
end

function M.setStatus(owner, menu, files, status)
    local list = {}
    for path in pairs(files or {}) do list[path] = true end
    if next(list) == nil then return end
    UIManager:show(ConfirmBox:new{
        text = sizeOf(list) == 1 and _("Alterar o status deste livro?") or _("Alterar o status dos livros selecionados?"),
        ok_text = _("Alterar"),
        ok_callback = function()
            for file in pairs(list) do
                local ds = BookList.getDocSettings(file)
                local summary = ds:readSetting("summary") or {}
                summary.status = status
                filemanagerutil.saveSummary(ds, summary)
                BookList.setBookInfoCacheProperty(file, "status", status)
            end
            refresh(menu)
        end,
    })
end

function M.showStatus(owner, menu, files)
    local list = {}
    for path in pairs(files or {}) do list[path] = true end
    local buttons = {}
    local statuses = {
        { "reading", _("Lendo") },
        { "abandoned", _("Em espera") },
        { "complete", _("Concluídos") },
    }
    for _, status in ipairs(statuses) do
        buttons[#buttons + 1] = {{ text = status[2], callback = function()
            UIManager:close(owner._bookvault_status_dialog)
            owner._bookvault_status_dialog = nil
            M.setStatus(owner, menu, list, status[1])
        end }}
    end
    buttons[#buttons + 1] = {{ text = _("Não iniciados"), callback = function()
        UIManager:close(owner._bookvault_status_dialog)
        owner._bookvault_status_dialog = nil
        for file in pairs(list) do
            local ds = BookList.getDocSettings(file)
            ds:purge(nil, { doc_settings = false })
            BookList.setBookInfoCacheProperty(file, "been_opened", false)
            BookList.setBookInfoCacheProperty(file, "status", nil)
        end
        refresh(menu)
    end }}
    buttons[#buttons + 1] = {{ text = _("Cancelar"), callback = function()
        UIManager:close(owner._bookvault_status_dialog)
        owner._bookvault_status_dialog = nil
    end }}
    owner._bookvault_status_dialog = ButtonDialog:new{ title = _("Status de leitura"), title_align = "center", buttons = buttons }
    UIManager:show(owner._bookvault_status_dialog)
end

function M.showCollections(owner, menu, files)
    local names = {}
    for name in pairs(ReadCollection.coll or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    local list = {}
    for path in pairs(files or {}) do list[path] = true end
    local buttons = {}
    for _, name in ipairs(names) do
        local all_checked = true
        for path in pairs(list) do
            if not ReadCollection:isFileInCollection(path, name) then all_checked = false; break end
        end
        buttons[#buttons + 1] = {{
            text = (all_checked and "☑ " or "☐ ") .. name,
            callback = function()
                for path in pairs(list) do
                    local current = ReadCollection:isFileInCollection(path, name)
                    local map = {}
                    for n in pairs(ReadCollection.coll or {}) do map[n] = ReadCollection:isFileInCollection(path, n) end
                    map[name] = not current
                    ReadCollection:addRemoveItemMultiple(path, map)
                end
                ReadCollection:write()
                UIManager:close(owner._bookvault_collection_dialog)
                owner._bookvault_collection_dialog = nil
                M.showCollections(owner, menu, list)
                refresh(menu)
            end,
        }}
    end
    buttons[#buttons + 1] = {{ text = _("Nova coleção"), callback = function()
        -- Keep the existing BookVault collection creator when available.
        local first = next(list)
        if first then
            UIManager:close(owner._bookvault_collection_dialog)
            owner._bookvault_collection_dialog = nil
            owner:showCollectionsForBook({ path = first, text = basename(first) }, menu)
        end
    end }}
    buttons[#buttons + 1] = {{ text = _("Concluído"), callback = function()
        UIManager:close(owner._bookvault_collection_dialog)
        owner._bookvault_collection_dialog = nil
        refresh(menu)
    end }}
    owner._bookvault_collection_dialog = ButtonDialog:new{ title = _("Coleções"), title_align = "center", buttons = buttons }
    UIManager:show(owner._bookvault_collection_dialog)
end

function M.copyMove(owner, menu, files, move)
    local list = {}
    for path in pairs(files or {}) do list[#list + 1] = path end
    if #list == 0 then return end
    UIManager:show(PathChooser:new{
        select_directory = true,
        select_file = false,
        onConfirm = function(dir)
            if not dir then return end
            local failed = 0
            for _, path in ipairs(list) do
                local dest = dir .. "/" .. basename(path)
                if not lfs.attributes(dest) then
                    local ok
                    if move then
                        ok = os.rename(path, dest)
                        if ok then
                            pcall(function() ReadCollection:updateItem(path, dest) end)
                            pcall(function() require("readhistory"):updateItem(path, dest) end)
                        end
                    else
                        ok = ffiUtil.copyFile(path, dest)
                    end
                    if not ok then failed = failed + 1 end
                else
                    failed = failed + 1
                end
            end
            pcall(ReadCollection.write, ReadCollection)
            if failed > 0 then
                UIManager:show(InfoMessage:new{ text = string.format(_("%d arquivo(s) não puderam ser processados."), failed) })
            end
            owner:leaveSelection(menu)
            refresh(menu)
        end,
    })
end

function M.delete(owner, menu, files)
    local list = {}
    for path in pairs(files or {}) do list[path] = true end
    local n = sizeOf(list)
    if n == 0 then return end
    UIManager:show(ConfirmBox:new{
        text = n == 1 and _("Excluir este livro?") or string.format(_("Excluir %d livros?"), n),
        ok_text = _("Excluir"),
        ok_callback = function()
            for path in pairs(list) do
                if os.remove(path) then
                    pcall(function() ReadCollection:removeItem(path, nil, true) end)
                end
            end
            pcall(ReadCollection.write, ReadCollection)
            owner:leaveSelection(menu)
            if menu._bookvault_source_items then
                menu._bookvault_source_items = owner:scanBooks(owner:privacyIncludePrivate())
                menu.item_table = menu._bookvault_source_items
            end
            refresh(menu)
        end,
    })
end

function M.enterSelection(owner, menu, item)
    menu._bookvault_selection_mode = true
    menu._bookvault_selected = {}
    if item and item.path then menu._bookvault_selected[item.path] = true end
    if menu.setTitleBarLeftIcon then pcall(menu.setTitleBarLeftIcon, menu, "check") end
    M.updateSelection(owner, menu)
end

function M.toggleSelection(owner, menu, item)
    if not item or not item.path then return end
    menu._bookvault_selected = menu._bookvault_selected or {}
    if menu._bookvault_selected[item.path] then
        menu._bookvault_selected[item.path] = nil
        item.dim = nil
    else
        menu._bookvault_selected[item.path] = true
        item.dim = true
    end
    M.updateSelection(owner, menu)
end

function M.leaveSelection(owner, menu)
    menu._bookvault_selection_mode = false
    menu._bookvault_selected = nil
    for _, item in ipairs(menu.item_table or {}) do item.dim = nil end
    if menu.setTitleBarLeftIcon then pcall(menu.setTitleBarLeftIcon, menu, "appbar.menu") end
    if menu._bookvault_selection_dialog then UIManager:close(menu._bookvault_selection_dialog); menu._bookvault_selection_dialog = nil end
    refresh(menu)
end

function M.updateSelection(owner, menu)
    if menu._bookvault_selection_dialog then UIManager:close(menu._bookvault_selection_dialog) end
    local selected = menu._bookvault_selected or {}
    local n = sizeOf(selected)
    if n == 0 then
        menu._bookvault_selection_dialog = ButtonDialog:new{ title = _("Nenhum livro selecionado"), buttons = {{ text = _("Sair da seleção"), callback = function() owner:leaveSelection(menu) end }} }
        UIManager:show(menu._bookvault_selection_dialog)
        refresh(menu)
        return
    end
    local buttons = {
        {{ text = _("Abrir livro"), callback = function() local p = next(selected); if p then UIManager:close(menu._bookvault_selection_dialog); filemanagerutil.openFile(owner.ui, p, function() owner:leaveSelection(menu) end) end end }},
        {{ text = _("Status de leitura"), callback = function() UIManager:close(menu._bookvault_selection_dialog); M.showStatus(owner, menu, selected) end }},
        {{ text = _("Coleções"), callback = function() UIManager:close(menu._bookvault_selection_dialog); M.showCollections(owner, menu, selected) end }},
        {{ text = _("Mover %d livros"):format(n), callback = function() UIManager:close(menu._bookvault_selection_dialog); M.copyMove(owner, menu, selected, true) end }},
        {{ text = _("Copiar %d livros"):format(n), callback = function() UIManager:close(menu._bookvault_selection_dialog); M.copyMove(owner, menu, selected, false) end }},
        {{ text = _("Excluir %d livros"):format(n), callback = function() UIManager:close(menu._bookvault_selection_dialog); M.delete(owner, menu, selected) end }},
        {{ text = _("Sair da seleção"), callback = function() owner:leaveSelection(menu) end }},
    }
    menu._bookvault_selection_dialog = ButtonDialog:new{ title = string.format(_("%d livro(s) selecionado(s)"), n), title_align = "center", buttons = buttons }
    UIManager:show(menu._bookvault_selection_dialog)
    refresh(menu)
end

function M.bookMenu(owner, menu, item)
    if not item or not item.path or not item.is_file then return true end
    if menu._bookvault_selection_mode then
        M.toggleSelection(owner, menu, item)
        return true
    end
    local buttons = {
        {{ text = _("Abrir livro"), callback = function()
            UIManager:close(owner._bookvault_action_dialog)
            filemanagerutil.openFile(owner.ui, item.path, function() end)
        end }},
        {{ text = _("Informações do livro"), callback = function()
            UIManager:close(owner._bookvault_action_dialog); M.showBookInfo(owner, menu, item)
        end }},
        {{ text = _("Status de leitura"), callback = function()
            UIManager:close(owner._bookvault_action_dialog); M.showStatus(owner, menu, {[item.path] = true})
        end }},
        {{ text = _("Coleções"), callback = function()
            UIManager:close(owner._bookvault_action_dialog); M.showCollections(owner, menu, {[item.path] = true})
        end }},
        {{ text = _("Editar capa/metadados"), callback = function()
            UIManager:close(owner._bookvault_action_dialog)
            if owner.showBookInfo then owner:showBookInfo(item) else M.showBookInfo(owner, menu, item) end
        end }},
        {{ text = _("Buscar capa no Google Imagens"), callback = function()
            UIManager:close(owner._bookvault_action_dialog)
            if owner.searchGoogleImagesForCover then owner:searchGoogleImagesForCover(item.path) end
        end }},
        {{ text = _("Selecionar vários"), callback = function() UIManager:close(owner._bookvault_action_dialog); M.enterSelection(owner, menu, item) end }},
        {{ text = _("Renomear"), callback = function() UIManager:close(owner._bookvault_action_dialog); owner:renameBook(item, menu) end }},
        {{ text = _("Copiar"), callback = function() UIManager:close(owner._bookvault_action_dialog); M.copyMove(owner, menu, {[item.path] = true}, false) end }},
        {{ text = _("Mover"), callback = function() UIManager:close(owner._bookvault_action_dialog); M.copyMove(owner, menu, {[item.path] = true}, true) end }},
        {{ text = _("Excluir"), callback = function() UIManager:close(owner._bookvault_action_dialog); M.delete(owner, menu, {[item.path] = true}) end }},
        {{ text = _("Abrir localização"), callback = function()
            UIManager:close(owner._bookvault_action_dialog)
            local dir = item.path:match("^(.*)/[^/]+$")
            if owner.ui and owner.ui.file_chooser and dir then owner.ui.file_chooser:changeToPath(dir, item.path) end
        end }},
        {{ text = _("Ações de plugins"), callback = function()
            UIManager:close(owner._bookvault_action_dialog)
            if owner.showPluginActions then owner:showPluginActions(menu, item) else UIManager:show(InfoMessage:new{ text = _("Nenhuma ação de plugin compatível foi encontrada.") }) end
        end }},
        {{ text = _("Cancelar"), callback = function() UIManager:close(owner._bookvault_action_dialog) end }},
    }
    owner._bookvault_action_dialog = ButtonDialog:new{ title = item.text or basename(item.path), title_align = "center", buttons = buttons }
    UIManager:show(owner._bookvault_action_dialog)
    return true
end

function M.decorate(owner, menu)
    if not menu or menu._bookvault_actions_fixed then return end
    menu._bookvault_actions_fixed = true
    local old_select = menu.onMenuSelect
    menu.onMenuSelect = function(m, item, pos)
        if m._bookvault_selection_mode then M.toggleSelection(owner, m, item); return true end
        return old_select and old_select(m, item, pos) or true
    end
    menu.onMenuHold = function(m, item, pos)
        return M.bookMenu(owner, m, item)
    end
    menu._bookvault_action_owner = owner
end

function M.install(owner)
    if owner._action_fix_installed then return end
    owner._action_fix_installed = true

    local old_show_info = owner.showBookInfo
    owner.showBookInfo = function(self, item)
        return M.showBookInfo(self, self.ui and self.ui.booklist_menu, item)
    end

    local old_leave = owner.leaveSelection
    owner.leaveSelection = function(self, menu)
        return M.leaveSelection(self, menu)
    end

    -- BookList is the concrete menu used by KOReader's mosaic/list implementations.
    -- The hook is scoped to the BookVault UI object and leaves all other BookLists untouched.
    local original_new = BookList.new
    if not owner._bookvault_booklist_bridge then
        owner._bookvault_booklist_bridge = true
        BookList.new = function(class, props, ...)
            local menu = original_new(class, props, ...)
            if props and props.ui == owner.ui then
                M.decorate(owner, menu)
            end
            return menu
        end
    end

    -- Decorate an already-created menu too (important when BookVault was opened before
    -- the action layer finished loading).
    local ui = owner.ui
    if ui and ui.booklist_menu then M.decorate(owner, ui.booklist_menu) end
end

return M
