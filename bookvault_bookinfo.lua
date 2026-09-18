local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local InputDialog = require("ui/widget/inputdialog")
local KeyValuePage = require("ui/widget/keyvaluepage")
local PathChooser = require("ui/widget/pathchooser")
local InfoMessage = require("ui/widget/infomessage")
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

local function plain(value)
    if value == nil or value == "" then return _("N/D") end
    return util.htmlToPlainTextIfHtml(tostring(value))
end

local function editMetadata(file, book_props, key, label, input_type, allow_newline, on_saved)
    local input = book_props[key]
    if input and key == "description" then input = util.htmlToPlainTextIfHtml(input) end
    local dialog
    dialog = InputDialog:new{
        title = _("Editar: ") .. label:gsub(":", ""),
        input = input or "",
        input_type = input_type,
        allow_newline = allow_newline,
        buttons = {{
            {
                text=_("Cancelar"),
                id="close",
                callback=function() UIManager:close(dialog) end,
            },
            {
                text=_("Salvar"),
                callback=function()
                    local value = dialog:getInputValue()
                    if value == nil then return end
                    UIManager:close(dialog)
                    local custom_file = DocSettings.findCustomMetadataFile(file)
                    local settings
                    if custom_file then
                        settings = DocSettings.openSettingsFile(custom_file)
                    else
                        settings = DocSettings.openSettingsFile()
                        local original = {}
                        for k,v in pairs(book_props) do original[k]=v end
                        original.display_title = nil
                        settings:saveSetting("doc_props", original)
                    end
                    local custom_props = settings:readSetting("custom_props", {})
                    custom_props[key] = value
                    settings:saveSetting("custom_props", custom_props)
                    settings:flushCustomMetadata(file)
                    book_props[key] = value
                    if key == "title" then book_props.display_title = value end
                    if on_saved then on_saved() end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function chooseCustomCover(file, on_saved)
    local chooser = PathChooser:new{
        select_directory=false,
        file_filter=function(filename)
            return DocumentRegistry:isImageFile(filename)
        end,
        onConfirm=function(image_file)
            if DocSettings:flushCustomCover(file, image_file) then
                if on_saved then on_saved() end
            else
                UIManager:show(InfoMessage:new{text=_("Não foi possível definir a capa personalizada.")})
            end
        end,
    }
    UIManager:show(chooser)
end

function M.show(ui, file, book_props)
    if not file then return end
    local native = FileManagerBookInfo:new{ui=ui}
    local attr = lfs.attributes(file)
    if not attr then
        UIManager:show(InfoMessage:new{text=_("O arquivo não existe mais.")})
        return
    end

    local folder, filename = util.splitFilePathName(file)
    local _, filetype = filemanagerutil.splitFileNameType(filename)
    book_props = book_props or native:getDocProps(file, book_props) or {}
    local cached = BookList.getBookInfo(file) or {}
    local pages = tonumber(book_props.pages or cached.pages)

    local doc_settings
    local summary = {}
    local percent_finished = cached.percent_finished
    local last_page
    if BookList.hasBookBeenOpened(file) then
        doc_settings = BookList.getDocSettings(file)
        summary = doc_settings:readSetting("summary") or {}
        percent_finished = doc_settings:readSetting("percent_finished") or percent_finished
        last_page = doc_settings:readSetting("last_page")
    end

    local custom_metadata_file = DocSettings.findCustomMetadataFile(file)
    local custom_props = {}
    if custom_metadata_file then
        local settings = DocSettings.openSettingsFile(custom_metadata_file)
        custom_props = settings:readSetting("custom_props", {}) or {}
        for key,value in pairs(custom_props) do book_props[key] = value end
    end

    local page
    local function reopen()
        UIManager:close(page)
        UIManager:nextTick(function() M.show(ui, file) end)
    end

    local kv = {
        { _("Nome do arquivo:"), BD.filename(filename) },
        { _("Formato:"), filetype and filetype:upper() or _("N/D") },
        { _("Tamanho:"), string.format("%s (%s bytes)", util.getFriendlySize(attr.size or 0), util.getFormattedSize(attr.size or 0)) },
        { _("Data do arquivo:"), os.date("%Y-%m-%d %H:%M:%S", attr.modification) },
        { _("Pasta:"), BD.dirpath(filemanagerutil.abbreviate(folder)), separator=true },
        {
            _("Imagem da capa:"),
            _("Toque para exibir · segure para alterar"),
            callback=function() native:onShowBookCover(file) end,
            hold_callback=function() chooseCustomCover(file, reopen) end,
            separator=true,
        },
    }

    local editable = {
        {"title", _("Título:"), nil, false},
        {"authors", _("Autor(es):"), nil, true},
        {"series", _("Série:"), nil, false},
        {"series_index", _("Número da série:"), "number", false},
        {"language", _("Idioma:"), nil, false},
        {"keywords", _("Palavras-chave:"), nil, true},
        {"description", _("Descrição:"), nil, true},
    }

    for _,entry in ipairs(editable) do
        local key, label, input_type, allow_newline = entry[1], entry[2], entry[3], entry[4]
        table.insert(kv, {
            custom_props[key] and ("✎ " .. label) or label,
            plain(book_props[key]),
            callback=function()
                editMetadata(file, book_props, key, label, input_type, allow_newline, reopen)
            end,
        })
    end

    table.insert(kv, { _("Páginas:"), pages and tostring(pages) or _("N/D"), separator=true })
    table.insert(kv, { _("Progresso:"), formatProgress(percent_finished) })
    table.insert(kv, { _("Status de leitura:"), BookList.getBookStatusString(summary.status or cached.status) or _("N/D") })

    if pages and last_page then
        table.insert(kv, { _("Página atual:"), T(_("%1 / %2"), tostring(last_page), tostring(pages)) })
    end

    table.insert(kv, { _("Localização:"), BD.dirpath(filemanagerutil.abbreviate(folder)), separator=true })

    page = KeyValuePage:new{
        title=_("Informações do livro"),
        value_overflow_align="right",
        kv_pairs=kv,
        close_callback=function()
            UIManager:broadcastEvent(require("ui/event"):new("InvalidateMetadataCache", file))
            UIManager:broadcastEvent(require("ui/event"):new("BookMetadataChanged", file))
        end,
    }
    UIManager:show(page)
end

return M
