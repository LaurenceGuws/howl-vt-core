//! Responsibility: run deterministic M7 baseline measurements.
//! Ownership: architect performance protocol tooling.
//! Reason: provide reproducible local latency/throughput/allocation evidence.

const std = @import("std");
const terminal = @import("vt_core");

const WorkloadResult = struct {
    name: []const u8,
    bytes_per_run: usize,
    runs: usize,
    median_ns: u64,
    p95_ns: u64,
    median_alloc_count: usize,
    median_alloc_bytes: usize,
    median_peak_live_bytes: usize,
    median_max_queue_depth: usize,
};

const RunObservation = struct {
    ns: u64,
    alloc_count: usize,
    alloc_bytes: usize,
    peak_live_bytes: usize,
    max_queue_depth: usize,
};

const CountingAllocator = struct {
    child: std.mem.Allocator,
    alloc_count: usize = 0,
    alloc_bytes: usize = 0,
    live_bytes: usize = 0,
    peak_live_bytes: usize = 0,
    window_alloc_count: usize = 0,
    window_alloc_bytes: usize = 0,
    window_peak_live_bytes: usize = 0,
    window_live_baseline: usize = 0,

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn init(child: std.mem.Allocator) CountingAllocator {
        return .{ .child = child };
    }

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn resetWindow(self: *CountingAllocator) void {
        self.window_alloc_count = 0;
        self.window_alloc_bytes = 0;
        self.window_peak_live_bytes = 0;
        self.window_live_baseline = self.live_bytes;
    }

    fn updateWindowPeak(self: *CountingAllocator) void {
        if (self.live_bytes >= self.window_live_baseline) {
            const delta = self.live_bytes - self.window_live_baseline;
            if (delta > self.window_peak_live_bytes) self.window_peak_live_bytes = delta;
        }
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.alloc_count += 1;
        self.alloc_bytes += len;
        self.live_bytes += len;
        if (self.live_bytes > self.peak_live_bytes) self.peak_live_bytes = self.live_bytes;
        self.window_alloc_count += 1;
        self.window_alloc_bytes += len;
        self.updateWindowPeak();
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        if (new_len > memory.len) {
            const delta = new_len - memory.len;
            self.alloc_bytes += delta;
            self.window_alloc_bytes += delta;
            self.live_bytes += delta;
        } else {
            const delta = memory.len - new_len;
            self.live_bytes -|= delta;
        }
        self.updateWindowPeak();
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        if (new_len > memory.len) {
            const delta = new_len - memory.len;
            self.alloc_bytes += delta;
            self.window_alloc_bytes += delta;
            self.live_bytes += delta;
        } else {
            const delta = memory.len - new_len;
            self.live_bytes -|= delta;
        }
        self.updateWindowPeak();
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
        self.live_bytes -|= memory.len;
        self.updateWindowPeak();
    }
};

fn lessU64(_: void, lhs: u64, rhs: u64) bool {
    return lhs < rhs;
}

fn lessUsize(_: void, lhs: usize, rhs: usize) bool {
    return lhs < rhs;
}

fn medianU64(scratch: []u64) u64 {
    std.sort.heap(u64, scratch, {}, lessU64);
    return scratch[scratch.len / 2];
}

fn p95U64(scratch: []u64) u64 {
    std.sort.heap(u64, scratch, {}, lessU64);
    const n = scratch.len;
    const idx = ((95 * n) + 99) / 100 - 1;
    return scratch[@min(idx, n - 1)];
}

fn medianUsize(scratch: []usize) usize {
    std.sort.heap(usize, scratch, {}, lessUsize);
    return scratch[scratch.len / 2];
}

