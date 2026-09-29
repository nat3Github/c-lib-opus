const std = @import("std");

// ponytail: float build, no custom modes, no DNN extras (deep-plc/dred/osce), SIMD picked at
// compile time from the target CPU features (opus "PRESUME" mode, no runtime CPU detection).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const libc_include = b.option(std.Build.LazyPath, "libc_include", "Build without libc against these headers; the consumer provides the symbols");
    const t = target.result;

    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = libc_include == null });
    if (libc_include) |p| mod.addIncludePath(p); // -I: must win over the macOS SDK headers zig always adds
    for ([_][]const u8{ ".", "include", "celt", "silk", "silk/float", "src" }) |dir| mod.addIncludePath(b.path(dir));
    mod.addCMacro("OPUS_BUILD", "1");
    mod.addCMacro("VAR_ARRAYS", "1");
    mod.addCMacro("HAVE_LRINT", "1");
    mod.addCMacro("HAVE_LRINTF", "1");
    mod.addCMacro("ENABLE_HARDENING", "1");
    if (t.os.tag == .windows) mod.addCMacro("DLL_EXPORT", "1");

    mod.addCSourceFiles(.{ .files = &(opus_sources ++ opus_float_sources ++ celt_sources ++ silk_sources ++ silk_float_sources) });

    switch (t.cpu.arch) {
        .x86, .x86_64 => {
            const has = std.Target.x86.featureSetHas;
            const f = t.cpu.features;
            if (has(f, .sse)) {
                presume(mod, "OPUS_X86", "SSE");
                mod.addCSourceFiles(.{ .files = &celt_sse_sources });
            }
            if (has(f, .sse2)) {
                presume(mod, "OPUS_X86", "SSE2");
                mod.addCSourceFiles(.{ .files = &celt_sse2_sources });
            }
            if (has(f, .sse4_1)) {
                presume(mod, "OPUS_X86", "SSE4_1");
                mod.addCSourceFiles(.{ .files = &(celt_sse4_1_sources ++ silk_sse4_1_sources) });
            }
            if (has(f, .avx2) and has(f, .fma)) {
                presume(mod, "OPUS_X86", "AVX2");
                mod.addCSourceFiles(.{ .files = &(celt_avx2_sources ++ silk_avx2_sources ++ silk_float_avx2_sources) });
            }
        },
        .arm, .aarch64 => if (std.Target.arm.featureSetHas(t.cpu.features, .neon) or
            std.Target.aarch64.featureSetHas(t.cpu.features, .neon))
        {
            presume(mod, "OPUS_ARM", "NEON_INTR");
            if (t.cpu.arch == .aarch64) presume(mod, "OPUS_X86", "AARCH64_NEON_INTR");
            // includes aarch64 .S files, which are guarded by __aarch64__
            mod.addCSourceFiles(.{ .files = &(celt_neon_sources ++ silk_neon_sources) });
        },
        else => {},
    }

    const lib = b.addLibrary(.{ .name = "opus", .root_module = mod });
    lib.installHeadersDirectory(b.path("include"), "", .{ .include_extensions = &.{".h"} });
    b.installArtifact(lib);
}

fn presume(mod: *std.Build.Module, comptime prefix: []const u8, comptime name: []const u8) void {
    mod.addCMacro(prefix ++ "_MAY_HAVE_" ++ name, "1");
    mod.addCMacro(prefix ++ "_PRESUME_" ++ name, "1");
}

const opus_sources = [_][]const u8{
    "src/opus.c",
    "src/opus_decoder.c",
    "src/opus_encoder.c",
    "src/extensions.c",
    "src/opus_multistream.c",
    "src/opus_multistream_encoder.c",
    "src/opus_multistream_decoder.c",
    "src/repacketizer.c",
    "src/opus_projection_encoder.c",
    "src/opus_projection_decoder.c",
    "src/mapping_matrix.c",
};

const opus_float_sources = [_][]const u8{
    "src/analysis.c",
    "src/mlp.c",
    "src/mlp_data.c",
};

const celt_sources = [_][]const u8{
    "celt/bands.c",
    "celt/celt.c",
    "celt/celt_encoder.c",
    "celt/celt_decoder.c",
    "celt/cwrs.c",
    "celt/entcode.c",
    "celt/entdec.c",
    "celt/entenc.c",
    "celt/kiss_fft.c",
    "celt/laplace.c",
    "celt/mathops.c",
    "celt/mdct.c",
    "celt/mdct_pfa.c",
    "celt/modes.c",
    "celt/pitch.c",
    "celt/celt_lpc.c",
    "celt/quant_bands.c",
    "celt/rate.c",
    "celt/vq.c",
    "celt/celt_tx_tables.c",
};

const celt_sse_sources = [_][]const u8{
    "celt/x86/pitch_sse.c",
};

const celt_sse2_sources = [_][]const u8{
    "celt/x86/pitch_sse2.c",
    "celt/x86/vq_sse2.c",
};

const celt_sse4_1_sources = [_][]const u8{
    "celt/x86/celt_lpc_sse4_1.c",
    "celt/x86/pitch_sse4_1.c",
};

const celt_avx2_sources = [_][]const u8{
    "celt/x86/pitch_avx.c",
};

const celt_neon_sources = [_][]const u8{
    "celt/arm/celt_neon_intr.c",
    "celt/arm/celt_neon_aarch64.S",
    "celt/arm/celt_mdct_tx.c",
    "celt/arm/celt_tx_neon.S",
    "celt/arm/pitch_neon_intr.c",
};

