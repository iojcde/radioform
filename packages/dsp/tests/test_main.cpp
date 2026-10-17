/**
 * @file test_main.cpp
 * @brief Test suite entry point
 */

#include "test_utils.h"

// Declare test functions
// Preset tests
void test_preset_init_flat();
void test_preset_validate_valid();
void test_preset_validate_invalid_frequency();
void test_preset_validate_invalid_gain();
void test_preset_validate_invalid_q();

void test_preset_validate_extended_bands();
void test_freq_response_last_extended_filter_is_processed();

// Smoothing tests
void test_smoother_initialization();
void test_smoother_set_value_immediate();
void test_smoother_ramps_to_target();
void test_smoother_no_zipper_noise();
void test_db_to_gain_conversion();

// Biquad tests
void test_biquad_passthrough_when_flat();
void test_biquad_impulse_response_peak_filter();
void test_biquad_low_pass_attenuates_high_freq();
void test_biquad_high_pass_attenuates_low_freq();
void test_biquad_peak_filter_boosts_at_center_freq();
void test_biquad_reset_clears_state();

// Engine tests
void test_engine_create_destroy();
void test_engine_invalid_sample_rate();
void test_engine_bypass_is_bit_perfect();
void test_engine_bypass_interleaved_is_bit_perfect();
void test_engine_apply_flat_preset();
void test_engine_process_with_flat_preset();
void test_engine_peak_filter_boosts_signal();
void test_engine_limiter_prevents_clipping();
void test_engine_update_band_gain_realtime();
void test_engine_statistics_tracking();
void test_engine_reset_clears_state();

// Frequency response tests
void test_freq_response_flat_preset_is_transparent();
void test_freq_response_peak_filter_at_1khz();
void test_freq_response_low_shelf_boosts_bass();
void test_freq_response_high_shelf_boosts_treble();
void test_freq_response_multi_band_eq();
void test_freq_response_thd_remains_low();

void test_spatial_disabled_is_exact_passthrough();
void test_spatial_crossfeed_is_delayed_bounded_and_resettable();
void test_spatial_preserves_mono_balance_and_fades_to_dry();
void test_spatial_engine_planar_and_interleaved_agree();
void test_spatial_rejects_invalid_amount();
void test_spatial_keeps_direct_sound_dominant_and_room_short();

int main(int argc, char** argv) {
    REGISTER_TEST(spatial_disabled_is_exact_passthrough);
    REGISTER_TEST(spatial_crossfeed_is_delayed_bounded_and_resettable);
    REGISTER_TEST(spatial_preserves_mono_balance_and_fades_to_dry);
    REGISTER_TEST(spatial_engine_planar_and_interleaved_agree);
    REGISTER_TEST(spatial_rejects_invalid_amount);
    REGISTER_TEST(spatial_keeps_direct_sound_dominant_and_room_short);
    REGISTER_TEST(preset_validate_extended_bands);
    REGISTER_TEST(freq_response_last_extended_filter_is_processed);
    // Register all tests
    REGISTER_TEST(preset_init_flat);
    REGISTER_TEST(preset_validate_valid);
    REGISTER_TEST(preset_validate_invalid_frequency);
    REGISTER_TEST(preset_validate_invalid_gain);
    REGISTER_TEST(preset_validate_invalid_q);

    REGISTER_TEST(smoother_initialization);
    REGISTER_TEST(smoother_set_value_immediate);
    REGISTER_TEST(smoother_ramps_to_target);
    REGISTER_TEST(smoother_no_zipper_noise);
    REGISTER_TEST(db_to_gain_conversion);

    REGISTER_TEST(biquad_passthrough_when_flat);
    REGISTER_TEST(biquad_impulse_response_peak_filter);
    REGISTER_TEST(biquad_low_pass_attenuates_high_freq);
    REGISTER_TEST(biquad_high_pass_attenuates_low_freq);
    REGISTER_TEST(biquad_peak_filter_boosts_at_center_freq);
    REGISTER_TEST(biquad_reset_clears_state);

    REGISTER_TEST(engine_create_destroy);
    REGISTER_TEST(engine_invalid_sample_rate);
    REGISTER_TEST(engine_bypass_is_bit_perfect);
    REGISTER_TEST(engine_bypass_interleaved_is_bit_perfect);
    REGISTER_TEST(engine_apply_flat_preset);
    REGISTER_TEST(engine_process_with_flat_preset);
    REGISTER_TEST(engine_peak_filter_boosts_signal);
    REGISTER_TEST(engine_limiter_prevents_clipping);
    REGISTER_TEST(engine_update_band_gain_realtime);
    REGISTER_TEST(engine_statistics_tracking);
    REGISTER_TEST(engine_reset_clears_state);

    REGISTER_TEST(freq_response_flat_preset_is_transparent);
    REGISTER_TEST(freq_response_peak_filter_at_1khz);
    REGISTER_TEST(freq_response_low_shelf_boosts_bass);
    REGISTER_TEST(freq_response_high_shelf_boosts_treble);
    REGISTER_TEST(freq_response_multi_band_eq);
    REGISTER_TEST(freq_response_thd_remains_low);

    // Run all tests
    return run_all_tests();
}
