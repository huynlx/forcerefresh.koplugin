local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Widget = require("ui/widget/widget")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local BlankRefreshWidget = Widget:extend {
    name = "forcerefresh_blank",
}

function BlankRefreshWidget:getSize()
    return Screen:getSize()
end

function BlankRefreshWidget:paintTo(bb, x, y)
    self.has_images = true
    if self.only_flash_on_page_with_images then
        local image_count = self.document:getDrawnImagesStatistics()
        self.has_images = image_count > 0
    end
    if self.has_images then
        local screen_size = Screen:getSize()
        bb:paintRect(x, y, screen_size.w, screen_size.h, self.background)
        UIManager:setDirty(nil, self.blank_refresh_mode)
    else
        self.invisible = true
    end
end

-- Plugin main class
local ForceRefresh = WidgetContainer:extend {
    name = "forcerefresh",
    is_doc_only = true, -- Only runs when a document is open
}

function ForceRefresh:init()
    logger.info("ForceRefresh plugin initialized.")

    -- Load saved settings or use defaults
    self.enabled = G_reader_settings:readSetting("forcerefresh_enabled", false)
    self.refresh_mode = G_reader_settings:readSetting("forcerefresh_mode", "flashui")
    self.refresh_on_suspend = G_reader_settings:readSetting("forcerefresh_on_suspend", false)
    self.only_flash_on_page_with_images = G_reader_settings:readSetting("forcerefresh_only_images", false)
    self.blank_page_color = G_reader_settings:readSetting("forcerefresh_blank_color", "white")
    self.show_blank_page = G_reader_settings:readSetting("forcerefresh_show_blank_page", true)
    self.skip_chapter_start = G_reader_settings:readSetting("forcerefresh_skip_chapter_start", false)
    self.blank_refresh_mode = G_reader_settings:readSetting("forcerefresh_blank_mode", "flashui")
    local refresh_count = tonumber(G_reader_settings:readSetting("forcerefresh_count", 1)) or 1
    self.refresh_count = math.max(1, math.min(5, math.floor(refresh_count)))
    local blank_refresh_count = tonumber(G_reader_settings:readSetting("forcerefresh_blank_count", 1)) or 1
    self.blank_refresh_count = math.max(1, math.min(5, math.floor(blank_refresh_count)))

    -- Add to main menu
    self.ui.menu:registerToMainMenu(self)
end

