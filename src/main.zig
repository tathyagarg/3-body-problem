const std = @import("std");
const rl = @import("raylib");

const BASE_SCALE = 1.0;
const BODY_COUNT = 3;

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 640;

const TARGET_FPS = 60;
const GRAVITATIONAL_CONSTANT = 1.0;

const CAMERA_SPEED = 3;

const TRAIL_LENGTH = 100;
const RESTITUTION_COEFFICIENT = 0.9;

const Body = struct {
    aPosition: rl.Vector3,
    aVelocity: rl.Vector3,
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

        body.trail = [_]rl.Vector3{body.aPosition} ** TRAIL_LENGTH;
        return body;
    }

    pub fn update_trail(self: *Body) void {
        self.trail[self.trail_index] = self.aPosition;
        self.trail_index = (self.trail_index + 1) % TRAIL_LENGTH;
    }
};

fn simulate(bodies: *[BODY_COUNT]Body, options: struct {
    vel_damping: f32 = 0.999,
}) void {
    for (bodies, 0..) |*body, i| {
        var force = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        for (bodies, 0..) |*other_body, j| {
            if (i != j) {
                if (rl.checkCollisionSpheres(body.aPosition, 2.5, other_body.aPosition, 2.5)) {
                    const n = other_body.aPosition.subtract(body.aPosition).normalize();
                    const relative_velocity = other_body.aVelocity.subtract(body.aVelocity);
                    const velocity_along_normal = relative_velocity.dotProduct(n);

                    if (velocity_along_normal < 0) {
                        const impulse = ((1.0 + RESTITUTION_COEFFICIENT) * velocity_along_normal) / (body.mass + other_body.mass);
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
        // std.debug.print("Body {} Acceleration: ({}, {}, {})\n", .{ i, acceleration.x, acceleration.y, acceleration.z });
        body.aVelocity = body.aVelocity.add(acceleration);
        body.aVelocity = body.aVelocity.scale(options.vel_damping);
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

    var camera = rl.Camera3D{
        .position = (rl.Vector3{ .x = 0.0, .y = 0.0, .z = 300.0 }).scale(BASE_SCALE),
        .target = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = rl.Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

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
        // Body.init(
        //     rl.Vector3{ .x = -10.0, .y = 0.0, .z = 0.0 },
        //     rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        //     5.0,
        //     .red,
        //     .{},
        // ),
        // Body.init(
        //     rl.Vector3{ .x = 10.0, .y = 0.0, .z = 0.0 },
        //     rl.Vector3{ .x = 0.0, .y = 0.0, .z = -0.0 },
        //     5.0,
        //     .green,
        //     .{},
        // ),
    };

    // hard clone INITIAL_POSITION into bodies
    var bodies: [BODY_COUNT]Body = undefined;
    for (INITIAL_POSITION, 0..) |body, i| {
        bodies[i] = body;
    }

    rl.setTargetFPS(TARGET_FPS);

    var focused_body_index: usize = 3;
    var is_paused = true;
    var damping: f32 = 0.999;

    var is_following = false;

    var offset = rl.Vector3{ .x = 0.0, .y = 20.0, .z = 20.0 };

    var text_visible = true;

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
        if (rl.isKeyPressed(.up)) simulations_per_frame += 1;
        if (rl.isKeyPressed(.down)) {
            if (simulations_per_frame > 0) {
                simulations_per_frame -= 1;
            }
        }

        if (rl.isKeyPressed(.r)) {
            for (INITIAL_POSITION, 0..) |body, i| {
                bodies[i] = body;
            }
        }

        if (rl.isKeyPressed(.f)) {
            is_following = !is_following;
            if (is_following and focused_body_index < BODY_COUNT) {
                camera.target = bodies[focused_body_index].aPosition;
                camera.position = bodies[focused_body_index].aPosition.add(offset);
            }
        }

        if (rl.isKeyPressed(.equal)) {
            damping += 0.001;
            if (damping > 1.0) damping = 1.0;
        }
        if (rl.isKeyPressed(.minus)) {
            damping -= 0.001;
            if (damping < 0.0) damping = 0.0;
        }

        if (rl.isKeyPressed(.u)) text_visible = !text_visible;

        if (!is_paused) {
            if (simulations_per_frame > 0) {
                for (0..simulations_per_frame) |_| {
                    simulate(&bodies, .{ .vel_damping = damping });
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
        rl.clearBackground(.white);
        rl.beginMode3D(camera);

        for (&bodies, 0..) |*body, i| {
            body.update_trail();
            rl.drawSphere(body.aPosition, 2.5, body.color);

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
                        // alpha goes from 100 at the head (at the object) to 0 at the tail
                        .a = @as(u8, @intFromFloat(100.0 * ((@as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(TRAIL_LENGTH)))))),
                    },
                );
            }

            if (i == focused_body_index) {
                rl.drawSphereWires(body.aPosition, 3.0, 5, 8, .black);
            }
        }

        draw_grid_around(camera.target, .{});

        rl.endMode3D();
        if (text_visible) {
            rl.drawText("3-Body Problem Simulation", 10, 10, 20, .dark_gray);

            var campos_buffer: [64]u8 = undefined;
            var looking_at_buffer: [64]u8 = undefined;
            var sim_per_frame_buffer: [32]u8 = undefined;
            var damping_buffer: [32]u8 = undefined;

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
                .dark_gray,
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
                .dark_gray,
            );

            rl.drawText(
                try std.fmt.bufPrintZ(
                    &sim_per_frame_buffer,
                    "Sims. per frame: {}",
                    .{simulations_per_frame},
                ),
                10,
                100,
                20,
                .dark_gray,
            );

            rl.drawText(
                try std.fmt.bufPrintZ(
                    &damping_buffer,
                    "Damping: {}",
                    .{damping},
                ),
                10,
                130,
                20,
                .dark_gray,
            );

            rl.drawFPS(10, SCREEN_HEIGHT - 30);
        }

        rl.endDrawing();
    }

    rl.closeWindow();
}
