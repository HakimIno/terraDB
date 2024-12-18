const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MemoryPool = struct {
    allocator: Allocator,
    pages: std.ArrayList([]align(8) u8),
    free_list: std.ArrayList([]align(8) u8),
    page_size: usize,
    
    free_ring: [32]?[]align(8) u8,
    ring_head: usize,
    ring_tail: usize,

    pub fn init(allocator: Allocator, initial_pages: usize, page_size: usize) !MemoryPool {
        var pages = std.ArrayList([]align(8) u8).init(allocator);
        var free_list = std.ArrayList([]align(8) u8).init(allocator);

        const INIT_CAPACITY = initial_pages * 2;
        try pages.ensureUnusedCapacity(INIT_CAPACITY);
        try free_list.ensureUnusedCapacity(INIT_CAPACITY);
        
        for (0..initial_pages) |_| {
            const page = try allocator.alignedAlloc(u8, 8, page_size);
            try pages.append(page);
            try free_list.append(page);
        }

        return MemoryPool{
            .allocator = allocator,
            .pages = pages,
            .free_list = free_list,
            .page_size = page_size,
            .free_ring = .{null} ** 32,
            .ring_head = 0,
            .ring_tail = 0,
        };
    }

    pub fn deinit(self: *MemoryPool) void {
        for (self.pages.items) |page| {
            self.allocator.free(page);
        }
        self.pages.deinit();
        self.free_list.deinit();
    }

    pub fn acquire(self: *MemoryPool) ![]align(8) u8 {
        if (self.ring_head != self.ring_tail) {
            const head = self.ring_head;
            if (self.free_ring[head]) |page| {
                self.free_ring[head] = null;
                self.ring_head = (head + 1) & 31;
                return page;
            }
        }

        if (self.free_list.items.len == 0) {
            const BATCH_SIZE = 16;
            try self.free_list.ensureUnusedCapacity(BATCH_SIZE);
            try self.pages.ensureUnusedCapacity(BATCH_SIZE);
            
            inline for (0..BATCH_SIZE) |_| {
                const new_page = try self.allocator.alignedAlloc(u8, 8, self.page_size);
                try self.pages.append(new_page);
                try self.free_list.append(new_page);
            }
        }

        return self.free_list.pop();
    }

    pub fn release(self: *MemoryPool, page: []align(8) u8) void {
        const next_tail = (self.ring_tail + 1) & 31;
        if (next_tail != self.ring_head) {
            self.free_ring[self.ring_tail] = page;
            self.ring_tail = next_tail;
            return;
        }
        self.free_list.append(page) catch unreachable;
    }
};