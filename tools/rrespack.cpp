#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr std::uint16_t kRresVersion = 100;

struct Asset {
    fs::path source;
    std::string name;
    std::vector<std::uint8_t> bytes;
    std::uint32_t id = 0;
};

// Compute the archive CRC32 for raw bytes using the same polynomial as the Lua reader.
std::uint32_t crc32(const std::uint8_t* data, std::size_t size) {
    // Construct the bytewise CRC lookup once, then reuse it for every resource.
    static const auto table = [] {
        std::array<std::uint32_t, 256> values{};
        for (std::uint32_t n = 0; n < values.size(); ++n) {
            std::uint32_t c = n;
            for (int bit = 0; bit < 8; ++bit) {
                c = (c & 1u) ? (0xEDB88320u ^ (c >> 1u)) : (c >> 1u);
            }
            values[n] = c;
        }
        return values;
    }();

    std::uint32_t crc = 0xFFFFFFFFu;
    for (std::size_t i = 0; i < size; ++i) {
        crc = table[(crc ^ data[i]) & 0xFFu] ^ (crc >> 8u);
    }
    return crc ^ 0xFFFFFFFFu;
}

// Hash normalized resource names through the same byte-oriented checksum.
std::uint32_t crc32(const std::string& value) {
    return crc32(reinterpret_cast<const std::uint8_t*>(value.data()), value.size());
}

// Write a 16-bit little-endian field independently of host byte order.
void writeU16(std::ostream& out, std::uint16_t value) {
    const std::array<char, 2> bytes{
        static_cast<char>(value & 0xFFu),
        static_cast<char>((value >> 8u) & 0xFFu),
    };
    out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}

// Write a 32-bit little-endian field independently of host byte order.
void writeU32(std::ostream& out, std::uint32_t value) {
    const std::array<char, 4> bytes{
        static_cast<char>(value & 0xFFu),
        static_cast<char>((value >> 8u) & 0xFFu),
        static_cast<char>((value >> 16u) & 0xFFu),
        static_cast<char>((value >> 24u) & 0xFFu),
    };
    out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}

// Append a little-endian property word to an in-memory resource block.
void appendU32(std::vector<std::uint8_t>& bytes, std::uint32_t value) {
    bytes.push_back(static_cast<std::uint8_t>(value));
    bytes.push_back(static_cast<std::uint8_t>(value >> 8u));
    bytes.push_back(static_cast<std::uint8_t>(value >> 16u));
    bytes.push_back(static_cast<std::uint8_t>(value >> 24u));
}

// Pack four extension characters into a property word, padding missing bytes with zero.
std::uint32_t extensionWord(const std::string& extension, std::size_t offset) {
    std::uint32_t result = 0;
    for (std::size_t i = 0; i < 4; ++i) {
        const std::uint8_t byte = offset + i < extension.size()
            ? static_cast<std::uint8_t>(extension[offset + i]) : 0;
        result = (result << 8u) | byte;
    }
    return result;
}

// Read one complete binary asset and report open, size, or read failures.
std::vector<std::uint8_t> readFile(const fs::path& path) {
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) throw std::runtime_error("could not open input: " + path.string());
    const auto end = input.tellg();
    if (end < 0) throw std::runtime_error("could not size input: " + path.string());
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(end));
    input.seekg(0);
    if (!bytes.empty()) {
        input.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        if (!input) throw std::runtime_error("could not read input: " + path.string());
    }
    return bytes;
}

