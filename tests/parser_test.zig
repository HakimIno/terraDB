const std = @import("std");
const testing = std.testing;
const Parser = @import("parser").Parser;
const Lexer = @import("parser").Lexer;
const TokenType = @import("parser").TokenType;
const Token = @import("parser").Token;
const ASTNodeType = @import("parser").ASTNodeType;
const ASTNode = @import("parser").ASTNode;

fn expectNodeType(expected: ASTNodeType, node: *const ASTNode) !void {
    try testing.expectEqual(expected, node.type);
}

fn expectNodeValue(expected: []const u8, node: *const ASTNode) !void {
    try testing.expectEqualStrings(expected, node.value);
}

fn parseSQL(sql: []const u8, allocator: std.mem.Allocator) !*ASTNode {
    var lexer = Lexer.init(sql, allocator);
    var parser = try Parser.init(&lexer, allocator);
    return parser.parse();
}

test "lexer basic tokens" {
    const allocator = testing.allocator;
    
    // Test simple SQL
    const sql = "SELECT id, name FROM users WHERE age > 18;";
    var lexer = Lexer.init(sql, allocator);
    
    // Verify tokens
    try testing.expectEqual(TokenType.keyword_select, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.identifier, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.comma, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.identifier, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.keyword_from, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.identifier, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.keyword_where, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.identifier, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.greater_than, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.integer_literal, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.semicolon, (try lexer.nextToken()).type);
    try testing.expectEqual(TokenType.eof, (try lexer.nextToken()).type);
}

test "parser select statement" {
    const allocator = testing.allocator;
    
    // Test SELECT statement
    const sql = "SELECT id, name FROM users WHERE age > 18";
    var lexer = Lexer.init(sql, allocator);
    var parser = try Parser.init(&lexer, allocator);
    
    const ast = try parser.parse();
    defer ast.deinit();
    
    // Verify AST structure
    try testing.expectEqual(ASTNodeType.select_statement, ast.type);
    const children = ast.getChildren();
    try testing.expectEqual(@as(usize, 4), children.len); // 2 columns + table ref + where condition
    
    // Verify columns
    try expectNodeType(.column_ref, children[0]);
    try expectNodeValue("id", children[0]);
    
    try expectNodeType(.column_ref, children[1]);
    try expectNodeValue("name", children[1]);
    
    // Verify table reference
    try expectNodeType(.table_ref, children[2]);
    try expectNodeValue("users", children[2]);
    
    // Verify WHERE condition
    try expectNodeType(.binary_expr, children[3]);
    const where_children = children[3].getChildren();
    try testing.expectEqual(@as(usize, 2), where_children.len);
    
    try expectNodeType(.column_ref, where_children[0]);
    try expectNodeValue("age", where_children[0]);
    
    try expectNodeType(.literal, where_children[1]);
    try expectNodeValue("18", where_children[1]);
}

test "parser complex queries" {
    const allocator = testing.allocator;
    
    // Test more complex SQL statements
    const test_cases = [_][]const u8{
        "SELECT * FROM users",
        "SELECT id, name, age FROM users WHERE age >= 18 AND name = 'John'",
        "INSERT INTO users (name, age) VALUES ('Alice', 25)",
        "UPDATE users SET age = 30 WHERE id = 1",
        "DELETE FROM users WHERE id = 1",
        "CREATE TABLE users (id INT PRIMARY KEY, name TEXT)",
    };
    
    for (test_cases) |sql| {
        std.debug.print("\nทดสอบ SQL: {s}\n", .{sql});
        
        var lexer = Lexer.init(sql, allocator);
        var parser = try Parser.init(&lexer, allocator);
        
        // Wrap parsing in errdefer for better cleanup
        const ast = try parser.parse();
        defer {
            ast.deinit();
            std.debug.print("คืนหน่วยความจำสำหรับ: {s}\n", .{sql});
        }
        
        // Verify basic structure
        try testing.expect(ast.type != ASTNodeType.literal);
        const children = ast.getChildren();
        try testing.expect(children.len > 0);
        
        // Additional verification based on statement type
        switch (ast.type) {
            .select_statement => {
                try testing.expect(children.len >= 2); // At least columns and table
                try testing.expect(children[0].type == .column_ref or children[0].type == .literal);
            },
            .insert_statement => {
                try testing.expect(children.len >= 2); // At least table and one value
                try expectNodeType(.table_ref, children[0]);
            },
            .update_statement => {
                try testing.expect(children.len >= 2); // At least table and one set
                try expectNodeType(.table_ref, children[0]);
            },
            .delete_statement => {
                try testing.expect(children.len >= 1); // At least table
                try expectNodeType(.table_ref, children[0]);
            },
            .create_table_statement => {
                try testing.expect(children.len >= 2); // At least table name and one column
                try expectNodeType(.table_ref, children[0]);
            },
            else => return error.UnexpectedStatementType,
        }
    }
}

