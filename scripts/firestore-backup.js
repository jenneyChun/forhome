const fs = require('fs');
const path = require('path');

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
    } else {
      args[key] = next;
      i += 1;
    }
  }
  return args;
}

function kstDateKey(now = new Date()) {
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  return kst.toISOString().slice(0, 10);
}

function readJsonFile(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function dateKey(ts) {
  const d = new Date(Number(ts) + 9 * 60 * 60 * 1000);
  return d.toISOString().slice(0, 10);
}

function addDaysKey(date, days) {
  const d = new Date(`${date}T00:00:00.000+09:00`);
  d.setDate(d.getDate() + days);
  return dateKey(d.getTime());
}

function formatClock(ts) {
  return new Date(Number(ts)).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Seoul' });
}

function formatMinutes(minutes) {
  const value = Math.max(0, Number(minutes || 0));
  const h = Math.floor(value / 60);
  const m = value % 60;
  if (h && m) return `${h}h ${m}m`;
  if (h) return `${h}h`;
  return `${m}m`;
}

function statusLabel(status) {
  return ({ pending: 'pending', approved: 'approved', rejected: 'rejected' })[status] || status || 'pending';
}

function requestLabel(status) {
  return ({ pending: 'pending approval', accepted: 'today task', declined: 'declined' })[status] || status || 'pending approval';
}

function approvalText(task, members) {
  const requests = Array.isArray(task.approvalRequests) ? task.approvalRequests : [];
  if (!requests.length) {
    const reviewer = members.get(task.reviewerId);
    return reviewer ? `${reviewer.name}: ${statusLabel(task.verificationStatus)}` : 'no approval requests';
  }
  return requests.map((request) => {
    const reviewer = members.get(request.reviewerId);
    return `${reviewer?.name || request.reviewerId}: ${statusLabel(request.status)}`;
  }).join(', ');
}

function dailySummary(state, date) {
  const members = new Map((state.members || []).map((m) => [m.id, m]));
  const chores = new Map((state.chores || []).map((c) => [c.id, c]));
  const tomorrow = new Date(`${date}T00:00:00.000+09:00`);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowKey = dateKey(tomorrow.getTime());
  const tasks = (state.history || [])
    .filter((h) => dateKey(h.timestamp) === date)
    .map((h) => {
      const member = members.get(h.memberId);
      const chore = chores.get(h.choreId);
      const reviewer = members.get(h.reviewerId);
      return {
        memberName: member?.name || h.memberId,
        choreName: h.choreName || chore?.name || h.choreId,
        status: h.verificationStatus || 'approved',
        reviewerName: reviewer?.name || '',
        approvals: approvalText(h, members),
        proof: h.proofImage ? 'photo' : (h.proofCaption ? 'memo' : 'none'),
        xp: Number(h.xpEarned || 0),
        time: formatClock(h.timestamp)
      };
    });
  const messages = (state.messages || [])
    .filter((m) => dateKey(m.timestamp) === date)
    .map((m) => {
      const from = members.get(m.fromId);
      const to = m.toId ? members.get(m.toId) : null;
      return {
        from: from?.name || m.fromId,
        to: to?.name || 'All',
        text: m.text || '',
        time: formatClock(m.timestamp)
      };
    });
  const careAssignments = (state.careAssignments || []).find((item) => item.date === date) || null;
  const careSessions = (state.careSessions || [])
    .filter((session) => session.date === date)
    .map((session) => ({
      memberName: members.get(session.memberId)?.name || session.memberId,
      startTime: session.startTime || '',
      endTime: session.endTime || '',
      minutes: Number(session.minutes || 0),
      note: session.note || ''
    }));
  const todayPlans = (state.tomorrowPlans || [])
    .filter((plan) => plan.targetDate === date)
    .map((plan) => {
      const to = members.get(plan.toId);
      const from = members.get(plan.fromId);
      const chore = chores.get(plan.choreId);
      return {
        from: from?.name || plan.fromId || 'admin',
        to: to?.name || plan.toId,
        title: plan.title || chore?.name || plan.choreId,
        note: plan.note || '',
        requestStatus: plan.requestStatus || 'accepted',
        declineReason: plan.declineReason || '',
        status: plan.status || 'open'
      };
    });
  const tomorrowPlans = (state.tomorrowPlans || [])
    .filter((plan) => plan.targetDate === tomorrowKey && plan.status !== 'closed')
    .map((plan) => {
      const to = members.get(plan.toId);
      const chore = chores.get(plan.choreId);
      return {
        to: to?.name || plan.toId,
        title: plan.title || chore?.name || plan.choreId,
        note: plan.note || ''
      };
    });
  return { date, tasks, messages, careAssignments, careSessions, todayPlans, tomorrowPlans };
}

function markdownReport(state, summary) {
  const lines = [
    `# ForHome Daily Report - ${summary.date}`,
    '',
    `- State version: ${state.version || 0}`,
    `- Updated at: ${state.updatedAt || 'unknown'}`,
    `- Tasks today: ${summary.tasks.length}`,
    `- Messages today: ${summary.messages.length}`,
    `- Care sessions today: ${summary.careSessions.length}`,
    `- Today task requests: ${summary.todayPlans.length}`,
    `- Tomorrow plans: ${summary.tomorrowPlans.length}`,
    '',
    '## Tasks',
    ''
  ];

  if (summary.tasks.length) {
    summary.tasks.forEach((task) => {
      const reviewer = task.reviewerName ? `, reviewer: ${task.reviewerName}` : '';
      lines.push(`- ${task.time} ${task.memberName}: ${task.choreName} (${task.status}, ${task.proof}${reviewer}, approvals: ${task.approvals}, +${task.xp} XP)`);
    });
  } else {
    lines.push('- No tasks recorded.');
  }

  lines.push('', '## Care', '');
  if (summary.careAssignments) {
    lines.push(`- Morning: ${summary.careAssignments.morningId || 'unassigned'}`);
    lines.push(`- Evening: ${summary.careAssignments.eveningId || 'unassigned'}`);
  } else {
    lines.push('- No care assignment recorded.');
  }
  if (summary.careSessions.length) {
    summary.careSessions.forEach((session) => {
      lines.push(`- ${session.memberName}: ${session.startTime}-${session.endTime} (${formatMinutes(session.minutes)})${session.note ? ` - ${session.note}` : ''}`);
    });
  } else {
    lines.push('- No care sessions recorded.');
  }

  lines.push('', '## Today Requests', '');
  if (summary.todayPlans.length) {
    summary.todayPlans.forEach((plan) => {
      const decline = plan.declineReason ? `, reason: ${plan.declineReason}` : '';
      lines.push(`- ${plan.from} -> ${plan.to}: ${plan.title} (${requestLabel(plan.requestStatus)}${decline})`);
    });
  } else {
    lines.push('- No task requests for today.');
  }

  lines.push('', '## Messages', '');
  if (summary.messages.length) {
    summary.messages.forEach((message) => {
      lines.push(`- ${message.time} ${message.from} to ${message.to}: ${message.text}`);
    });
  } else {
    lines.push('- No messages recorded.');
  }

  lines.push('');
  lines.push('## Tomorrow', '');
  if (summary.tomorrowPlans.length) {
    summary.tomorrowPlans.forEach((plan) => {
      lines.push(`- ${plan.to}: ${plan.title}${plan.note ? ` - ${plan.note}` : ''}`);
    });
  } else {
    lines.push('- No plans for tomorrow.');
  }

  lines.push('');
  return lines.join('\n');
}

function morningBriefing(state, date) {
  const members = new Map((state.members || []).map((m) => [m.id, m]));
  const yesterday = addDaysKey(date, -1);
  const yesterdaySummary = dailySummary(state, yesterday);
  const todaySummary = dailySummary(state, date);
  const assignment = todaySummary.careAssignments || {};
  const accepted = todaySummary.todayPlans.filter((plan) => plan.requestStatus === 'accepted' && plan.status !== 'closed');
  const pending = todaySummary.todayPlans.filter((plan) => plan.requestStatus === 'pending');
  const lines = [
    `ForHome morning briefing - ${date}`,
    '',
    `Yesterday tasks: ${yesterdaySummary.tasks.length}`
  ];

  if (yesterdaySummary.tasks.length) {
    yesterdaySummary.tasks.slice(0, 8).forEach((task) => {
      lines.push(`- ${task.memberName}: ${task.choreName} (${task.status}, ${task.approvals})`);
    });
  } else {
    lines.push('- No tasks recorded yesterday.');
  }

  lines.push('', `Yesterday care: ${yesterdaySummary.careSessions.length}`);
  if (yesterdaySummary.careSessions.length) {
    yesterdaySummary.careSessions.forEach((session) => {
      lines.push(`- ${session.memberName}: ${session.startTime}-${session.endTime} (${formatMinutes(session.minutes)})`);
    });
  } else {
    lines.push('- No care time recorded yesterday.');
  }

  lines.push('', 'Today care assignment');
  lines.push(`- Morning: ${members.get(assignment.morningId)?.name || assignment.morningId || 'unassigned'}`);
  lines.push(`- Evening: ${members.get(assignment.eveningId)?.name || assignment.eveningId || 'unassigned'}`);

  lines.push('', `Today tasks: ${accepted.length}`);
  if (accepted.length) {
    accepted.forEach((plan) => lines.push(`- ${plan.to}: ${plan.title}${plan.note ? ` - ${plan.note}` : ''}`));
  } else {
    lines.push('- No accepted tasks for today.');
  }

  lines.push('', `Pending requests: ${pending.length}`);
  if (pending.length) {
    pending.forEach((plan) => lines.push(`- ${plan.from} -> ${plan.to}: ${plan.title}`));
  } else {
    lines.push('- No pending task requests.');
  }

  const text = lines.join('\n');
  return {
    date,
    yesterday,
    text: text.length > 1800 ? `${text.slice(0, 1797)}...` : text,
    summary: { yesterday: yesterdaySummary, today: todaySummary }
  };
}

async function loadFirestoreState(projectId, familyId) {
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!serviceAccountJson) {
    throw new Error('Missing FIREBASE_SERVICE_ACCOUNT_JSON secret.');
  }

  const admin = require('firebase-admin');
  const serviceAccount = JSON.parse(serviceAccountJson);
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId
    });
  }

  const snap = await admin.firestore().doc(`families/${familyId}/state/app`).get();
  if (!snap.exists) {
    throw new Error(`Missing Firestore state document: families/${familyId}/state/app`);
  }
  return snap.data();
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const repoRoot = path.resolve(__dirname, '..');
  const outDir = path.resolve(args['out-dir'] || repoRoot);
  const date = args.date || process.env.BACKUP_DATE || kstDateKey();
  const familyId = process.env.FIRESTORE_FAMILY_ID || 'forhome';
  const projectId = process.env.FIREBASE_PROJECT_ID || 'forhome-19317';
  const state = args.fixture
    ? readJsonFile(path.resolve(args.fixture))
    : await loadFirestoreState(projectId, familyId);

  if (args.briefing) {
    const briefing = morningBriefing(state, date);
    if (args['out-file']) {
      const outFile = path.resolve(args['out-file']);
      fs.mkdirSync(path.dirname(outFile), { recursive: true });
      fs.writeFileSync(outFile, `${JSON.stringify(briefing, null, 2)}\n`, 'utf8');
      console.log(`Wrote ${outFile}`);
    } else {
      console.log(briefing.text);
    }
    return;
  }

  const summary = dailySummary(state, date);

  const jsonPath = path.join(outDir, 'data', 'backups', date, 'state.json');
  const mdPath = path.join(outDir, 'reports', 'daily', `${date}.md`);
  fs.mkdirSync(path.dirname(jsonPath), { recursive: true });
  fs.mkdirSync(path.dirname(mdPath), { recursive: true });
  fs.writeFileSync(jsonPath, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
  fs.writeFileSync(mdPath, markdownReport(state, summary), 'utf8');

  console.log(`Wrote ${path.relative(outDir, jsonPath)}`);
  console.log(`Wrote ${path.relative(outDir, mdPath)}`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = { dailySummary, kstDateKey, markdownReport, morningBriefing };
