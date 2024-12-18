// src/storage/buffer.zig
const std = @import("std");
const Page = @import("page.zig").Page;

pub const BufferPool = struct {
    pages: std.AutoHashMap(u32, *Page),
    max_pages: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, max_pages: u32) !BufferPool {
        return BufferPool{
            .pages = std.AutoHashMap(u32, *Page).init(allocator),
            .max_pages = max_pages,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BufferPool) void {
        var it = self.pages.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.pages.deinit();
    }
};