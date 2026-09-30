local Rres = {}
Rres.__index = Rres

local bit = bit or require("bit")
local UINT32 = 4294967296

-- Convert a signed bit-operation result into an unsigned 32-bit number.
local function unsigned(value)
    return value < 0 and value + UINT32 or value
end

-- Read a little-endian 16-bit integer from a byte string.
local function u16le(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

-- Read a little-endian 32-bit integer from a byte string.
local function u32le(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local crcTable = {}
-- Build the CRC lookup once for both resource-name hashes and payload checks.
for n = 0, 255 do
    local c = n
    for _ = 1, 8 do
        if bit.band(c, 1) ~= 0 then
            c = bit.bxor(bit.rshift(c, 1), 0xEDB88320)
        else
            c = bit.rshift(c, 1)
        end
    end
    crcTable[n] = c
end

-- Compute the checksum used for resource IDs and chunk integrity.
local function crc32(data)
    local crc = -1
    for i = 1, #data do
        local index = bit.band(bit.bxor(crc, data:byte(i)), 0xff)
        crc = bit.bxor(bit.rshift(crc, 8), crcTable[index])
    end
    return unsigned(bit.bnot(crc))
end

-- Normalize path separators before hashing a resource name.
local function pathId(path)
    return crc32(path:gsub("\\", "/"))
end

-- Unpack the zero-terminated extension from two RAWD property words.
local function extensionFromProps(a, b)
    local chars = {
        bit.band(bit.rshift(a, 24), 0xff), bit.band(bit.rshift(a, 16), 0xff),
        bit.band(bit.rshift(a, 8), 0xff), bit.band(a, 0xff),
        bit.band(bit.rshift(b, 24), 0xff), bit.band(bit.rshift(b, 16), 0xff),
        bit.band(bit.rshift(b, 8), 0xff), bit.band(b, 0xff),
    }
    local out = {}
    for _, byte in ipairs(chars) do
        if byte == 0 then break end
        out[#out + 1] = string.char(byte)
    end
    return table.concat(out)
end

-- Read the required byte count or fail with a truncation diagnostic.
local function readExactly(file, size, description)
    local data = file:read(size)
    assert(data and #data == size, "truncated rres " .. description)
    return data
end

-- Validate the archive and index supported RAWD chunks without loading payloads.
function Rres.open(filename)
    local file, err = love.filesystem.newFile(filename, "r")
    assert(file, err or ("unable to open " .. filename))

    local header = readExactly(file, 16, "header")
    assert(header:sub(1, 4) == "rres", "invalid rres signature")
    local version = u16le(header, 5)
    assert(version == 100, "unsupported rres version " .. version)

    local self = setmetatable({
        filename = filename,
        file = file,
        version = version,
        entries = {},
        chunkCount = u16le(header, 7),
    }, Rres)

    -- Index offsets now and seek over payloads so resources are loaded only when requested.
    for _ = 1, self.chunkCount do
        local infoOffset = file:tell()
        local info = readExactly(file, 32, "chunk header")
        local kind = info:sub(1, 4)
        local id = u32le(info, 5)
        local compression = info:byte(9)
        local cipher = info:byte(10)
        local packedSize = u32le(info, 13)
        local baseSize = u32le(info, 17)
        local checksum = u32le(info, 29)

        -- The reader intentionally supports only the uncompressed, unencrypted format written by the packer.
        assert(kind == "RAWD", "unsupported rres chunk type " .. kind)
        assert(compression == 0, "compressed chunks are not supported yet")
        assert(cipher == 0, "encrypted chunks are not supported")
        assert(not self.entries[id], "duplicate/colliding resource id " .. id)

        self.entries[id] = {
            infoOffset = infoOffset,
            dataOffset = file:tell(),
            packedSize = packedSize,
            baseSize = baseSize,
            checksum = checksum,
        }
        assert(file:seek(file:tell() + packedSize), "unable to seek over rres chunk")
    end

    return self
end

-- Count indexed resources, whose IDs are not sequential array positions.
function Rres:count()
    local count = 0
    for _ in pairs(self.entries) do count = count + 1 end
    return count
end

-- Look up a resource, validate its checksum, and return bytes plus extension.
function Rres:read(path)
    local normalized = path:gsub("\\", "/")
    local entry = self.entries[pathId(normalized)]
    assert(entry, "resource not found: " .. normalized)
    assert(self.file:seek(entry.dataOffset), "unable to seek to resource: " .. normalized)

    -- Validate the full property-plus-payload block before interpreting its fields.
    local chunkData = readExactly(self.file, entry.packedSize, "resource data")
    assert(crc32(chunkData) == entry.checksum, "CRC32 mismatch: " .. normalized)

    local propCount = u32le(chunkData, 1)
    assert(propCount == 4, "invalid RAWD property count: " .. propCount)
    local size = u32le(chunkData, 5)
    local ext1 = u32le(chunkData, 9)
    local ext2 = u32le(chunkData, 13)
    -- Skip the property count and all property words; Lua byte offsets are one-based.
    local dataOffset = 4 + propCount * 4 + 1
    local data = chunkData:sub(dataOffset, dataOffset + size - 1)
    assert(#data == size, "invalid resource size: " .. normalized)
    return data, extensionFromProps(ext1, ext2)
end

-- Wrap resource bytes for LÖVE, restoring an extension when the name lacks one.
function Rres:fileData(path)
    local data, extension = self:read(path)
    local name = path
    if extension ~= "" and not name:lower():match("%.[^/]+$") then
        name = name .. extension
    end
    return love.filesystem.newFileData(data, name)
end

-- Decode a packed resource as a LÖVE image.
function Rres:image(path, settings)
    return love.graphics.newImage(self:fileData(path), settings)
end

-- Create a LÖVE audio source, defaulting to a fully loaded static source.
function Rres:audio(path, sourceType)
    return love.audio.newSource(self:fileData(path), sourceType or "static")
end

-- Close the archive handle if it is still open.
function Rres:close()
    if self.file and self.file:isOpen() then self.file:close() end
end

return Rres

