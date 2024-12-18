const std = @import("std");
const testing = std.testing;
const Pager = @import("storage").Pager;

test "benchmark pager operations" {
    const allocator = testing.allocator;
    
    const tmp_path = "test.db";
    defer std.fs.cwd().deleteFile(tmp_path) catch {};
    
    var pager = try Pager.init(allocator, tmp_path);
    defer pager.deinit();
    
    const iterations = 10_000;
    var timer = try std.time.Timer.start();
    
    var total_read_time: u64 = 0;
    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();
    
    for (0..iterations) |_| {
        const page_id = random.intRangeAtMost(u32, 0, 1000);
        timer.reset();
        _ = try pager.getPage(page_id);
        total_read_time += timer.read();
    }
    
    var total_write_time: u64 = 0;
    for (0..iterations) |_| {
        const page_id = random.intRangeAtMost(u32, 0, 1000);
        timer.reset();
        try pager.writePage(page_id);
        total_write_time += timer.read();
    }
    
    const page_ids = try allocator.alloc(u32, 100);
    defer allocator.free(page_ids);
    for (page_ids, 0..) |*id, i| {
        id.* = @intCast(i);
    }
    
    timer.reset();
    try pager.writePages(page_ids);
    const batch_write_time = timer.read();
    
    std.debug.print("\n=== Pager Performance Benchmark ===\n", .{});
    std.debug.print("Average read time: {d:.2} ns\n", .{@as(f64, @floatFromInt(total_read_time)) / iterations});
    std.debug.print("Average write time: {d:.2} ns\n", .{@as(f64, @floatFromInt(total_write_time)) / iterations});
    std.debug.print("Batch write time (100 pages): {d:.2} ns\n", .{@as(f64, @floatFromInt(batch_write_time))});
} 