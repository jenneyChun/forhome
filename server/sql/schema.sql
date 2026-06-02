CREATE TABLE IF NOT EXISTS app_version (
    singleton boolean PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    version bigint NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS settings (
    singleton boolean PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    vacation_threshold integer NOT NULL DEFAULT 25,
    week_starts_on integer NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS members (
    id text PRIMARY KEY,
    name text NOT NULL,
    emoji text NOT NULL,
    restricted boolean NOT NULL DEFAULT FALSE,
    color text NOT NULL DEFAULT '#2563eb',
    xp integer NOT NULL DEFAULT 0,
    total_fatigue integer NOT NULL DEFAULT 0,
    completed_tasks integer NOT NULL DEFAULT 0,
    stickers integer NOT NULL DEFAULT 0,
    on_vacation boolean NOT NULL DEFAULT FALSE,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS accounts (
    id text PRIMARY KEY,
    password text NOT NULL,
    member_id text REFERENCES members(id) ON DELETE SET NULL,
    is_admin boolean NOT NULL DEFAULT FALSE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chores (
    id text PRIMARY KEY,
    name text NOT NULL,
    emoji text NOT NULL,
    fatigue integer NOT NULL,
    xp integer NOT NULL,
    category text NOT NULL,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS history (
    id text PRIMARY KEY,
    member_id text REFERENCES members(id) ON DELETE CASCADE,
    chore_id text REFERENCES chores(id) ON DELETE SET NULL,
    chore_name text NOT NULL,
    chore_emoji text NOT NULL,
    category text NOT NULL,
    fatigue_added integer NOT NULL,
    xp_earned integer NOT NULL,
    completed_at_ms bigint NOT NULL,
    completed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS messages (
    id text PRIMARY KEY,
    from_member_id text,
    to_member_id text REFERENCES members(id) ON DELETE SET NULL,
    text text NOT NULL,
    sent_at_ms bigint NOT NULL,
    sent_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS badge_history (
    id text PRIMARY KEY,
    member_id text REFERENCES members(id) ON DELETE CASCADE,
    badge_id text NOT NULL,
    name text NOT NULL,
    emoji text NOT NULL,
    earned_at_ms bigint,
    earned_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS member_badges (
    member_id text REFERENCES members(id) ON DELETE CASCADE,
    badge_id text NOT NULL,
    earned_at_ms bigint,
    earned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (member_id, badge_id)
);

CREATE INDEX IF NOT EXISTS idx_history_member_time ON history(member_id, completed_at_ms);
CREATE INDEX IF NOT EXISTS idx_messages_time ON messages(sent_at_ms);
CREATE INDEX IF NOT EXISTS idx_badge_history_member_time ON badge_history(member_id, earned_at_ms);

INSERT INTO app_version (singleton, version)
VALUES (TRUE, 0)
ON CONFLICT (singleton) DO NOTHING;

INSERT INTO settings (singleton, vacation_threshold, week_starts_on)
VALUES (TRUE, 25, 1)
ON CONFLICT (singleton) DO NOTHING;

INSERT INTO members (id, name, emoji, restricted, color, sort_order) VALUES
    ('mom', 'Mom', 'M', TRUE, '#ef4444', 1),
    ('dad', 'Dad', 'D', TRUE, '#2563eb', 2),
    ('son', 'Son', 'S', FALSE, '#f59e0b', 3),
    ('jerry', 'Jerry', 'J', FALSE, '#0f9f8f', 4),
    ('tori', 'Tori', 'T', FALSE, '#7c3aed', 5)
ON CONFLICT (id) DO NOTHING;

INSERT INTO accounts (id, password, member_id, is_admin) VALUES
    ('mom', 'mom1234', 'mom', FALSE),
    ('dad', 'dad1234', 'dad', FALSE),
    ('son', 'son1234', 'son', FALSE),
    ('admin', 'admin1234', NULL, TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO chores (id, name, emoji, fatigue, xp, category, sort_order) VALUES
    ('c1', 'Dishes', 'DI', 2, 20, 'house', 1),
    ('c2', 'Vacuum', 'VA', 3, 30, 'house', 2),
    ('c3', 'Laundry wash', 'LW', 2, 20, 'house', 3),
    ('c4', 'Fold laundry', 'FL', 2, 20, 'house', 4),
    ('c5', 'Bathroom clean', 'BC', 4, 40, 'house', 5),
    ('c6', 'Cook', 'CO', 3, 30, 'house', 6),
    ('c7', 'Recycling', 'RC', 2, 20, 'house', 7),
    ('c8', 'Trash', 'TR', 1, 10, 'house', 8),
    ('p1', 'Medicine', 'ME', 2, 20, 'care', 9),
    ('p2', 'Read book', 'RB', 1, 10, 'care', 10),
    ('pet1', 'Pet food', 'PF', 1, 10, 'pet', 11),
    ('pet2', 'Pet cleanup', 'PC', 2, 20, 'pet', 12),
    ('ch1', 'Clean room', 'CR', 1, 10, 'child', 13),
    ('ch2', 'Desk cleanup', 'DC', 1, 10, 'child', 14)
ON CONFLICT (id) DO NOTHING;
