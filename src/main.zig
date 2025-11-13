const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const style = @embedFile("style");

const BASE_SCALE = 1.0;
const BODY_COUNT = 3;
const RADIUS = 2.5;

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 640;

const TARGET_FPS = 60;
const GRAVITATIONAL_CONSTANT = 1.0;

const CAMERA_SPEED = 3;

const TRAIL_LENGTH = 100;

const Body = struct {
    aPosition: rl.Vector3,
    aVelocity: rl.Vector3,

    raw_vel: f32 = 0.0,

    mass: f32,

    color: rl.Color = .blue,

    trail: [TRAIL_LENGTH]rl.Vector3 = undefined,
    trail_index: usize = 0,

    pub fn init(position: rl.Vector3, velocity: rl.Vector3, mass: f32, color: rl.Color, options: struct { scale: f32 = BASE_SCALE }) Body {
        var body = Body{
            .aPosition = position.scale(options.scale),
            .aVelocity = velocity.scale(options.scale),
            .mass = mass * options.scale,
            .color = color,
        };

        body.raw_vel = body.aVelocity.length();
        body.trail = [_]rl.Vector3{body.aPosition} ** TRAIL_LENGTH;
        return body;
    }

    pub fn update_trail(self: *Body) void {
        self.trail[self.trail_index] = self.aPosition;
        self.trail_index = (self.trail_index + 1) % TRAIL_LENGTH;
    }
};

fn hex_to_color(hex: i32) rl.Color {
    return rl.Color{
        .r = @intCast((hex >> 24) & 0xFF),
        .g = @intCast((hex >> 16) & 0xFF),
        .b = @intCast((hex >> 8) & 0xFF),
        .a = @intCast(hex & 0xFF),
    };
}

fn simulate(bodies: *[BODY_COUNT]Body, options: struct {
    vel_damping: i32 = 999,
    restitution_coefficient: i32 = 999,
}) void {
    for (bodies, 0..) |*body, i| {
        var force = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        for (bodies, 0..) |*other_body, j| {
            if (i != j) {
                if (rl.checkCollisionSpheres(body.aPosition, RADIUS, other_body.aPosition, RADIUS)) {
                    const n = other_body.aPosition.subtract(body.aPosition).normalize();
                    const relative_velocity = other_body.aVelocity.subtract(body.aVelocity);
                    const velocity_along_normal = relative_velocity.dotProduct(n);

                    if (velocity_along_normal < 0) {
                        const impulse = ((1.0 + @as(f32, @floatFromInt(options.restitution_coefficient)) / 1000.0) * velocity_along_normal) / (body.mass + other_body.mass);
                        body.aVelocity = body.aVelocity.add(n.scale(impulse * other_body.mass));
                        other_body.aVelocity = other_body.aVelocity.subtract(n.scale(impulse * body.mass));
                    }
                } else {
                    const direction = rl.Vector3{
                        .x = other_body.aPosition.x - body.aPosition.x,
                        .y = other_body.aPosition.y - body.aPosition.y,
                        .z = other_body.aPosition.z - body.aPosition.z,
                    };
                    const distance = direction.length();

                    const f = GRAVITATIONAL_CONSTANT * (body.mass * other_body.mass) / (distance * distance);
                    const norm_direction = direction.normalize();
                    force = force.add(norm_direction.scale(f));
                }
            }
        }
        const acceleration = force.scale(1 / body.mass);
        body.aVelocity = body.aVelocity.add(acceleration);
        body.aVelocity = body.aVelocity.scale(@as(f32, @floatFromInt(options.vel_damping)) / 1000.0);
        body.raw_vel = body.aVelocity.length();
    }

    for (bodies) |*body| {
        body.aPosition = body.aPosition.add(body.aVelocity);
    }
}

