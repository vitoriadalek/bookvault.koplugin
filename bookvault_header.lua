local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Font = require("ui/font")
local Screen = require("device").screen
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Header = InputContainer:extend{
    width = nil, active_status = "all", visible_statuses = nil, on_status = nil, on_search = nil,
    on_sort = nil, on_settings = nil, on_close = nil, show_cat = true, show_moon = true,
}

local STATUS = {
    { key="all", label=_("Todos") }, { key="reading", label=_("Lendo") },
    { key="abandoned", label=_("Em espera") }, { key="complete", label=_("Concluídos") },
    { key="new", label=_("Não iniciados") },
}

function Header:init()
    self.width = self.width or Screen:getWidth()
    local icon_size = Screen:scaleBySize(25)
    local small_icon = Screen:scaleBySize(19)
    local gap = Screen:scaleBySize(2)
    local pad = Screen:scaleBySize(5)

    local close = IconButton:new{icon="back.top",width=icon_size,height=icon_size,padding=pad,
        callback=function() if self.on_close then self.on_close() end end,show_parent=self}
    -- Compatibility surface expected by KOReader Menu/SortWidget when a custom
    -- title bar is supplied. Keep these references per instance (no global patch).
    self.left_button = close
    local logo = IconWidget:new{icon="bookvault-cat",width=small_icon,height=small_icon,dim=true}
    if not self.show_cat then logo:hide() end
    local title = TextWidget:new{text="BookVault",face=Font:getFace("smalltfont",18),bold=true,padding=0}
    local subtitle = TextWidget:new{text=_("biblioteca pessoal"),face=Font:getFace("smallinfofont",11),
        fgcolor=Blitbuffer.COLOR_DARK_GRAY,padding=0}
    self.title_widget = title
    self.subtitle_widget = subtitle
    local identity = VerticalGroup:new{align="left",title,subtitle}
    local left = HorizontalGroup:new{close,HorizontalSpan:new{width=gap},logo,
        HorizontalSpan:new{width=Screen:scaleBySize(7)},identity}

    local search = IconButton:new{icon="bookvault-search",width=icon_size,height=icon_size,padding=pad,
        callback=function() if self.on_search then self.on_search() end end,show_parent=self}
    local moon = IconWidget:new{icon="bookvault-moon",width=small_icon,height=small_icon,dim=true}
    if not self.show_moon then moon:hide() end
    local sort = IconButton:new{icon="bookvault-sort",width=icon_size,height=icon_size,padding=pad,
        callback=function() if self.on_sort then self.on_sort() end end,show_parent=self}
    local settings = IconButton:new{icon="gear",width=icon_size,height=icon_size,padding=pad,
        callback=function() if self.on_settings then self.on_settings() end end,show_parent=self}
    self.right_button = settings
    local right = HorizontalGroup:new{search,HorizontalSpan:new{width=gap},moon,HorizontalSpan:new{width=gap},sort,
        HorizontalSpan:new{width=gap},settings}
    -- Use an overlap layout here. A full-width RightContainer inside a
    -- HorizontalGroup would increase the measured width and push the actions
    -- outside the screen on e-ink devices. This keeps both sides visible.
    local top = OverlapGroup:new{
        dimen=Geom:new{x=0,y=0,w=self.width,h=Screen:scaleBySize(52)},
        left,
        RightContainer:new{
            dimen=Geom:new{x=0,y=0,w=self.width,h=Screen:scaleBySize(52)},
            right,
        },
    }

    local visible = {}
    for _,status in ipairs(STATUS) do
        if not self.visible_statuses or self.visible_statuses[status.key] ~= false then
            visible[#visible+1] = status
        end
    end
    if #visible == 0 then visible = { STATUS[1] } end

    local tabs = HorizontalGroup:new{align="center"}
    local tab_width = math.floor(self.width/#visible)
    for _,status in ipairs(visible) do
        local key = status.key
        local active = self.active_status == key
        local button = Button:new{text=status.label,width=tab_width,height=Screen:scaleBySize(34),bordersize=0,
            padding=Screen:scaleBySize(3),text_font_face="NotoSans-Regular.ttf",text_font_size=12,
            text_font_bold=active,callback=function() if self.on_status then self.on_status(key) end end,show_parent=self}
        if button.label_widget then button.label_widget.fgcolor=active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY end
        table.insert(tabs,UnderlineContainer:new{padding=0,linesize=active and Size.line.thick or 0,
            color=Blitbuffer.COLOR_BLACK,dimen=Geom:new{w=tab_width,h=Screen:scaleBySize(36)},button})
    end

    self[1]=VerticalGroup:new{align="left",top,VerticalSpan:new{width=Screen:scaleBySize(5)},tabs,
        UnderlineContainer:new{padding=0,linesize=Size.line.thin,color=Blitbuffer.COLOR_LIGHT_GRAY,
            dimen=Geom:new{w=self.width,h=Screen:scaleBySize(1)},VerticalSpan:new{width=0}},
        VerticalSpan:new{width=Screen:scaleBySize(4)}}
    self.dimen=Geom:new{x=0,y=0,w=self.width,h=self[1]:getSize().h}
end

function Header:setTitle(title)
    if title then self.title_widget:setText(title) end
    UIManager:setDirty(self, "ui", self.dimen)
end

function Header:setSubTitle(subtitle)
    if subtitle then self.subtitle_widget:setText(subtitle) end
    UIManager:setDirty(self, "ui", self.dimen)
end

function Header:setLeftIcon(icon)
    -- BookVault owns the left icon in this custom header; keep API compatibility.
end

function Header:setRightIcon(icon)
    -- BookVault owns the right controls in this custom header; keep API compatibility.
end

function Header:generateVerticalLayout()
    -- Menu uses this for keyboard/focus navigation. Expose the actual actionable
    -- title-bar buttons without requiring the native TitleBar implementation.
    local layout = {}
    if self.left_button then table.insert(layout, { self.left_button }) end
    if self.right_button then table.insert(layout, { self.right_button }) end
    return layout
end

function Header:setSelectionCount(count)
    if not self.title_widget or not self.subtitle_widget then return end
    if count and count > 0 then
        self.title_widget:setText(tostring(count) .. " " .. _("selecionado(s)"))
        self.subtitle_widget:setText(_("modo de seleção"))
    else
        self.title_widget:setText("BookVault")
        self.subtitle_widget:setText(_("biblioteca pessoal"))
    end
    UIManager:setDirty(self, "ui", self.dimen)
end

function Header:getHeight() return self.dimen.h end
return Header
