const std = @import("std");
const Page = @import("page.zig").Page;
const Allocator = std.mem.Allocator;
const MemoryPool = @import("memory_pool.zig").MemoryPool;

const ThreadLocal = struct {
    var last_accessed_page: ?*Page = null;
};

pub const PageCache = struct {
    const CacheEntry = struct {
        page: Page,
        last_access: i64,
        access_count: u32,
    };

    cache: std.AutoHashMap(u32, CacheEntry),
    allocator: Allocator,
    max_size: usize,
    memory_pool: *MemoryPool,

    pub fn init(allocator: Allocator, max_size: usize, memory_pool: *MemoryPool) !PageCache {
        return .{
            .cache = std.AutoHashMap(u32, CacheEntry).init(allocator),
            .allocator = allocator,
            .max_size = max_size,
            .memory_pool = memory_pool,
        };
    }

    pub fn deinit(self: *PageCache) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.page.deinit();
        }
        self.cache.deinit();
    }

    pub fn get(self: *PageCache, page_id: u32) ?*Page {
        // Check thread local cache first
        if (ThreadLocal.last_accessed_page) |page| {
            if (page.header.page_id == page_id) {
                return page;
            }
        }
        
        if (self.cache.getPtr(page_id)) |entry| {
            entry.last_access = std.time.timestamp();
            entry.access_count += 1;
            return &entry.page;
        }
        return null;
    }

    pub fn put(self: *PageCache, page: Page) !void {
        // ถ้า cache เต็ม ลบ entry ที่เก่าที่สุดออก
        if (self.cache.count() >= self.max_size) {
            var oldest_time: i64 = std.math.maxInt(i64);
            var oldest_id: ?u32 = null;

            var it = self.cache.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.last_access < oldest_time) {
                    oldest_time = entry.value_ptr.last_access;
                    oldest_id = entry.key_ptr.*;
                }
            }

            if (oldest_id) |id| {
                if (self.cache.fetchRemove(id)) |removed| {
                    removed.value.page.deinit();
                }
            }
        }

        try self.cache.put(page.header.page_id, .{
            .page = page,
            .last_access = std.time.timestamp(),
            .access_count = 0,
        });
    }
}; 