const std = @import("std");
const math = std.math;
const random = std.crypto.random;
const rl = @import("raylib");

const Settings = struct {
    win_h: i32,
    win_w: i32,
    ph: i32,
    pw: i32,
    p_speed: f32,
    border_w: i32,
};

const Player = struct {
    rect: rl.Rectangle,
    collided: bool,
    speed: f32,
};
const Ball = struct {
    rect: rl.Rectangle,
    direction: rl.Vector2,
    speed: f32,
    collided: bool,
    hidden: bool,
};
const State = struct {
    t: f64,
    dt: f32,
    last_goal: bool, // 0 P1, 1 P2
    round_start_time: f64,
    hit_count: usize,
    p1: Player,
    p2: Player,
    ball: Ball,
};

const Sounds = struct {
    hit: [3]rl.Sound,
    high_hit: rl.Sound,
    white: [2]rl.Sound,
    decay_white: rl.Sound,
};

pub fn main() !void {
    rl.setConfigFlags(.{ .window_undecorated = true });
    rl.initWindow(0, 0, "Pong");
    defer rl.closeWindow();
    rl.beginDrawing();
    rl.endDrawing();

    rl.setTargetFPS(60);
    const screen_rec: rl.Rectangle = .{ .height = @floatFromInt(rl.getScreenHeight()), .width = @floatFromInt(rl.getScreenWidth()), .x = 0, .y = 0 };

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    const settings = loadDefaultSettings();

    var state = resetState(settings);
    const game_tex = try rl.loadRenderTexture(settings.win_w, settings.win_h);
    defer rl.unloadRenderTexture(game_tex);
    // Invert height to reinvert when drawing texture (weird stuff)
    const game_tex_rec: rl.Rectangle = .{ .height = @floatFromInt(-game_tex.texture.height), .width = @floatFromInt(game_tex.texture.width), .x = 0, .y = 0 };

    const hit_1 = try rl.loadSound("assets/hit_1.wav");
    const hit_2 = try rl.loadSound("assets/hit_2.wav");
    const hit_3 = try rl.loadSound("assets/hit_3.wav");
    const high_hit_1 = try rl.loadSound("assets/high_hit_1.wav");
    const white_1 = try rl.loadSound("assets/white_1.wav");
    const white_2 = try rl.loadSound("assets/white_2.wav");
    const decay_white_1 = try rl.loadSound("assets/decay_white_1.wav");
    const sounds: Sounds = .{
        .hit = .{ hit_1, hit_2, hit_3 },
        .high_hit = high_hit_1,
        .white = .{ white_1, white_2 },
        .decay_white = decay_white_1,
    };

    const min_arena_y = @as(f32, @floatFromInt(settings.border_w * 2));
    const max_arena_y = @as(f32, @floatFromInt(settings.win_h - (settings.border_w * 2)));

    while (!rl.windowShouldClose()) {
        // Update
        state.t = rl.getTime();
        state.dt = rl.getFrameTime();

        if (rl.isKeyPressed(rl.KeyboardKey.escape)) {
            rl.closeWindow();
        }

        if (rl.isKeyDown(rl.KeyboardKey.down)) {
            state.p1.rect.y += state.dt * state.p1.speed * state.p1.rect.height;
        } else if (rl.isKeyDown(rl.KeyboardKey.up)) {
            state.p1.rect.y -= state.dt * state.p1.speed * state.p1.rect.height;
        }

        state.p1.rect.y = math.clamp(state.p1.rect.y, min_arena_y, max_arena_y - state.p1.rect.height);

        if (state.p1.rect.y == min_arena_y or state.p1.rect.y == max_arena_y) {
            if (!state.p1.collided) {
                rl.playSound(sounds.high_hit);
            }
            state.p1.collided = true;
        } else {
            state.p1.collided = false;
        }

        if (rl.isKeyDown(rl.KeyboardKey.s)) {
            state.p2.rect.y += state.dt * state.p2.speed * state.p2.rect.height;
        } else if (rl.isKeyDown(rl.KeyboardKey.w)) {
            state.p2.rect.y -= state.dt * state.p2.speed * state.p2.rect.height;
        }

        state.p2.rect.y = math.clamp(state.p2.rect.y, min_arena_y, max_arena_y - state.p2.rect.height);

        if (state.p2.rect.y == min_arena_y or state.p2.rect.y == max_arena_y) {
            if (!state.p2.collided) {
                rl.playSound(sounds.high_hit);
            }
            state.p2.collided = true;
        } else {
            state.p2.collided = false;
        }

        if (state.ball.hidden) {
            state.ball.hidden = false;
            state.ball.rect.x = (@as(f32, @floatFromInt(settings.win_w)) - state.ball.rect.width) / 2;
            state.ball.rect.y = (@as(f32, @floatFromInt(settings.win_h)) - state.ball.rect.width) / 2;
            state.round_start_time = state.t;
        } else if (state.ball.speed == 0 and (rl.getTime() - state.round_start_time) >= 3.0) {
            const x: f32 = 1 - (@as(f32, @floatFromInt(random.intRangeAtMost(i32, 0, 1))) * 2);
            const y: f32 = 1 - (@as(f32, @floatFromInt(random.intRangeAtMost(i32, 0, 1))) * 2);
            state.ball.direction = .{ .x = x, .y = y };
            state.ball.direction = state.ball.direction.normalize();
            state.ball.speed = state.ball.rect.width * 15;
        }

        const vel = state.ball.direction.scale(state.ball.speed);
        state.ball.rect.x += (vel.x * state.dt);
        state.ball.rect.y += (vel.y * state.dt);
        state.ball.rect.y = math.clamp(state.ball.rect.y, min_arena_y, max_arena_y - state.ball.rect.height);

        var p_collided = false;
        if (state.ball.speed != 0 and state.ball.direction.x != 0) {
            var p_rect: rl.Rectangle = undefined;

            if (state.ball.direction.x < 0) {
                p_rect = state.p1.rect;
            } else if (state.ball.direction.x > 0) {
                p_rect = state.p2.rect;
            }

            if (rl.Rectangle.checkCollision(p_rect, state.ball.rect)) {
                p_collided = true;
                const rel_intersect = ((state.ball.rect.y + (state.ball.rect.height / 2)) - p_rect.y) / p_rect.height;
                var new_dir: f32 = undefined;
                if (rel_intersect < 0.1) {
                    new_dir = -0.75;
                } else if (rel_intersect < 0.3) {
                    new_dir = -0.5;
                } else if (rel_intersect < 0.7) {
                    new_dir = if (state.ball.direction.y < 0) -0.25 else 0.25;
                } else if (rel_intersect < 0.9) {
                    new_dir = 0.5;
                } else {
                    new_dir = 0.75;
                }

                state.ball.direction.x *= -1;
                state.ball.direction.y = new_dir;
                state.ball.direction = state.ball.direction.normalize();
                state.ball.speed *= 1.1;

                state.p1.speed *= 1.05;
                state.p2.speed *= 1.05;
            }
        }

        const already_collided = state.ball.collided;
        if (p_collided) {
            state.ball.collided = true;
            state.hit_count += 1;
        } else if (state.ball.rect.y == min_arena_y or state.ball.rect.y == (max_arena_y - state.ball.rect.height)) {
            state.ball.collided = true;
            state.ball.direction.y *= -1;
        } else {
            state.ball.collided = false;
        }

        if (!already_collided and state.ball.collided) {
            rl.playSound(sounds.hit[random.intRangeAtMost(usize, 0, sounds.hit.len - 1)]);
        }

        // Render
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.beginTextureMode(game_tex);
        rl.clearBackground(.black);

        // Arena
        rl.drawRectangle(settings.border_w, settings.border_w, settings.win_w - (2 * settings.border_w), settings.border_w, .white);
        rl.drawRectangle(settings.border_w, settings.win_h - (2 * settings.border_w), settings.win_w - (2 * settings.border_w), settings.border_w, .white);
        var i: i32 = 0;
        const max_i = @divFloor(settings.win_h, (settings.border_w * 2)) - 2;
        while (i < max_i) {
            rl.drawRectangle(@divFloor(settings.win_w - settings.border_w, 2), @divFloor(settings.border_w, 2) + settings.border_w * 2 * (i + 1), settings.border_w, settings.border_w, .white);
            i += 1;
        }

        // P1
        rl.drawRectangleRec(state.p1.rect, .white);
        // P2
        rl.drawRectangleRec(state.p2.rect, .white);

        // Ball
        if (!state.ball.hidden) {
            rl.drawRectangleRec(state.ball.rect, .white);
        }

        rl.endTextureMode();

        rl.clearBackground(.black);
        rl.drawTexturePro(game_tex.texture, game_tex_rec, screen_rec, rl.Vector2.zero(), 0.0, .white);
    }
}

