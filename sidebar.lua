local suits = {'Spades', 'Hearts', 'Clubs', 'Diamonds'}
local ranks = {'Ace', 'King', 'Queen', 'Jack', '10', '9', '8', '7', '6', '5', '4', '3', '2'}
local special_kinds = {{pool = 'Enhanced', set = 'Enhanced', strip = ' Card$'},
    {pool = 'Edition', set = 'Edition'}, {pool = 'Seal', set = 'Other', suffix = '_seal'}}
local PANEL_WIDTH = 2.6
local LAYOUT_WIDTH = 260
local PANEL_GAP = 4
local REFRESH_INTERVAL = 0.4
local TOGGLE_KEY = '`'
local BODY, HEADING, SMALL = 18, 22, 16
local elapsed, hidden = 0, false
local cache, cache_height, cache_scale, signature, previous_game
local fonts, quads = {}, {}

local function in_run()
    return G and G.STAGE == G.STAGES.RUN and G.GAME and G.GAME.hands and G.deck
end

-- Talisman turns some values into big-number tables.
local function plain(value)
    return to_number and to_number(value) or value
end

-- Vanilla entries first, then modded ones that appear in the deck.
local function ordered(base, buffer, present, counts)
    local list, seen = {}, {}
    for _, key in ipairs(base) do seen[key] = true end
    for _, key in ipairs(buffer) do
        if not seen[key] and present[key] then base[#base + 1] = key; seen[key] = true end
    end
    for _, key in ipairs(base) do list[#list + 1] = {key = key, n = counts[key] or 0} end
    return list
end

local function snapshot()
    local data = {special = {}, hands = {}, left = #G.deck.cards,
        total = #(G.playing_cards or {}), counted = 0, hidden = false}
    local suit_counts, rank_counts, special_counts = {}, {}, {}
    local present_suits, present_ranks = {}, {}
    local function add(counts, key)
        counts[key] = (counts[key] or 0) + 1
    end
    for _, card in pairs(G.playing_cards or {}) do
        local suit, rank = card.base.suit, card.base.value
        present_suits[suit], present_ranks[rank] = true, true
        -- Match View Deck: concealed cards remain grouped with undrawn cards.
        if card.area == G.deck or card.ability.wheel_flipped then
            data.counted = data.counted + 1
            if card.ability.wheel_flipped then data.hidden = true end
            if not SMODS.has_no_suit(card) then add(suit_counts, suit) end
            if not SMODS.has_no_rank(card) then add(rank_counts, rank) end
            if card.ability.set == 'Enhanced' then add(special_counts, card.config.center.key) end
            if card.edition and card.edition.type then add(special_counts, card.edition.key or 'e_'..card.edition.type) end
            if card.seal then add(special_counts, card.seal) end
        end
    end
    data.suits = ordered({unpack(suits)}, SMODS.Suit.obj_buffer, present_suits, suit_counts)
    data.ranks = ordered({unpack(ranks)}, SMODS.Rank.obj_buffer, present_ranks, rank_counts)
    for _, kind in ipairs(special_kinds) do
        for _, center in ipairs(G.P_CENTER_POOLS[kind.pool]) do
            local n = special_counts[center.key]
            if n then
                local key = kind.suffix and center.key:lower()..kind.suffix or center.key
                local name = localize{type = 'name_text', set = kind.set, key = key}
                if kind.strip then name = name:gsub(kind.strip, '') end
                data.special[#data.special + 1] = {key = name, n = n}
            end
        end
    end
    local parts = {tostring(data.left), tostring(data.total), tostring(data.counted), tostring(data.hidden),
        tostring(G.SETTINGS.colourblind_option), G.LANG.font.file}
    for _, list in ipairs({data.suits, data.ranks, data.special}) do
        for _, entry in ipairs(list) do parts[#parts + 1] = entry.key..'='..entry.n end
    end
    -- The panel bakes in the blind's UI colours, which ease over ~half a second.
    for _, colour in ipairs({G.C.DYN_UI.MAIN, G.C.DYN_UI.BOSS_DARK}) do
        parts[#parts + 1] = string.format('%.2f,%.2f,%.2f', colour[1], colour[2], colour[3])
    end
    for _, name in ipairs(G.handlist) do
        local hand = G.GAME.hands[name]
        if hand and hand.visible then
            local entry = {name = localize(name, 'poker_hands'), level = plain(hand.level),
                chips = number_format(hand.chips), mult = number_format(hand.mult), played = plain(hand.played)}
            data.hands[#data.hands + 1] = entry
            parts[#parts + 1] = name..':'..entry.level..':'..entry.chips..':'..entry.mult..':'..entry.played
        end
    end
    return data, table.concat(parts, '|')
end

local function layout(data)
    local special_top = 76 + #data.suits * 18
    local deck_height = math.max(81 + #data.ranks * 18, special_top + 41 + math.max(1, #data.special) * 18)
        + (data.hidden and 20 or 0)
    local run_height = 56 + #data.hands * 20
    return deck_height, run_height, deck_height + PANEL_GAP + run_height + 4, special_top
end

local function placement(height)
    local unit = G.TILESIZE * G.TILESCALE
    local top = G.consumeables.T.y + G.consumeables.T.h + 0.18
    local available = math.max(0.1, G.deck.T.y - top - 0.3)
    return math.min(PANEL_WIDTH * unit / LAYOUT_WIDTH, available * unit / height), top, unit
end

local function font_at(size)
    local key = G.LANG.font.file..':'..size
    fonts[key] = fonts[key] or love.graphics.newFont(G.LANG.font.file, size)
    return fonts[key]
end

-- Draws at the final on-screen size so text stays sharp.
local function render(data, scale)
    local lg = love.graphics
    local deck_height, run_height, height, special_top = layout(data)
    local width, pixel_height = math.ceil(LAYOUT_WIDTH * scale), math.ceil(height * scale)
    if not cache or cache:getWidth() ~= width or cache:getHeight() ~= pixel_height then
        if cache then cache:release() end
        cache = lg.newCanvas(width, pixel_height)
    end
    cache_height, cache_scale = height, scale
    lg.push('all')
    lg.setCanvas(cache)
    lg.origin()
    lg.setShader()
    lg.setScissor()
    lg.clear(0, 0, 0, 0)
    lg.scale(scale)
    local function text(value, x, y, w, colour, size, align)
        local label = tostring(value)
        local font = font_at(math.max(1, math.floor((size or BODY) * scale + 0.5)))
        local label_width = font:getWidth(label) / scale
        local fit = math.min(1, w / math.max(1, label_width))
        if align == 'right' then x = x + w - label_width * fit end
        if align == 'center' then x = x + (w - label_width * fit) / 2 end
        lg.push()
        lg.translate(x, y)
        lg.scale(fit / scale)
        lg.setFont(font)
        lg.setColor(0, 0, 0, 0.5)
        lg.print(label, scale, scale)
        lg.setColor(colour or G.C.UI.TEXT_LIGHT)
        lg.print(label, 0, 0)
        lg.pop()
    end
    local function box(y, h)
        local function shape(x, top, w, height, colour)
            lg.setColor(colour)
            lg.rectangle('fill', x + 4, top, w - 8, height)
            lg.rectangle('fill', x, top + 4, w, height - 8)
        end
        shape(1, y + 3, 258, h, {0, 0, 0, 0.45})
        shape(1, y, 258, h, G.C.DYN_UI.MAIN)
        shape(4, y + 3, 252, h - 6, G.C.DYN_UI.BOSS_DARK)
    end
    local function count(label, value, list, x, y, w)
        local maximum = 1
        for _, entry in ipairs(list) do maximum = math.max(maximum, entry.n) end
        local fraction = value / maximum
        lg.setColor(G.C.GOLD[1], G.C.GOLD[2], G.C.GOLD[3], 0.15 + 0.45 * fraction)
        lg.rectangle('fill', x, y, w * fraction, 17)
        local colour = value == 0 and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT
        if label then text(label, x + 2, y, w - 26, colour) end
        text(value, x, y, w - 2, colour, nil, 'right')
    end
    box(0, deck_height)
    text('Deck', 12, 6, 236, nil, HEADING, 'center')
    text(data.left..' / '..data.total..' left', 12, 29, 236, G.C.GOLD, HEADING, 'center')
    text('Ranks', 12, 53, 92, nil, SMALL)
    text('Suits', 116, 53, 132, nil, SMALL)
    for i, rank in ipairs(data.ranks) do
        count(SMODS.Ranks[rank.key].shorthand, rank.n, data.ranks, 12, 73 + (i-1)*18, 92)
    end
    for i, suit in ipairs(data.suits) do
        local y = 73 + (i-1)*18
        count(false, suit.n, data.suits, 116, y, 132)
        local suit_info = SMODS.Suits[suit.key]
        local atlas_key = suit_info[G.SETTINGS.colourblind_option and 'hc_ui_atlas' or 'lc_ui_atlas']
        local atlas = SMODS.get_atlas(atlas_key) or G.ASSET_ATLAS[G.SETTINGS.colourblind_option and 'ui_2' or 'ui_1']
        local quad_key = tostring(atlas)..':'..suit.key
        if not quads[quad_key] then
            quads[quad_key] = lg.newQuad(suit_info.ui_pos.x * atlas.px, suit_info.ui_pos.y * atlas.py,
                atlas.px, atlas.py, atlas.image:getDimensions())
        end
        lg.setColor(G.C.WHITE)
        lg.draw(atlas.image, quads[quad_key], 118, y + 1, 0, 15 / atlas.px, 15 / atlas.py)
    end
    text('Special', 116, special_top, 132, nil, SMALL)
    for i, entry in ipairs(data.special) do
        count(entry.key, entry.n, data.special, 116, special_top + 20 + (i-1)*18, 132)
    end
    if #data.special == 0 then text('None', 118, special_top + 20, 128, G.C.UI.TEXT_INACTIVE) end
    if data.hidden then text('Counts: '..data.counted..' incl. concealed', 12, deck_height - 23, 236, nil, SMALL) end
    local top = deck_height + PANEL_GAP
    box(top, run_height)
    text('Run info', 12, top + 6, 236, nil, HEADING, 'center')
    text('Hand', 12, top + 30, 110, nil, SMALL)
    text('Lv', 123, top + 30, 22, nil, SMALL, 'right')
    text('Chips x Mult', 150, top + 30, 78, nil, SMALL, 'center')
    text('#', 231, top + 30, 17, nil, SMALL, 'right')
    for i, hand in ipairs(data.hands) do
        local y = top + 51 + (i-1)*20
        if i % 2 == 0 then
            lg.setColor(0, 0, 0, 0.12)
            lg.rectangle('fill', 10, y, 240, 19)
        end
        local upgraded = hand.level > 1 and G.C.GOLD or G.C.UI.TEXT_LIGHT
        text(hand.name, 12, y, 109, upgraded)
        text(hand.level, 123, y, 22, upgraded, nil, 'right')
        text(hand.chips, 149, y, 34, G.C.CHIPS, nil, 'right')
        text('x', 185, y, 9, nil, SMALL)
        text(hand.mult, 196, y, 31, G.C.MULT, nil, 'right')
        text(hand.played, 231, y, 17, hand.played == 0 and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT, nil, 'right')
    end
    lg.setCanvas()
    lg.pop()
end

local update = Game.update
function Game:update(dt, ...)
    update(self, dt, ...)
    if not in_run() then
        elapsed, signature, previous_game = 0, nil, nil
        return
    end
    elapsed = elapsed + dt
    if previous_game == G.GAME and elapsed < REFRESH_INTERVAL then return end
    elapsed = 0
    local data, current = snapshot()
    local _, _, height = layout(data)
    local scale = placement(height)
    if current ~= signature or previous_game ~= G.GAME or scale ~= cache_scale then
        render(data, scale)
        signature, previous_game = current, G.GAME
    end
end

local key_press_update = Controller.key_press_update
function Controller:key_press_update(key, dt)
    if key == TOGGLE_KEY and not self.text_input_hook then hidden = not hidden end
    return key_press_update(self, key, dt)
end

local foreground, foreground_piece
local collecting, capturing = false, false

local function foreground_object(node)
    if node == G.deck_preview or node == G.achievement_notification or node.attention_text then return true end
    for _, group in ipairs({G.I.POPUP, G.I.ALERT}) do
        for _, object in pairs(group) do if node == object then return true end end
    end
    if getmetatable(node) == Card then
        for _, state in ipairs({'hovering', 'dragging', 'focused'}) do
            if G.CONTROLLER[state].target == node then return true end
        end
    end
    return false
end

local function capture_draw(original, node, ...)
    if not collecting or capturing or not foreground_object(node) then
        return original(node, ...)
    end
    local lg = love.graphics
    lg.push('all')
    lg.setCanvas({foreground_piece, stencil = true})
    lg.clear(0, 0, 0, 0)
    capturing = true
    original(node, ...)
    capturing = false
    lg.pop()
    lg.push('all')
    lg.origin()
    lg.setShader()
    lg.setScissor()
    lg.setStencilTest()
    lg.setColor(G.C.WHITE)
    lg.setBlendMode('alpha', 'premultiplied')
    -- Draw once, then reuse its transparent pixels in the foreground layer.
    lg.draw(foreground_piece)
    lg.setCanvas(foreground)
    lg.draw(foreground_piece)
    lg.pop()
end

local card_draw, ui_draw = Card.draw, UIBox.draw
function Card:draw(...) return capture_draw(card_draw, self, ...) end
function UIBox:draw(...) return capture_draw(ui_draw, self, ...) end

local draw = Game.draw
function Game:draw(...)
    local lg = love.graphics
    local show = not hidden and in_run() and cache and previous_game == G.GAME and not G.OVERLAY_MENU
    if show then
        local width, height = G.CANVAS:getDimensions()
        if not foreground or foreground:getWidth() ~= width or foreground:getHeight() ~= height then
            if foreground then foreground:release(); foreground_piece:release() end
            foreground = lg.newCanvas(width, height)
            foreground_piece = lg.newCanvas(width, height)
        end
        lg.push('all')
        lg.setCanvas(foreground)
        lg.clear(0, 0, 0, 0)
        lg.pop()
        collecting = true
    end
    draw(self, ...)
    collecting = false
    if not show then return end
    local _, top, unit = placement(cache_height)
    local room = G.ROOM_ORIG or G.ROOM.T
    local x = math.floor((room.x + G.TILE_W - 0.08) * unit - cache:getWidth())
    local y = math.floor((room.y + top + 0.3) * unit)
    lg.push('all')
    lg.origin()
    lg.setShader()
    lg.setColor(G.C.WHITE)
    lg.draw(cache, x, y)
    lg.setScissor(x, y, cache:getWidth(), cache:getHeight())
    lg.setBlendMode('alpha', 'premultiplied')
    lg.draw(foreground, 0, 0, 0, 1 / G.CANV_SCALE, 1 / G.CANV_SCALE)
    lg.pop()
end
