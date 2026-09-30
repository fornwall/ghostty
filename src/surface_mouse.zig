/// SurfaceMouse represents mouse helper functionality for the core surface.
///
/// It's currently small in scope; its purpose is to isolate mouse logic that
/// has gotten a bit complex (e.g. pointer shape handling for key events), but
/// the intention is to grow it later so that we can better test said logic).
const SurfaceMouse = @This();

const std = @import("std");
const builtin = @import("builtin");
const input = @import("input.zig");
const terminal = @import("terminal/main.zig");
const MouseShape = terminal.MouseShape;

/// For processing key events; the key that was physically pressed on the
/// keyboard.
physical_key: input.Key,

/// The mouse event tracking mode, if any.
mouse_event: terminal.MouseEvent,

/// The application's OSC 22 request, if any.
mouse_shape: ?MouseShape,

/// The last mods state when the last mouse button (whatever it was) was
/// pressed or release.
mods: input.Mods,

/// True if the mouse position is currently over a link.
over_link: bool,

/// True if the mouse pointer is currently hidden.
hidden: bool,

/// Translates key state to mouse shape, called during key events. This mainly
/// handles overrides on key presses depending on whether or not we are in
/// mouse tracking mode, however it is also responsible for resetting cursor
/// state on any particular key releases.
///
/// null is returned when the mouse shape does not need changing.
pub fn keyToMouseShape(self: SurfaceMouse) ?MouseShape {
    // Filter for appropriate key events
    if (!eligibleMouseShapeKeyEvent(self.physical_key)) return null;

    // Exceptions: link hover or hidden state overrides any other shape
    // processing and does not change state.
    //
    // TODO: As we unravel mouse state, we can fix this to be more explicit.
    if (self.over_link or self.hidden) {
        return null;
    }

    return self.shape();
}

/// Resolve the displayed shape from host overrides, the application request,
/// and finally the mouse tracking default.
pub fn shape(self: SurfaceMouse) MouseShape {
    if (self.over_link) return .pointer;

    if (isRectangleSelectState(self.mods) and
        (self.mouse_event == .none or isMouseModeOverrideState(self.mods)))
    {
        return .crosshair;
    }
    if (isMouseModeOverrideState(self.mods)) return .text;

    return self.mouse_shape orelse if (self.mouse_event == .none) .text else .default;
}

fn eligibleMouseShapeKeyEvent(physical_key: input.Key) bool {
    return physical_key.ctrlOrSuper() or
        physical_key.leftOrRightShift() or
        physical_key.leftOrRightAlt();
}

fn isMouseModeOverrideState(mods: input.Mods) bool {
    return mods.shift;
}

/// Returns true if our modifiers put us in a state where dragging
/// should cause a rectangle select.
pub fn isRectangleSelectState(mods: input.Mods) bool {
    return if (comptime builtin.target.os.tag.isDarwin())
        mods.alt
    else
        mods.ctrlOrSuper() and mods.alt;
}

test "keyToMouseShape" {
    const testing = std.testing;

    {
        // No specific key pressed
        const m: SurfaceMouse = .{
            .physical_key = .unidentified,
            .mouse_event = .none,
            .mouse_shape = .progress,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const got = m.keyToMouseShape();
        try testing.expect(got == null);
    }

    {
        // Over a link. NOTE: This tests that we don't touch the inbound state,
        // not necessarily if we're over a link.
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .none,
            .mouse_shape = .progress,
            .mods = .{},
            .over_link = true,
            .hidden = false,
        };

        const got = m.keyToMouseShape();
        try testing.expect(got == null);
    }

    {
        // Mouse is currently hidden
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .none,
            .mouse_shape = .progress,
            .mods = .{},
            .over_link = true,
            .hidden = true,
        };

        const got = m.keyToMouseShape();
        try testing.expect(got == null);
    }

    {
        // default, no mods (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .x10,
            .mouse_shape = .default,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .default;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // default -> crosshair (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .x10,
            .mouse_shape = .default,
            .mods = .{ .ctrl = true, .super = true, .alt = true, .shift = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .crosshair;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // default -> text (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .x10,
            .mouse_shape = .default,
            .mods = .{ .shift = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .text;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // crosshair -> text (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .x10,
            .mouse_shape = .crosshair,
            .mods = .{ .shift = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .text;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // no override restores the application shape (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .x10,
            .mouse_shape = .crosshair,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .crosshair;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // text -> crosshair (mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .x10,
            .mouse_shape = .text,
            .mods = .{ .ctrl = true, .super = true, .alt = true, .shift = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .crosshair;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // text, no mods (no mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .shift_left,
            .mouse_event = .none,
            .mouse_shape = .text,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .text;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // text -> crosshair (no mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .none,
            .mouse_shape = .text,
            .mods = .{ .ctrl = true, .super = true, .alt = true },
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .crosshair;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }

    {
        // no override restores the application shape (no mouse tracking)
        const m: SurfaceMouse = .{
            .physical_key = .alt_left,
            .mouse_event = .none,
            .mouse_shape = .crosshair,
            .mods = .{},
            .over_link = false,
            .hidden = false,
        };

        const want: MouseShape = .crosshair;
        const got = m.keyToMouseShape();
        try testing.expect(want == got);
    }
}

test "mouse shape request and host overrides" {
    const testing = std.testing;
    var m: SurfaceMouse = .{
        .physical_key = .unidentified,
        .mouse_event = .none,
        .mouse_shape = null,
        .mods = .{},
        .over_link = false,
        .hidden = false,
    };

    for ([_]terminal.MouseEvent{ .none, .normal }) |event| {
        m.mouse_event = event;
        m.mouse_shape = null;
        const default: MouseShape = if (event == .none) .text else .default;
        try testing.expectEqual(default, m.shape());

        // Explicit text also overrides the tracking default.
        for ([_]MouseShape{ .text, .wait }) |request| {
            m.mouse_shape = request;
            try testing.expectEqual(request, m.shape());
        }
    }

    m.mods = .{ .shift = true, .ctrl = true, .super = true, .alt = true };
    m.over_link = true;
    try testing.expectEqual(MouseShape.pointer, m.shape());
}
