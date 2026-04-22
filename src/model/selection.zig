//! Responsibility: hold terminal selection state and transitions.
//! Ownership: terminal model selection primitive.
//! Reason: keep selection behavior explicit and independent from UI/runtime layers.

/// Row/column position used by selection endpoints.
pub const SelectionPos = struct {
    row: usize,
    col: usize,
};

/// Active selection bounds and lifecycle flags.
pub const TerminalSelection = struct {
    active: bool,
    selecting: bool,
    start: SelectionPos,
    end: SelectionPos,
};

/// Selection lifecycle operations for begin/update/finish/clear flows.
pub const SelectionState = struct {
    selection: TerminalSelection,

    /// Create an inactive selection state at origin.
    pub fn init() SelectionState {
        return .{
            .selection = .{
                .active = false,
                .selecting = false,
                .start = .{ .row = 0, .col = 0 },
                .end = .{ .row = 0, .col = 0 },
            },
        };
    }

    /// Clear current selection and mark selection as inactive.
    pub fn clear(self: *SelectionState) void {
        self.selection.active = false;
        self.selection.selecting = false;
    }

    /// Begin a new selection at `row`/`col`.
    pub fn start(self: *SelectionState, row: usize, col: usize) void {
        self.selection.active = true;
        self.selection.selecting = true;
        self.selection.start = .{ .row = row, .col = col };
        self.selection.end = .{ .row = row, .col = col };
    }

    /// Update the selection end position while selection is active.
    pub fn update(self: *SelectionState, row: usize, col: usize) void {
        if (!self.selection.active) return;
        self.selection.end = .{ .row = row, .col = col };
    }

    /// Mark active selection as finished.
    pub fn finish(self: *SelectionState) void {
        if (!self.selection.active) return;
        self.selection.selecting = false;
    }

    /// Return current selection when active; otherwise return `null`.
    pub fn state(self: *const SelectionState) ?TerminalSelection {
        if (!self.selection.active) return null;
        return self.selection;
    }
};
