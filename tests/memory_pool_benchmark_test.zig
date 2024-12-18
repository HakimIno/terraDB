const std = @import("std");
const testing = std.testing;
const Timer = std.time.Timer;
const Page = @import("storage").Page;
const MemoryPool = @import("storage").MemoryPool;
const PAGE_SIZE = @import("storage").PAGE_SIZE;

const ITERATIONS = 10_000;

test "benchmark memory pool vs direct allocation" {
    const allocator = testing.allocator;
    var timer = try Timer.start();

    // สร้าง memory pool
    var memory_pool = try MemoryPool.init(allocator, 10, PAGE_SIZE);
    defer memory_pool.deinit();

    var total_pool_time: u64 = 0;
    var total_direct_time: u64 = 0;

    // ทดสอบ Memory Pool
    {
        timer.reset();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            const buffer = try memory_pool.acquire();
            total_pool_time += timer.lap();
            memory_pool.release(buffer);
        }
    }

    // ทดสอบ Direct Allocation
    {
        timer.reset();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            const buffer = try allocator.alignedAlloc(u8, 8, PAGE_SIZE);
            total_direct_time += timer.lap();
            allocator.free(buffer);
        }
    }

    // แสดงผลลัพธ์ด้วย stderr
    const stderr = std.io.getStdErr().writer();
    try stderr.print("\n=== Memory Pool Performance Benchmark ===\n", .{});
    
    const avg_pool = @as(f64, @floatFromInt(total_pool_time)) / @as(f64, @floatFromInt(ITERATIONS));
    const avg_direct = @as(f64, @floatFromInt(total_direct_time)) / @as(f64, @floatFromInt(ITERATIONS));
    
    try stderr.print("Memory Pool average time: {d:.2} ns\n", .{avg_pool});
    try stderr.print("Direct allocation average time: {d:.2} ns\n", .{avg_direct});
    try stderr.print("Improvement: {d:.2}x\n", .{avg_direct / avg_pool});
    try stderr.print("Total operations: {d}\n\n", .{ITERATIONS});

    // เพิ่ม expectation เพื่อให้แน่ใจว่า test จะไม่ถูก optimize ออก
    try testing.expect(avg_pool > 0);
    try testing.expect(avg_direct > 0);
} 