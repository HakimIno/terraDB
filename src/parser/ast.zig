// Optimized AST node with small buffer optimization
pub const OptimizedASTNode = struct {
    const INLINE_CAPACITY = 4;
    
    allocator: Allocator,
    type: ASTNodeType,
    value: []const u8,
    children: union {
        inline: struct {
            data: [INLINE_CAPACITY]*OptimizedASTNode,
            len: u8,
        },
        list: std.ArrayList(*OptimizedASTNode),
    },
    is_inline: bool,

    pub fn init(allocator: Allocator, node_type: ASTNodeType, value: []const u8) !*OptimizedASTNode {
        const node = try allocator.create(OptimizedASTNode);
        node.* = .{
            .allocator = allocator,
            .type = node_type,
            .value = value,
            .children = .{ .inline = .{ .data = undefined, .len = 0 } },
            .is_inline = true,
        };
        return node;
    }

    pub fn addChild(self: *OptimizedASTNode, child: *OptimizedASTNode) !void {
        if (self.is_inline) {
            if (self.children.inline.len < INLINE_CAPACITY) {
                self.children.inline.data[self.children.inline.len] = child;
                self.children.inline.len += 1;
                return;
            }
            try self.convertToList();
        }
        try self.children.list.append(child);
    }

    fn convertToList(self: *OptimizedASTNode) !void {
        var list = std.ArrayList(*OptimizedASTNode).init(self.allocator);
        try list.ensureTotalCapacity(8);
        
        for (self.children.inline.data[0..self.children.inline.len]) |child| {
            try list.append(child);
        }
        
        self.children = .{ .list = list };
        self.is_inline = false;
    }
}; 