const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const search_messages = shift.algebraic.TransformOp("search_messages", []const u8, usize);
const search_tool_calls = shift.algebraic.TransformOp("search_tool_calls", []const u8, usize);
const search_memory_blocks = shift.algebraic.TransformOp("search_memory_blocks", []const u8, usize);
const load_opencode = shift.algebraic.ChoiceOp("load_opencode_prompts", void, usize);
const search_program = shift.algebraic.Program(usize, NoError, .{
    search_messages,
    search_tool_calls,
    search_memory_blocks,
    load_opencode,
});

const SearchState = struct {
    lines: [8][]const u8 = [_][]const u8{""} ** 8,
    len: usize = 0,
    db_available: bool = false,

    fn note(self: *SearchState, line: []const u8) void {
        self.lines[self.len] = line;
        self.len += 1;
    }
};

const handlers = struct {
    /// Return the message-surface hit count for the artifact-search example.
    pub fn searchMessages(search_state: *SearchState, query: []const u8) usize {
        if (!std.mem.eql(u8, query, "artifact-search")) unreachable;
        search_state.note("messages=1");
        return 1;
    }

    /// Return the tool-call-surface hit count for the artifact-search example.
    pub fn searchToolCalls(search_state: *SearchState, query: []const u8) usize {
        if (!std.mem.eql(u8, query, "artifact-search")) unreachable;
        search_state.note("tool_calls=0");
        return 0;
    }

    /// Return the memory-block-surface hit count for the artifact-search example.
    pub fn searchMemoryBlocks(search_state: *SearchState, query: []const u8) usize {
        if (!std.mem.eql(u8, query, "artifact-search")) unreachable;
        search_state.note("memory_blocks=1");
        return 1;
    }

    /// Choose the opencode source branch for the artifact-search example.
    pub fn loadOpencode(search_state: *SearchState, _: void) shift.ResumeOrReturn(usize, usize) {
        if (search_state.db_available) {
            search_state.note("opencode_source=db");
            return shift.ResumeOrReturn(usize, usize).resumeWith(2);
        }
        search_state.note("opencode_source=jsonl");
        return shift.ResumeOrReturn(usize, usize).resumeWith(1);
    }
};

const search_messages_handler = struct {
    /// Return the message-surface hit count for the artifact-search example.
    pub fn resumeValue(search_state: *SearchState, query: []const u8) usize {
        return handlers.searchMessages(search_state, query);
    }

    /// Preserve the resumed count unchanged.
    pub fn afterResume(_: *SearchState, answer: usize) usize {
        return answer;
    }
};

const search_tool_calls_handler = struct {
    /// Return the tool-call-surface hit count for the artifact-search example.
    pub fn resumeValue(search_state: *SearchState, query: []const u8) usize {
        return handlers.searchToolCalls(search_state, query);
    }

    /// Preserve the resumed count unchanged.
    pub fn afterResume(_: *SearchState, answer: usize) usize {
        return answer;
    }
};

const search_memory_blocks_handler = struct {
    /// Return the memory-block-surface hit count for the artifact-search example.
    pub fn resumeValue(search_state: *SearchState, query: []const u8) usize {
        return handlers.searchMemoryBlocks(search_state, query);
    }

    /// Preserve the resumed count unchanged.
    pub fn afterResume(_: *SearchState, answer: usize) usize {
        return answer;
    }
};

const load_opencode_handler = struct {
    /// Choose the opencode source branch for the artifact-search example.
    pub fn resumeOrReturn(search_state: *SearchState, _: void) shift.ResumeOrReturn(usize, usize) {
        return handlers.loadOpencode(search_state, {});
    }

    /// Preserve the resumed count unchanged.
    pub fn afterResume(_: *SearchState, answer: usize) usize {
        return answer;
    }
};

const configured = search_program.handlers(.{
    shift.algebraic.handleTransform(search_messages, &state, search_messages_handler),
    shift.algebraic.handleTransform(search_tool_calls, &state, search_tool_calls_handler),
    shift.algebraic.handleTransform(search_memory_blocks, &state, search_memory_blocks_handler),
    shift.algebraic.handleChoice(load_opencode, &state, load_opencode_handler),
});

var state = SearchState{};

const body = struct {
    /// Run the artifact-search witness body over the closed-world algebraic surface.
    pub fn body(ctx: *@TypeOf(configured).Context) shift.ResetError(NoError)!usize {
        state.note("query=artifact-search");
        var total: usize = 0;
        total += try ctx.perform(search_messages, "artifact-search");
        total += try ctx.perform(search_tool_calls, "artifact-search");
        total += try ctx.perform(search_memory_blocks, "artifact-search");
        total += try ctx.perform(load_opencode, {});
        return total;
    }
};

/// Run the exact-output artifact-search example.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    state = .{};
    const total = try configured.run(&runtime, body);
    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;

    var i: usize = 0;
    while (i < state.len) : (i += 1) {
        try stdout.print("{s}\n", .{state.lines[i]});
    }
    try stdout.print("total={d}\n", .{total});
}