const silk_sources = [_][]const u8{
    "silk/CNG.c",
    "silk/code_signs.c",
    "silk/init_decoder.c",
    "silk/decode_core.c",
    "silk/decode_frame.c",
    "silk/decode_parameters.c",
    "silk/decode_indices.c",
    "silk/decode_pulses.c",
    "silk/decoder_set_fs.c",
    "silk/dec_API.c",
    "silk/enc_API.c",
    "silk/encode_indices.c",
    "silk/encode_pulses.c",
    "silk/gain_quant.c",
    "silk/interpolate.c",
    "silk/LP_variable_cutoff.c",
    "silk/NLSF_decode.c",
    "silk/NSQ.c",
    "silk/NSQ_del_dec.c",
    "silk/PLC.c",
    "silk/shell_coder.c",
    "silk/tables_gain.c",
    "silk/tables_LTP.c",
    "silk/tables_NLSF_CB_NB_MB.c",
    "silk/tables_NLSF_CB_WB.c",
    "silk/tables_other.c",
    "silk/tables_pitch_lag.c",
    "silk/tables_pulses_per_block.c",
    "silk/VAD.c",
    "silk/control_audio_bandwidth.c",
    "silk/quant_LTP_gains.c",
    "silk/VQ_WMat_EC.c",
    "silk/HP_variable_cutoff.c",
    "silk/NLSF_encode.c",
    "silk/NLSF_VQ.c",
    "silk/NLSF_unpack.c",
    "silk/NLSF_del_dec_quant.c",
    "silk/process_NLSFs.c",
    "silk/stereo_LR_to_MS.c",
    "silk/stereo_MS_to_LR.c",
    "silk/check_control_input.c",
    "silk/control_SNR.c",
    "silk/init_encoder.c",
    "silk/control_codec.c",
    "silk/A2NLSF.c",
    "silk/ana_filt_bank_1.c",
    "silk/biquad_alt.c",
    "silk/bwexpander_32.c",
    "silk/bwexpander.c",
    "silk/debug.c",
    "silk/decode_pitch.c",
    "silk/inner_prod_aligned.c",
    "silk/lin2log.c",
    "silk/log2lin.c",
    "silk/LPC_analysis_filter.c",
    "silk/LPC_inv_pred_gain.c",
    "silk/table_LSF_cos.c",
    "silk/NLSF2A.c",
    "silk/NLSF_stabilize.c",
    "silk/NLSF_VQ_weights_laroia.c",
    "silk/pitch_est_tables.c",
    "silk/resampler.c",
    "silk/resampler_down2_3.c",
    "silk/resampler_down2.c",
    "silk/resampler_private_AR2.c",
    "silk/resampler_private_down_FIR.c",
    "silk/resampler_private_IIR_FIR.c",
    "silk/resampler_private_up2_HQ.c",
    "silk/resampler_rom.c",
    "silk/sigm_Q15.c",
    "silk/sort.c",
    "silk/sum_sqr_shift.c",
    "silk/stereo_decode_pred.c",
    "silk/stereo_encode_pred.c",
    "silk/stereo_find_predictor.c",
    "silk/stereo_quant_pred.c",
    "silk/LPC_fit.c",
};

const silk_float_sources = [_][]const u8{
    "silk/float/apply_sine_window_FLP.c",
    "silk/float/corrMatrix_FLP.c",
    "silk/float/encode_frame_FLP.c",
    "silk/float/find_LPC_FLP.c",
    "silk/float/find_LTP_FLP.c",
    "silk/float/find_pitch_lags_FLP.c",
    "silk/float/find_pred_coefs_FLP.c",
    "silk/float/LPC_analysis_filter_FLP.c",
    "silk/float/LTP_analysis_filter_FLP.c",
    "silk/float/LTP_scale_ctrl_FLP.c",
    "silk/float/noise_shape_analysis_FLP.c",
    "silk/float/process_gains_FLP.c",
    "silk/float/regularize_correlations_FLP.c",
    "silk/float/residual_energy_FLP.c",
    "silk/float/warped_autocorrelation_FLP.c",
    "silk/float/wrappers_FLP.c",
    "silk/float/autocorrelation_FLP.c",
    "silk/float/burg_modified_FLP.c",
    "silk/float/bwexpander_FLP.c",
    "silk/float/energy_FLP.c",
    "silk/float/inner_product_FLP.c",
    "silk/float/k2a_FLP.c",
    "silk/float/LPC_inv_pred_gain_FLP.c",
    "silk/float/pitch_analysis_core_FLP.c",
    "silk/float/scale_copy_vector_FLP.c",
    "silk/float/scale_vector_FLP.c",
    "silk/float/schur_FLP.c",
    "silk/float/sort_FLP.c",
};

const silk_sse4_1_sources = [_][]const u8{
    "silk/x86/NSQ_sse4_1.c",
    "silk/x86/NSQ_del_dec_sse4_1.c",
    "silk/x86/VAD_sse4_1.c",
    "silk/x86/VQ_WMat_EC_sse4_1.c",
};

const silk_avx2_sources = [_][]const u8{
    "silk/x86/NSQ_del_dec_avx2.c",
};

const silk_float_avx2_sources = [_][]const u8{
    "silk/float/x86/inner_product_FLP_avx2.c",
};

const silk_neon_sources = [_][]const u8{
    "silk/arm/biquad_alt_neon_intr.c",
    "silk/arm/LPC_inv_pred_gain_neon_intr.c",
    "silk/arm/NSQ_del_dec_neon_intr.c",
    "silk/arm/NSQ_neon.c",
};
