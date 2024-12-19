pub const PlanNodeType = enum {
    sequential_scan,
    index_scan,
    nested_loop_join,
    hash_join,
    sort,
    aggregate,
    filter,
};

pub const PlanNode = struct {
    type: PlanNodeType,
    cost: f64,
    estimated_rows: usize,
    children: std.ArrayList(*PlanNode),
    
    // Statistics for optimization
    table_stats: ?*TableStatistics,
    index_stats: ?*IndexStatistics,
    
    pub fn estimateCost(self: *PlanNode) f64 {
        var total_cost: f64 = switch(self.type) {
            .sequential_scan => self.estimateSequentialScanCost(),
            .index_scan => self.estimateIndexScanCost(),
            .nested_loop_join => self.estimateNestedLoopJoinCost(),
            .hash_join => self.estimateHashJoinCost(),
            // ... อื่นๆ
        };
        
        // Add children costs
        for (self.children.items) |child| {
            total_cost += child.estimateCost();
        }
        
        return total_cost;
    }
}; 