test "parser error handling" {
    const allocator = testing.allocator;
    
    // Test invalid SQL statements
    const invalid_queries = [_][]const u8{
        "SELECT",  // Incomplete
        "FROM users",  // Missing SELECT
        "SELECT * FROM",  // Missing table name
        "INSERT VALUES (1, 2)",  // Missing INTO
    };
    
    for (invalid_queries) |sql| {
        var lexer = Lexer.init(sql, allocator);
        var parser = try Parser.init(&lexer, allocator);
        
        // Expect parsing to fail
        try testing.expectError(error.UnexpectedToken, parser.parse());
    }
}

test "lexer string literals" {
    const allocator = testing.allocator;
    
    const sql = "SELECT * FROM users WHERE name = 'John Smith'";
    var lexer = Lexer.init(sql, allocator);
    
    // เก็บ token ไว้ในตัวแปรระหว่าง loop
    var token: Token = undefined;
    while (true) {
        token = try lexer.nextToken();
        if (token.type == TokenType.string_literal) break;
        if (token.type == TokenType.eof) {
            // ถ้าเจอ EOF ก่อนเจอ string literal แสดงว่ามีปัญหา
            return error.StringLiteralNotFound;
        }
    }
    
    // ตรวจสอบค่าที่ได้
    try testing.expectEqual(TokenType.string_literal, token.type);
    try testing.expectEqualStrings("'John Smith'", token.value);
}

test "parser memory management" {
    const allocator = testing.allocator;
    
    // สร้าง arena allocator สำหรับการทดสอบ
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    const test_cases = [_][]const u8{
        "SELECT id, name FROM users",
        "SELECT * FROM users WHERE id = 1",
        "INSERT INTO users (name) VALUES ('test')",
    };

    // ทดสอบแต่ละ query
    for (test_cases) |sql| {
        std.debug.print("\nทดสอบ Memory Management: {s}\n", .{sql});
        
        var lexer = Lexer.init(sql, arena.allocator());
        var parser = try Parser.init(&lexer, arena.allocator());
        
        const ast = try parser.parse();
        defer {
            std.debug.print("คืนหน่วยความจำสำหรับ AST\n", .{});
            ast.deinit();
        }
        
        // ตรวจสอบว่า AST ถูกสร้างอย่างถูกต้อง
        try testing.expect(ast.type != ASTNodeType.literal);
        const children = ast.getChildren();
        try testing.expect(children.len > 0);
        
        // ตรวจสอบว่าทุก node มี allocator ที่ถูกต้อง
        for (children) |child| {
            try testing.expect(child.allocator.ptr == arena.allocator().ptr);
        }
    }
    
    // ถ้าไม่มี memory leak, arena.deinit() จะทำงานได้โดยไม่มีปัญหา
}

// test "parser complex joins" {
//     const allocator = testing.allocator;
    
//     const sql = 
//         \\SELECT users.name, orders.total 
//         \\FROM users 
//         \\JOIN orders ON users.id = orders.user_id 
//         \\WHERE orders.total > 1000
//     ;
    
