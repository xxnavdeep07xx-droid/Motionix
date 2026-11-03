#include "rational.h"

#include <cstdlib>
#include <cstring>
#include <numeric>

namespace motionix {

Rational Rational::make(int64_t n, int64_t d) {
    if (d == 0) d = 1;
    if (d < 0) {   // keep denominator positive
        n = -n;
        d = -d;
    }
    Rational r{n, d};
    r.reduce();
    return r;
}

void Rational::reduce() {
    if (den == 0) den = 1;
    if (den < 0) {
        num = -num;
        den = -den;
    }
    if (num == 0) {
        den = 1;
        return;
    }
    int64_t g = std::gcd(num < 0 ? -num : num, den);
    if (g > 1) {
        num /= g;
        den /= g;
    }
}

double Rational::toDouble() const {
    return den == 0 ? 0.0 : static_cast<double>(num) / static_cast<double>(den);
}

int64_t Rational::toMicros() const {
    if (den == 0) return 0;
    __int128 v = static_cast<__int128>(num) * 1000000;
    __int128 d = static_cast<__int128>(den);
    // round to nearest, halfway away from zero
    __int128 q = v / d;
    __int128 rem = v % d;
    if (rem < 0) rem = -rem;
    if (rem * 2 >= d) q += (v < 0 ? -1 : 1);
    return static_cast<int64_t>(q);
}

Rational Rational::parse(const char* s) {
    if (s == nullptr) return make(30, 1);
    const char* slash = std::strchr(s, '/');
    if (slash == nullptr) {
        int64_t n = std::atoll(s);
        return make(n == 0 ? 30 : n, 1);
    }
    int64_t n = std::atoll(s);
    int64_t d = std::atoll(slash + 1);
    if (d == 0) d = 1;
    return make(n, d);
}

}  // namespace motionix
