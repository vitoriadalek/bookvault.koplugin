from pathlib import Path

p = Path('main.lua')
s = p.read_text()

start = s.index('function BookVault:ensureCatIcon()')
end = s.index('\nfunction BookVault:showGridSettings', start)
new = r'''function BookVault:ensureBookVaultIcons()
    local icon_dir=DataStorage:getDataDir().."/icons"
    if lfs.attributes(icon_dir,"mode")~="directory" then pcall(lfs.mkdir,icon_dir) end
    if lfs.attributes(icon_dir,"mode")~="directory" then return false end
    local icons={
        ["bookvault-cat.svg"]=[[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path d="M18 27 13 13l14 7c3-1 7-1 10 0l14-7-5 14c3 3 5 7 5 12 0 9-9 15-22 15S7 48 7 39c0-5 2-9 5-12z" fill="#000"/><path d="M20 38h.1M44 38h.1" stroke="#fff" stroke-width="4" stroke-linecap="round"/><path d="M29 44c2 2 4 2 6 0M32 42v3M32 7v5M26 10h12" fill="none" stroke="#000" stroke-width="3" stroke-linecap="round"/></svg>]],
        ["bookvault-sort.svg"]=[[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><g fill="none" stroke="#000" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M18 14v36"/><path d="m10 22 8-8 8 8"/><path d="M38 50V14"/><path d="m30 42 8 8 8-8"/><path d="M50 14h6M50 26h6M50 38h6"/></g></svg>]],
        ["bookvault-sort-cat.svg"]=[[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><g fill="none" stroke="#000" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M12 39V21l9 5c4-2 10-2 14 0l9-5v18c0 8-7 14-16 14S12 47 12 39z" fill="#000"/><path d="M20 38h.1M36 38h.1M25 44c2 2 4 2 6 0" stroke="#fff" stroke-width="3"/><path d="M49 12v36M43 18l6-6 6 6M43 42l6 6 6-6"/><path d="M2 18h6M2 30h6M2 42h6"/></g></svg>]],
    }
    for name,data in pairs(icons) do
        local path=icon_dir.."/"..name
        if lfs.attributes(path,"mode")~="file" then
            local file=io.open(path,"w")
            if file then file:write(data); file:close() end
        end
    end
    return lfs.attributes(icon_dir.."/bookvault-sort.svg","mode")=="file"
end

function BookVault:loadBookInfoManager()
    local old_path=package.path
    package.path="plugins/coverbrowser.koplugin/?.lua;./plugins/coverbrowser.koplugin/?.lua;"..package.path
    local ok,bim=pcall(require,"bookinfomanager")
    package.path=old_path
    if ok and bim then return bim end
    logger.warn("BookVault: BookInfoManager unavailable")
    return nil
end
'''
s = s[:start] + new + s[end:]

old = '''function BookVault:getBookMetadata(item)\n    if not item or not item.path then return {} end\n    local ok,bim=pcall(require,"bookinfomanager")\n    if not ok or not bim then return {} end\n    local ok_info,info=pcall(bim.getBookInfo,bim,item.path,false)\n    if not ok_info or type(info)~="table" then return {} end\n    return info\nend'''
new2 = '''function BookVault:getBookMetadata(item)\n    if not item or not item.path then return {} end\n    local bim=self:loadBookInfoManager()\n    if not bim then return {} end\n    local ok_info,info=pcall(bim.getBookInfo,bim,item.path,false)\n    if not ok_info or type(info)~="table" then return {} end\n    return info\nend'''
assert old in s
s = s.replace(old,new2)

