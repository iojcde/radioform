#ifndef RADIOFORM_FIXED_SPATIAL_H
#define RADIOFORM_FIXED_SPATIAL_H

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>

namespace radioform {

// A lightweight fixed virtual-speaker approximation, not Apple's renderer or a
// measured HRTF. Contralateral head shadow / 0.25 ms delay plus short, different
// early-reflection paths for each ear. No feedback, realtime allocation or locks.
class FixedSpatial {
public:
    void init(float sampleRate) {
        crossDelay_ = sampleRate * 0.00025f;
        roomDelays_ = {static_cast<uint32_t>(sampleRate * .0023f),
                       static_cast<uint32_t>(sampleRate * .0037f),
                       static_cast<uint32_t>(sampleRate * .0061f),
                       static_cast<uint32_t>(sampleRate * .0027f),
                       static_cast<uint32_t>(sampleRate * .0043f),
                       static_cast<uint32_t>(sampleRate * .0053f)};
        crossAlpha_ = 1 - std::exp(-6.28318530718f * 1500 / sampleRate);
        roomAlpha_ = 1 - std::exp(-6.28318530718f * 2200 / sampleRate);
        mixAlpha_ = 1 - std::exp(-1 / (.020f * sampleRate));
        mix_ = 0;
        targetMix_.store(0, std::memory_order_relaxed);
        reset();
    }

    void setAmount(bool enabled, float amount) {
        const float amountClamped = std::clamp(amount, 0.0f, 1.0f);
        const float target = enabled ? amountClamped * (1.6f - .6f * amountClamped) : 0;
        // Presets arrive on the control thread. Only the audio thread touches
        // delay history and the current fade position.
        targetMix_.store(target, std::memory_order_relaxed);
    }

    void reset() {
        left_.fill(0);
        right_.fill(0);
        write_ = 0;
        crossLeft_ = crossRight_ = roomLeft_ = roomRight_ = 0;
    }

    void process(float& left, float& right) {
        const float target = targetMix_.load(std::memory_order_relaxed);
        if (mix_ == 0 && target == 0) return;
        if (mix_ == 0 && target > 0) reset();
        mix_ += mixAlpha_ * (target - mix_);
        if (std::abs(mix_ - target) < 0.000001f) mix_ = target;
        left_[write_] = left;
        right_[write_] = right;
        crossLeft_ += crossAlpha_ * (delayed(left_, crossDelay_) - crossLeft_);
        crossRight_ += crossAlpha_ * (delayed(right_, crossDelay_) - crossRight_);
        const float reflectionsLeft = .02f * delayed(left_, roomDelays_[0])
            + .012f * delayed(right_, roomDelays_[1]) + .008f * delayed(left_, roomDelays_[2]);
        const float reflectionsRight = .02f * delayed(right_, roomDelays_[3])
            + .012f * delayed(left_, roomDelays_[4]) + .008f * delayed(right_, roomDelays_[5]);
        roomLeft_ += roomAlpha_ * (reflectionsLeft - roomLeft_);
        roomRight_ += roomAlpha_ * (reflectionsRight - roomRight_);
        // Positive weights sum to one: the wet path cannot increase the peak
        // beyond the largest input sample, including the reflection history.
        const float wetLeft = .68f * left + .28f * crossRight_ + roomLeft_;
        const float wetRight = .68f * right + .28f * crossLeft_ + roomRight_;
        left += mix_ * (wetLeft - left);
        right += mix_ * (wetRight - right);
        write_ = (write_ + 1) & mask;
    }

private:
    static constexpr uint32_t size = 4096; // 6.1 ms at the maximum 384 kHz rate.
    static constexpr uint32_t mask = size - 1;
    using Buffer = std::array<float, size>;
    float delayed(const Buffer& buffer, float samples) const {
        const auto whole = static_cast<uint32_t>(samples);
        const float fraction = samples - whole;
        const auto index = (write_ + size - whole) & mask;
        return buffer[index] * (1 - fraction) + buffer[(index + size - 1) & mask] * fraction;
    }
    Buffer left_{}, right_{};
    uint32_t write_ = 0;
    std::array<uint32_t, 6> roomDelays_{};
    float crossDelay_ = 0, crossAlpha_ = 0, roomAlpha_ = 0, mixAlpha_ = 0;
    float crossLeft_ = 0, crossRight_ = 0, roomLeft_ = 0, roomRight_ = 0;
    float mix_ = 0;
    static_assert(std::atomic<float>::is_always_lock_free, "Spatial control must be lock-free");
    std::atomic<float> targetMix_{0};
};
}
#endif