fn buildAsciiFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 700_000);
    defer out.deinit(allocator);
    const line = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        try out.appendSlice(allocator, line);
        try out.appendSlice(allocator, "\r\n");
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn buildCsiFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 120_000);
    defer out.deinit(allocator);
    const block = "\x1b[H\x1b[2J\x1b[31mHELLO\x1b[0m\x1b[5C\x1b[2K\x1b[1;1H";
    var i: usize = 0;
    while (i < 2_000) : (i += 1) {
        try out.appendSlice(allocator, block);
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn buildScrollFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 80_000);
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < 20_000) : (i += 1) {
        try out.appendSlice(allocator, "X\r\n");
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn runFeedApplyWorkload(
    base_allocator: std.mem.Allocator,
    name: []const u8,
    fixture: []const u8,
    rows: u16,
    cols: u16,
    history_capacity: u16,
    runs: usize,
) !WorkloadResult {
    const observations = try base_allocator.alloc(RunObservation, runs);
    defer base_allocator.free(observations);
    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var engine = try terminal.Engine.initWithCellsAndHistory(
            counting.allocator(),
            rows,
            cols,
            history_capacity,
        );
        defer engine.deinit();
        counting.resetWindow();
        const start = timer.read();
        engine.feedSlice(fixture);
        const max_queue_depth = engine.queuedEventCount();
        engine.apply();
        const end = timer.read();
        observations[i] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
            .max_queue_depth = max_queue_depth,
        };
    }

    const ns_values = try base_allocator.alloc(u64, runs);
    defer base_allocator.free(ns_values);
    const alloc_count_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_count_values);
    const alloc_bytes_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_bytes_values);
    const peak_live_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(peak_live_values);
    const queue_depth_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(queue_depth_values);

    for (observations, 0..) |obs, idx| {
        ns_values[idx] = obs.ns;
        alloc_count_values[idx] = obs.alloc_count;
        alloc_bytes_values[idx] = obs.alloc_bytes;
        peak_live_values[idx] = obs.peak_live_bytes;
        queue_depth_values[idx] = obs.max_queue_depth;
    }

    return .{
        .name = name,
        .bytes_per_run = fixture.len,
        .runs = runs,
        .median_ns = medianU64(ns_values),
        .p95_ns = p95U64(ns_values),
        .median_alloc_count = medianUsize(alloc_count_values),
        .median_alloc_bytes = medianUsize(alloc_bytes_values),
        .median_peak_live_bytes = medianUsize(peak_live_values),
        .median_max_queue_depth = medianUsize(queue_depth_values),
    };
}

fn runMixedInteractiveWorkload(
    base_allocator: std.mem.Allocator,
    runs: usize,
) !WorkloadResult {
    const bursts_per_run: usize = 5_000;
    const burst = "abc\x1b[D\x1b[C\r";
    const observations = try base_allocator.alloc(RunObservation, runs);
    defer base_allocator.free(observations);
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var engine = try terminal.Engine.initWithCellsAndHistory(
            counting.allocator(),
            40,
            120,
            1_000,
        );
        defer engine.deinit();
        counting.resetWindow();
        const start = timer.read();
        var j: usize = 0;
        var max_queue_depth: usize = 0;
        while (j < bursts_per_run) : (j += 1) {
            engine.feedSlice(burst);
            max_queue_depth = @max(max_queue_depth, engine.queuedEventCount());
            engine.apply();
        }
        const end = timer.read();
        observations[i] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
            .max_queue_depth = max_queue_depth,
        };
    }

    const ns_values = try base_allocator.alloc(u64, runs);
    defer base_allocator.free(ns_values);
    const alloc_count_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_count_values);
    const alloc_bytes_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_bytes_values);
    const peak_live_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(peak_live_values);
    const queue_depth_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(queue_depth_values);

    for (observations, 0..) |obs, idx| {
        ns_values[idx] = obs.ns;
        alloc_count_values[idx] = obs.alloc_count;
        alloc_bytes_values[idx] = obs.alloc_bytes;
        peak_live_values[idx] = obs.peak_live_bytes;
        queue_depth_values[idx] = obs.max_queue_depth;
    }

    return .{
        .name = "mixed_interactive",
        .bytes_per_run = bursts_per_run * burst.len,
        .runs = runs,
        .median_ns = medianU64(ns_values),
        .p95_ns = p95U64(ns_values),
        .median_alloc_count = medianUsize(alloc_count_values),
        .median_alloc_bytes = medianUsize(alloc_bytes_values),
        .median_peak_live_bytes = medianUsize(peak_live_values),
        .median_max_queue_depth = medianUsize(queue_depth_values),
    };
}

