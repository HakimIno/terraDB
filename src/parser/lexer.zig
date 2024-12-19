const std = @import("std");
const Allocator = std.mem.Allocator;
const Vector = @Vector(16, u8);
const parser = @import("parser.zig");

// Enhanced character classification with bitfields for faster lookup
const CharacterClass = packed struct {
    is_whitespace: bool = false,
    is_digit: bool = false,
    is_alpha: bool = false,
    is_operator: bool = false,
    is_quote: bool = false,
    is_delimiter: bool = false,
    is_alphanumeric: bool = false,  // New field for combined alpha+digit check
};

// Optimized lookup table with pre-computed combinations
const char_class_table = blk: {
    var table: [256]CharacterClass = undefined;
    for (0..256) |i| {
        const is_alpha = switch (i) {
            'A'...'Z', 'a'...'z', '_' => true,
            else => false,
        };
        const is_digit = switch (i) {
            '0'...'9' => true,
            else => false,
        };
        
        table[i] = .{
            .is_whitespace = switch (i) {
                ' ', '\t', '\n', '\r' => true,
                else => false,
            },
            .is_digit = is_digit,
            .is_alpha = is_alpha,
            .is_operator = switch (i) {
                '=', '>', '<', '!', '+', '-', '*', '/', '%' => true,
                else => false,
            },
            .is_quote = switch (i) {
                '\'', '"' => true,
                else => false,
            },
            .is_delimiter = switch (i) {
                ',', '(', ')', ';', '{', '}', '[', ']' => true,
                else => false,
            },
            .is_alphanumeric = is_alpha or is_digit,
        };
    }
    break :blk table;
};

// Token pool with power-of-two size for faster modulo operations
const TokenPool = struct {
    const POOL_SIZE = 2048;  // Increased and power of 2
    const POOL_MASK = POOL_SIZE - 1;
    
    tokens: [POOL_SIZE]Token = undefined,
    len: usize = 0,
    
    fn get(self: *TokenPool) ?*Token {
        if (self.len >= POOL_SIZE) return null;
        const token = &self.tokens[self.len & POOL_MASK];
        self.len += 1;
        return token;
    }

    fn reset(self: *TokenPool) void {
        self.len = 0;
    }
};

