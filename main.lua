local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen


local ForceRefresh = WidgetContainer:extend {
    name = "forcerefresh",
    is_doc_only = true,
}


----------------------------------------------------------------
-- INIT
----------------------------------------------------------------

function ForceRefresh:init()
    logger.info("ForceRefresh: initialized")

    self.enabled =
        G_reader_settings:readSetting(
            "forcerefresh_enabled",
            true
        )

    self.refresh_on_suspend =
        G_reader_settings:readSetting(
            "forcerefresh_on_suspend",
            false
        )

    self.reader_ready = false
    self.last_page_number = nil
    self.refreshing = false

    self.ui.menu:registerToMainMenu(self)
end

----------------------------------------------------------------
-- MENU
----------------------------------------------------------------

function ForceRefresh:addToMainMenu(menu_items)
    menu_items.force_refresh = {

        text = _("Force refresh"),

        sorting_hint = "tools",

        sub_item_table = {

            ------------------------------------------------------
            -- ENABLE / DISABLE
            ------------------------------------------------------

            {
                text = _("Enable forced page refresh"),

                checked_func = function()
                    return self.enabled
                end,

                callback = function()
                    self.enabled = not self.enabled

                    G_reader_settings:saveSetting(
                        "forcerefresh_enabled",
                        self.enabled
                    )

                    logger.info(
                        "ForceRefresh enabled:",
                        self.enabled
                    )
                end,
            },


            ------------------------------------------------------
            -- SUSPEND
            ------------------------------------------------------

            {
                text = _("Refresh on suspend/sleep"),

                checked_func = function()
                    return self.refresh_on_suspend
                end,

                callback = function()
                    self.refresh_on_suspend =
                        not self.refresh_on_suspend

                    G_reader_settings:saveSetting(
                        "forcerefresh_on_suspend",
                        self.refresh_on_suspend
                    )

                    logger.info(
                        "ForceRefresh suspend:",
                        self.refresh_on_suspend
                    )
                end,
            },


            ------------------------------------------------------
            -- MANUAL FULL REFRESH
            ------------------------------------------------------

            {
                text = _("Full refresh now"),

                callback = function()
                    self:fullRefresh()
                end,
            },

        },
    }
end

----------------------------------------------------------------
-- GET SCREEN SIZE
----------------------------------------------------------------

function ForceRefresh:getScreenSize()
    local w = Screen:getWidth()
    local h = Screen:getHeight()

    return w, h
end

----------------------------------------------------------------
-- FULL REFRESH
----------------------------------------------------------------
--
-- Dùng cho:
--   - menu "Full refresh now"
--   - suspend
--
-- Không liên quan trực tiếp tới page turn.
--
----------------------------------------------------------------

function ForceRefresh:fullRefresh()
    if not Screen or not Screen.bb then
        logger.warn(
            "ForceRefresh: Screen.bb unavailable"
        )
        return
    end


    local w, h = self:getScreenSize()


    logger.dbg(
        "ForceRefresh: full refresh",
        w,
        h
    )


    Screen:refreshFull(
        0,
        0,
        w,
        h
    )


    if Screen.refreshWaitForLast then
        Screen:refreshWaitForLast()
    else
        UIManager:waitForVSync()
    end
end

----------------------------------------------------------------
-- CLEAR FRAMEBUFFER
----------------------------------------------------------------
--
-- CỰC KỲ QUAN TRỌNG:
--
-- Hàm này CHỈ xóa framebuffer trong RAM.
--
-- Không gọi Screen:refreshFull().
--
-- Vì vậy màn E-Ink vẫn đang hiển thị PAGE A.
--
----------------------------------------------------------------

function ForceRefresh:clearFramebuffer()
    if not Screen or not Screen.bb then
        logger.warn(
            "ForceRefresh: Screen.bb unavailable"
        )
        return false
    end


    logger.dbg(
        "ForceRefresh: clearing framebuffer"
    )


    Screen.bb:fill(
        Blitbuffer.COLOR_WHITE
    )


    return true
end

----------------------------------------------------------------
-- REFRESH CURRENT FRAMEBUFFER
----------------------------------------------------------------
--
-- Sau khi ReaderUI đã render PAGE B vào framebuffer,
-- hàm này đưa framebuffer đó lên E-Ink.
--
-- Đây là lần refresh DUY NHẤT của page turn.
--
----------------------------------------------------------------

