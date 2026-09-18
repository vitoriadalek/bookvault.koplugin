local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local DocSettings = require("docsettings")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local KeyValuePage = require("ui/widget/keyvaluepage")
local UIManager = require("ui/uimanager")
local util = require("util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = require("ffi/util").template

local M = {}

local function formatProgress(value)
    if type(value) ~= "number" then return _("N/D") end
    return string.format("%.0f%%", math.max(0, math.min(100, value * 100)))
end

function M.show(ui, file, book_props)
    if not file then return end
    local native = FileManagerBookInfo:new{ui=ui}
    local attr = lfs.attributes(file)
    if not attr then
        UIManager:show(require("ui/widget/infomessage"):new{text=_("O arquivo não existe mais.")})
        return
    end

    local folder, filename = util.splitFilePathName(file)
    local _, filetype = filemanagerutil.splitFileNameType(filename)
    local size_f = util.getFriendlySize(attr.size or 0)
    local size_b = util.getFormattedSize(attr.size or 0)

    book_props = book_props or native:getDocProps(file, book_props)
    book_props = book_props or {}
    book_props.pages = book_props.pages or BookList.getBookInfo(file).pages

    local doc_settings
    local summary = {}
    local percent_finished
    local last_page
    if BookList.hasBookBeenOpened(file) then
        doc_settings = BookList.getDocSettings(file)
        summary = doc_settings:readSetting("summary") or {}
        percent_finished = doc_settings:readSetting("percent_finished")
        last_page = doc_settings:readSetting("last_page")
        if not book_props.pages then
            book_props.pages = doc_settings:readSetting("doc_pages")
        end
    else
        local cached = BookList.getBookInfo(file)
        percent_finished = cached and cached.percent_finished
        summary.status = cached and cached.status
    end

    local kv = {
        { _("Nome do arquivo:"), BD.filename(filename) },
        { _("Formato:"), filetype and filetype:upper() or _("N/D") },
        { _("Tamanho:"), string.format("%s (%s bytes)", size_f, size_b) },
        { _("Data do arquivo:"), os.date("%Y-%m-%d %H:%M:%S", attr.modification) },
        { _("Pasta:"), BD.dirpath(filemanagerutil.abbreviate(folder)), separator=true },
    }

    local custom_cover = DocSettings.findCustomCoverFile(file)
    table.insert(kv, {
        custom_cover and ("✎ " .. _("Imagem da capa:")) or _("Imagem da capa:"),
        _("Toque para exibir"),
        callback=function() native:onShowBookCover(file) end,
        hold_callback=function() native:showCustomDialog(file, book_props) end,
        separator=true,
    })

    local n_a = _("N/D")
    local props = {
        {"title", _("Título:")},
        {"authors", _("Autor(es):")},
        {"series", _("Série:")},
        {"series_index", _("Número da série:")},
        {"language", _("Idioma:")},
        {"keywords", _("Palavras-chave:")},
        {"description", _("Descrição:")},
    }

    local custom_metadata_file = DocSettings.findCustomMetadataFile(file)
    local custom_props
    if custom_metadata_file then
        local cs = DocSettings.openSettingsFile(custom_metadata_file)
        custom_props = cs and cs:readSetting("custom_props")
    end

    for _, entry in ipairs(props) do
        local key, label = entry[1], entry[2]
        local value = book_props[key]
        if value == nil or value == "" then
            value = n_a
        elseif key == "authors" or key == "keywords" then
            value = BD.auto(value)
        elseif key == "title" then
            value = BD.auto(value)
        elseif key == "description" then
            value = util.htmlToPlainTextIfHtml(value)
        end
        local key_text = label
        if custom_props and custom_props[key] then key_text = "✎ " .. label end
        local prop_value = value
        local callback
        if key == "description" and value ~= n_a then
            callback=function()
                native:showBookProp("description", value)
            end
        end
        table.insert(kv, {
            key_text,
            prop_value,
            callback=callback,
            hold_callback=function()
                native:showCustomDialog(file, book_props, key)
            end,
        })
    end

    local pages = tonumber(book_props.pages)
    table.insert(kv, {
        _("Páginas:"),
        pages and tostring(pages) or n_a,
        separator=true,
    })

    table.insert(kv, {
        _("Progresso:"),
        percent_finished and formatProgress(percent_finished) or n_a,
    })

    local status = summary.status
    local status_text = BookList.getBookStatusString(status) or n_a
    table.insert(kv, {
        _("Status de leitura:"),
        status_text,
    })

    if pages and last_page then
        table.insert(kv, {
            _("Página atual:"),
            T(_("%1 / %2"), tostring(last_page), tostring(pages)),
        })
    end

    table.insert(kv, {
        _("Localização:"),
        BD.dirpath(filemanagerutil.abbreviate(folder)),
        separator=true,
    })

    local page = KeyValuePage:new{
        title=_("Informações do livro"),
        value_overflow_align="right",
        kv_pairs=kv,
        close_callback=function()
            native.custom_doc_settings=nil
            native.custom_book_cover=nil
            UIManager:broadcastEvent(require("ui/event"):new("InvalidateMetadataCache", file))
            UIManager:broadcastEvent(require("ui/event"):new("BookMetadataChanged", file))
        end,
    }
    UIManager:show(page)
end

return M