pub fn loadDefaultSettings() Settings {
    return .{
        .win_h = 100,
        .win_w = 200,
        .ph = 16,
        .pw = 4,
        .p_speed = 3, // Player height/s
        .border_w = 2,
    };
}

pub fn resetState(s: Settings) State {
    return .{
        .t = 0,
        .dt = 0,
        .p1 = .{
            .rect = .{
                .x = @as(f32, @floatFromInt(s.border_w)) * 3,
                .y = @floatFromInt(@divFloor((s.win_h - s.ph), 2)),
                .width = @as(f32, @floatFromInt(s.pw)),
                .height = @as(f32, @floatFromInt(s.ph)),
            },
            .collided = false,
            .speed = 3,
        },
        .p2 = .{
            .rect = .{
                .x = @as(f32, @floatFromInt(s.win_w - (s.border_w * 3) - s.pw)),
                .y = @floatFromInt(@divFloor((s.win_h - s.ph), 2)),
                .width = @as(f32, @floatFromInt(s.pw)),
                .height = @as(f32, @floatFromInt(s.ph)),
            },
            .collided = false,
            .speed = 3,
        },
        .last_goal = false,
        .round_start_time = 0,
        .hit_count = 0,
        .ball = .{
            .rect = .{
                .x = @floatFromInt(@divFloor(s.win_w - s.pw, 2)),
                .y = @floatFromInt(@divFloor(s.win_h - s.pw, 2)),
                .width = @as(f32, @floatFromInt(s.pw)),
                .height = @as(f32, @floatFromInt(s.pw)),
            },
            .direction = rl.Vector2.zero(),
            .speed = 0,
            .collided = false,
            .hidden = true,
        },
    };
}