function ForceRefresh:refreshFramebuffer()
    local w, h = self:getScreenSize()


    logger.dbg(
        "ForceRefresh: refreshing framebuffer"
    )


    -- Screen:refreshFull(
    --     0,
    --     0,
    --     w,
    --     h
    -- )


    if Screen.refreshWaitForLast then
        Screen:refreshWaitForLast()
    else
        UIManager:waitForVSync()
    end
end

----------------------------------------------------------------
-- PAGE UPDATE
----------------------------------------------------------------
--
-- FLOW:
--
-- PAGE A
--   ↓
-- clear framebuffer
--   ↓
-- render PAGE B
--   ↓
-- full refresh
--   ↓
-- PAGE B
--
----------------------------------------------------------------

function ForceRefresh:onPageUpdate(page_number)
    ------------------------------------------------------------
    -- Không có reader
    ------------------------------------------------------------

    if not self.reader_ready then
        return false
    end


    ------------------------------------------------------------
    -- Không phải page mới
    ------------------------------------------------------------

    if page_number == self.last_page_number then
        return false
    end


    self.last_page_number = page_number


    ------------------------------------------------------------
    -- Plugin disabled
    ------------------------------------------------------------

    if not self.enabled then
        return false
    end


    ------------------------------------------------------------
    -- Chống refresh chồng nhau
    ------------------------------------------------------------

    if self.refreshing then
        logger.dbg(
            "ForceRefresh: refresh already running"
        )

        return false
    end


    self.refreshing = true


    logger.dbg(
        "ForceRefresh: page update:",
        page_number
    )


    ------------------------------------------------------------
    -- STEP 1
    --
    -- XÓA FRAMEBUFFER
    --
    -- E-Ink VẪN ĐANG HIỂN THỊ PAGE A.
    --
    ------------------------------------------------------------

    if not self:clearFramebuffer() then
        self.refreshing = false

        return false
    end


    ------------------------------------------------------------
    -- STEP 2
    --
    -- Đánh dấu ReaderUI dirty.
    --
    -- KOReader sẽ render PAGE B vào framebuffer
    -- hiện tại đang là màu trắng.
    --
    ------------------------------------------------------------

    UIManager:setDirty(
        self.ui,
        "full"
    )


    ------------------------------------------------------------
    -- STEP 3
    --
    -- Force repaint để PAGE B được vẽ vào framebuffer.
    --
    -- CHƯA refresh E-Ink ở đây.
    --
    ------------------------------------------------------------

    UIManager:forceRePaint()


    ------------------------------------------------------------
    -- STEP 4
    --
    -- Chờ UIManager hoàn thành vòng event/repaint hiện tại.
    --
    -- Sau đó framebuffer phải chứa PAGE B.
    --
    ------------------------------------------------------------

    UIManager:scheduleIn(
        0,
        function()
            ----------------------------------------------------
            -- Kiểm tra plugin/document còn tồn tại
            ----------------------------------------------------

            if not self.ui
                or not self.ui.document
                or not self.reader_ready then
                self.refreshing = false

                return
            end


            ----------------------------------------------------
            -- STEP 5
            --
            -- FRAMEBUFFER hiện tại:
            --
            --     PAGE B
            --
            -- Đưa nó lên E-Ink bằng FULL refresh.
            --
            -- Đây là refresh vật lý DUY NHẤT.
            --
            ----------------------------------------------------

            self:refreshFramebuffer()


            ----------------------------------------------------
            -- DONE
            ----------------------------------------------------

            self.refreshing = false


            logger.dbg(
                "ForceRefresh: page",
                page_number,
                "fully refreshed"
            )
        end
    )


    ------------------------------------------------------------
    -- Cho các page-turn handler khác tiếp tục.
    ------------------------------------------------------------

    return false
end

----------------------------------------------------------------
-- READER READY
----------------------------------------------------------------

function ForceRefresh:onReaderReady()
    self.reader_ready = true

    self.last_page_number =
        self.ui:getCurrentPage()


    logger.dbg(
        "ForceRefresh: reader ready, page:",
        self.last_page_number
    )
end

----------------------------------------------------------------
-- CLOSE DOCUMENT
----------------------------------------------------------------

function ForceRefresh:onCloseDocument()
    self.reader_ready = false

    self.last_page_number = nil

    self.refreshing = false
end

----------------------------------------------------------------
-- SUSPEND / SLEEP
----------------------------------------------------------------

function ForceRefresh:onSuspend()
    if not self.refresh_on_suspend then
        return false
    end


    logger.dbg(
        "ForceRefresh: refreshing before suspend"
    )


    self:fullRefresh()


    return false
end

return ForceRefresh
