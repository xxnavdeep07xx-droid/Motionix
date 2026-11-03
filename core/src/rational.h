// Motionix core — exact rational time.
// Floats drift; edited video does not forgive drift. Every position in a
// Motionix project is a rational number of seconds (num/den) so 29.97,
// 59.94 and drop-frame rates survive round trips exactly.
#pragma once

#include <cstdint>

namespace motionix {

struct Rational {
    int64_t num = 0;  // numerator (seconds * den)
    int64_t den = 1;  // denominator, always > 0 after reduce()

    static Rational make(int64_t n, int64_t d);
    void reduce();
    double toDouble() const;
    // Convert to integer microseconds with round-to-nearest. Uses 128-bit
    // intermediates so 3-hour 4K timelines never overflow.
    int64_t toMicros() const;
    // Parse "30000/1001" or "30" style fps strings.
    static Rational parse(const char* s);
};

}  // namespace motionix
