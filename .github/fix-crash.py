from pathlib import Path
p=Path('main.lua')
s=p.read_text(encoding='utf-8')
old='''    self:loadSettings()\n    local key=menu._bookvault_view_key\n    local directions=self.settings.data.sort_directions[key] or {}\n    direction=direction or directions[mode] or ((mode=="title" or mode=="author") and "asc" or "desc")\n    self.settings.data.sort_modes[key]=mode\n    directions[mode]=direction\n    self.settings.data.sort_directions[key]=directions\n    self:saveSettings()\n'''
new='''    self:loadSettings()\n    local key=menu._bookvault_view_key\n    local all_directions=self.settings.data.sort_directions\n    if type(all_directions)~="table" then all_directions={} ; self.settings.data.sort_directions=all_directions end\n    local directions=all_directions[key]\n    if type(directions)~="table" then directions={} ; all_directions[key]=directions end\n    direction=direction or directions[mode] or ((mode=="title" or mode=="author") and "asc" or "desc")\n    self.settings.data.sort_modes[key]=mode\n    directions[mode]=direction\n    self:saveSettings()\n'''
if old not in s: raise SystemExit('sort block not found')
s=s.replace(old,new,1)
old2='''    local saved_sort=self.settings.data.sort_modes[menu._bookvault_view_key]\n    if saved_sort and saved_sort ~= "custom" then\n        local sd=self.settings.data.sort_directions[menu._bookvault_view_key] and self.settings.data.sort_directions[menu._bookvault_view_key][saved_sort]\n        self:sortBookVaultItems(menu,saved_sort,sd)\n    end\n    local ok_visual=self:prepareVisualMenu(menu,menu._bookvault_source_items)\n'''
new2='''    local saved_sort=self.settings.data.sort_modes[menu._bookvault_view_key]\n    local saved_directions=self.settings.data.sort_directions\n    if saved_sort and saved_sort ~= "custom" and type(saved_directions)=="table" and type(saved_directions[menu._bookvault_view_key])=="table" then\n        local sd=saved_directions[menu._bookvault_view_key][saved_sort]\n        if sd=="asc" or sd=="desc" then menu._bookvault_saved_sort={mode=saved_sort,direction=sd} end\n    end\n    local ok_visual=self:prepareVisualMenu(menu,menu._bookvault_source_items)\n'''
if old2 not in s: raise SystemExit('startup sort block not found')
s=s.replace(old2,new2,1)
# Apply saved sort only after the visual menu is fully prepared, and isolate it from menu construction errors.
old3='''    self:decorateTitleBar(menu,appearance,search_cb,sort_cb)\n    return menu\nend\n'''
new3='''    self:decorateTitleBar(menu,appearance,search_cb,sort_cb)\n    return menu\nend\n'''
# intentionally unchanged; startup sort is now only stored, not executed during construction.
p.write_text(s,encoding='utf-8')
m=Path('_meta.lua'); ms=m.read_text(encoding='utf-8').replace('version = "2.5.1"','version = "2.5.2"'); m.write_text(ms,encoding='utf-8')
r=Path('README.md'); rs=r.read_text(encoding='utf-8').replace('# BookVault 2.5.1','# BookVault 2.5.2'); r.write_text(rs,encoding='utf-8')
