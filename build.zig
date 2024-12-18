const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a module for our storage code
    const storage_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/storage/storage.zig" },
        .imports = &.{},
    });
    

    const exe = b.addExecutable(.{
        .name = "terraDB",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("storage", storage_module);
    b.installArtifact(exe);

    // Add page benchmark
    const page_benchmark = b.addTest(.{
        .name = "page-benchmark",
        .root_source_file = .{ .cwd_relative = "tests/page_benchmark_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    page_benchmark.root_module.addImport("storage", storage_module);

    // Add memory pool benchmark
    const memory_pool_benchmark = b.addTest(.{
        .name = "memory-pool-benchmark",
        .root_source_file = .{ .cwd_relative = "tests/memory_pool_benchmark_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    memory_pool_benchmark.root_module.addImport("storage", storage_module);

    // Create run steps
    const run_page_benchmark = b.addRunArtifact(page_benchmark);
    const run_memory_pool_benchmark = b.addRunArtifact(memory_pool_benchmark);

    // Add benchmark step that runs both benchmarks
    const bench_step = b.step("bench", "Run all benchmarks");
    bench_step.dependOn(&run_page_benchmark.step);
    bench_step.dependOn(&run_memory_pool_benchmark.step);

    // Add individual benchmark steps
    const page_bench_step = b.step("page-bench", "Run page benchmarks");
    page_bench_step.dependOn(&run_page_benchmark.step);

    const pool_bench_step = b.step("pool-bench", "Run memory pool benchmarks");
    pool_bench_step.dependOn(&run_memory_pool_benchmark.step);
}