// Enumerate visible files, normalize names, sort output, and reject path-hash collisions.
std::vector<Asset> collectAssets(const fs::path& root, const fs::path& output) {
    std::vector<Asset> assets;
    const fs::path canonicalOutput = fs::absolute(output).lexically_normal();
    for (const auto& entry : fs::recursive_directory_iterator(root)) {
        if (!entry.is_regular_file()) continue;
        if (fs::absolute(entry.path()).lexically_normal() == canonicalOutput) continue;

        const fs::path relative = fs::relative(entry.path(), root);
        // Exclude a file when any relative path component begins with a dot.
        const bool hidden = std::any_of(relative.begin(), relative.end(), [](const fs::path& part) {
            const std::string name = part.string();
            return !name.empty() && name.front() == '.';
        });
        if (hidden) continue;

        Asset asset;
        asset.source = entry.path();
        asset.name = relative.generic_string();
        asset.id = crc32(asset.name);
        assets.push_back(std::move(asset));
    }
    // Sort by normalized name so filesystem traversal order cannot change the archive.
    std::sort(assets.begin(), assets.end(), [](const Asset& a, const Asset& b) {
        return a.name < b.name;
    });

    // Distinct names must not silently share the reader's checksum-based lookup key.
    std::unordered_map<std::uint32_t, std::string> ids;
    for (const auto& asset : assets) {
        const auto [it, inserted] = ids.emplace(asset.id, asset.name);
        if (!inserted) {
            throw std::runtime_error("CRC32 path collision: " + it->second + " and " + asset.name);
        }
    }
    return assets;
}

// Write an rres header followed by one uncompressed RAWD chunk per asset.
void pack(const fs::path& root, const fs::path& output) {
    if (!fs::is_directory(root)) throw std::runtime_error("input is not a directory: " + root.string());
    auto assets = collectAssets(root, output);
    if (assets.size() > 65535) throw std::runtime_error("rres supports at most 65535 chunks");

    fs::create_directories(output.parent_path().empty() ? fs::path(".") : output.parent_path());
    std::ofstream out(output, std::ios::binary | std::ios::trunc);
    if (!out) throw std::runtime_error("could not create output: " + output.string());

    // The fixed 16-byte file header declares version and chunk count.
    out.write("rres", 4);
    writeU16(out, kRresVersion);
    writeU16(out, static_cast<std::uint16_t>(assets.size()));
    writeU32(out, 0); // Optional central directory omitted; IDs provide lookup.
    writeU32(out, 0);

    std::uint64_t totalBytes = 0;
    for (auto& asset : assets) {
        asset.bytes = readFile(asset.source);
        if (asset.bytes.size() > UINT32_MAX - 20u) {
            throw std::runtime_error("asset is too large for rres: " + asset.name);
        }

        std::string extension = asset.source.extension().string();
        // Lowercase extensions for consistent type hints when LÖVE decodes FileData.
        std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });
        if (extension.size() > 8) extension.resize(8);

        std::vector<std::uint8_t> chunkData;
        // Checksum properties together with payload, matching the Lua reader's integrity check.
        chunkData.reserve(20 + asset.bytes.size());
        appendU32(chunkData, 4);
        appendU32(chunkData, static_cast<std::uint32_t>(asset.bytes.size()));
        appendU32(chunkData, extensionWord(extension, 0));
        appendU32(chunkData, extensionWord(extension, 4));
        appendU32(chunkData, 0);
        chunkData.insert(chunkData.end(), asset.bytes.begin(), asset.bytes.end());

        // The 32-byte chunk header precedes the property block and original file bytes.
        out.write("RAWD", 4);
        writeU32(out, asset.id);
        out.put(0); // RRES_COMP_NONE
        out.put(0); // RRES_CIPHER_NONE
        writeU16(out, 0);
        writeU32(out, static_cast<std::uint32_t>(chunkData.size()));
        writeU32(out, static_cast<std::uint32_t>(chunkData.size()));
        writeU32(out, 0);
        writeU32(out, 0);
        writeU32(out, crc32(chunkData.data(), chunkData.size()));
        out.write(reinterpret_cast<const char*>(chunkData.data()), static_cast<std::streamsize>(chunkData.size()));
        if (!out) throw std::runtime_error("failed writing output: " + output.string());

        totalBytes += asset.bytes.size();
        std::cout << "packed  " << asset.name << " (" << asset.bytes.size() << " bytes)\n";
    }

    std::cout << "wrote " << output.string() << ": " << assets.size()
              << " resources, " << totalBytes << " source bytes\n";
}

} // namespace

// Validate CLI arguments and translate packing failures into a nonzero exit status.
int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "usage: rrespack <input-directory> <output.rres>\n";
        return 2;
    }
    try {
        pack(argv[1], argv[2]);
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "rrespack: " << error.what() << '\n';
        return 1;
    }
}
