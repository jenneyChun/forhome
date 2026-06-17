CREATE TABLE IF NOT EXISTS app_version (
    singleton boolean PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    version bigint NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id text PRIMARY KEY,
    account_id text UNIQUE NOT NULL,
    email text UNIQUE,
    password_hash text NOT NULL,
    display_name text NOT NULL,
    is_admin boolean NOT NULL DEFAULT FALSE,
    active boolean NOT NULL DEFAULT TRUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    last_login_at timestamptz
);

CREATE TABLE IF NOT EXISTS households (
    id text PRIMARY KEY,
    name text NOT NULL,
    owner_user_id text REFERENCES users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS settings (
    household_id text PRIMARY KEY REFERENCES households(id) ON DELETE CASCADE,
    vacation_threshold integer NOT NULL DEFAULT 25,
    week_starts_on integer NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS household_members (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    user_id text REFERENCES users(id) ON DELETE SET NULL,
    name text NOT NULL,
    emoji text NOT NULL,
    restricted boolean NOT NULL DEFAULT FALSE,
    role text NOT NULL DEFAULT 'hero',
    color text NOT NULL DEFAULT '#2563eb',
    xp integer NOT NULL DEFAULT 0,
    total_fatigue integer NOT NULL DEFAULT 0,
    completed_tasks integer NOT NULL DEFAULT 0,
    stickers integer NOT NULL DEFAULT 0,
    on_vacation boolean NOT NULL DEFAULT FALSE,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS sessions (
    token_hash text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    household_id text REFERENCES households(id) ON DELETE CASCADE,
    member_id text,
    is_admin boolean NOT NULL DEFAULT FALSE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS invitations (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    token_hash text NOT NULL,
    code_hash text NOT NULL,
    role_hint text NOT NULL DEFAULT 'hero',
    role_locked boolean NOT NULL DEFAULT FALSE,
    display_name_hint text,
    max_uses integer NOT NULL DEFAULT 1,
    used_count integer NOT NULL DEFAULT 0,
    expires_at timestamptz NOT NULL,
    created_by_user_id text REFERENCES users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    last_used_at timestamptz,
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS chores (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    name text NOT NULL,
    emoji text NOT NULL,
    fatigue integer NOT NULL,
    xp integer NOT NULL,
    category text NOT NULL,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS task_entries (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    member_id text NOT NULL,
    chore_id text,
    chore_name text NOT NULL,
    chore_emoji text NOT NULL,
    category text NOT NULL,
    fatigue_added integer NOT NULL DEFAULT 0,
    xp_earned integer NOT NULL DEFAULT 0,
    verification_status text NOT NULL DEFAULT 'approved',
    proof_image text,
    proof_caption text,
    proof_analysis text,
    review_note text,
    completed_at_ms bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS task_approvals (
    household_id text NOT NULL,
    entry_id text NOT NULL,
    reviewer_id text NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    reviewed_at_ms bigint,
    review_note text,
    PRIMARY KEY (household_id, entry_id, reviewer_id),
    FOREIGN KEY (household_id, entry_id) REFERENCES task_entries(household_id, id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS task_point_recipients (
    household_id text NOT NULL,
    entry_id text NOT NULL,
    member_id text NOT NULL,
    PRIMARY KEY (household_id, entry_id, member_id),
    FOREIGN KEY (household_id, entry_id) REFERENCES task_entries(household_id, id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS messages (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    from_member_id text,
    to_member_id text,
    text text NOT NULL,
    sent_at_ms bigint NOT NULL,
    sent_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS badge_history (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    member_id text NOT NULL,
    badge_id text NOT NULL,
    name text NOT NULL,
    emoji text NOT NULL,
    earned_at_ms bigint,
    earned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS member_badges (
    household_id text NOT NULL,
    member_id text NOT NULL,
    badge_id text NOT NULL,
    earned_at_ms bigint,
    earned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, member_id, badge_id),
    FOREIGN KEY (household_id, member_id) REFERENCES household_members(household_id, id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS care_items (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    name text NOT NULL,
    emoji text NOT NULL,
    points integer NOT NULL,
    xp integer NOT NULL,
    locked boolean NOT NULL DEFAULT FALSE,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS care_assignments (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    date_key text NOT NULL,
    morning_id text,
    evening_id text,
    updated_at_ms bigint,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, date_key)
);

CREATE TABLE IF NOT EXISTS care_sessions (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    date_key text NOT NULL,
    member_id text NOT NULL,
    care_item_id text,
    child_member_id text,
    points integer NOT NULL DEFAULT 0,
    xp_earned integer NOT NULL DEFAULT 0,
    start_time text,
    end_time text,
    minutes integer NOT NULL DEFAULT 0,
    note text,
    created_at_ms bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS care_session_point_recipients (
    household_id text NOT NULL,
    session_id text NOT NULL,
    member_id text NOT NULL,
    PRIMARY KEY (household_id, session_id, member_id),
    FOREIGN KEY (household_id, session_id) REFERENCES care_sessions(household_id, id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tomorrow_plans (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    from_member_id text,
    to_member_id text,
    chore_id text,
    title text NOT NULL,
    target_date text NOT NULL,
    note text,
    status text NOT NULL DEFAULT 'open',
    request_status text NOT NULL DEFAULT 'pending',
    decline_reason text,
    responded_at_ms bigint,
    created_at_ms bigint NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS change_requests (
    household_id text NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    id text NOT NULL,
    type text NOT NULL,
    before_json jsonb,
    after_json jsonb,
    requested_by text,
    requested_at_ms bigint NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    reviewed_at_ms bigint,
    review_note text,
    applied_at_ms bigint,
    PRIMARY KEY (household_id, id)
);

CREATE TABLE IF NOT EXISTS change_request_approvals (
    household_id text NOT NULL,
    request_id text NOT NULL,
    reviewer_id text NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    reviewed_at_ms bigint,
    review_note text,
    PRIMARY KEY (household_id, request_id, reviewer_id),
    FOREIGN KEY (household_id, request_id) REFERENCES change_requests(household_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id, expires_at);
CREATE INDEX IF NOT EXISTS idx_invitations_id ON invitations(id);
CREATE INDEX IF NOT EXISTS idx_task_entries_member_time ON task_entries(household_id, member_id, completed_at_ms);
CREATE INDEX IF NOT EXISTS idx_messages_time ON messages(household_id, sent_at_ms);
CREATE INDEX IF NOT EXISTS idx_tomorrow_plans_date ON tomorrow_plans(household_id, target_date);
CREATE INDEX IF NOT EXISTS idx_care_sessions_date ON care_sessions(household_id, date_key);

INSERT INTO app_version (singleton, version)
VALUES (TRUE, 0)
ON CONFLICT (singleton) DO NOTHING;

INSERT INTO households (id, name)
VALUES ('home', '우리집')
ON CONFLICT (id) DO NOTHING;

INSERT INTO settings (household_id, vacation_threshold, week_starts_on)
VALUES ('home', 25, 1)
ON CONFLICT (household_id) DO NOTHING;

INSERT INTO household_members (household_id, id, name, emoji, restricted, role, color, sort_order) VALUES
    ('home', 'mom', '엄마', '엄', TRUE, 'hero', '#ef4444', 1),
    ('home', 'dad', '아빠', '아', TRUE, 'hero', '#2563eb', 2),
    ('home', 'son', '아들', '들', FALSE, 'care_member', '#f59e0b', 3)
ON CONFLICT (household_id, id) DO NOTHING;

INSERT INTO chores (household_id, id, name, emoji, fatigue, xp, category, sort_order) VALUES
    ('home', 'c1', '설거지', '식', 2, 20, 'house', 1),
    ('home', 'c2', '청소기 돌리기', '청', 3, 30, 'house', 2),
    ('home', 'c3', '빨래', '빨', 2, 20, 'house', 3),
    ('home', 'p1', '약 챙기기', '약', 2, 20, 'care', 4),
    ('home', 'pet1', '밥 주기', '밥', 1, 10, 'pet', 5),
    ('home', 'ch1', '방 정리', '방', 1, 10, 'child', 6),
    ('home', 'hw1', '숙제 확인', '숙', 2, 20, 'child', 7)
ON CONFLICT (household_id, id) DO NOTHING;

INSERT INTO care_items (household_id, id, name, emoji, points, xp, locked, sort_order) VALUES
    ('home', 'edu', 'Education', 'ED', 3, 30, TRUE, 1),
    ('home', 'meal', 'Meal care', 'ME', 2, 20, FALSE, 2),
    ('home', 'play', 'Play care', 'PL', 2, 20, FALSE, 3)
ON CONFLICT (household_id, id) DO NOTHING;