fn runSnapshotWorkload(
    base_allocator: std.mem.Allocator,
    fixture: []const u8,
    runs: usize,
) !WorkloadResult {
    const snapshot_calls_per_run: usize = 200;
    const observations = try base_allocator.alloc(RunObservation, runs);
    defer base_allocator.free(observations);
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var engine = try terminal.Engine.initWithCellsAndHistory(
            counting.allocator(),
            40,
            120,
            1_000,
        );
        defer engine.deinit();
        engine.feedSlice(fixture);
        engine.apply();
        counting.resetWindow();
        const start = timer.read();
        var j: usize = 0;
        while (j < snapshot_calls_per_run) : (j += 1) {
            var snap = try engine.snapshot();
            snap.deinit();
        }
        const end = timer.read();
        observations[i] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
            .max_queue_depth = 0,
        };
    }

    const ns_values = try base_allocator.alloc(u64, runs);
    defer base_allocator.free(ns_values);
    const alloc_count_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_count_values);
    const alloc_bytes_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_bytes_values);
    const peak_live_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(peak_live_values);
    const queue_depth_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(queue_depth_values);

    for (observations, 0..) |obs, idx| {
        ns_values[idx] = obs.ns;
        alloc_count_values[idx] = obs.alloc_count;
        alloc_bytes_values[idx] = obs.alloc_bytes;
        peak_live_values[idx] = obs.peak_live_bytes;
        queue_depth_values[idx] = obs.max_queue_depth;
    }

    return .{
        .name = "snapshot_opt_in",
        .bytes_per_run = snapshot_calls_per_run,
        .runs = runs,
        .median_ns = medianU64(ns_values),
        .p95_ns = p95U64(ns_values),
        .median_alloc_count = medianUsize(alloc_count_values),
        .median_alloc_bytes = medianUsize(alloc_bytes_values),
        .median_peak_live_bytes = medianUsize(peak_live_values),
        .median_max_queue_depth = medianUsize(queue_depth_values),
    };
}

fn runQueueGrowthChunkedWorkload(
    base_allocator: std.mem.Allocator,
    name: []const u8,
    fixture: []const u8,
    chunk_size: usize,
    rows: u16,
    cols: u16,
    history_capacity: u16,
    runs: usize,
) !WorkloadResult {
    const observations = try base_allocator.alloc(RunObservation, runs);
    defer base_allocator.free(observations);
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var engine = try terminal.Engine.initWithCellsAndHistory(
            counting.allocator(),
            rows,
            cols,
            history_capacity,
        );
        defer engine.deinit();

        counting.resetWindow();
        var offset: usize = 0;
        var max_queue_depth: usize = 0;
        const start = timer.read();
        while (offset < fixture.len) {
            const next = @min(offset + chunk_size, fixture.len);
            engine.feedSlice(fixture[offset..next]);
            max_queue_depth = @max(max_queue_depth, engine.queuedEventCount());
            offset = next;
        }
        engine.apply();
        const end = timer.read();
        observations[i] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
            .max_queue_depth = max_queue_depth,
        };
    }

    const ns_values = try base_allocator.alloc(u64, runs);
    defer base_allocator.free(ns_values);
    const alloc_count_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_count_values);
    const alloc_bytes_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_bytes_values);
    const peak_live_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(peak_live_values);
    const queue_depth_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(queue_depth_values);

    for (observations, 0..) |obs, idx| {
        ns_values[idx] = obs.ns;
        alloc_count_values[idx] = obs.alloc_count;
        alloc_bytes_values[idx] = obs.alloc_bytes;
        peak_live_values[idx] = obs.peak_live_bytes;
        queue_depth_values[idx] = obs.max_queue_depth;
    }

    return .{
        .name = name,
        .bytes_per_run = fixture.len,
        .runs = runs,
        .median_ns = medianU64(ns_values),
        .p95_ns = p95U64(ns_values),
        .median_alloc_count = medianUsize(alloc_count_values),
        .median_alloc_bytes = medianUsize(alloc_bytes_values),
        .median_peak_live_bytes = medianUsize(peak_live_values),
        .median_max_queue_depth = medianUsize(queue_depth_values),
    };
}

