// zlinter-disable declaration_naming require_doc_comment
const boundary = @import("boundary");

const ProductPayload = struct {
    amount: i32,
};

const ProductStateRows = boundary.ir.schema.LowerBinding(
    boundary.ir.schema.Binding("state", boundary.effect.state.Schema(ProductPayload, error{}), void),
    .{ .requirement_index = 0, .first_op = 0, .first_output = 0 },
);

test "schema lowerer rejects product refs without schema-index map" {
    _ = ProductStateRows;
}