function ForceRefresh:addToMainMenu(menu_items)
    menu_items.force_refresh = {
        text = _("Force refresh"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Enable forced refresh"),
                checked_func = function()
                    return self.enabled
                end,
                callback = function()
                    self.enabled = not self.enabled
                    self:saveBookSetting("forcerefresh_enabled", self.enabled)
                    logger.info("ForceRefresh on page turn:", self.enabled)
                end
            },
            {
                text = _("Refresh on suspend/sleep"),
                checked_func = function()
                    return self.refresh_on_suspend
                end,
                callback = function()
                    self.refresh_on_suspend = not self.refresh_on_suspend
                    G_reader_settings:saveSetting("forcerefresh_on_suspend", self.refresh_on_suspend)
                    logger.info("ForceRefresh on suspend:", self.refresh_on_suspend)
                end,
            },
            {
                text = _("Only flash on page with images"),
                checked_func = function()
                    return self.only_flash_on_page_with_images
                end,
                callback = function()
                    self.only_flash_on_page_with_images = not self.only_flash_on_page_with_images
                    self:saveBookSetting("forcerefresh_only_images", self.only_flash_on_page_with_images)
                    logger.info("ForceRefresh only on pages with images:", self.only_flash_on_page_with_images)
                end,
            },
            {
                text = _("Skip first page of new chapters"),
                checked_func = function()
                    return self.skip_chapter_start
                end,
                callback = function()
                    self.skip_chapter_start = not self.skip_chapter_start
                    self:saveBookSetting("forcerefresh_skip_chapter_start", self.skip_chapter_start)
                end,
            },
            {
                text = _("Show blank page"),
                checked_func = function()
                    return self.show_blank_page
                end,
                callback = function()
                    self.show_blank_page = not self.show_blank_page
                    self:saveBookSetting("forcerefresh_show_blank_page", self.show_blank_page)
                end,
            },
            {
                text = _("Blank page color"),
                sub_item_table = {
                    {
                        text = _("White"),
                        checked_func = function()
                            return self.blank_page_color == "white"
                        end,
                        callback = function()
                            self.blank_page_color = "white"
                            self:saveBookSetting("forcerefresh_blank_color", self.blank_page_color)
                        end,
                    },
                    {
                        text = _("Black"),
                        checked_func = function()
                            return self.blank_page_color == "black"
                        end,
                        callback = function()
                            self.blank_page_color = "black"
                            self:saveBookSetting("forcerefresh_blank_color", self.blank_page_color)
                        end,
                    },
                },
            },
            {
                text = _("Blank refresh mode"),
                sub_item_table = {
                    {
                        text = _("Full refresh (slowest, cleanest)"),
                        checked_func = function()
                            return self.blank_refresh_mode == "full"
                        end,
                        callback = function()
                            self.blank_refresh_mode = "full"
                            self:saveBookSetting("forcerefresh_blank_mode", self.blank_refresh_mode)
                        end,
                    },
                    {
                        text = _("Partial refresh (faster, some ghosting)"),
                        checked_func = function()
                            return self.blank_refresh_mode == "partial"
                        end,
                        callback = function()
                            self.blank_refresh_mode = "partial"
                            self:saveBookSetting("forcerefresh_blank_mode", self.blank_refresh_mode)
                        end,
                    },
                    {
                        text = _("Flash UI (balanced)"),
                        checked_func = function()
                            return self.blank_refresh_mode == "flashui"
                        end,
                        callback = function()
                            self.blank_refresh_mode = "flashui"
                            self:saveBookSetting("forcerefresh_blank_mode", self.blank_refresh_mode)
                        end,
                    },
                    {
                        text = _("Flash partial (fast with quick flash)"),
                        checked_func = function()
                            return self.blank_refresh_mode == "flashpartial"
                        end,
                        callback = function()
                            self.blank_refresh_mode = "flashpartial"
                            self:saveBookSetting("forcerefresh_blank_mode", self.blank_refresh_mode)
                        end,
                    },
                },
            },
            {
                text = _("Blank refresh count"),
                sub_item_table = {
                    {
                        text = "1",
                        checked_func = function()
                            return self.blank_refresh_count == 1
                        end,
                        callback = function()
                            self.blank_refresh_count = 1
                            self:saveBookSetting("forcerefresh_blank_count", self.blank_refresh_count)
                        end,
                    },
                    {
                        text = "2",
                        checked_func = function()
                            return self.blank_refresh_count == 2
                        end,
                        callback = function()
                            self.blank_refresh_count = 2
                            self:saveBookSetting("forcerefresh_blank_count", self.blank_refresh_count)
                        end,
                    },
                    {
                        text = "3",
                        checked_func = function()
                            return self.blank_refresh_count == 3
                        end,
                        callback = function()
                            self.blank_refresh_count = 3
                            self:saveBookSetting("forcerefresh_blank_count", self.blank_refresh_count)
                        end,
                    },
                    {
                        text = "4",
                        checked_func = function()
                            return self.blank_refresh_count == 4
                        end,
                        callback = function()
                            self.blank_refresh_count = 4
                            self:saveBookSetting("forcerefresh_blank_count", self.blank_refresh_count)
                        end,
                    },
                    {
                        text = "5",
                        checked_func = function()
                            return self.blank_refresh_count == 5
                        end,
                        callback = function()
                            self.blank_refresh_count = 5
                            self:saveBookSetting("forcerefresh_blank_count", self.blank_refresh_count)
                        end,
                    },
                },
            },
            {
                text = _("Refresh count"),
                sub_item_table = {
                    {
                        text = "1",
                        checked_func = function()
                            return self.refresh_count == 1
                        end,
                        callback = function()
                            self.refresh_count = 1
                            self:saveBookSetting("forcerefresh_count", self.refresh_count)
                        end,
                    },
                    {
                        text = "2",
                        checked_func = function()
                            return self.refresh_count == 2
                        end,
                        callback = function()
                            self.refresh_count = 2
                            self:saveBookSetting("forcerefresh_count", self.refresh_count)
                        end,
                    },
                    {
                        text = "3",
                        checked_func = function()
                            return self.refresh_count == 3
                        end,
                        callback = function()
                            self.refresh_count = 3
                            self:saveBookSetting("forcerefresh_count", self.refresh_count)
                        end,
                    },
                    {
                        text = "4",
                        checked_func = function()
                            return self.refresh_count == 4
                        end,
                        callback = function()
                            self.refresh_count = 4
                            self:saveBookSetting("forcerefresh_count", self.refresh_count)
                        end,
                    },
                    {
                        text = "5",
                        checked_func = function()
                            return self.refresh_count == 5
                        end,
                        callback = function()
                            self.refresh_count = 5
                            self:saveBookSetting("forcerefresh_count", self.refresh_count)
                        end,
                    },
                },
            },
            {
                text = _("Refresh mode"),
                sub_item_table = {
                    {
                        text = _("Full refresh (slowest, cleanest)"),
                        checked_func = function()
                            return self.refresh_mode == "full"
                        end,
                        callback = function()
                            self.refresh_mode = "full"
                            self:saveBookSetting("forcerefresh_mode", "full")
                            logger.info("ForceRefresh mode set to: full")
                        end,
                    },
                    {
                        text = _("Partial refresh (faster, some ghosting)"),
                        checked_func = function()
                            return self.refresh_mode == "partial"
                        end,
                        callback = function()
                            self.refresh_mode = "partial"
                            self:saveBookSetting("forcerefresh_mode", "partial")
                            logger.info("ForceRefresh mode set to: partial")
                        end,
                    },
                    {
                        text = _("Flash UI (balanced)"),
                        checked_func = function()
                            return self.refresh_mode == "flashui"
                        end,
                        callback = function()
                            self.refresh_mode = "flashui"
                            self:saveBookSetting("forcerefresh_mode", "flashui")
                            logger.info("ForceRefresh mode set to: flashui")
                        end,
                    },
                    {
                        text = _("Flash partial (fast with quick flash)"),
                        checked_func = function()
                            return self.refresh_mode == "flashpartial"
                        end,
                        callback = function()
                            self.refresh_mode = "flashpartial"
                            self:saveBookSetting("forcerefresh_mode", "flashpartial")
                            logger.info("ForceRefresh mode set to: flashpartial")
                        end,
                    },
                },
            },
        }
    }
