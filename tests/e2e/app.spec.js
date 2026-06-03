const { test, expect } = require('@playwright/test');

async function login(page, id = 'admin', password = 'admin1234') {
  await page.goto('/');
  await page.getByTestId('login-id').fill(id);
  await page.getByTestId('login-password').fill(password);
  await page.getByTestId('login-submit').click();
  await expect(page.getByTestId('section-home')).toBeVisible();
}

test('desktop flow records a chore and shows activity', async ({ page }) => {
  await login(page);
  await page.getByTestId('tab-tasks').click();
  await expect(page.getByTestId('section-tasks')).toBeVisible();
  await page.getByTestId('proof-caption').fill('Sink and counter are clear.');
  await page.getByTestId('complete-task').click();
  await expect(page.locator('#successOverlay')).toBeVisible();
  await page.locator('#closeDialog').click();
  await page.getByTestId('tab-home').click();
  await expect(page.getByText('확인 대기')).toBeVisible();
});

test('mobile browser can log in and navigate', async ({ page }) => {
  await login(page, 'son', 'son1234');
  await page.getByTestId('tab-calendar').click();
  await expect(page.getByTestId('section-calendar')).toBeVisible();
  await expect(page.getByText('내일 알려줄 일')).toBeVisible();
  await page.getByTestId('tab-badges').click();
  await expect(page.getByTestId('section-badges')).toBeVisible();
});

test('mock shared storage reflects a saved chore across tabs', async ({ context }) => {
  const first = await context.newPage();
  const second = await context.newPage();
  await login(first);
  await login(second);
  await first.getByTestId('tab-tasks').click();
  await first.getByTestId('complete-task').click();
  await expect(first.locator('#successOverlay')).toBeVisible();
  await first.locator('#closeDialog').click();
  await expect(second.getByText('확인 대기')).toBeVisible();
});

test('adds tomorrow plan', async ({ page }) => {
  await login(page);
  await page.getByTestId('tab-calendar').click();
  await page.getByTestId('tomorrow-note').fill('Please do this before breakfast.');
  await page.getByTestId('add-tomorrow-plan').click();
  await expect(page.getByText('예정')).toBeVisible();
});

test('photo proof input is available for task evidence', async ({ page }) => {
  await login(page);
  await page.getByTestId('tab-tasks').click();
  await expect(page.getByTestId('proof-photo')).toBeVisible();
});
