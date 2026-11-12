// SHA-256, HMAC-SHA256 и PBKDF2-HMAC-SHA256 без внешних библиотек (для хранения пароля администратора).
// Проверено на стандартных тестовых векторах (FIPS 180-4, RFC 4231, RFC 7914 / общеизвестные векторы PBKDF2).
#pragma once
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <random>
#include <string>
#include <vector>

namespace dp {
namespace sha {

class Sha256 {
public:
    Sha256() { reset(); }
    void reset() {
        static const uint32_t h0[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
        std::memcpy(h_, h0, sizeof h_); len_ = 0; fill_ = 0;
    }
    void update(const uint8_t* d, size_t n) {
        len_ += n;
        while (n > 0) {
            const size_t k = std::min(n, size_t(64) - fill_);
            std::memcpy(buf_ + fill_, d, k); fill_ += k; d += k; n -= k;
            if (fill_ == 64) { block(buf_); fill_ = 0; }
        }
    }
    void update(const std::string& s) { update(reinterpret_cast<const uint8_t*>(s.data()), s.size()); }
    std::vector<uint8_t> finish() {
        const uint64_t bits = len_ * 8;
        uint8_t pad = 0x80; update(&pad, 1);
        pad = 0; while (fill_ != 56) update(&pad, 1);
        uint8_t l[8]; for (int i = 0; i < 8; ++i) l[i] = uint8_t(bits >> (56 - 8 * i));
        update(l, 8);
        std::vector<uint8_t> out(32);
        for (int i = 0; i < 8; ++i) { out[4 * i] = uint8_t(h_[i] >> 24); out[4 * i + 1] = uint8_t(h_[i] >> 16); out[4 * i + 2] = uint8_t(h_[i] >> 8); out[4 * i + 3] = uint8_t(h_[i]); }
        reset();
        return out;
    }
private:
    static uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
    void block(const uint8_t* p) {
        static const uint32_t k[64] = {
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
        uint32_t w[64];
        for (int i = 0; i < 16; ++i) w[i] = (uint32_t(p[4 * i]) << 24) | (uint32_t(p[4 * i + 1]) << 16) | (uint32_t(p[4 * i + 2]) << 8) | p[4 * i + 3];
        for (int i = 16; i < 64; ++i) {
            const uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            const uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        uint32_t a = h_[0], b = h_[1], c = h_[2], d = h_[3], e = h_[4], f = h_[5], g = h_[6], h = h_[7];
        for (int i = 0; i < 64; ++i) {
            const uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25), ch = (e & f) ^ (~e & g);
            const uint32_t t1 = h + S1 + ch + k[i] + w[i];
            const uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22), mj = (a & b) ^ (a & c) ^ (b & c);
            const uint32_t t2 = S0 + mj;
            h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
        }
        h_[0] += a; h_[1] += b; h_[2] += c; h_[3] += d; h_[4] += e; h_[5] += f; h_[6] += g; h_[7] += h;
    }
    uint32_t h_[8]; uint8_t buf_[64]; uint64_t len_ = 0; size_t fill_ = 0;
};

inline std::vector<uint8_t> sha256(const std::string& s) { Sha256 h; h.update(s); return h.finish(); }

inline std::vector<uint8_t> hmac(const std::vector<uint8_t>& key, const uint8_t* msg, size_t n) {
    std::vector<uint8_t> k = key;
    if (k.size() > 64) { Sha256 h; h.update(k.data(), k.size()); k = h.finish(); }
    k.resize(64, 0);
    uint8_t ip[64], op[64];
    for (int i = 0; i < 64; ++i) { ip[i] = k[i] ^ 0x36; op[i] = k[i] ^ 0x5c; }
    Sha256 in; in.update(ip, 64); in.update(msg, n); const auto ih = in.finish();
    Sha256 out; out.update(op, 64); out.update(ih.data(), ih.size());
    return out.finish();
}

// PBKDF2-HMAC-SHA256, длина ключа dkLen байт
inline std::vector<uint8_t> pbkdf2(const std::string& password, const std::vector<uint8_t>& salt, int iterations, size_t dkLen = 32) {
    const std::vector<uint8_t> pw(password.begin(), password.end());
    std::vector<uint8_t> dk;
    for (uint32_t blk = 1; dk.size() < dkLen; ++blk) {
        std::vector<uint8_t> s = salt;
        s.push_back(uint8_t(blk >> 24)); s.push_back(uint8_t(blk >> 16)); s.push_back(uint8_t(blk >> 8)); s.push_back(uint8_t(blk));
        std::vector<uint8_t> u = hmac(pw, s.data(), s.size()), t = u;
        for (int i = 1; i < iterations; ++i) { u = hmac(pw, u.data(), u.size()); for (size_t j = 0; j < t.size(); ++j) t[j] ^= u[j]; }
        dk.insert(dk.end(), t.begin(), t.end());
    }
    dk.resize(dkLen);
    return dk;
}

inline std::string toHex(const std::vector<uint8_t>& v) {
    static const char* d = "0123456789abcdef"; std::string r;
    for (uint8_t b : v) { r += d[b >> 4]; r += d[b & 15]; }
    return r;
}
inline bool fromHex(const std::string& s, std::vector<uint8_t>& out) {
    out.clear(); if (s.size() % 2) return false;
    auto hv = [](char c) { return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1; };
    for (size_t i = 0; i < s.size(); i += 2) { const int a = hv(s[i]), b = hv(s[i + 1]); if (a < 0 || b < 0) return false; out.push_back(uint8_t(a * 16 + b)); }
    return true;
}
// Сравнение за постоянное время (не зависит от места первого отличия)
inline bool equalConst(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
    if (a.size() != b.size()) return false;
    uint8_t d = 0; for (size_t i = 0; i < a.size(); ++i) d |= uint8_t(a[i] ^ b[i]);
    return d == 0;
}
// Случайные байты от генератора ОС (std::random_device). На Linux/macOS/Windows (MSVC, MinGW с GCC ≥ 9.2) это системный источник.
inline std::vector<uint8_t> randomBytes(size_t n) {
    std::random_device rd; std::vector<uint8_t> r(n);
    for (auto& b : r) b = uint8_t(rd() & 0xFF);
    return r;
}

}  // namespace sha
}  // namespace dp
