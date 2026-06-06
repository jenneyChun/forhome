const { test, expect } = require('@playwright/test');

async function login(page, id = 'admin', password = 'admin1234', path = '/') {
  await page.goto(path);
  await page.getByTestId('login-id').fill(id);
  await page.getByTestId('login-password').fill(password);
  await page.getByTestId('login-submit').click();
  await expect(page.getByTestId('section-home')).toBeVisible();
}

async function readState(page) {
  return page.evaluate(() => JSON.parse(localStorage.getItem('forhome-test-state-v1')));
}

async function approveFirstPending(page) {
  page.once('dialog', dialog => dialog.accept('확인했습니다'));
  await page.getByTestId('tab-badges').click();
  await page.locator('.review-actions .btn.primary').first().click();
}

test('mom work requires dad approval before it counts', async ({ context }) => {
  const mom = await context.newPage();
  await login(mom, 'mom', 'mom1234');
  await mom.getByTestId('tab-tasks').click();
  await mom.getByTestId('proof-caption').fill('설거지를 끝냈습니다.');
  await mom.getByTestId('complete-task').click();
  await expect(mom.locator('#successOverlay')).toBeVisible();

  let state = await readState(mom);
  expect(state.history[0].approvalRequests).toEqual([
    expect.objectContaining({ reviewerId: 'dad', status: 'pending' })
  ]);

  const dad = await context.newPage();
  await login(dad, 'dad', 'dad1234');
  await approveFirstPending(dad);

  await expect.poll(async () => {
    const next = await readState(dad);
    return next.history[0].verificationStatus;
  }).toBe('approved');
});

test('dad work requires mom approval before it counts', async ({ context }) => {
  const dad = await context.newPage();
  await login(dad, 'dad', 'dad1234');
  await dad.getByTestId('tab-tasks').click();
  await dad.getByTestId('proof-caption').fill('청소를 끝냈습니다.');
  await dad.getByTestId('complete-task').click();
  await expect(dad.locator('#successOverlay')).toBeVisible();

  const mom = await context.newPage();
  await login(mom, 'mom', 'mom1234');
  await approveFirstPending(mom);

  await expect.poll(async () => {
    const next = await readState(mom);
    return `${next.history[0].approvalRequests[0].reviewerId}:${next.history[0].verificationStatus}`;
  }).toBe('mom:approved');
});

test('child category requires both mom and dad approvals', async ({ context }) => {
  const son = await context.newPage();
  await login(son, 'son', 'son1234');
  await son.getByTestId('tab-tasks').click();
  await son.getByRole('button', { name: '아이' }).click();
  await son.getByTestId('proof-caption').fill('숙제를 끝냈습니다.');
  await son.getByTestId('complete-task').click();
  await expect(son.locator('#successOverlay')).toBeVisible();

  const mom = await context.newPage();
  await login(mom, 'mom', 'mom1234');
  await approveFirstPending(mom);
  await expect.poll(async () => {
    const next = await readState(mom);
    return next.history[0].verificationStatus;
  }).toBe('pending');

  const dad = await context.newPage();
  await login(dad, 'dad', 'dad1234');
  await approveFirstPending(dad);
  await expect.poll(async () => {
    const next = await readState(dad);
    return next.history[0].verificationStatus;
  }).toBe('approved');
});

test('task requests must be accepted or declined with a reason', async ({ context }) => {
  const mom = await context.newPage();
  await login(mom, 'mom', 'mom1234');
  await mom.getByTestId('tab-calendar').click();
  await mom.locator('#planTo').selectOption('dad');
  await mom.getByTestId('tomorrow-note').fill('아침 전에 부탁해요.');
  await mom.getByTestId('add-tomorrow-plan').click();

  const dad = await context.newPage();
  await login(dad, 'dad', 'dad1234');
  await dad.getByTestId('tab-calendar').click();
  await dad.getByTestId('accept-plan').first().click();
  await expect.poll(async () => {
    const next = await readState(dad);
    return next.tomorrowPlans[0].requestStatus;
  }).toBe('accepted');

  await mom.locator('#planTo').selectOption('dad');
  await mom.getByTestId('add-tomorrow-plan').click();
  await dad.reload();
  await dad.getByTestId('tab-calendar').click();
  dad.once('dialog', dialog => dialog.accept('회의가 있어 어렵습니다.'));
  await dad.getByTestId('decline-plan').first().click();
  await expect.poll(async () => {
    const next = await readState(dad);
    return next.tomorrowPlans.some(plan => plan.requestStatus === 'declined' && plan.declineReason);
  }).toBe(true);
});

test('calendar records care assignment and child care time', async ({ page }) => {
  await login(page, 'mom', 'mom1234');
  await page.getByTestId('tab-calendar').click();
  await page.getByTestId('care-morning').selectOption('mom');
  await page.getByTestId('care-evening').selectOption('dad');
  await page.getByTestId('save-care-assignment').click();
  await page.getByTestId('care-start').fill('07:30');
  await page.getByTestId('care-end').fill('09:00');
  await page.getByTestId('care-note').fill('등원 준비');
  await page.getByTestId('add-care-session').click();
  await expect(page.getByText('1시간 30분')).toBeVisible();
});

test('morning briefing appears after 07:00 and input flow stays fast', async ({ page }) => {
  await login(page, 'admin', 'admin1234', '/?now=2026-06-04T07:05:00');
  await expect(page.getByTestId('morning-briefing')).toBeVisible();

  await page.getByTestId('tab-tasks').click();
  const start = Date.now();
  await page.getByTestId('complete-task').click();
  await expect(page.locator('#successOverlay')).toBeVisible();
  expect(Date.now() - start).toBeLessThan(2000);
});
