const { test, expect } = require('@playwright/test');

async function fillLoginForm(page, id = 'admin', password = 'admin1234') {
  await page.getByTestId('login-id').fill(id);
  await page.getByTestId('login-password').fill(password);
}

async function expectAppShellSoonAfterLogin(page) {
  const loginResponse = page.waitForResponse(
    (response) => response.url().includes('/api/auth/login') && response.ok()
  );
  await page.getByTestId('login-submit').click();
  await loginResponse;
  const afterLogin = Date.now();
  await expect(page.getByTestId('app-shell')).toBeVisible();
  await expect(page.getByTestId('login-screen')).toBeHidden();
  expect(Date.now() - afterLogin).toBeLessThan(500);
}

test('test storage home content appears within 3s after login click', async ({ page }) => {
  await page.goto('/?storage=test');
  await fillLoginForm(page, 'admin', 'admin1234');
  const clickAt = Date.now();
  await page.getByTestId('login-submit').click();
  await expect(page.getByTestId('section-home')).toBeVisible();
  await expect(page.locator('#section-home .panel-title', { hasText: '오늘 요약' })).toBeVisible();
  expect(Date.now() - clickAt).toBeLessThan(3000);
});

test('postgres summary loads home content within 3s after login API', async ({ page, request }) => {
  test.setTimeout(60000);
  const health = await request.get('/api/health');
  const healthBody = await health.json();
  test.skip(!healthBody.ok, 'PostgreSQL not available');

  await page.goto('/');
  await fillLoginForm(page, 'admin', 'admin1234');
  const loginResponse = page.waitForResponse(
    (response) => response.url().includes('/api/auth/login') && response.ok()
  );
  await page.getByTestId('login-submit').click();
  await loginResponse;
  const afterLogin = Date.now();
  await expect(page.locator('#section-home .panel-title', { hasText: '오늘 요약' })).toBeVisible({ timeout: 3000 });
  expect(Date.now() - afterLogin).toBeLessThan(3000);
});

test('test storage login shows app shell within 500ms after click', async ({ page }) => {
  await page.goto('/?storage=test');
  await fillLoginForm(page, 'admin', 'admin1234');
  const clickAt = Date.now();
  await page.getByTestId('login-submit').click();
  await expect(page.getByTestId('app-shell')).toBeVisible();
  await expect(page.getByTestId('login-screen')).toBeHidden();
  expect(Date.now() - clickAt).toBeLessThan(500);
});

test('test storage login screen hides before sync completes', async ({ page }) => {
  await page.goto('/?storage=test');
  await fillLoginForm(page, 'admin', 'admin1234');
  await page.getByTestId('login-submit').click();
  await expect(page.getByTestId('app-shell')).toBeVisible();
  await expect(page.getByTestId('login-screen')).toBeHidden();
  await expect(page.getByTestId('section-home')).toBeVisible();
  await expect.poll(async () => page.locator('#syncStatus').textContent()).toMatch(/동기화됨/);
});

test('test storage restored session shows app before full reload delay', async ({ page }) => {
  await page.goto('/?storage=test');
  await fillLoginForm(page, 'admin', 'admin1234');
  await page.getByTestId('login-submit').click();
  await expect(page.getByTestId('app-shell')).toBeVisible();
  await page.goto('/?storage=test');
  await expect(page.getByTestId('app-shell')).toBeVisible({ timeout: 2000 });
  await expect(page.getByTestId('login-screen')).toBeHidden();
});

test('postgres login shows app shell within 500ms after API responds', async ({ page, request }) => {
  test.setTimeout(60000);
  const health = await request.get('/api/health');
  const healthBody = await health.json();
  test.skip(!healthBody.ok, 'PostgreSQL not available');

  await page.goto('/');
  await fillLoginForm(page, 'admin', 'admin1234');
  await expectAppShellSoonAfterLogin(page);
});

test('postgres login screen hides before sync completes', async ({ page, request }) => {
  test.setTimeout(60000);
  const health = await request.get('/api/health');
  const healthBody = await health.json();
  test.skip(!healthBody.ok, 'PostgreSQL not available');

  await page.goto('/');
  await fillLoginForm(page, 'admin', 'admin1234');
  const loginResponse = page.waitForResponse(
    (response) => response.url().includes('/api/auth/login') && response.ok()
  );
  await page.getByTestId('login-submit').click();
  await loginResponse;
  await expect(page.getByTestId('app-shell')).toBeVisible();
  await expect(page.getByTestId('login-screen')).toBeHidden();
  await expect.poll(async () => page.locator('#syncStatus').textContent(), { timeout: 15000 }).toMatch(/동기화됨|요약 불러옴/);
});

test('mobile host serves mobile shell and home after login', async ({ page }) => {
  await page.goto('http://m.localhost:8080/?storage=test');
  await fillLoginForm(page, 'admin', 'admin1234');
  await page.getByTestId('login-submit').click();
  await expect(page.getByTestId('app-shell')).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('data-surface', 'mobile');
  await expect(page.locator('.tabbar')).toBeVisible();
  await expect(page.locator('#section-home .panel-title', { hasText: '오늘 요약' })).toBeVisible();
});
