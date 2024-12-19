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

    // Add pager benchmark
    const pager_benchmark = b.addTest(.{
        .name = "pager-benchmark",
        .root_source_file = .{ .cwd_relative = "tests/pager_benchmark_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    pager_benchmark.root_module.addImport("storage", storage_module);

    // Create run steps
    const run_page_benchmark = b.addRunArtifact(page_benchmark);
    const run_pager_benchmark = b.addRunArtifact(pager_benchmark);

    // Add benchmark step that runs both benchmarks
    const bench_step = b.step("bench", "Run all benchmarks");
    bench_step.dependOn(&run_page_benchmark.step);
    bench_step.dependOn(&run_pager_benchmark.step);

    // Add individual benchmark steps
    const page_bench_step = b.step("page-bench", "Run page benchmarks");
    page_bench_step.dependOn(&run_page_benchmark.step);

    const pager_bench_step = b.step("pager-bench", "Run pager benchmarks");
    pager_bench_step.dependOn(&run_pager_benchmark.step);

    // Create lexer module
    const lexer_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/parser/lexer.zig" },
        .imports = &.{},
    });

    // Create parser module with lexer dependency
    const parser_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/parser/parser.zig" },
        .imports = &.{
            .{ .name = "lexer", .module = lexer_module },
        },
    });

    // Add parser tests
    const parser_tests = b.addTest(.{
        .name = "parser-tests",
        .root_source_file = .{ .cwd_relative = "tests/parser_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    parser_tests.root_module.addImport("parser", parser_module);

    // Add parser benchmark test
    const parser_benchmark = b.addTest(.{
        .name = "parser-benchmark",
        .root_source_file = .{ .cwd_relative = "tests/parser_benchmark.zig" },
        .target = target,
        .optimize = optimize,
    });
    parser_benchmark.root_module.addImport("parser", parser_module);

    // Create run steps
    const run_parser_tests = b.addRunArtifact(parser_tests);
    const run_parser_benchmark = b.addRunArtifact(parser_benchmark);

    // Add test step
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_parser_tests.step);

    // Add parser-test step
    const parser_test_step = b.step("parser-test", "Run parser tests");
    parser_test_step.dependOn(&run_parser_tests.step);

    // Add parser-bench step
    const parser_bench_step = b.step("parser-bench", "Run parser benchmarks");
    parser_bench_step.dependOn(&run_parser_benchmark.step);

    // Add to main bench step
    bench_step.dependOn(&run_parser_benchmark.step);
}
