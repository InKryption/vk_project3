pub const src = struct {
    pub const triangle_frag: []const u8 = @embedFile("shader/triangle.frag");
    pub const triangle_vert: []const u8 = @embedFile("shader/triangle.vert");
};

pub const bin = struct {
    pub const triangle_frag: []const u8 = @embedFile("shader/triangle.frag.spv");
    pub const triangle_vert: []const u8 = @embedFile("shader/triangle.vert.spv");
};