fn draw_grid_around(center: rl.Vector3, options: struct {
    slices: usize = 10,
    spacing: f32 = 10.0 * BASE_SCALE,
}) void {
    const half_size = @as(f32, @floatFromInt(options.slices)) * options.spacing / 2.0;

    for (0..options.slices + 1) |i| {
        const offset = (@as(f32, @floatFromInt(i)) * options.spacing) - half_size;

        rl.drawLine3D(
            rl.Vector3{ .x = center.x - half_size, .y = center.y, .z = center.z + offset },
            rl.Vector3{ .x = center.x + half_size, .y = center.y, .z = center.z + offset },
            .light_gray,
        );

        rl.drawLine3D(
            rl.Vector3{ .x = center.x + offset, .y = center.y, .z = center.z - half_size },
            rl.Vector3{ .x = center.x + offset, .y = center.y, .z = center.z + half_size },
            .light_gray,
        );
    }
}

pub fn main() !void {
    var simulations_per_frame: usize = 1;

    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "3-body problem simulation");

    var tmp = try std.fs.cwd().createFile("style.rgsl", .{ .truncate = true });
    defer tmp.close();
    defer std.fs.cwd().deleteFile("style.rgsl") catch {};

    try tmp.writeAll(style);

    rg.loadStyle("style.rgsl");

    var camera = rl.Camera3D{
        .position = (rl.Vector3{ .x = 0.0, .y = 0.0, .z = 300.0 }).scale(BASE_SCALE),
        .target = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = rl.Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    const background_color_raw = rg.getStyle(.default, .{ .default = .background_color });
    const background_color = hex_to_color(background_color_raw);

    const text_color_raw = rg.getStyle(.control11, .{ .control = .text_color_normal });
    const text_color = hex_to_color(text_color_raw);

    const INITIAL_POSITION = [BODY_COUNT]Body{
        Body.init(
            rl.Vector3{ .x = 20.0, .y = 0.0, .z = 0.0 },
            rl.Vector3{ .x = 0.0, .y = 0.0, .z = -0.17 },
            5.0,
            .red,
            .{},
        ),
        Body.init(
            rl.Vector3{ .x = -10.0, .y = 0.0, .z = 17.320508 },
            rl.Vector3{ .x = 0.147198, .y = 0.0, .z = 0.084949 },
            1.0,
            .green,
            .{},
        ),
        Body.init(
            rl.Vector3{ .x = -10.0, .y = 0.0, .z = -17.320508 },
            rl.Vector3{ .x = -0.147198, .y = 0.0, .z = 0.084949 },
            10.0,
            .blue,
            .{},
        ),
    };

    // hard clone INITIAL_POSITION into bodies
    var bodies: [BODY_COUNT]Body = undefined;
    for (INITIAL_POSITION, 0..) |body, i| {
        bodies[i] = body;
    }

    rl.setTargetFPS(TARGET_FPS);

    var focused_body_index: usize = 3;
    var is_paused = true;
    var damping: i32 = 999;
    var restitution: i32 = 999;

    var is_following = false;
    var text_visible = true;
    var controls_visible = true;

    var offset = rl.Vector3{ .x = 0.0, .y = 20.0, .z = 20.0 };

    const total_editable = 3;
    var current_ui_elem: i32 = total_editable;

    const CONTROLS_POS_VISIBLE: rl.Rectangle = .{
        .x = SCREEN_WIDTH - 240,
        .y = 10,
        .width = 230,
        .height = 220,
    };

    const CONTROLS_POS_HIDDEN: rl.Rectangle = .{
        .x = SCREEN_WIDTH - 240,
        .y = 10,
        .width = 230,
        .height = 10,
    };

    var controls_pos = CONTROLS_POS_VISIBLE;

    while (!rl.windowShouldClose()) {
        var update_target = if (is_following and focused_body_index < BODY_COUNT)
            &offset
        else
            &camera.position;

        if (rl.isKeyDown(.w)) update_target.y += CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.s)) update_target.y -= CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.a)) update_target.x -= CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.d)) update_target.x += CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.q)) update_target.z -= CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.e)) update_target.z += CAMERA_SPEED * BASE_SCALE;

        if (rl.isKeyPressed(.one)) focused_body_index = 0;
        if (rl.isKeyPressed(.two)) focused_body_index = 1;
        if (rl.isKeyPressed(.three)) focused_body_index = 2;
        if (rl.isKeyPressed(.left)) focused_body_index = (focused_body_index + BODY_COUNT) % (BODY_COUNT + 1);
        if (rl.isKeyPressed(.right)) focused_body_index = (focused_body_index + 1) % (BODY_COUNT + 1);

        if (rl.isKeyPressed(.p)) is_paused = !is_paused;

        if (rl.isKeyPressed(.tab)) {
            current_ui_elem = if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift))
                @mod(current_ui_elem - 1 + total_editable + 1, total_editable + 1)
            else
                @mod(current_ui_elem + 1, total_editable + 1);
        }

        if (rl.isKeyPressed(.f)) {
            is_following = !is_following;
            if (is_following and focused_body_index < BODY_COUNT) {
                camera.target = bodies[focused_body_index].aPosition;
                camera.position = bodies[focused_body_index].aPosition.add(offset);
            }
        }

        if (rl.isKeyPressed(.u)) text_visible = !text_visible;
        if (rl.isKeyPressed(.c)) {
            controls_visible = !controls_visible;
            controls_pos = if (controls_visible) CONTROLS_POS_VISIBLE else CONTROLS_POS_HIDDEN;
        }

        if (!is_paused) {
            if (simulations_per_frame > 0) {
                for (0..simulations_per_frame) |_| {
                    simulate(&bodies, .{
                        .vel_damping = damping,
                        .restitution_coefficient = restitution,
                    });
                }
            }
        }

        camera.target = if (focused_body_index < BODY_COUNT)
            bodies[focused_body_index].aPosition
        else
            rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };

        camera.position = if (is_following and focused_body_index < BODY_COUNT)
            bodies[focused_body_index].aPosition.add(offset)
        else
            camera.position;

        // Draw
        rl.beginDrawing();
        rl.clearBackground(background_color);

        if (text_visible)
            _ = rg.groupBox(controls_pos, "Controls (c)");

        if (text_visible and controls_visible) {
            _ = .{ rg.spinner(
                .{
                    .x = controls_pos.x + controls_pos.width - 110,
                    .y = controls_pos.y + 20,
                    .width = 100,
                    .height = 30,
                },
                "Sims/Frame",
                @as(*i32, @ptrCast(&simulations_per_frame)),
                1,
                100,
                current_ui_elem == 0,
            ), rg.spinner(
                .{
                    .x = controls_pos.x + controls_pos.width - 110,
                    .y = controls_pos.y + 60,
                    .width = 100,
                    .height = 30,
                },
                "Damping(/1000)",
                &damping,
                900,
                1000,
                current_ui_elem == 1,
            ), rg.spinner(
                .{
                    .x = controls_pos.x + controls_pos.width - 110,
                    .y = controls_pos.y + 100,
                    .width = 100,
                    .height = 30,
                },
                "Restitution(/1000)",
                &restitution,
                900,
                1000,
                current_ui_elem == 2,
            ) };

            if (rg.button(
                .{
                    .x = controls_pos.x + 10,
                    .y = controls_pos.y + 140,
                    .width = controls_pos.width - 20,
                    .height = 30,
                },
                if (is_paused) "#131#Play" else "#132#Pause",
            ))
                is_paused = !is_paused;

            if (rg.button(
                .{
                    .x = controls_pos.x + 10,
                    .y = controls_pos.y + 180,
                    .width = controls_pos.width - 20,
                    .height = 30,
                },
                "#211#Reset",
            )) {
                for (INITIAL_POSITION, 0..) |body, i|
                    bodies[i] = body;
            }
        }

        rl.beginMode3D(camera);

        for (&bodies, 0..) |*body, i| {
            body.update_trail();
            rl.drawSphere(body.aPosition, RADIUS, body.color);

            for (0..TRAIL_LENGTH - 1) |j| {
                const index = (body.trail_index + j) % TRAIL_LENGTH;
                const next_index = (body.trail_index + j + 1) % TRAIL_LENGTH;
                rl.drawCylinderEx(
                    body.trail[index],
                    body.trail[next_index],
                    @as(f32, @floatFromInt(j + 1)) / @as(f32, @floatFromInt(TRAIL_LENGTH)),
                    @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(TRAIL_LENGTH)),
                    8,
                    rl.Color{
                        .r = body.color.r,
                        .g = body.color.g,
                        .b = body.color.b,
                        .a = @as(u8, @intFromFloat(100.0 * ((@as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(TRAIL_LENGTH)))))),
                    },
                );
            }

            if (i == focused_body_index) {
                rl.drawSphereWires(body.aPosition, RADIUS * 1.2, 5, 8, text_color);
            }
        }

        draw_grid_around(camera.target, .{});

        rl.endMode3D();

        if (text_visible) {
            rl.drawText("3-Body Problem Simulation", 10, 10, 20, text_color);

            var campos_buffer: [64]u8 = undefined;
            var looking_at_buffer: [64]u8 = undefined;

            rl.drawText(
                try std.fmt.bufPrintZ(
                    &campos_buffer,
                    "Camera: {}, {}, {}",
                    if (is_following and focused_body_index < BODY_COUNT) .{
                        offset.x / BASE_SCALE,
                        offset.y / BASE_SCALE,
                        offset.z / BASE_SCALE,
                    } else .{
                        camera.position.x / BASE_SCALE,
                        camera.position.y / BASE_SCALE,
                        camera.position.z / BASE_SCALE,
                    },
                ),
                10,
                40,
                20,
                text_color,
            );

            rl.drawText(
                try std.fmt.bufPrintZ(
                    &looking_at_buffer,
                    "Looking at: {}, {}, {}",
                    .{
                        camera.target.x / BASE_SCALE,
                        camera.target.y / BASE_SCALE,
                        camera.target.z / BASE_SCALE,
                    },
                ),
                10,
                70,
                20,
                text_color,
            );

            rl.drawFPS(10, SCREEN_HEIGHT - 30);

            // use circles to draw a graph from (SCREEN_WIDTH - 100, SCREEN_HEIGHT - 30) to (SCREEN_WIDTH - 10, SCREEN_HEIGHT - 10)

            // container:
            _ = rg.groupBox(
                rl.Rectangle{
                    .x = SCREEN_WIDTH - 180,
                    .y = SCREEN_HEIGHT - 110,
                    .width = 170,
                    .height = 100,
                },
                "Velocities",
            );

            _ = rg.progressBar(
                rl.Rectangle{
                    .x = SCREEN_WIDTH - 120,
                    .y = SCREEN_HEIGHT - 100,
                    .width = 80,
                    .height = 20,
                },
                "Body 1",
                ">5",
                &bodies[0].raw_vel,
                0.0,
                5.0,
            );

            rl.drawCircle(
                SCREEN_WIDTH - 115 + (@as(i32, @intFromFloat((bodies[0].raw_vel / 5.0) * 80.0))),
                SCREEN_HEIGHT - 90,
                5,
                bodies[0].color,
            );

            _ = rg.progressBar(
                rl.Rectangle{
                    .x = SCREEN_WIDTH - 120,
                    .y = SCREEN_HEIGHT - 70,
                    .width = 80,
                    .height = 20,
                },
                "Body 2",
                ">5",
                &bodies[1].raw_vel,
                0.0,
                5.0,
            );

            rl.drawCircle(
                SCREEN_WIDTH - 115 + (@as(i32, @intFromFloat((bodies[1].raw_vel / 5.0) * 80.0))),
                SCREEN_HEIGHT - 60,
                5,
                bodies[1].color,
            );

            _ = rg.progressBar(
                rl.Rectangle{
                    .x = SCREEN_WIDTH - 120,
                    .y = SCREEN_HEIGHT - 40,
                    .width = 80,
                    .height = 20,
                },
                "Body 3",
                ">5",
                &bodies[2].raw_vel,
                0.0,
                5.0,
            );

            rl.drawCircle(
                SCREEN_WIDTH - 115 + (@as(i32, @intFromFloat((bodies[2].raw_vel / 5.0) * 80.0))),
                SCREEN_HEIGHT - 30,
                5,
                bodies[2].color,
            );
        }

        rl.endDrawing();
    }

    rl.closeWindow();
}
