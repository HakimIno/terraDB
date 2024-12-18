// const std = @import("std");
// const builtin = @import("builtin");
// const os = std.os;
// const page_mod = @import("page.zig");
// const Page = page_mod.Page;
// const PageID = u32;
// const PAGE_SIZE = page_mod.PAGE_SIZE;
// const linux = os.linux;
// const darwin = os.darwin;

// pub const DirectIO = struct {
//     // Constants for direct I/O
//     const O_DIRECT = if (builtin.os.tag == .linux) 
//         0x4000 
//     else if (builtin.os.tag == .macos) 
//         0x100000 
//     else 
//         @compileError("Unsupported OS");

//     // Fast read using direct syscall
//     pub inline fn fastRead(fd: std.c.fd_t, buffer: []u8, offset: u64) usize {
//         if (builtin.cpu.arch == .x86_64) {
//             // x86_64 Linux syscall
//             if (builtin.os.tag == .linux) {
//                 return asm volatile (
//                     \\ syscall                 // make syscall
//                     : [ret] "={rax}" (-> usize)
//                     : [syscall] "{rax}" (@intFromEnum(linux.SYS.pread64)),
//                       [fd] "{rdi}" (fd),
//                       [buf] "{rsi}" (buffer.ptr),
//                       [len] "{rdx}" (buffer.len),
//                       [off] "{r10}" (offset)
//                     : "rcx", "r11", "memory"
//                 );
//             } 
//             // x86_64 macOS syscall
//             else if (builtin.os.tag == .macos) {
//                 return asm volatile (
//                     \\ syscall
//                     : [ret] "={rax}" (-> usize)
//                     : [syscall] "{rax}" (@as(usize, 0x2000000) + 153), // pread syscall
//                       [fd] "{rdi}" (fd),
//                       [buf] "{rsi}" (buffer.ptr),
//                       [len] "{rdx}" (buffer.len),
//                       [off] "{r10}" (offset)
//                     : "rcx", "r11", "memory"
//                 );
//             }
//         }
//         return 0;
//     }

//     // Fast write using direct syscall
//     pub inline fn fastWrite(fd: std.c.fd_t, buffer: []const u8, offset: u64) usize {
//         if (builtin.cpu.arch == .x86_64) {
//             if (builtin.os.tag == .linux) {
//                 return asm volatile (
//                     \\ syscall
//                     : [ret] "={rax}" (-> usize)
//                     : [syscall] "{rax}" (@intFromEnum(linux.SYS.pwrite64)),
//                       [fd] "{rdi}" (fd),
//                       [buf] "{rsi}" (buffer.ptr),
//                       [len] "{rdx}" (buffer.len),
//                       [off] "{r10}" (offset)
//                     : "rcx", "r11", "memory"
//                 );
//             } 
//             else if (builtin.os.tag == .macos) {
//                 return asm volatile (
//                     \\ syscall
//                     : [ret] "={rax}" (-> usize)
//                     : [syscall] "{rax}" (@as(usize, 0x2000000) + 154), // pwrite syscall
//                       [fd] "{rdi}" (fd),
//                       [buf] "{rsi}" (buffer.ptr),
//                       [len] "{rdx}" (buffer.len),
//                       [off] "{r10}" (offset)
//                     : "rcx", "r11", "memory"
//                 );
//             }
//         }
//         return 0;
//     }
// };

// pub const Pager = struct {
//     file: std.fs.File,
//     page_cache: std.AutoHashMap(PageID, *Page),
//     allocator: std.mem.Allocator,
//     file_size: u64,
//     aligned_buffer: []align(4096) u8,
    
//     pub fn init(allocator: std.mem.Allocator, path: []const u8) !Pager {
//         const file = try std.fs.cwd().createFile(path, .{
//             .read = true,
//             .truncate = false,
//             .mode = 0o666,
//         });

