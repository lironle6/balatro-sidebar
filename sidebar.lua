local suits = {'Spades', 'Hearts', 'Clubs', 'Diamonds'}
local ranks = {'Ace', 'King', 'Queen', 'Jack', '10', '9', '8', '7', '6', '5', '4', '3', '2'}
local rank_labels = {'A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2'}
local special_order = {'Steel', 'Glass', 'Gold', 'Lucky', 'Mult', 'Bonus', 'Wild', 'Stone',
    'Foil', 'Holo', 'Polychrome', 'Negative', 'Red seal', 'Blue seal', 'Gold seal', 'Purple seal'}
local PANEL_WIDTH = 2.6
local CACHE_WIDTH = 260
local PANEL_GAP = 4
local REFRESH_INTERVAL = 0.4
local elapsed, cache_height = 0, 0
local cache, signature, previous_game, fonts
local quads = {}

local function in_run()
    return G and G.STAGE == G.STAGES.RUN and G.GAME and G.GAME.hands and G.deck
end

local function snapshot()
    local data = {suits = {}, ranks = {}, special = {}, hands = {}, left = #G.deck.cards,
        total = #(G.playing_cards or {}), counted = 0, hidden = false}
    for _, suit in ipairs(suits) do data.suits[suit] = 0 end
    for _, rank in ipairs(ranks) do data.ranks[rank] = 0 end
    local function add(key)
        data.special[key] = (data.special[key] or 0) + 1
    end
    for _, card in pairs(G.playing_cards or {}) do
        -- Match View Deck: concealed cards remain grouped with undrawn cards.
        if card.area == G.deck or card.ability.wheel_flipped then
            data.counted = data.counted + 1
            if card.ability.wheel_flipped then data.hidden = true end
            local suit, rank = card.base.suit, card.base.value
            if not SMODS.has_no_suit(card) and data.suits[suit] ~= nil then data.suits[suit] = data.suits[suit] + 1 end
            if not SMODS.has_no_rank(card) and data.ranks[rank] ~= nil then data.ranks[rank] = data.ranks[rank] + 1 end
            local effect = card.ability.effect
            if effect and effect ~= 'Base' then add(effect:gsub(' Card$', '')) end
            if card.edition and card.edition.type then add(card.edition.type:gsub('^%l', string.upper)) end
            if card.seal then add(card.seal..' seal') end
        end
    end
    local parts = {tostring(data.left), tostring(data.total), tostring(data.counted), tostring(data.hidden), tostring(G.SETTINGS.colourblind_option)}
    for _, suit in ipairs(suits) do parts[#parts + 1] = tostring(data.suits[suit]) end
    for _, rank in ipairs(ranks) do parts[#parts + 1] = tostring(data.ranks[rank]) end
    for _, key in ipairs(special_order) do parts[#parts + 1] = tostring(data.special[key]) end
    for _, name in ipairs(G.handlist) do
        local hand = G.GAME.hands[name]
        if hand and hand.visible then
            local entry = {name = localize(name, 'poker_hands'), level = hand.level,
                chips = number_format(hand.chips), mult = number_format(hand.mult), played = hand.played}
            data.hands[#data.hands + 1] = entry
            parts[#parts + 1] = name..':'..entry.level..':'..entry.chips..':'..entry.mult..':'..entry.played
        end
    end
    return data, table.concat(parts, '|')
end

local function render(data)
    local lg = love.graphics
    fonts = fonts or {body = lg.newFont('resources/fonts/m6x11plus.ttf', 18),
        heading = lg.newFont('resources/fonts/m6x11plus.ttf', 22),
        small = lg.newFont('resources/fonts/m6x11plus.ttf', 16)}
    local special_keys = {}
    for _, key in ipairs(special_order) do
        if data.special[key] then special_keys[#special_keys + 1] = key end
    end
    local deck_height = 81 + math.max(13, 6 + #special_keys) * 18 + (data.hidden and 20 or 0)
    local run_height = 56 + #data.hands * 20
    local height = deck_height + PANEL_GAP + run_height + 4
    if not cache or cache_height ~= height then
        if cache then cache:release() end
        cache = lg.newCanvas(CACHE_WIDTH, height)
        cache:setFilter('linear', 'linear')
        cache_height = height
    end
    lg.push('all')
    lg.setCanvas(cache)
    lg.origin()
    lg.setShader()
    lg.setScissor()
    lg.clear(0, 0, 0, 0)
    local function text(value, x, y, w, colour, font, align)
        local label = tostring(value)
        font = font or fonts.body
        local scale = math.min(1, w / math.max(1, font:getWidth(label)))
        local actual_width = font:getWidth(label) * scale
        if align == 'right' then x = x + w - actual_width end
        if align == 'center' then x = x + (w - actual_width) / 2 end
        lg.push()
        lg.translate(x, y)
        lg.scale(scale)
        lg.setFont(font)
        lg.setColor(0, 0, 0, 0.5)
        lg.print(label, 1, 1)
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
    local function count(label, value, counts, x, y, w)
        local maximum = 1
        for _, n in pairs(counts) do maximum = math.max(maximum, n) end
        local fraction = value / maximum
        lg.setColor(G.C.GOLD[1], G.C.GOLD[2], G.C.GOLD[3], 0.15 + 0.45 * fraction)
        lg.rectangle('fill', x, y, w * fraction, 17)
        local colour = value == 0 and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT
        if type(label) == 'string' then text(label, x + 2, y, w - 26, colour) end
        text(value, x, y, w - 2, colour, nil, 'right')
    end
    box(0, deck_height)
    text('Deck', 12, 6, 236, nil, fonts.heading, 'center')
    text(data.left..' / '..data.total..' left', 12, 29, 236, G.C.GOLD, fonts.heading, 'center')
    text('Ranks', 12, 53, 92, nil, fonts.small)
    text('Suits', 116, 53, 132, nil, fonts.small)
    for i, rank in ipairs(ranks) do count(rank_labels[i], data.ranks[rank], data.ranks, 12, 73 + (i-1)*18, 92) end
    for i, suit in ipairs(suits) do
        local y = 73 + (i-1)*18
        count(false, data.suits[suit], data.suits, 116, y, 132)
        local suit_info = SMODS.Suits[suit]
        local atlas_key = suit_info[G.SETTINGS.colourblind_option and 'hc_ui_atlas' or 'lc_ui_atlas']
        local atlas = SMODS.get_atlas(atlas_key) or G.ASSET_ATLAS[G.SETTINGS.colourblind_option and 'ui_2' or 'ui_1']
        local quad_key = tostring(atlas)..':'..suit
        if not quads[quad_key] then
            quads[quad_key] = lg.newQuad(suit_info.ui_pos.x * atlas.px, suit_info.ui_pos.y * atlas.py,
                atlas.px, atlas.py, atlas.image:getDimensions())
        end
        lg.setColor(G.C.WHITE)
        lg.draw(atlas.image, quads[quad_key], 118, y + 1, 0, 15 / atlas.px, 15 / atlas.py)
    end
    text('Special', 116, 148, 132, nil, fonts.small)
    for i, key in ipairs(special_keys) do count(key, data.special[key], data.special, 116, 168 + (i-1)*18, 132) end
    if #special_keys == 0 then text('None', 118, 168, 128, G.C.UI.TEXT_INACTIVE) end
    if data.hidden then text('Counts: '..data.counted..' incl. concealed', 12, deck_height - 23, 236, nil, fonts.small) end
    local top = deck_height + PANEL_GAP
    box(top, run_height)
    text('Run info', 12, top + 6, 236, nil, fonts.heading, 'center')
    text('Hand', 12, top + 30, 110, nil, fonts.small)
    text('Lv', 123, top + 30, 22, nil, fonts.small, 'right')
    text('Chips x Mult', 150, top + 30, 78, nil, fonts.small, 'center')
    text('#', 231, top + 30, 17, nil, fonts.small, 'right')
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
        text('x', 185, y, 9, nil, fonts.small)
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
    if current ~= signature or previous_game ~= G.GAME then
        render(data)
        signature, previous_game = current, G.GAME
    end
end

local foreground, foreground_piece
local collecting, capturing = false, false

local function foreground_object(node)
    if node == G.deck_preview or node == G.achievement_notification then return true end
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
    if in_run() and cache and not G.OVERLAY_MENU then
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
    if not in_run() or not cache or previous_game ~= G.GAME or G.OVERLAY_MENU then return end
    local unit = G.TILESIZE * G.TILESCALE
    local top = G.consumeables.T.h + 0.18
    local available = math.max(0.1, G.deck.T.y - top - 0.3)
    local scale = math.min(PANEL_WIDTH * unit / CACHE_WIDTH, available * unit / cache_height)
    local room = G.ROOM_ORIG or G.ROOM.T
    local x = (room.x + G.TILE_W - 0.08) * unit - CACHE_WIDTH * scale
    local y = (room.y + top + 0.3) * unit
    lg.push('all')
    lg.origin()
    lg.setShader()
    lg.setColor(G.C.WHITE)
    lg.draw(cache, x, y, 0, scale, scale)
    if foreground then
        lg.setScissor(x, y, CACHE_WIDTH * scale, cache_height * scale)
        lg.setBlendMode('alpha', 'premultiplied')
        lg.draw(foreground, 0, 0, 0, 1 / G.CANV_SCALE, 1 / G.CANV_SCALE)
    end
    lg.pop()
end
