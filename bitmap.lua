local bit = bit or bit32 or require("bit")
local table_create = table.create or function(n) return {}; end

local Buffer = {}
function Buffer.new(size)
    local self = {}
    self._raw = table_create(size or 0)
    self.LittleEndian = false
    self.Position = 1
    return setmetatable(self, { __index = Buffer })
end

function Buffer:GetData()
    return table.concat(self._raw)
end

function Buffer:GetHexData()
    local raw, hex = self._raw, ""
    for i = 1, #raw do
        hex = hex..string.format("%02x ", string.byte(raw[i]))
    end
    return hex
end

function Buffer:_WriteBytes(bytes)
    local raw, pos, size = self._raw, self.Position, #bytes
    if self.LittleEndian then
        for i = 1, size do
            raw[pos + i - 1] = string.char(bytes[size - i + 1])
        end
    else
        for i = 1, size do
            raw[pos + i - 1] = string.char(bytes[i])
        end
    end
    self.Position = pos + size
end

function Buffer:Write8(n)
    assert(n <= 0xFF, "integer too large")
    self:_WriteBytes({ n })
end

function Buffer:Write16(n)
    assert(n <= 0xFFFF, "integer too large")
    self:_WriteBytes({
        bit.band(n, 0xFF00) / 0x100,
        bit.band(n, 0x00FF) / 0x001,
    })
end

function Buffer:Write24(n)
    assert(n <= 0xFFFFFF, "integer too large")
    self:_WriteBytes({
        bit.band(n, 0xFF0000) / 0x10000,
        bit.band(n, 0x00FF00) / 0x00100,
        bit.band(n, 0x0000FF) / 0x00001,
    })
end

function Buffer:Write32(n)
    assert(n <= 0xFFFFFFFF, "integer too large")
    self:_WriteBytes({
        bit.band(n, 0xFF000000) / 0x1000000,
        bit.band(n, 0x00FF0000) / 0x0010000,
        bit.band(n, 0x0000FF00) / 0x0000100,
        bit.band(n, 0x000000FF) / 0x0000001,
    })
end

function Buffer:WriteStr(str)
    local raw, pos, size = self._raw, self.Position, #str
    for i = 1, size do
        raw[pos + i - 1] = string.sub(str, i, i)
    end
    self.Position = pos + size
end

function Buffer:WriteLStr(str, size)
    size = size or #str
    self:Write32(size)
    self:WriteStr(str)
end

local Bitmap = {}
function Bitmap.new(size)
    local self = {}
    self._buf = Buffer.new()
    self._buf.LittleEndian = true
    self.Size = size
    self.Pixels = {}
    return setmetatable(self, { __index = Bitmap })
end

function Bitmap:Compile()
    local buf = self._buf
    buf.Position = 1

    -- File header
    buf:Write16(0x4D42)     -- Magic short
    buf:Write32(0xAABBCCDD) -- File size (come back to it)
    buf:Write32(0x00000000) -- Reserved
    buf:Write32(0x00000036) -- Pixel array offset

    -- pixels per meter formula
    -- px   -> 64 00 00 00 (100px)
    -- px/m -> C3 0E 00 00 (3779ppm)
    -- solve for x (im actually using algebra for once)
    -- 100x / 100 = 3779 / 100
    -- x = 37.79
    -- px * 37.79 = ppm

    -- DIB header
    buf:Write32(0x00000028)  -- Size of header (BITMAPINFOHEADER)
    buf:Write32(self.Size.X) -- Size (X, signed)
    buf:Write32(self.Size.Y) -- Size (Y, signed)
    buf:Write16(0x0001)      -- # of color planes
    buf:Write16(0x0018)      -- # of bits per pixel (24 bits; 3 bytes)
    buf:Write32(0x00000000)  -- Compression (BI_RGB; none)
    buf:Write32(0x00000000)  -- Image size (not needed)
    buf:Write32(self.Size.X * 37.79) -- Horizontal resolution (px/m, signed, you can tell that i dont give a shit if its signed or not)
    buf:Write32(self.Size.Y * 37.79) -- Vertical resolution (px/m, signed)
    buf:Write32(0x00000000)  -- # of colors in palette (0=2^n)
    buf:Write32(0x00000000)  -- # of important colors (0=all)

    -- Image data
    local pixels = self.Pixels
    for i = 1, #pixels do
        local px = pixels[i]
        buf:Write8(px.R)
        buf:Write8(px.G)
        buf:Write8(px.B)
    end

    buf.Position = 0x03 -- Jump to file size offset
    buf:Write32(#buf._raw)

    return buf
end

function hsvToRgb(h, s, v) -- pasted from stack overflow
    local r, g, b

    local i = math.floor(h * 6);
    local f = h * 6 - i;
    local p = v * (1 - s);
    local q = v * (1 - f * s);
    local t = v * (1 - (1 - f) * s);

    i = i % 6

    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    end

    return {R = r * 255, G = g * 255, B = b * 255}
end

-- make a 100x100 bitmap with a purple gradient
local bmp = Bitmap.new(Vector2.new(100, 100))
for x = 1, bmp.Size.X do
    for y = 1, bmp.Size.Y do
        bmp.Pixels[#bmp.Pixels + 1] = hsvToRgb(0.5, (100-y)/100, x/100)
    end
end

local img = Drawing.new("Image")
img.Size = Vector2.new(100, 100)
img.Position = Vector2.new(0, 0)
img.Data = bmp:Compile():GetData()
img.Transparency = 1
img.Visible = true

print("DONE")