fn printResult(result: WorkloadResult) void {
    const median_ms = @as(f64, @floatFromInt(result.median_ns)) / 1_000_000.0;
    const p95_ms = @as(f64, @floatFromInt(result.p95_ns)) / 1_000_000.0;
    const median_seconds = @as(f64, @floatFromInt(result.median_ns)) / 1_000_000_000.0;
    const throughput_mib = if (median_seconds > 0)
        (@as(f64, @floatFromInt(result.bytes_per_run)) / median_seconds) / (1024.0 * 1024.0)
    else
        0.0;

    std.debug.print("workload={s}\n", .{result.name});
    std.debug.print("runs={d}\n", .{result.runs});
    std.debug.print("bytes_per_run={d}\n", .{result.bytes_per_run});
    std.debug.print("median_ms={d:.3}\n", .{median_ms});
    std.debug.print("p95_ms={d:.3}\n", .{p95_ms});
    std.debug.print("throughput_mib_s={d:.2}\n", .{throughput_mib});
    std.debug.print("median_alloc_count={d}\n", .{result.median_alloc_count});
    std.debug.print("median_alloc_bytes={d}\n", .{result.median_alloc_bytes});
    std.debug.print("median_peak_live_bytes={d}\n", .{result.median_peak_live_bytes});
    std.debug.print("median_max_queue_depth={d}\n", .{result.median_max_queue_depth});
    std.debug.print("---\n", .{});
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const runs: usize = 10;

    const ascii_fixture = try buildAsciiFixture(allocator);
    defer allocator.free(ascii_fixture);
    const csi_fixture = try buildCsiFixture(allocator);
    defer allocator.free(csi_fixture);
    const scroll_fixture = try buildScrollFixture(allocator);
    defer allocator.free(scroll_fixture);

    const ascii_result = try runFeedApplyWorkload(
        allocator,
        "ascii_heavy",
        ascii_fixture,
        40,
        120,
        0,
        runs,
    );
    const csi_result = try runFeedApplyWorkload(
        allocator,
        "csi_heavy",
        csi_fixture,
        40,
        120,
        0,
        runs,
    );
    const scroll_no_history = try runFeedApplyWorkload(
        allocator,
        "scroll_heavy_history0",
        scroll_fixture,
        40,
        120,
        0,
        runs,
    );
    const scroll_with_history = try runFeedApplyWorkload(
        allocator,
        "scroll_heavy_history1000",
        scroll_fixture,
        40,
        120,
        1_000,
        runs,
    );
    const mixed_result = try runMixedInteractiveWorkload(allocator, runs);
    const snapshot_result = try runSnapshotWorkload(allocator, scroll_fixture, runs);
    const queue_growth_ascii = try runQueueGrowthChunkedWorkload(
        allocator,
        "queue_growth_ascii_chunked_64",
        ascii_fixture,
        64,
        40,
        120,
        0,
        runs,
    );
    const queue_growth_scroll = try runQueueGrowthChunkedWorkload(
        allocator,
        "queue_growth_scroll_chunked_16",
        scroll_fixture,
        16,
        40,
        120,
        1_000,
        runs,
    );

    std.debug.print("m7_baseline_v1\n", .{});
    std.debug.print("rows=40 cols=120 runs={d}\n", .{runs});
    std.debug.print("---\n", .{});
    printResult(ascii_result);
    printResult(csi_result);
    printResult(scroll_no_history);
    printResult(scroll_with_history);
    printResult(mixed_result);
    printResult(snapshot_result);
    printResult(queue_growth_ascii);
    printResult(queue_growth_scroll);
}