//         if (builtin.os.tag == .linux) {
//             const flags = try os.linux.fcntl(file.handle, os.linux.F.GETFL, 0);
//             _ = try os.linux.fcntl(file.handle, os.linux.F.SETFL, flags | DirectIO.O_DIRECT);
//         } else if (builtin.os.tag == .macos) {
//             const F_GETFL = 3;  // macOS fcntl constant
//             const F_SETFL = 4;  // macOS fcntl constant
//             const flags = std.c.fcntl(file.handle, @as(c_int, F_GETFL), @as(c_int, 0));
//             if (flags < 0) return error.FcntlError;
//             const result = std.c.fcntl(file.handle, @as(c_int, F_SETFL), @as(c_int, flags | DirectIO.O_DIRECT));
//             if (result < 0) return error.FcntlError;
//         }
        
//         const aligned_buffer = try allocator.alignedAlloc(
//             u8, 
//             4096,
//             PAGE_SIZE
//         );
        
//         return Pager{
//             .file = file,
//             .page_cache = std.AutoHashMap(PageID, *Page).init(allocator),
//             .allocator = allocator,
//             .file_size = 0,
//             .aligned_buffer = aligned_buffer,
//         };
//     }
    
//     pub fn deinit(self: *Pager) void {
//         // Free all cached pages
//         var it = self.page_cache.iterator();
//         while (it.next()) |entry| {
//             entry.value_ptr.*.deinit();
//             self.allocator.destroy(entry.value_ptr.*);
//         }
//         self.page_cache.deinit();

//         // Free aligned buffer
//         self.allocator.free(self.aligned_buffer);
        
//         // Close file
//         self.file.close();
//     }
    
//     pub fn getPage(self: *Pager, page_id: PageID) !*Page {
//         // Check cache first
//         if (self.page_cache.get(page_id)) |cached_page| {
//             return cached_page;
//         }
        
//         const offset = page_id * PAGE_SIZE;
        
//         // Use direct I/O for reading
//         const bytes_read = DirectIO.fastRead(
//             self.file.handle,
//             self.aligned_buffer[0..PAGE_SIZE],
//             offset
//         );

//         if (bytes_read == 0) {
//             // Create new page
//             const page_ptr = try self.allocator.create(Page);
//             errdefer self.allocator.destroy(page_ptr);
            
//             page_ptr.* = try Page.init(self.allocator, .data, page_id);
//             try self.page_cache.put(page_id, page_ptr);
//             return page_ptr;
//         }

//         // Process read data
//         const page = try Page.deserialize(self.allocator, @alignCast(self.aligned_buffer[0..PAGE_SIZE]));
//         const page_ptr = try self.allocator.create(Page);
//         errdefer self.allocator.destroy(page_ptr);
        
//         page_ptr.* = page;
//         try self.page_cache.put(page_id, page_ptr);

//         return page_ptr;
//     }
    
//     pub fn writePage(self: *Pager, page_id: PageID) !void {
//         const page = self.page_cache.get(page_id) orelse return error.PageNotFound;
        
//         // Serialize to aligned buffer
//         const serialized = try page.serialize();
//         @memcpy(self.aligned_buffer[0..PAGE_SIZE], &serialized);

//         const offset = page_id * PAGE_SIZE;
        
//         // Use direct I/O for writing
//         _ = DirectIO.fastWrite(
//             self.file.handle,
//             self.aligned_buffer[0..PAGE_SIZE],
//             offset
//         );

//         self.file_size = @max(self.file_size, offset + PAGE_SIZE);
//     }
    
//     pub fn writePages(self: *Pager, page_ids: []const PageID) !void {
//         // Create a mutable copy of the page_ids slice
//         const sorted_ids = try self.allocator.alloc(PageID, page_ids.len);
//         defer self.allocator.free(sorted_ids);
        
//         // Copy the IDs
//         @memcpy(sorted_ids, page_ids);
        
//         // Sort the copy for sequential access
//         std.mem.sort(PageID, sorted_ids, {}, comptime std.sort.asc(PageID));
        
//         // Write pages in sorted order
//         for (sorted_ids) |page_id| {
//             try self.writePage(page_id);
//         }
//     }
// }; 