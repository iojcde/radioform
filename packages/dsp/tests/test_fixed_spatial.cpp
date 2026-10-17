#include "test_utils.h"
#include "radioform_dsp.h"
#include "fixed_spatial.h"

using namespace radioform;
using namespace dsp_test;

TEST(spatial_disabled_is_exact_passthrough) {
    FixedSpatial spatial;
    spatial.init(48000);
    for (int i = 0; i < 1000; ++i) {
        const float a = std::sin(i * .17f), b = std::cos(i * .13f);
        float left = a, right = b;
        spatial.process(left, right);
        ASSERT_EQ(left, a);
        ASSERT_EQ(right, b);
    }
    PASS();
}

TEST(spatial_crossfeed_is_delayed_bounded_and_resettable) {
    for (float sr : {8000.f, 44100.f, 48000.f, 192000.f, 384000.f}) {
        FixedSpatial spatial;
        spatial.init(sr);
        spatial.setAmount(true, 1);
        float energy = 0;
        for (int i = 0; i < static_cast<int>(sr * .05f); ++i) {
            float left = i == 0 ? 1 : 0, right = 0;
            spatial.process(left, right);
            if (i == 0) ASSERT_EQ(right, 0.f);
            ASSERT(std::isfinite(left) && std::isfinite(right));
            ASSERT(std::abs(left) <= 1 && std::abs(right) <= 1);
            energy += right * right;
        }
        ASSERT(energy > 0);
        spatial.reset();
        float left = 0, right = 0;
        spatial.process(left, right);
        ASSERT_EQ(left, 0.f);
        ASSERT_EQ(right, 0.f);
    }
    PASS();
}

TEST(spatial_preserves_mono_balance_and_fades_to_dry) {
    FixedSpatial spatial;
    spatial.init(48000);
    spatial.setAmount(true, 1);
    float left = 0, right = 0;
    for (int i = 0; i < 48000; ++i) {
        left = right = 1;
        spatial.process(left, right);
        ASSERT(left <= 1.000001f && right <= 1.000001f);
    }
    ASSERT_NEAR(left, 1, .0001);
    ASSERT_NEAR(right, left, .0001);
    spatial.setAmount(false, 1);
    for (int i = 0; i < 24000; ++i) {
        left = .3f; right = -.7f;
        spatial.process(left, right);
    }
    ASSERT_EQ(left, .3f);
    ASSERT_EQ(right, -.7f);
    PASS();
}

TEST(spatial_engine_planar_and_interleaved_agree) {
    for (uint32_t sr : {44100u, 48000u, 192000u, 384000u}) {
        auto* planar = radioform_dsp_create(sr);
        auto* interleaved = radioform_dsp_create(sr);
        ASSERT(planar && interleaved);
        radioform_preset_t preset;
        radioform_dsp_preset_init_flat(&preset);
        preset.spatial_enabled = true;
        preset.spatial_mix = .65f;
        ASSERT_EQ(radioform_dsp_apply_preset(planar, &preset), RADIOFORM_OK);
        ASSERT_EQ(radioform_dsp_apply_preset(interleaved, &preset), RADIOFORM_OK);
        std::vector<float> left(10000), right(10000), input(20000), output(20000);
        for (size_t i = 0; i < left.size(); ++i) {
            input[2*i] = left[i] = .2f * std::sin(i * .07f);
            input[2*i+1] = right[i] = .3f * std::cos(i * .11f);
        }
        radioform_dsp_process_planar(planar, left.data(), right.data(), left.data(), right.data(), left.size());
        for (size_t i = 0; i < left.size(); i += 257) {
            radioform_dsp_process_interleaved(interleaved, input.data()+2*i, output.data()+2*i,
                std::min<size_t>(257, left.size()-i));
        }
        for (size_t i = 0; i < left.size(); ++i) {
            ASSERT_NEAR(left[i], output[2*i], .00001);
            ASSERT_NEAR(right[i], output[2*i+1], .00001);
        }
        radioform_dsp_set_bypass(interleaved, true);
        radioform_dsp_process_interleaved(interleaved, input.data(), output.data(), left.size());
        ASSERT(input == output);
        radioform_dsp_destroy(planar);
        radioform_dsp_destroy(interleaved);
    }
    PASS();
}

TEST(spatial_rejects_invalid_amount) {
    radioform_preset_t preset;
    radioform_dsp_preset_init_flat(&preset);
    for (float value : {-1.f, 1.1f, INFINITY, NAN}) {
        preset.spatial_mix = value;
        ASSERT_EQ(radioform_dsp_preset_validate(&preset), RADIOFORM_ERROR_INVALID_PARAM);
    }
    PASS();
}

TEST(spatial_keeps_direct_sound_dominant_and_room_short) {
    float energies[2] = {};
    for (int level = 0; level < 2; ++level) {
        FixedSpatial spatial;
        spatial.init(48000);
        spatial.setAmount(true, level == 0 ? .4f : 1.f);
        // Settle the amount fade before measuring the impulse response.
        for (int i = 0; i < 48000; ++i) {
            float left = 0, right = 0;
            spatial.process(left, right);
        }
        float roomEnergy = 0, stereoDifference = 0, lateEnergy = 0;
        for (int i = 0; i < 2400; ++i) {
            float left = i == 0 ? 1 : 0, right = left;
            spatial.process(left, right);
            if (i == 0 && level == 1) {
                ASSERT(left >= .67f && right >= .67f);
            }
            if (i > 384) lateEnergy += left * left + right * right;
            if (i > 96) {
                roomEnergy += left * left + right * right;
                stereoDifference += (left-right) * (left-right);
            }
        }
        energies[level] = roomEnergy;
        // Even a mono source now has different reflection timing at each ear.
        ASSERT(stereoDifference > .000001f);
        ASSERT(lateEnergy < .0000001f);
    }
    ASSERT(energies[1] > .00005f && energies[1] < .0005f);
    ASSERT(energies[1] > energies[0] * 2.5f);
    PASS();
}