//     var lexer = Lexer.init(sql, allocator);
//     var parser = try Parser.init(&lexer, allocator);
    
//     const ast = try parser.parse();
//     defer ast.deinit();
    
//     // Verify AST structure
//     try testing.expectEqual(ASTNodeType.select_statement, ast.type);
//     // Add more specific checks...
// }

test "parser create table with constraints" {
    const allocator = testing.allocator;
    
    const sql = 
        \\CREATE TABLE products (
        \\    id INT PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    price FLOAT DEFAULT 0.0,
        \\    category_id INT REFERENCES categories(id)
        \\)
    ;
    
    std.debug.print("\nเริ่มการทดสอบ CREATE TABLE\n", .{});
    
    var lexer = Lexer.init(sql, allocator);
    var parser = try Parser.init(&lexer, allocator);
    
    std.debug.print("กำลังแยกวิเคราะห์ SQL\n", .{});
    
    const ast = try parser.parse();
    defer {
        std.debug.print("กำลังคืนหน่วยความจำ\n", .{});
        ast.deinit();
    }
    
    std.debug.print("ตรวจสอบโครงสร้าง AST\n", .{});
    
    try testing.expectEqual(ASTNodeType.create_table_statement, ast.type);
    const children = ast.getChildren();
    
    std.debug.print("จำนวน children: {d}\n", .{children.len});
    
    // ตรวจสอบชื่อตาราง
    try testing.expectEqual(ASTNodeType.table_ref, children[0].type);
    try testing.expectEqualStrings("products", children[0].value);
    
    // ตรวจสอบคอลัมน์แรก (id)
    if (children.len > 1) {
        const id_column = children[1];
        try testing.expectEqual(ASTNodeType.column_def, id_column.type);
        try testing.expectEqualStrings("id", id_column.value);
        
        const id_children = id_column.getChildren();
        std.debug.print("จำนวน children ของคอลัมน์ id: {d}\n", .{id_children.len});
        
        if (id_children.len >= 2) {
            try testing.expectEqual(ASTNodeType.data_type, id_children[0].type);
            try testing.expectEqualStrings("INT", id_children[0].value);
            try testing.expectEqual(ASTNodeType.constraint, id_children[1].type);
            try testing.expectEqualStrings("PRIMARY KEY", id_children[1].value);
        } else {
            return error.InsufficientChildren;
        }
    } else {
        return error.MissingColumns;
    }
}

test "parser helper functions" {
    const allocator = testing.allocator;
    
    const sql = "SELECT id FROM users";
    const ast = try parseSQL(sql, allocator);
    defer ast.deinit();
    
    try expectNodeType(.select_statement, ast);
    try expectNodeType(.column_ref, ast.getChildren()[0]);
    try expectNodeValue("id", ast.getChildren()[0]);
}

test "parser performance benchmark" {
    const allocator = testing.allocator;
    
    // ประกาศ test_cases ก่อนใช้
    const test_cases = [_][]const u8{
        "SELECT id, name, email FROM users WHERE age > 18 AND status = 'active'",
        "SELECT * FROM users",
        "SELECT id FROM users WHERE id = 1",
    };
    
    // Reduce iterations for development/debugging
    const iterations = 1000;
    
    var timer = try std.time.Timer.start();
    
    // Test each query type
    for (test_cases) |sql| {
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            var lexer = Lexer.init(sql, allocator);
            var parser = try Parser.init(&lexer, allocator);
            const ast = try parser.parse();
            ast.deinit();
        }
        
        const elapsed = timer.read();
        const avg_time = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations));
        
        std.debug.print("\nQuery: {s}\n", .{sql});
        std.debug.print("Average parse time: {d:.2} ns\n", .{avg_time});
        std.debug.print("Queries per second: {d:.2}\n", .{1_000_000_000 / avg_time});
    }
}