(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory(root);
  } else {
    root.ForHomeAuthInvitation = factory(root);
  }
})(typeof globalThis !== 'undefined' ? globalThis : window, function (root) {
  'use strict';

  var ROLE_OWNER = 'owner';
  var ROLE_HERO = 'hero';
  var ROLE_CARE_MEMBER = 'care_member';
  var DEFAULT_TTL_HOURS = 24;
  var DEFAULT_STORAGE_KEY = 'forhome-auth-invitation-v1';
  var ROLE_LABELS = {};
  ROLE_LABELS[ROLE_OWNER] = '대표 히어로';
  ROLE_LABELS[ROLE_HERO] = '홈 히어로';
  ROLE_LABELS[ROLE_CARE_MEMBER] = '케어 멤버';

  var DEFAULT_PERMISSIONS = {};
  DEFAULT_PERMISSIONS[ROLE_OWNER] = {
    canInvite: true,
    canManageMembers: true,
    canApproveTasks: true,
    canRecordCare: true,
    canDeleteHousehold: true
  };
  DEFAULT_PERMISSIONS[ROLE_HERO] = {
    canInvite: false,
    canManageMembers: false,
    canApproveTasks: true,
    canRecordCare: true,
    canDeleteHousehold: false
  };
  DEFAULT_PERMISSIONS[ROLE_CARE_MEMBER] = {
    canInvite: false,
    canManageMembers: false,
    canApproveTasks: false,
    canRecordCare: false,
    canDeleteHousehold: false
  };

  function clone(value) {
    return value == null ? value : JSON.parse(JSON.stringify(value));
  }

  function nowIso(now) {
    return new Date(now || Date.now()).toISOString();
  }

  function addHoursIso(hours, now) {
    var date = new Date(now || Date.now());
    date.setHours(date.getHours() + Number(hours || DEFAULT_TTL_HOURS));
    return date.toISOString();
  }

  function requireText(value, fieldName) {
    var text = String(value || '').trim();
    if (!text) throw new Error(fieldName + ' is required.');
    return text;
  }

  function normalizeEmail(email) {
    return String(email || '').trim().toLowerCase();
  }

  function normalizeInviteCode(code) {
    return String(code || '').replace(/[^0-9a-z]/gi, '').toUpperCase();
  }

  function normalizeRole(role, fallback) {
    var value = String(role || fallback || ROLE_CARE_MEMBER).trim().toLowerCase();
    if (value === 'admin' || value === 'owner') return ROLE_OWNER;
    if (value === 'adult' || value === 'parent' || value === 'guardian' || value === 'hero') return ROLE_HERO;
    if (value === 'child' || value === 'member' || value === 'care_member') return ROLE_CARE_MEMBER;
    return fallback || ROLE_CARE_MEMBER;
  }

  function roleLabel(role) {
    return ROLE_LABELS[normalizeRole(role)] || ROLE_LABELS[ROLE_CARE_MEMBER];
  }

  function permissionsForRole(role, overrides) {
    var base = clone(DEFAULT_PERMISSIONS[normalizeRole(role)] || DEFAULT_PERMISSIONS[ROLE_CARE_MEMBER]);
    return Object.assign(base, overrides || {});
  }

  function canInvite(member, household) {
    if (!member || member.status === 'removed') return false;
    if (member.role === ROLE_OWNER) return true;
    if (member.permissions && member.permissions.canInvite) return true;
    return member.role === ROLE_HERO && !!(household && household.invitePolicy && household.invitePolicy.allowHeroInvite);
  }

  function canManageMembers(member) {
    if (!member || member.status === 'removed') return false;
    return member.role === ROLE_OWNER || !!(member.permissions && member.permissions.canManageMembers);
  }

  function randomBytes(length) {
    var bytes = new Uint8Array(length);
    if (root.crypto && root.crypto.getRandomValues) {
      root.crypto.getRandomValues(bytes);
      return bytes;
    }
    for (var i = 0; i < length; i += 1) bytes[i] = Math.floor(Math.random() * 256);
    return bytes;
  }

  function randomBase62(length) {
    var alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    var bytes = randomBytes(length);
    var out = '';
    for (var i = 0; i < length; i += 1) out += alphabet[bytes[i] % alphabet.length];
    return out;
  }

  function createId(prefix) {
    return String(prefix || 'id') + '_' + Date.now().toString(36) + '_' + randomBase62(10);
  }

  function createProfileMark(name, fallback) {
    var text = String(name || fallback || '홈').trim();
    return text ? text.slice(0, 2) : '홈';
  }

  function generateInviteNumber(groups, groupSize) {
    var groupCount = Number(groups || 2);
    var size = Number(groupSize || 3);
    var parts = [];
    for (var g = 0; g < groupCount; g += 1) {
      var digits = '';
      var bytes = randomBytes(size);
      for (var i = 0; i < size; i += 1) digits += String(bytes[i] % 10);
      parts.push(digits);
    }
    return parts.join('-');
  }

  function insecureHashHex(text) {
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    var input = String(text || '');
    for (var i = 0; i < input.length; i += 1) {
      h1 ^= input.charCodeAt(i);
      h1 = Math.imul(h1, 0x01000193);
      h2 = Math.imul(h2 ^ input.charCodeAt(i), 0x85ebca6b);
    }
    return ('00000000' + (h1 >>> 0).toString(16)).slice(-8)
      + ('00000000' + (h2 >>> 0).toString(16)).slice(-8);
  }

  async function sha256Hex(text) {
    var input = String(text || '');
    if (root.crypto && root.crypto.subtle && typeof TextEncoder !== 'undefined') {
      var data = new TextEncoder().encode(input);
      var hash = await root.crypto.subtle.digest('SHA-256', data);
      return Array.from(new Uint8Array(hash)).map(function (b) {
        return b.toString(16).padStart(2, '0');
      }).join('');
    }
    return 'dev-' + insecureHashHex(input);
  }

  async function hashInviteSecret(householdId, inviteId, secret) {
    return sha256Hex([
      'forhome-invite-v1',
      requireText(householdId, 'householdId'),
      requireText(inviteId, 'inviteId'),
      requireText(secret, 'secret')
    ].join(':'));
  }

  function createHouseholdRegistration(input) {
    var createdAt = nowIso(input && input.now);
    var uid = requireText(input && input.uid, 'uid');
    var displayName = requireText(input && input.displayName, 'displayName');
    var householdId = (input && input.householdId) || createId('home');
    var householdName = requireText(input && input.householdName, 'householdName');
    var member = {
      uid: uid,
      householdId: householdId,
      displayName: displayName,
      role: ROLE_OWNER,
      roleLabel: ROLE_LABELS[ROLE_OWNER],
      relationLabel: (input && input.relationLabel) || '',
      profileMark: (input && input.profileMark) || createProfileMark(displayName),
      color: (input && input.color) || '#d97706',
      permissions: permissionsForRole(ROLE_OWNER),
      status: 'active',
      joinedAt: createdAt,
      invitedBy: null
    };
    return {
      user: {
        uid: uid,
        email: normalizeEmail(input && input.email),
        displayName: displayName,
        createdAt: createdAt,
        lastLoginAt: createdAt
      },
      household: {
        householdId: householdId,
        name: householdName,
        ownerUid: uid,
        createdAt: createdAt,
        updatedAt: createdAt,
        invitePolicy: Object.assign({
          defaultExpiresHours: DEFAULT_TTL_HOURS,
          allowHeroInvite: false
        }, input && input.invitePolicy || {})
      },
      member: member
    };
  }

  function createInviteUrl(options) {
    var baseUrl = requireText(options && options.baseUrl, 'baseUrl').replace(/\/+$/, '');
    var inviteId = encodeURIComponent(requireText(options && options.inviteId, 'inviteId'));
    var token = requireText(options && options.token, 'token');
    var url = new URL(baseUrl + '/invite/' + inviteId);
    url.searchParams.set('token', token);
    if (options && options.surface) url.searchParams.set('surface', options.surface);
    return url.toString();
  }

  function createDefaultMobileBaseUrl(baseUrl) {
    try {
      var url = new URL(baseUrl);
      var host = url.hostname.toLowerCase();
      var localHosts = ['localhost', '127.0.0.1', '::1'];
      var isLocalHost = localHosts.indexOf(host) >= 0
        || host.endsWith('.local')
        || /^192\.168\.\d{1,3}\.\d{1,3}$/.test(host)
        || /^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host)
        || /^172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}$/.test(host);
      if (isLocalHost) {
        if (host === 'localhost' || host === '127.0.0.1' || host === '::1') {
          url.hostname = 'm.localhost';
        } else if (!host.startsWith('m.')) {
          url.hostname = 'm.' + host;
        }
        return url.origin;
      }
      if (!host.startsWith('m.')) {
        url.hostname = host.startsWith('www.') ? 'm.' + host.slice(4) : 'm.' + host;
      }
      return url.origin;
    } catch {
      return baseUrl;
    }
  }

  async function createInviteDraft(input) {
    var householdId = requireText(input && input.householdId, 'householdId');
    var createdBy = requireText(input && input.createdBy, 'createdBy');
    var inviteId = (input && input.inviteId) || createId('inv');
    var rawToken = (input && input.token) || randomBase62(36);
    var rawCode = normalizeInviteCode((input && input.shortCode) || generateInviteNumber());
    var roleHint = normalizeRole(input && input.roleHint, ROLE_HERO);
    if (roleHint === ROLE_OWNER) roleHint = ROLE_HERO;
    var createdAt = nowIso(input && input.now);
    var ttlHours = input && input.ttlHours != null ? Number(input.ttlHours) : DEFAULT_TTL_HOURS;
    var invite = {
      inviteId: inviteId,
      householdId: householdId,
      tokenHash: await hashInviteSecret(householdId, inviteId, rawToken),
      codeHash: await hashInviteSecret(householdId, inviteId, rawCode),
      roleHint: roleHint,
      roleLabel: roleLabel(roleHint),
      roleLocked: !!(input && input.roleLocked),
      displayNameHint: String(input && input.displayNameHint || '').trim(),
      maxUses: Math.max(1, Number(input && input.maxUses || 1)),
      usedCount: 0,
      expiresAt: (input && input.expiresAt) || addHoursIso(ttlHours, input && input.now),
      createdBy: createdBy,
      createdAt: createdAt,
      revokedAt: null,
      acceptedBy: []
    };
    return {
      invite: invite,
      rawToken: rawToken,
      rawCode: rawCode
    };
  }

  function inviteStatus(invite, now) {
    if (!invite) return { status: 'missing', usable: false, reason: '초대장을 찾을 수 없습니다.' };
    if (invite.revokedAt) return { status: 'revoked', usable: false, reason: '취소된 초대장입니다.' };
    if (invite.expiresAt && new Date(invite.expiresAt).getTime() <= new Date(now || Date.now()).getTime()) {
      return { status: 'expired', usable: false, reason: '초대장이 만료되었습니다.' };
    }
    if (Number(invite.usedCount || 0) >= Number(invite.maxUses || 1)) {
      return { status: 'exhausted', usable: false, reason: '이미 사용된 초대장입니다.' };
    }
    return { status: 'active', usable: true, reason: '' };
  }

  async function verifyInviteToken(invite, token) {
    if (!invite || !token) return false;
    var expected = await hashInviteSecret(invite.householdId, invite.inviteId, token);
    return expected === invite.tokenHash;
  }

  async function verifyInviteNumber(invite, code) {
    if (!invite || !code) return false;
    var expected = await hashInviteSecret(invite.householdId, invite.inviteId, normalizeInviteCode(code));
    return expected === invite.codeHash;
  }

  async function acceptInviteDraft(input) {
    var invite = clone(input && input.invite);
    var status = inviteStatus(invite, input && input.now);
    if (!status.usable) throw new Error(status.reason);
    if (!(input && input.token) && !(input && input.shortCode)) {
      throw new Error('초대 URL 토큰이나 초대 번호가 필요합니다.');
    }
    if (input && input.token && !(await verifyInviteToken(invite, input.token))) {
      throw new Error('초대 URL 토큰이 올바르지 않습니다.');
    }
    if (input && input.shortCode && !(await verifyInviteNumber(invite, input.shortCode))) {
      throw new Error('초대 번호가 올바르지 않습니다.');
    }
    var user = input && input.user || {};
    var uid = requireText(user.uid, 'uid');
    var selectedRole = normalizeRole(input && input.selectedRole, invite.roleHint);
    var role = invite.roleLocked ? invite.roleHint : selectedRole;
    if (role === ROLE_OWNER) role = ROLE_HERO;
    var displayName = requireText((input && input.displayName) || user.displayName || invite.displayNameHint, 'displayName');
    var joinedAt = nowIso(input && input.now);
    var member = {
      uid: uid,
      householdId: invite.householdId,
      displayName: displayName,
      role: role,
      roleLabel: roleLabel(role),
      relationLabel: String(input && input.relationLabel || '').trim(),
      profileMark: String(input && input.profileMark || createProfileMark(displayName)).trim(),
      color: String(input && input.color || '#2563eb').trim(),
      permissions: permissionsForRole(role, input && input.permissions),
      status: 'active',
      joinedAt: joinedAt,
      invitedBy: invite.createdBy
    };
    invite.usedCount = Number(invite.usedCount || 0) + 1;
    invite.lastUsedAt = joinedAt;
    invite.acceptedBy = Array.isArray(invite.acceptedBy) ? invite.acceptedBy.concat(uid) : [uid];
    return { member: member, invite: invite };
  }

  function createInviteShareBundle(options) {
    var invite = options && options.invite || {};
    var rawToken = requireText(options && options.rawToken, 'rawToken');
    var rawCode = requireText(options && options.rawCode, 'rawCode');
    var webUrl = createInviteUrl({
      baseUrl: options.baseUrl,
      inviteId: invite.inviteId,
      token: rawToken,
      surface: 'web'
    });
    var mobileUrl = createInviteUrl({
      baseUrl: options.mobileBaseUrl || options.baseUrl,
      inviteId: invite.inviteId,
      token: rawToken,
      surface: 'mobile'
    });
    var label = roleLabel(invite.roleHint);
    return {
      webUrl: webUrl,
      mobileUrl: mobileUrl,
      qrPayload: mobileUrl,
      shortCode: rawCode,
      message: [
        'ForHome 초대장이 도착했어요.',
        '역할: ' + label,
        '초대 URL: ' + mobileUrl,
        '초대 번호: ' + rawCode
      ].join('\n')
    };
  }

  function renderQrCode(container, payload, options) {
    var target = typeof container === 'string' ? root.document && root.document.querySelector(container) : container;
    if (!target) throw new Error('QR container is required.');
    var text = requireText(payload, 'payload');
    target.innerHTML = '';
    if (root.QRCode) {
      var qrOptions = Object.assign({ text: text, width: 180, height: 180 }, options || {});
      return { renderer: 'QRCode', instance: new root.QRCode(target, qrOptions) };
    }
    var box = root.document.createElement('div');
    box.className = 'forhome-qr-fallback';
    box.innerHTML = '<strong>QR 렌더러가 필요합니다</strong><p></p><code></code>';
    box.querySelector('p').textContent = 'qrcodejs 같은 클라이언트 QR 렌더러를 먼저 로드하면 이 영역에 QR 코드가 표시됩니다.';
    box.querySelector('code').textContent = text;
    target.appendChild(box);
    return { renderer: 'fallback', payload: text };
  }

  function emptyDb() {
    return { users: {}, households: {}, members: {}, invites: {} };
  }

  function memberKey(householdId, uid) {
    return householdId + ':' + uid;
  }

  function inviteKey(householdId, inviteId) {
    return householdId + ':' + inviteId;
  }

  function createMemoryInvitationRepository(initialState) {
    var db = Object.assign(emptyDb(), clone(initialState || {}));
    return {
      async read() { return clone(db); },
      async write(next) { db = Object.assign(emptyDb(), clone(next || {})); return clone(db); },
      async saveUser(user) { db.users[user.uid] = clone(user); return clone(user); },
      async getUser(uid) { return clone(db.users[uid]); },
      async saveHousehold(household) { db.households[household.householdId] = clone(household); return clone(household); },
      async getHousehold(householdId) { return clone(db.households[householdId]); },
      async saveMember(member) { db.members[memberKey(member.householdId, member.uid)] = clone(member); return clone(member); },
      async getMember(householdId, uid) { return clone(db.members[memberKey(householdId, uid)]); },
      async saveInvite(invite) { db.invites[inviteKey(invite.householdId, invite.inviteId)] = clone(invite); return clone(invite); },
      async getInvite(householdId, inviteId) { return clone(db.invites[inviteKey(householdId, inviteId)]); }
    };
  }

  function createLocalStorageInvitationRepository(options) {
    var storage = options && options.storage || root.localStorage;
    var key = options && options.key || DEFAULT_STORAGE_KEY;
    if (!storage) throw new Error('localStorage is not available.');
    var memory = createMemoryInvitationRepository(readStorage());

    function readStorage() {
      try {
        return Object.assign(emptyDb(), JSON.parse(storage.getItem(key) || '{}'));
      } catch {
        return emptyDb();
      }
    }

    async function persist() {
      var db = await memory.read();
      storage.setItem(key, JSON.stringify(db));
      return db;
    }

    return {
      async read() { return memory.read(); },
      async write(next) { var saved = await memory.write(next); await persist(); return saved; },
      async saveUser(user) { var saved = await memory.saveUser(user); await persist(); return saved; },
      async getUser(uid) { return memory.getUser(uid); },
      async saveHousehold(household) { var saved = await memory.saveHousehold(household); await persist(); return saved; },
      async getHousehold(householdId) { return memory.getHousehold(householdId); },
      async saveMember(member) { var saved = await memory.saveMember(member); await persist(); return saved; },
      async getMember(householdId, uid) { return memory.getMember(householdId, uid); },
      async saveInvite(invite) { var saved = await memory.saveInvite(invite); await persist(); return saved; },
      async getInvite(householdId, inviteId) { return memory.getInvite(householdId, inviteId); }
    };
  }

  function createAuthInvitationService(options) {
    var repository = options && options.repository || createMemoryInvitationRepository();
    var baseUrl = options && options.baseUrl || (root.location ? root.location.origin : 'https://forhome.example.com');
    var mobileBaseUrl = options && options.mobileBaseUrl || createDefaultMobileBaseUrl(baseUrl);

    return {
      repository: repository,

      async registerOwner(input) {
        var result = createHouseholdRegistration(input || {});
        await repository.saveUser(result.user);
        await repository.saveHousehold(result.household);
        await repository.saveMember(result.member);
        return result;
      },

      async createInvite(input) {
        var householdId = requireText(input && input.householdId, 'householdId');
        var createdBy = requireText(input && input.createdBy, 'createdBy');
        var household = await repository.getHousehold(householdId);
        var creator = await repository.getMember(householdId, createdBy);
        if (!canInvite(creator, household)) throw new Error('초대 권한이 없습니다.');
        var draft = await createInviteDraft(input || {});
        await repository.saveInvite(draft.invite);
        var share = createInviteShareBundle({
          invite: draft.invite,
          rawToken: draft.rawToken,
          rawCode: draft.rawCode,
          baseUrl: input && input.baseUrl || baseUrl,
          mobileBaseUrl: input && input.mobileBaseUrl || mobileBaseUrl
        });
        return Object.assign({}, draft, { share: share });
      },

      async previewInvite(input) {
        var invite = await repository.getInvite(requireText(input && input.householdId, 'householdId'), requireText(input && input.inviteId, 'inviteId'));
        if (!invite) throw new Error('초대장을 찾을 수 없습니다.');
        return {
          invite: invite,
          status: inviteStatus(invite, input && input.now),
          tokenOk: input && input.token ? await verifyInviteToken(invite, input.token) : null,
          codeOk: input && input.shortCode ? await verifyInviteNumber(invite, input.shortCode) : null
        };
      },

      async acceptInvite(input) {
        var householdId = requireText(input && input.householdId, 'householdId');
        var inviteId = requireText(input && input.inviteId, 'inviteId');
        var invite = await repository.getInvite(householdId, inviteId);
        if (!invite) throw new Error('초대장을 찾을 수 없습니다.');
        var accepted = await acceptInviteDraft(Object.assign({}, input || {}, { invite: invite }));
        await repository.saveUser(input.user);
        await repository.saveMember(accepted.member);
        await repository.saveInvite(accepted.invite);
        return accepted;
      }
    };
  }

  return {
    ROLE_OWNER: ROLE_OWNER,
    ROLE_HERO: ROLE_HERO,
    ROLE_CARE_MEMBER: ROLE_CARE_MEMBER,
    ROLE_LABELS: clone(ROLE_LABELS),
    DEFAULT_PERMISSIONS: clone(DEFAULT_PERMISSIONS),
    normalizeRole: normalizeRole,
    roleLabel: roleLabel,
    permissionsForRole: permissionsForRole,
    canInvite: canInvite,
    canManageMembers: canManageMembers,
    createId: createId,
    generateInviteNumber: generateInviteNumber,
    normalizeInviteCode: normalizeInviteCode,
    sha256Hex: sha256Hex,
    hashInviteSecret: hashInviteSecret,
    createHouseholdRegistration: createHouseholdRegistration,
    createInviteUrl: createInviteUrl,
    createDefaultMobileBaseUrl: createDefaultMobileBaseUrl,
    createInviteDraft: createInviteDraft,
    createInviteShareBundle: createInviteShareBundle,
    inviteStatus: inviteStatus,
    verifyInviteToken: verifyInviteToken,
    verifyInviteNumber: verifyInviteNumber,
    acceptInviteDraft: acceptInviteDraft,
    renderQrCode: renderQrCode,
    createMemoryInvitationRepository: createMemoryInvitationRepository,
    createLocalStorageInvitationRepository: createLocalStorageInvitationRepository,
    createAuthInvitationService: createAuthInvitationService
  };
});