end

function ForceRefresh:loadBookSettings()
    local settings = self.ui.doc_settings
    local function read_setting(key, current_value)
        local value = settings:readSetting(key)
        if value ~= nil then
            return value
        end
        return current_value
    end

    self.enabled = read_setting("forcerefresh_enabled", self.enabled)
    self.refresh_mode = read_setting("forcerefresh_mode", self.refresh_mode)
    self.only_flash_on_page_with_images = read_setting("forcerefresh_only_images", self.only_flash_on_page_with_images)
    self.blank_page_color = read_setting("forcerefresh_blank_color", self.blank_page_color)
    self.show_blank_page = read_setting("forcerefresh_show_blank_page", self.show_blank_page)
    self.skip_chapter_start = read_setting("forcerefresh_skip_chapter_start", self.skip_chapter_start)
    self.blank_refresh_mode = read_setting("forcerefresh_blank_mode", self.blank_refresh_mode)
    self.refresh_count = math.max(1, math.min(5, math.floor(tonumber(
        read_setting("forcerefresh_count", self.refresh_count)) or 1)))
    self.blank_refresh_count = math.max(1, math.min(5, math.floor(tonumber(
        read_setting("forcerefresh_blank_count", self.blank_refresh_count)) or 1)))
end

function ForceRefresh:saveBookSetting(key, value)
    self.ui.doc_settings:saveSetting(key, value)
end

function ForceRefresh:refreshPageAdditionalTimes()
    for _ = 2, self.refresh_count do
        UIManager:waitForVSync()
        UIManager:setDirty(self.ui, self.refresh_mode)
        UIManager:forceRePaint()
    end
end

-- Register plugin to a page turn event
function ForceRefresh:onPageUpdate(page_number)
    if self.enabled then
        if self.skip_chapter_start and self.ui.toc then
            for _, chapter_page in ipairs(self.ui.toc:getTocTicksFlattened(true)) do
                if chapter_page == page_number then
                    return false
                end
            end
        end

        logger.dbg("ForceRefresh: page:", page_number, "mode:", self.refresh_mode)

        if not self.show_blank_page then
            UIManager:setDirty(self.ui, function()
                self.page_has_images = not self.only_flash_on_page_with_images
                if self.only_flash_on_page_with_images then
                    local image_count = self.ui.document:getDrawnImagesStatistics()
                    self.page_has_images = image_count > 0
                end
                if self.page_has_images then
                    return self.refresh_mode
                end
            end)
            UIManager:forceRePaint()
            if self.page_has_images then
                self:refreshPageAdditionalTimes()
            end
            return false
        end

        local blank_page = BlankRefreshWidget:new {
            background = self.blank_page_color == "black" and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            blank_refresh_mode = self.blank_refresh_mode,
            document = self.ui.document,
            only_flash_on_page_with_images = self.only_flash_on_page_with_images,
        }
        UIManager:show(blank_page)
        UIManager:setDirty(self.ui)
        UIManager:forceRePaint()
        if blank_page.has_images then
            for pass = 1, self.blank_refresh_count do
                UIManager:waitForVSync()
                if pass < self.blank_refresh_count then
                    UIManager:setDirty(nil, self.blank_refresh_mode)
                    UIManager:forceRePaint()
                end
            end
            UIManager:close(blank_page, self.refresh_mode)
            UIManager:forceRePaint()
            self:refreshPageAdditionalTimes()
        else
            UIManager:close(blank_page)
        end

        -- allow other handlers to handle this event
        return false
    end
end

-- Called when a document is opened
function ForceRefresh:onReaderReady()
    self:loadBookSettings()
end

-- Called when a document is closed
function ForceRefresh:onCloseDocument()
    -- do something here
end

-- Called when device is about to suspend/sleep
function ForceRefresh:onSuspend()
    if self.refresh_on_suspend then
        logger.dbg("ForceRefresh: Refreshing screen before suspend with mode:", self.refresh_mode)

        -- force refresh the screen after some time
        UIManager:scheduleIn(0.1, function()
            UIManager:setDirty(self.ui, self.refresh_mode)
        end
        )

        -- allow other handlers to handle this event
        return false
    end
end

return ForceRefresh