// Optimized lexer with enhanced SIMD support and branch prediction hints
pub const FastLexer = struct {
    input: []const u8,
    position: usize,
    line: usize,
    column: usize,
    token_pool: TokenPool,
    allocator: Allocator,
    
    // Pre-computed SIMD constants
    const SPACE_VECTOR: Vector = @splat(' ');
    const TAB_VECTOR: Vector = @splat('\t');
    const NEWLINE_VECTOR: Vector = @splat('\n');
    const LOWER_A_VECTOR: Vector = @splat('a');
    const LOWER_Z_VECTOR: Vector = @splat('z');
    const UPPER_A_VECTOR: Vector = @splat('A');
    const UPPER_Z_VECTOR: Vector = @splat('Z');
    const UNDERSCORE_VECTOR: Vector = @splat('_');
    const DIGIT_0_VECTOR: Vector = @splat('0');
    const DIGIT_9_VECTOR: Vector = @splat('9');

    pub fn init(input: []const u8, allocator: Allocator) FastLexer {
        return .{
            .input = input,
            .position = 0,
            .line = 1,
            .column = 1,
            .token_pool = .{},
            .allocator = allocator,
        };
    }

    // SIMD-optimized whitespace skipping with branch prediction
    fn skipWhitespace(self: *FastLexer) void {
        const input_len = self.input.len;
        
        while (self.position < input_len) {
            if (self.position + 32 <= input_len) {
                var i: usize = 0;
                while (i < 2) : (i += 1) {
                    const offset = self.position + (i * 16);
                    const chunk: Vector = @bitCast([16]u8{
                        self.input[offset + 0],  self.input[offset + 1],
                        self.input[offset + 2],  self.input[offset + 3],
                        self.input[offset + 4],  self.input[offset + 5],
                        self.input[offset + 6],  self.input[offset + 7],
                        self.input[offset + 8],  self.input[offset + 9],
                        self.input[offset + 10], self.input[offset + 11],
                        self.input[offset + 12], self.input[offset + 13],
                        self.input[offset + 14], self.input[offset + 15],
                    });
                    
                    const space_cmp = chunk == SPACE_VECTOR;
                    const tab_cmp = chunk == TAB_VECTOR;
                    const newline_cmp = chunk == NEWLINE_VECTOR;

                    const space_bits = @select(u8, space_cmp, @as(Vector, @splat(1)), @as(Vector, @splat(0)));
                    const tab_bits = @select(u8, tab_cmp, @as(Vector, @splat(1)), @as(Vector, @splat(0)));
                    const newline_bits = @select(u8, newline_cmp, @as(Vector, @splat(1)), @as(Vector, @splat(0)));

                    const ws_mask = @reduce(.Or, space_bits | tab_bits | newline_bits);
                    
                    if (ws_mask == 0) {
                        self.position += 16;
                        self.column += 16;
                        continue;
                    }
                    
                    const trailing_zeros = if (ws_mask == 0xFFFF) 16 else @ctz(~ws_mask);
                    
                    self.position += trailing_zeros;
                    self.column += trailing_zeros;
                    break;
                }
            }

            // Optimized single-character processing
            const char = self.input[self.position];
            if (!char_class_table[char].is_whitespace) break;
            
            const is_newline = (char == '\n');
            self.line += @intFromBool(is_newline);
            self.column = if (is_newline) 1 else self.column + 1;
            self.position += 1;
        }
    }

    // Enhanced keyword matching using perfect hash table with FNV-1a
    const KeywordMap = struct {
        const Entry = struct {
            key: []const u8,
            value: TokenType,
        };
        
        const TABLE_SIZE = 64;  // Power of 2 for faster modulo
        const TABLE_MASK = TABLE_SIZE - 1;
        
        fn hash(str: []const u8) u64 {
            var h: u64 = 0xcbf29ce484222325;
            for (str) |b| {
                h = (h ^ b) *% 0x100000001b3;
            }
            return h;
        }
        
        var table: [TABLE_SIZE]?Entry = .{null} ** TABLE_SIZE;
        
        pub fn init() void {
            const keywords = .{
    // Basic query keywords
    .{ "SELECT", .keyword_select },
    .{ "FROM", .keyword_from },
    .{ "WHERE", .keyword_where },
    .{ "INSERT", .keyword_insert },
    .{ "UPDATE", .keyword_update },
    .{ "DELETE", .keyword_delete },
    .{ "CREATE", .keyword_create },
    .{ "TABLE", .keyword_table },
    
    // Data manipulation
    .{ "INTO", .keyword_into },
    .{ "VALUES", .keyword_values },
    .{ "SET", .keyword_set },
    
    // Joins
    .{ "JOIN", .keyword_join },
    .{ "INNER", .keyword_inner },
    .{ "LEFT", .keyword_left },
    .{ "RIGHT", .keyword_right },
    .{ "OUTER", .keyword_outer },
    .{ "FULL", .keyword_full },
    .{ "ON", .keyword_on },
    
    // Filtering and grouping
    .{ "GROUP", .keyword_group },
    .{ "BY", .keyword_by },
    .{ "HAVING", .keyword_having },
    .{ "ORDER", .keyword_order },
    .{ "ASC", .keyword_asc },
    .{ "DESC", .keyword_desc },
    .{ "LIMIT", .keyword_limit },
    .{ "OFFSET", .keyword_offset },
    
    // Conditionals
    .{ "AND", .keyword_and },
    .{ "OR", .keyword_or },
    .{ "NOT", .keyword_not },
    .{ "IN", .keyword_in },
    .{ "BETWEEN", .keyword_between },
    .{ "LIKE", .keyword_like },
    .{ "IS", .keyword_is },
    .{ "NULL", .keyword_null },
    
    // Table operations
    .{ "ALTER", .keyword_alter },
    .{ "DROP", .keyword_drop },
    .{ "TRUNCATE", .keyword_truncate },
    .{ "RENAME", .keyword_rename },
    .{ "TO", .keyword_to },
    .{ "ADD", .keyword_add },
    .{ "COLUMN", .keyword_column },
    .{ "MODIFY", .keyword_modify },
    
    // Constraints
    .{ "PRIMARY", .keyword_primary },
    .{ "KEY", .keyword_key },
    .{ "FOREIGN", .keyword_foreign },
    .{ "REFERENCES", .keyword_references },
    .{ "UNIQUE", .keyword_unique },
    .{ "CHECK", .keyword_check },
    .{ "DEFAULT", .keyword_default },
    .{ "INDEX", .keyword_index },
    
    // Data types
    .{ "INT", .keyword_int },
    .{ "INTEGER", .keyword_integer },
    .{ "BIGINT", .keyword_bigint },
    .{ "SMALLINT", .keyword_smallint },
    .{ "DECIMAL", .keyword_decimal },
    .{ "NUMERIC", .keyword_numeric },
    .{ "FLOAT", .keyword_float },
    .{ "DOUBLE", .keyword_double },
    .{ "CHAR", .keyword_char },
    .{ "VARCHAR", .keyword_varchar },
    .{ "TEXT", .keyword_text },
    .{ "DATE", .keyword_date },
    .{ "TIME", .keyword_time },
    .{ "TIMESTAMP", .keyword_timestamp },
    .{ "BOOLEAN", .keyword_boolean },
    
    // Transaction control
    .{ "BEGIN", .keyword_begin },
    .{ "TRANSACTION", .keyword_transaction },
    .{ "COMMIT", .keyword_commit },
    .{ "ROLLBACK", .keyword_rollback },
    .{ "SAVEPOINT", .keyword_savepoint },
    
    // Database operations
    .{ "DATABASE", .keyword_database },
    .{ "SCHEMA", .keyword_schema },
    .{ "USE", .keyword_use },
    .{ "SHOW", .keyword_show },
    .{ "GRANT", .keyword_grant },
    .{ "REVOKE", .keyword_revoke },
    .{ "TO", .keyword_to },
    .{ "FROM", .keyword_from },
    
    // Aggregate functions
    .{ "COUNT", .keyword_count },
    .{ "SUM", .keyword_sum },
    .{ "AVG", .keyword_avg },
    .{ "MIN", .keyword_min },
    .{ "MAX", .keyword_max },
    
    // Set operations
    .{ "UNION", .keyword_union },
    .{ "INTERSECT", .keyword_intersect },
    .{ "EXCEPT", .keyword_except },
    .{ "ALL", .keyword_all },
    
    // Views
    .{ "VIEW", .keyword_view },
    .{ "MATERIALIZED", .keyword_materialized },
    
    // Temporary tables
    .{ "TEMPORARY", .keyword_temporary },
    .{ "TEMP", .keyword_temp },
    
    // Case expression
    .{ "CASE", .keyword_case },
    .{ "WHEN", .keyword_when },
    .{ "THEN", .keyword_then },
    .{ "ELSE", .keyword_else },
    .{ "END", .keyword_end },
    
    // Window functions
    .{ "OVER", .keyword_over },
    .{ "PARTITION", .keyword_partition },
    .{ "RANGE", .keyword_range },
    .{ "ROWS", .keyword_rows },
    .{ "UNBOUNDED", .keyword_unbounded },
    .{ "PRECEDING", .keyword_preceding },
    .{ "FOLLOWING", .keyword_following },
    
    // Constraints modifiers
    .{ "CASCADE", .keyword_cascade },
    .{ "RESTRICT", .keyword_restrict },
    .{ "NO", .keyword_no },
    .{ "ACTION", .keyword_action },
    
    // Other common keywords
    .{ "AS", .keyword_as },
    .{ "WITH", .keyword_with },
    .{ "DISTINCT", .keyword_distinct },
    .{ "EXISTS", .keyword_exists },
    .{ "EXPLAIN", .keyword_explain },
    .{ "ANALYZE", .keyword_analyze },
    .{ "VACUUM", .keyword_vacuum },
    .{ "RETURNING", .keyword_returning },
};
            
            inline for (keywords) |kw| {
                var idx = hash(kw[0]) & TABLE_MASK;
                while (table[idx] != null) {
                    idx = (idx + 1) & TABLE_MASK;
                }
                table[idx] = .{ .key = kw[0], .value = kw[1] };
            }
        }
        
        pub fn get(str: []const u8) ?TokenType {
            var idx = hash(str) & TABLE_MASK;
            while (table[idx]) |entry| {
                if (std.mem.eql(u8, entry.key, str)) {
                    return entry.value;
                }
                idx = (idx + 1) & TABLE_MASK;
            }
            return null;
        }
    };

    // SIMD-optimized identifier reading
    fn readIdentifierOrKeyword(self: *FastLexer) !Token {
        const start = self.position;
        const start_column = self.column;
        const input_len = self.input.len;

        while (self.position + 32 <= input_len) {
            var i: usize = 0;
            while (i < 2) : (i += 1) {
                const offset = self.position + (i * 16);
                const chunk: Vector = @bitCast([16]u8{
                    self.input[offset + 0],  self.input[offset + 1],
                    self.input[offset + 2],  self.input[offset + 3],
                    self.input[offset + 4],  self.input[offset + 5],
                    self.input[offset + 6],  self.input[offset + 7],
                    self.input[offset + 8],  self.input[offset + 9],
                    self.input[offset + 10], self.input[offset + 11],
                    self.input[offset + 12], self.input[offset + 13],
                    self.input[offset + 14], self.input[offset + 15],
                });
                
                const lower_min = @select(u8, chunk >= LOWER_A_VECTOR, @as(Vector, @splat(1)), @as(Vector, @splat(0)));
                const lower_max = @select(u8, chunk <= LOWER_Z_VECTOR, @as(Vector, @splat(1)), @as(Vector, @splat(0)));
                const lower_bits = lower_min & lower_max;
                
                const upper_min = @select(u8, chunk >= UPPER_A_VECTOR, @as(Vector, @splat(1)), @as(Vector, @splat(0)));
                const upper_max = @select(u8, chunk <= UPPER_Z_VECTOR, @as(Vector, @splat(1)), @as(Vector, @splat(0)));
                const upper_bits = upper_min & upper_max;
                
                const underscore_bits = @select(u8, chunk == UNDERSCORE_VECTOR, @as(Vector, @splat(1)), @as(Vector, @splat(0)));
                
                const digit_min = @select(u8, chunk >= DIGIT_0_VECTOR, @as(Vector, @splat(1)), @as(Vector, @splat(0)));
                const digit_max = @select(u8, chunk <= DIGIT_9_VECTOR, @as(Vector, @splat(1)), @as(Vector, @splat(0)));
                const digit_bits = digit_min & digit_max;

                const valid_bits = lower_bits | upper_bits | underscore_bits | digit_bits;
                const valid_mask = @reduce(.Or, valid_bits);
                
                if (valid_mask != 0xFFFF) {
                    const trailing_valid = if (valid_mask == 0) 0 else @ctz(~valid_mask);
                    self.position += trailing_valid;
                    self.column += trailing_valid;
                    break;
                }
                
                self.position += 16;
                self.column += 16;
            }
        }

        while (self.position < input_len) {
            const char = self.input[self.position];
            if (!char_class_table[char].is_alphanumeric) break;
            self.position += 1;
            self.column += 1;
        }

        const value = self.input[start..self.position];
        
        // Use optimized keyword lookup
        if (KeywordMap.get(value)) |keyword_type| {
            return Token.init(keyword_type, value, self.line, start_column);
        }

        return Token.init(.identifier, value, self.line, start_column);
    }

    pub fn nextToken(self: *FastLexer) !Token {
        self.skipWhitespace();

        if (self.position >= self.input.len) {
            return Token.init(.eof, "", self.line, self.column);
        }

        const char = self.input[self.position];
        const char_class = char_class_table[char];

        if (char_class.is_alpha) {
            return try self.readIdentifierOrKeyword();
        } else if (char_class.is_digit) {
            return try self.readNumber();
        } else if (char_class.is_operator) {
            return try self.readOperator();
        } else if (char_class.is_quote) {
            return try self.readString();
        } else if (char_class.is_delimiter) {
            const token = Token.init(
                switch (char) {
                    ',' => .comma,
                    '(' => .left_paren,
                    ')' => .right_paren,
                    ';' => .semicolon,
                    '{' => .left_brace,
                    '}' => .right_brace,
                    '[' => .left_bracket,
                    ']' => .right_bracket,
                    else => unreachable,
                },
                self.input[self.position..self.position + 1],
                self.line,
                self.column,
            );
            self.position += 1;
            self.column += 1;
            return token;
        }

        return Token.init(
            .invalid,
            self.input[self.position..self.position + 1],
            self.line,
            self.column,
        );
    }

    // Helper methods with _ to indicate unused parameters
    fn readNumber(_: *FastLexer) !Token {
        // TODO: Implement number parsing
        @panic("Not implemented"); // Temporary
    }

    fn readOperator(_: *FastLexer) !Token {
        // TODO: Implement operator parsing
        @panic("Not implemented"); // Temporary
    }

    fn readString(_: *FastLexer) !Token {
        // TODO: Implement string parsing
        @panic("Not implemented"); // Temporary
    }
};

pub const TokenType = enum {
    // Keywords
    keyword_select,
    keyword_from,
    keyword_where,
    
    // Basic token types
    identifier,
    eof,
    comma,
    left_paren,
    right_paren,
    semicolon,
    left_brace,
    right_brace,
    left_bracket,
    right_bracket,
    invalid,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    line: usize,
    column: usize,

    pub fn init(token_type: TokenType, value: []const u8, line: usize, column: usize) Token {
        return Token{
            .type = token_type,
            .value = value,
            .line = line,
            .column = column,
        };
    }

    pub fn toParserToken(self: Token) parser.Token {
        return parser.Token{
            .type = @enumFromInt(@intFromEnum(self.type)),
            .value = self.value,
            .line = self.line,
            .column = self.column,
        };
    }
};