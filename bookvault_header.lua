local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local Font = require("ui/font")
local Screen = require("device").screen
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Header = InputContainer:extend{
    width = nil,
    active_status = "all",
    visible_statuses = nil,
    on_status = nil,
    on_search = nil,
    on_sort = nil,
    on_settings = nil,
    on_close = nil,
    on_selection_collections = nil,
    on_selection_move = nil,
    on_selection_copy = nil,
    on_selection_delete = nil,
    on_selection_more = nil,
    on_selection_exit = nil,
    show_cat = true,
    show_moon = true,
}

local STATUS = {
    { key="all", label=_("Todos") },
    { key="reading", label=_("Lendo") },
    { key="abandoned", label=_("Em espera") },
    { key="complete", label=_("Concluídos") },
    { key="new", label=_("Não iniciados") },
}

local function makeIconButton(icon, callback, icon_size, pad, parent)
    return IconButton:new{
        icon=icon,
        width=icon_size,
        height=icon_size,
        padding=pad,
        callback=callback,
        show_parent=parent,
    }
end

function Header:_buildTabs()
    local visible = {}
    for _,status in ipairs(STATUS) do
        if not self.visible_statuses or self.visible_statuses[status.key] ~= false then
            visible[#visible+1] = status
        end
    end
    if #visible == 0 then visible = { STATUS[1] } end

    local tabs = HorizontalGroup:new{align="center"}
    local tab_width = math.floor(self.width/#visible)
    self._status_tabs = {}
    for _,status in ipairs(visible) do
        local key = status.key
        local active = self.active_status == key
        local button = Button:new{
            text=status.label,
            width=tab_width,
            height=Screen:scaleBySize(34),
            bordersize=0,
            padding=Screen:scaleBySize(3),
            text_font_face="NotoSans-Regular.ttf",
            text_font_size=12,
            text_font_bold=active,
            callback=function() if self.on_status then self.on_status(key) end end,
            show_parent=self,
        }
        if button.label_widget then
            button.label_widget.fgcolor=active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
        end
        local underline = UnderlineContainer:new{
            padding=0,
            linesize=active and Size.line.thick or 0,
            color=Blitbuffer.COLOR_BLACK,
            dimen=Geom:new{w=tab_width,h=Screen:scaleBySize(36)},
            button,
        }
        self._status_tabs[key] = {button=button, underline=underline}
        table.insert(tabs, underline)
    end
    self.tabs = tabs
end

function Header:init()
    self.width = self.width or Screen:getWidth()
    local icon_size = Screen:scaleBySize(25)
    local small_icon = Screen:scaleBySize(19)
    local gap = Screen:scaleBySize(2)
    local pad = Screen:scaleBySize(5)
    local top_h = Screen:scaleBySize(52)

    self.left_button = nil

    local title = TextWidget:new{
        text="BookVault",
        face=Font:getFace("smalltfont",18),
        bold=true,
        padding=0,
    }
    local subtitle = TextWidget:new{
        text=_("biblioteca pessoal"),
        face=Font:getFace("smallinfofont",11),
        fgcolor=Blitbuffer.COLOR_DARK_GRAY,
        padding=0,
    }
    self.title_widget = title
    self.subtitle_widget = subtitle

    self.search_button = makeIconButton("bookvault-search",
        function() if self.on_search then self.on_search() end end, icon_size, pad, self)
    self.moon_widget = IconWidget:new{
        icon="bookvault-moon",
        width=small_icon,
        height=small_icon,
        dim=true,
    }
    if not self.show_moon then self.moon_widget:hide() end
    self.sort_button = makeIconButton(self.show_cat and "bookvault-sort-cat" or "bookvault-sort",
        function() if self.on_sort then self.on_sort() end end, icon_size, pad, self)

    self.settings_button = makeIconButton("bookvault-gear",
        function() if self.on_settings then self.on_settings() end end, icon_size, pad, self)

    self.close_button = makeIconButton("close",
        function() if self.on_close then self.on_close() end end, icon_size, pad, self)
    self.close_button.allow_flash = false
    self.right_button = self.settings_button

    self.selection_collections = makeIconButton("bookvault-collections",
        function() if self.on_selection_collections then self.on_selection_collections() end end,
        icon_size, pad, self)
    self.selection_move = makeIconButton("bookvault-move",
        function() if self.on_selection_move then self.on_selection_move() end end,
        icon_size, pad, self)
    self.selection_copy = makeIconButton("bookvault-copy",
        function() if self.on_selection_copy then self.on_selection_copy() end end,
        icon_size, pad, self)
    self.selection_delete = makeIconButton("bookvault-trash",
        function() if self.on_selection_delete then self.on_selection_delete() end end,
        icon_size, pad, self)
    self.selection_more = makeIconButton("bookvault-more",
        function() if self.on_selection_more then self.on_selection_more() end end,
        icon_size, pad, self)
    self.selection_exit = makeIconButton("bookvault-check",
        function() if self.on_selection_exit then self.on_selection_exit() end end,
        icon_size, pad, self)

    self.selection_collections.allow_flash = false
    self.selection_move.allow_flash = false
    self.selection_copy.allow_flash = false
    self.selection_delete.allow_flash = false
    self.selection_more.allow_flash = false
    self.selection_exit.allow_flash = false

    self:rebuildTop()

    self:_buildTabs()
    self[1]=VerticalGroup:new{
        align="left",
        self.top_widget,
        VerticalSpan:new{width=Screen:scaleBySize(5)},
        self.tabs,
        UnderlineContainer:new{
            padding=0,
            linesize=Size.line.thin,
            color=Blitbuffer.COLOR_LIGHT_GRAY,
            dimen=Geom:new{w=self.width,h=Screen:scaleBySize(1)},
            VerticalSpan:new{width=0},
        },
        VerticalSpan:new{width=Screen:scaleBySize(4)},
    }
    self.dimen=Geom:new{x=0,y=0,w=self.width,h=self[1]:getSize().h}
end

function Header:rebuildTop()
    local top_h = Screen:scaleBySize(52)
    local gap = Screen:scaleBySize(2)

    if not self.top_widget then
        local top = OverlapGroup:new{
            dimen=Geom:new{x=0,y=0,w=self.width,h=top_h},
        }

        local function makeLeft()
            local left_logo = IconWidget:new{
                icon="bookvault-cat",
                width=Screen:scaleBySize(19),
                height=Screen:scaleBySize(19),
                dim=true,
            }
            if not self.show_cat then left_logo:hide() end
            local identity = VerticalGroup:new{align="left",self.title_widget,self.subtitle_widget}
            return HorizontalGroup:new{
                left_logo,
                HorizontalSpan:new{width=Screen:scaleBySize(7)},
                identity,
            }
        end

        local normal_right = RightContainer:new{
            dimen=Geom:new{x=0,y=0,w=self.width,h=top_h},
            HorizontalGroup:new{
                self.search_button,
                HorizontalSpan:new{width=gap},
                self.moon_widget,
                HorizontalSpan:new{width=gap},
                self.sort_button,
                HorizontalSpan:new{width=gap},
                self.settings_button,
                HorizontalSpan:new{width=gap},
                self.close_button,
            },
        }
        local selection_right = RightContainer:new{
            dimen=Geom:new{x=0,y=0,w=self.width,h=top_h},
            HorizontalGroup:new{
                self.selection_collections,
                HorizontalSpan:new{width=gap},
                self.selection_move,
                HorizontalSpan:new{width=gap},
                self.selection_copy,
                HorizontalSpan:new{width=gap},
                self.selection_delete,
                HorizontalSpan:new{width=gap},
                self.selection_more,
                HorizontalSpan:new{width=gap},
                self.selection_exit,
            },
        }

        self._top_normal_right = normal_right
        self._top_selection_right = selection_right
        self._top_normal_left = makeLeft()
        self._top_selection_left = makeLeft()

        self._top_normal = OverlapGroup:new{
            dimen=Geom:new{x=0,y=0,w=self.width,h=top_h},
            self._top_normal_left,
            self._top_normal_right,
        }
        self._top_selection = OverlapGroup:new{
            dimen=Geom:new{x=0,y=0,w=self.width,h=top_h},
            self._top_selection_left,
            self._top_selection_right,
        }

        -- OverlapGroup is a pure container and has no show()/hide() API.
        -- Only the active child is placed in the top widget, so switching the
        -- child is sufficient and avoids calling nonexistent container methods.
        top[1] = self.selection_mode and self._top_selection or self._top_normal
        self.top_widget = top
    else
        local active = self.selection_mode and self._top_selection or self._top_normal
        self.top_widget[1] = active
    end
    if self[1] then self[1][1]=self.top_widget end
end

function Header:setTitle(title)
    if title then self.title_widget:setText(title) end
    UIManager:setDirty(self, "ui", self.dimen)
end

function Header:setSubTitle(subtitle)
    if subtitle then self.subtitle_widget:setText(subtitle) end
    UIManager:setDirty(self, "ui", self.dimen)
end

function Header:setActiveStatus(status)
    if not status then return end
    self.active_status = status
    for key, tab in pairs(self._status_tabs or {}) do
        local active = key == status
        tab.underline.linesize = active and Size.line.thick or 0
        local button = tab.button
        button.text_font_bold = active
        if button.label_widget then
            button.label_widget.text_font_bold = active
            button.label_widget.fgcolor = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
        end
    end
    UIManager:setDirty(self, "ui", self.dimen)
end

function Header:setLeftIcon(icon)
end

function Header:setRightIcon(icon)
end

function Header:generateVerticalLayout()
    if self.selection_mode then
        return {{self.selection_collections, self.selection_move, self.selection_copy,
            self.selection_delete, self.selection_more, self.selection_exit}}
    end
    return {{self.search_button, self.sort_button, self.settings_button, self.close_button}}
end

function Header:setSelectionCount(count)
    self.selection_mode = count and count > 0
    if self.selection_mode then
        self.title_widget:setText(tostring(count) .. " " .. _("selecionado(s)"))
        self.subtitle_widget:setText(_("modo de seleção"))
    else
        self.title_widget:setText("BookVault")
        self.subtitle_widget:setText(_("biblioteca pessoal"))
    end
    self:rebuildTop()
    UIManager:setDirty(self, "ui", self.dimen)
end

function Header:getHeight() return self.dimen.h end
return Header
