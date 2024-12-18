const std = @import("std");
const testing = std.testing;
const MemoryPool = @import("storage").MemoryPool;

test "memory pool basic operations" {
    const allocator = testing.allocator;
    
    // สร้าง pool ขนาด 3 pools
    var pool = try MemoryPool.init(allocator, 3, 1024);
    defer pool.deinit();

    // ทดสอบ acquire
    const buf1 = try pool.acquire();
    const buf2 = try pool.acquire();
    const buf3 = try pool.acquire();

    // เขียนข้อมูลลงใน buffer
    @memset(buf1, 1);
    @memset(buf2, 2);
    @memset(buf3, 3);

    // ตรวจสอบว่าแต่ละ buffer แยกจากกัน
    try testing.expect(buf1[0] == 1);
    try testing.expect(buf2[0] == 2);
    try testing.expect(buf3[0] == 3);

    // ทดสอบ release และ reuse
    pool.release(buf2);
    const buf4 = try pool.acquire();
    try testing.expect(buf4.ptr == buf2.ptr); // ควรได้ buffer เดิมที่ถูก release

    // ทดสอบการขยาย pool
    const buf5 = try pool.acquire(); // ควรสร้าง pool ใหม่อัตโนมัติ
    try testing.expect(buf5.len == 1024);
}

test "memory pool stress test" {
    const allocator = testing.allocator;
    var pool = try MemoryPool.init(allocator, 2, 1024);
    defer pool.deinit();

    // ทดสอบ acquire/release หลายๆ ครั้ง
    var buffers: [10][]align(8) u8 = undefined;
    
    // acquire จนเต็ม
    for (0..10) |i| {
        buffers[i] = try pool.acquire();
        @memset(buffers[i], @intCast(i + 1));
    }

    // release ทั้งหมด
    for (buffers) |buf| {
        pool.release(buf);
    }

    // acquire อีกครั้ง ควรได้ buffer เดิม
    const reused = try pool.acquire();
    try testing.expect(reused.ptr == buffers[0].ptr);
} 