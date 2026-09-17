-- BookVault action layer: kept separate from the visual core to minimize risk.
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local PathChooser = require("ui/widget/pathchooser")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local ReadCollection = require("readcollection")
local DocumentRegistry = require("document/documentregistry")
local DocSettings = require("docsettings")
local BookList = require("ui/widget/booklist")
local DataStorage = require("datastorage")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local _ = require("gettext")
local logger = require("logger")
local T = ffiUtil.template

local M = {}
local function count(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
local function basename(path) return ffiUtil.basename(path) or path end
local function real(path) return ffiUtil.realpath(path) or path end
local function safe(self, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then logger.err("BookVault action:", err); UIManager:show(InfoMessage:new{text=_("BookVault encontrou um erro e não conseguiu concluir a ação.")}) end
    return ok
end

function M.install(BV)
    if BV._actions_installed then return end
    BV._actions_installed = true
    local old_load = BV.loadSettings
    BV.loadSettings = function(self,...)
        old_load(self,...)
        local d=self.settings.data
        if d.privacy_enabled == nil then d.privacy_enabled=true end
        d.protected_paths=d.protected_paths or {}; d.private_paths=d.private_paths or {}
    end
    function BV:isPrivacyOn() self:loadSettings(); return self.settings.data.privacy_enabled ~= false end
    function BV:setPrivacy(on,reveal) self:loadSettings(); self.settings.data.privacy_enabled=on and true or false; self.unlocked=reveal and true or false; self:saveSettings() end
    function BV:togglePrivacy()
        if self:isPrivacyOn() then
            if not self:hasPassword() then
                self:setPassword(function() self:askPassword(function(ok) if ok then self:setPrivacy(false,true); self:showStatusChooser() end end,_("Revelar conteúdo")) end)
            else self:askPassword(function(ok) if ok then self:setPrivacy(false,true); self:showStatusChooser() end end,_("Revelar conteúdo")) end
        else self:setPrivacy(true,false); self:showStatusChooser() end
    end
    function BV:privacyIncludePrivate() return not self:isPrivacyOn() and self.unlocked end

    local old_add=BV.addToMainMenu
    BV.addToMainMenu=function(self,menu_items)
        old_add(self,menu_items)
        local root=menu_items.bookvault
        if not root or not root.sub_item_table then return end
        for _,it in ipairs(root.sub_item_table) do
            if it.text_func then
                it.text_func=function() return (self:isPrivacyOn() and "◉ " or "○ ").._("Privacidade: ")..(self:isPrivacyOn() and "ON" or "OFF") end
                it.callback=function() self:togglePrivacy() end
                break
            end
        end
    end

    function BV:installFileManagerProtection()
        local ui=self.ui; local fc=ui and ui.file_chooser
        if not fc or fc._bookvault_protection then return end
        fc._bookvault_protection=true
        local old_select,old_hold,old_change=fc.onFileSelect,fc.onFileHold,fc.changeToPath
        local plugin=self
        local function guarded(path,callback)
            if not plugin:isProtected(path) or plugin.unlocked then callback(); return true end
            plugin:askPassword(function(ok) if ok then plugin.unlocked=true; safe(plugin,callback) end end,_("Pasta protegida")); return true
        end
        fc.onFileSelect=function(f,item) if item and item.path and plugin:isProtected(item.path) and not plugin.unlocked then return guarded(item.path,function() old_select(f,item) end) end; return old_select(f,item) end
        fc.onFileHold=function(f,item) if item and item.path and plugin:isProtected(item.path) and not plugin.unlocked then return guarded(item.path,function() old_hold(f,item) end) end; return old_hold(f,item) end
        fc.changeToPath=function(f,path,focused_path) if path and plugin:isProtected(path) and not plugin.unlocked then return guarded(path,function() old_change(f,path,focused_path) end) end; return old_change(f,path,focused_path) end
    end
    local old_init=BV.init
    BV.init=function(self,...) local r=old_init(self,...); self:installFileManagerProtection(); return r end

    function BV:showBookInfo(item)
        local ui=self.ui; local bi=ui and ui.bookinfo
        if bi then safe(self,function() bi:show(item.path) end); return end
        local props=self:getBookMetadata(item); local attr=lfs.attributes(item.path) or {}
        local text=T(_("Título: %1\nAutor: %2\nPáginas: %3\nTamanho: %4\nFormato: %5\nLocal: %6"),props.title or basename(item.path),props.authors or _("N/A"),props.pages or _("N/A"),util.getFriendlySize(attr.size or 0),(basename(item.path):match("%.([^%.]+)$") or ""):upper(),item.path)
        UIManager:show(TextViewer:new{title=_("Informações do livro"),text=text})
    end
    function BV:showCollectionsForBook(item,menu)
        local names={}; for name in pairs(ReadCollection.coll or {}) do names[#names+1]=name end; table.sort(names,function(a,b) return a:lower()<b:lower() end)
        local buttons={}
        for _,name in ipairs(names) do local checked=ReadCollection:isFileInCollection(item.path,name); buttons[#buttons+1]={{text=(checked and "☑ " or "☐ ")..name,callback=function()
            local map={}; for _,n in ipairs(names) do map[n]=ReadCollection:isFileInCollection(item.path,n) end; map[name]=not checked; ReadCollection:addRemoveItemMultiple(item.path,map); ReadCollection:write(); UIManager:close(self._bookvault_collection_dialog); self._bookvault_collection_dialog=nil; self:showCollectionsForBook(item,menu)
        end}} end
        buttons[#buttons+1]={{text=_("Nova coleção"),callback=function() local d; d=InputDialog:new{title=_("Nova coleção"),input="",buttons={{text=_("Cancelar"),callback=function() UIManager:close(d) end},{text=_("Criar"),is_enter_default=true,callback=function() local name=d:getInputText(); UIManager:close(d); if name and name~="" and not ReadCollection.coll[name] then ReadCollection:addCollection(name); ReadCollection:addItem(item.path,name); ReadCollection:write() end; self:showCollectionsForBook(item,menu) end}}}; UIManager:show(d); pcall(d.onShowKeyboard,d) end}}
        buttons[#buttons+1]={{text=_("Concluído"),callback=function() UIManager:close(self._bookvault_collection_dialog); self._bookvault_collection_dialog=nil; if menu then menu:updateItems() end end}}
        self._bookvault_collection_dialog=ButtonDialog:new{title=_("Coleções"),title_align="center",buttons=buttons}; UIManager:show(self._bookvault_collection_dialog)
    end
    function BV:renameBook(item,menu)
        local d; d=InputDialog:new{title=_("Renomear livro"),input=basename(item.path),buttons={{text=_("Cancelar"),callback=function() UIManager:close(d) end},{text=_("Salvar"),is_enter_default=true,callback=function() local name=d:getInputText(); UIManager:close(d); if not name or name=="" then return end; local dir=item.path:match("^(.*)/[^/]+$") or "."; local dest=dir.."/"..name; if lfs.attributes(dest) then UIManager:show(InfoMessage:new{text=_("Já existe um arquivo com esse nome.")}); return end; if os.rename(item.path,dest) then ReadCollection:updateItem(item.path,dest); pcall(function() require("readhistory"):updateItem(item.path,dest) end); item.path=dest; item.filepath=dest; item.text=name; if menu then menu:updateItems() end else UIManager:show(InfoMessage:new{text=_("Não foi possível renomear o arquivo.")}) end end}}; UIManager:show(d); pcall(d.onShowKeyboard,d)
    end
    function BV:deleteBooks(paths,menu)
        local files={}; for path in pairs(paths) do files[path]=true end
        UIManager:show(ConfirmBox:new{text=T(N_("Excluir %1 livro?","Excluir %1 livros?",count(files)),count(files)),ok_text=_("Excluir"),ok_callback=function() local failed=0; for path in pairs(files) do if not os.remove(path) then failed=failed+1 else ReadCollection:removeItem(path,nil,true) end end; ReadCollection:write(); pcall(function() require("readhistory"):clearMissing() end); if failed>0 then UIManager:show(InfoMessage:new{text=T(_("%1 arquivo(s) não puderam ser excluídos."),failed)}) end; if menu then self:leaveSelection(menu); menu._bookvault_source_items=self:scanBooks(self:privacyIncludePrivate()); menu.item_table=menu._bookvault_source_items; menu:updateItems() end end})
    end
    function BV:copyOrMoveBook(item,menu,move)
        UIManager:show(PathChooser:new{select_directory=true,select_file=false,onConfirm=function(dir) if not dir then return end; local dest=real(dir).."/"..basename(item.path); if lfs.attributes(dest) then UIManager:show(InfoMessage:new{text=_("Já existe um arquivo com esse nome no destino.")}); return end; local ok; if move then ok=os.rename(item.path,dest); if ok then ReadCollection:updateItem(item.path,dest); pcall(function() require("readhistory"):updateItem(item.path,dest) end) end else ok=ffiUtil.copyFile(item.path,dest) end; if not ok then UIManager:show(InfoMessage:new{text=move and _("Não foi possível mover o arquivo.") or _("Não foi possível copiar o arquivo.")}) end; if menu then menu:updateItems() end end})
    end
    function BV:showBookActions(menu,item)
        if menu._bookvault_selection_mode then self:toggleSelection(menu,item); return end
        local buttons={
            {{text=_("Informações do livro"),callback=function() UIManager:close(self._bookvault_action_dialog); self:showBookInfo(item) end}},
            {{text=_("Coleções"),callback=function() UIManager:close(self._bookvault_action_dialog); self:showCollectionsForBook(item,menu) end}},
            {{text=_("Editar capa/metadados"),callback=function() UIManager:close(self._bookvault_action_dialog); self:showBookInfo(item) end}},
            {{text=_("Selecionar vários"),callback=function() UIManager:close(self._bookvault_action_dialog); self:enterSelection(menu,item) end}},
            {{text=_("Renomear"),callback=function() UIManager:close(self._bookvault_action_dialog); self:renameBook(item,menu) end}},
            {{text=_("Copiar"),callback=function() UIManager:close(self._bookvault_action_dialog); self:copyOrMoveBook(item,menu,false) end}},
            {{text=_("Mover"),callback=function() UIManager:close(self._bookvault_action_dialog); self:copyOrMoveBook(item,menu,true) end}},
            {{text=_("Excluir"),callback=function() UIManager:close(self._bookvault_action_dialog); self:deleteBooks({[item.path]=true},menu) end}},
            {{text=_("Abrir localização"),callback=function() UIManager:close(self._bookvault_action_dialog); local ui=self.ui; if ui and ui.file_chooser then local dir=item.path:match("^(.*)/[^/]+$"); ui.file_chooser:changeToPath(dir,item.path) end end}},
            {{text=_("Cancelar"),callback=function() UIManager:close(self._bookvault_action_dialog) end}},
        }
        self._bookvault_action_dialog=ButtonDialog:new{title=item.text or basename(item.path),title_align="center",buttons=buttons}; UIManager:show(self._bookvault_action_dialog)
    end
    function BV:enterSelection(menu,item) menu._bookvault_selection_mode=true; menu._bookvault_selected={}; self:toggleSelection(menu,item); if menu.setTitleBarLeftIcon then pcall(menu.setTitleBarLeftIcon,menu,"check") end; menu:updateItems(1,true) end
    function BV:toggleSelection(menu,item) if not item or not item.path then return end; local s=menu._bookvault_selected or {}; menu._bookvault_selected=s; if s[item.path] then s[item.path]=nil; item.dim=nil else s[item.path]=true; item.dim=true end; self:showSelectionActions(menu); menu:updateItems(1,true) end
    function BV:leaveSelection(menu) menu._bookvault_selection_mode=false; menu._bookvault_selected=nil; for _,it in ipairs(menu.item_table or {}) do it.dim=nil end; menu:updateItems(1,true) end
    function BV:showSelectionActions(menu)
        if menu._bookvault_selection_dialog then UIManager:close(menu._bookvault_selection_dialog); menu._bookvault_selection_dialog=nil end
        local selected=menu._bookvault_selected or {}; local n=count(selected); if n==0 then return end
        local buttons={
            {{text=T(N_("Informações (%1)","Informações (%1)",n),n),callback=function() local p=next(selected); if p then self:showBookInfo({path=p,text=basename(p)}) end end}},
            {{text=_("Coleções"),callback=function() local p=next(selected); if p then self:showCollectionsForBook({path=p,text=basename(p)},menu) end end}},
            {{text=_("Excluir"),callback=function() self:deleteBooks(selected,menu) end}},
            {{text=_("Sair da seleção"),callback=function() UIManager:close(menu._bookvault_selection_dialog); menu._bookvault_selection_dialog=nil; self:leaveSelection(menu) end}},
        }
        menu._bookvault_selection_dialog=ButtonDialog:new{title=T(N_("%1 livro selecionado","%1 livros selecionados",n),n),title_align="center",buttons=buttons}; UIManager:show(menu._bookvault_selection_dialog)
    end
    local old_make=BV.makeBookMenu
    BV.makeBookMenu=function(self,...)
        local menu=old_make(self,...); if not menu then return menu end
        local old_select,old_hold=menu.onMenuSelect,menu.onMenuHold
        menu.onMenuSelect=function(m,item) if m._bookvault_selection_mode then self:toggleSelection(m,item); return true end; return old_select(m,item) end
        menu.onMenuHold=function(m,item) self:showBookActions(m,item); return true end
        return menu
    end

    function BV:searchGoogleImagesForCover(file)
        local props=self:getBookMetadata({path=file}); local q=(props.title or basename(file):gsub("%.[^%.]+$","")).." "..(props.authors or "")
        local url="https://www.google.com/search?tbm=isch&q="..(q:gsub("[^%w%s%-]",""):gsub("%s+","+"))
        UIManager:show(InfoMessage:new{text=_("Pesquisando capas no Google Imagens…")})
        local sink={}; socketutil:set_timeout(10,20); local ok=pcall(function() return socket.skip(1,http.request{url=url,headers={["User-Agent"]="Mozilla/5.0",["Accept-Encoding"]="identity"},sink=ltn12.sink.table(sink)}) end); socketutil:reset_timeout(); local html=ok and table.concat(sink) or ""
        local found={}; local seen={}
        for u in html:gmatch('https?://[^"\\<> ]+') do u=u:gsub("\\u003d","="):gsub("\\u0026","&"); if (u:find("gstatic.com/images") or u:match("%.[Jj][Pp][Gg]") or u:match("%.[Pp][Nn][Gg]") or u:match("%.[Ww][Ee][Bb][Pp]")) and not seen[u] then seen[u]=true; found[#found+1]=u; if #found>=6 then break end end end
        if #found==0 then UIManager:show(InfoMessage:new{text=_("O Google Imagens não retornou uma capa utilizável.")}); return end
        local buttons={}; for i,u in ipairs(found) do local idx=i; buttons[#buttons+1]={{text=T(_("Usar resultado %1"),idx),callback=function() local cache=DataStorage:getDataDir().."/bookvault/covers"; pcall(lfs.mkdir,DataStorage:getDataDir().."/bookvault"); pcall(lfs.mkdir,cache); local out=cache.."/cover_"..tostring(os.time()).."_"..idx..".jpg"; local f=io.open(out,"wb"); if not f then return end; socketutil:set_timeout(10,20); local ok2=pcall(function() return socket.skip(1,http.request{url=u,sink=ltn12.sink.file(f),headers={["User-Agent"]="Mozilla/5.0"}}) end); socketutil:reset_timeout(); pcall(f.close,f); if not ok2 or lfs.attributes(out,"mode")~="file" then UIManager:show(InfoMessage:new{text=_("Não foi possível baixar esta capa.")}); return end; local bi=self.ui and self.ui.bookinfo; if bi and bi.setCustomCoverFromImage then bi:setCustomCoverFromImage(file,out); UIManager:close(self._google_cover_dialog) else UIManager:show(InfoMessage:new{text=_("A edição de capa nativa não está disponível nesta tela.")}) end end}} end; buttons[#buttons+1]={{text=_("Cancelar"),callback=function() UIManager:close(self._google_cover_dialog) end}}; self._google_cover_dialog=ButtonDialog:new{title=_("Google Imagens · capas"),buttons=buttons}; UIManager:show(self._google_cover_dialog)
    end
end
return M
