pub const QueryEngine = struct {
    parser: Parser,
    optimizer: QueryOptimizer,
    executor: Executor,
    statistics: Statistics,
    
    pub fn executeQuery(self: *QueryEngine, query: []const u8) !ResultSet {
        // 1. Parse SQL to AST
        const ast = try self.parser.parse(query);
        
        // 2. Generate initial plan
        var initial_plan = try self.generateInitialPlan(ast);
        
        // 3. Optimize plan
        const optimized_plan = try self.optimizer.optimize(initial_plan);
        
        // 4. Execute plan
        return self.executor.execute(optimized_plan);
    }
    
    pub fn prepareStatement(self: *QueryEngine, query: []const u8) !PreparedStatement {
        // Similar to executeQuery but caches the plan
        const ast = try self.parser.parse(query);
        const plan = try self.optimizer.optimize(try self.generateInitialPlan(ast));
        
        return PreparedStatement{
            .plan = plan,
            .parameter_types = try self.analyzeParameters(ast),
        };
    }
}; 