old = '''    self:ensureCatIcon()\n    self:loadSettings()\n    local appearance=self.settings.data.appearance\n    if appearance.show_cat == nil then appearance.show_cat=true end\n    if appearance.show_moon == nil then appearance.show_moon=true end\n    local title_text=(appearance.show_cat and "🐈 " or "")..title\n    local subtitle_text=appearance.show_moon and "☾" or nil\n    local custom_title_bar\n    local function search_cb() self:showSearchDialog(menu) end\n    local function sort_cb() self:showSortDialog(menu) end\n    custom_title_bar=TitleBar:new{\n        width=Screen:getWidth(),fullscreen="true",align="center",title=title_text,subtitle=subtitle_text,\n        left_icon="appbar.search",left_icon_tap_callback=search_cb,\n        right_icon="sort",right_icon_tap_callback=sort_cb,\n        show_parent=self,\n    }'''
new3 = '''    self:ensureBookVaultIcons()\n    self:loadSettings()\n    local appearance=self.settings.data.appearance\n    if appearance.show_cat == nil then appearance.show_cat=true end\n    if appearance.show_moon == nil then appearance.show_moon=true end\n    local subtitle_parts={}\n    if appearance.show_cat then subtitle_parts[#subtitle_parts+1]="=^.^=" end\n    if appearance.show_moon then subtitle_parts[#subtitle_parts+1]="☾" end\n    local subtitle_text=#subtitle_parts>0 and table.concat(subtitle_parts,"  ·  ") or nil\n    local custom_title_bar\n    local function search_cb() self:showSearchDialog(menu) end\n    local function sort_cb() self:showSortDialog(menu) end\n    custom_title_bar=TitleBar:new{\n        width=Screen:getWidth(),fullscreen="true",align="center",title=title,subtitle=subtitle_text,\n        left_icon="appbar.search",left_icon_tap_callback=search_cb,\n        right_icon=appearance.show_cat and "bookvault-sort-cat" or "bookvault-sort",right_icon_tap_callback=sort_cb,\n        show_parent=self,\n    }'''
assert old in s
s = s.replace(old,new3)
p.write_text(s)

meta=Path('_meta.lua').read_text().replace('version = "2.3.0"','version = "2.4.0"')
Path('_meta.lua').write_text(meta)

readme=Path('README.md').read_text()
readme=readme.replace('# BookVault 2.3.0','# BookVault 2.4.0')
readme=readme.replace('A versão 2.3.0 acompanha','A versão 2.4.0 acompanha')
readme=readme.replace('Ordenação visível na barra superior por título, autor, mais recentes, modificados recentemente, tamanho e páginas.','Ordenação visível na barra superior por título, autor, mais recentes, modificados recentemente, tamanho e páginas, com ícone próprio do BookVault.')
readme=readme.replace('Identidade visual BookVault opcional e detalhe lunar opcional na barra.','Identidade visual BookVault opcional, detalhe lunar opcional e assinatura visual sem emojis incompatíveis na barra.')
Path('README.md').write_text(readme)

Path('icons').mkdir(exist_ok=True)
Path('icons/bookvault-cat.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path d="M18 27 13 13l14 7c3-1 7-1 10 0l14-7-5 14c3 3 5 7 5 12 0 9-9 15-22 15S7 48 7 39c0-5 2-9 5-12z" fill="#000"/><path d="M20 38h.1M44 38h.1" stroke="#fff" stroke-width="4" stroke-linecap="round"/><path d="M29 44c2 2 4 2 6 0M32 42v3M32 7v5M26 10h12" fill="none" stroke="#000" stroke-width="3" stroke-linecap="round"/></svg>')
Path('icons/bookvault-sort.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><g fill="none" stroke="#000" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M18 14v36"/><path d="m10 22 8-8 8 8"/><path d="M38 50V14"/><path d="m30 42 8 8 8-8"/><path d="M50 14h6M50 26h6M50 38h6"/></g></svg>')
Path('icons/bookvault-sort-cat.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><g fill="none" stroke="#000" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M12 39V21l9 5c4-2 10-2 14 0l9-5v18c0 8-7 14-16 14S12 47 12 39z" fill="#000"/><path d="M20 38h.1M36 38h.1M25 44c2 2 4 2 6 0" stroke="#fff" stroke-width="3"/><path d="M49 12v36M43 18l6-6 6 6M43 42l6 6 6-6"/><path d="M2 18h6M2 30h6M2 42h6"/></g></svg>')
