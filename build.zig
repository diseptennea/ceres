const std = @import("std");

const FeatureMod = struct {
    add: std.Target.Cpu.Feature.Set = std.Target.Cpu.Feature.Set.empty,
    sub: std.Target.Cpu.Feature.Set = std.Target.Cpu.Feature.Set.empty,
};

fn getFeatureMod(comptime arch: std.Target.Cpu.Arch) FeatureMod {
    var mod: FeatureMod = .{};

    switch (arch) {
        .x86_64 => {
            const Features = std.Target.x86.Feature;

            // Remove SIMD instructions from the compilation - kernel won't do any of it
            mod.add.addFeature(@intFromEnum(Features.soft_float));
            mod.sub.addFeature(@intFromEnum(Features.mmx));
            mod.sub.addFeature(@intFromEnum(Features.sse));
            mod.sub.addFeature(@intFromEnum(Features.sse2));
            mod.sub.addFeature(@intFromEnum(Features.sse3));
            mod.sub.addFeature(@intFromEnum(Features.sse4_1));
            mod.sub.addFeature(@intFromEnum(Features.sse4_2));
            mod.sub.addFeature(@intFromEnum(Features.sse4a));
            mod.sub.addFeature(@intFromEnum(Features.ssse3));
            mod.sub.addFeature(@intFromEnum(Features.avx));
            mod.sub.addFeature(@intFromEnum(Features.avx2));
        },

        else => @compileError("unimplemented architecture"),
    }

    return mod;
}

const kernel_config = .{
    .arch = std.Target.Cpu.Arch.x86_64,
};

pub fn build(b: *std.Build) void {
    const feature_mod = getFeatureMod(kernel_config.arch);

    const target: std.zig.CrossTarget = .{
        .cpu_arch = kernel_config.arch,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = feature_mod.add,
        .cpu_features_sub = feature_mod.sub,
    };

    const kernel_optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "kernel/src/main.zig" },
        .target = b.resolveTargetQuery(target),
        .optimize = kernel_optimize,
        .code_model = .kernel,
    });
    kernel.pie = true;

    kernel.setLinkerScript(.{ .path = "kernel/linker.ld" });

    const kernel_step = b.step("kernel", "Build the kernel");
    const kernel_install = b.addInstallArtifact(kernel, .{});
    kernel_step.dependOn(&kernel_install.step);
}
