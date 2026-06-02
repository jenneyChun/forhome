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
  await page.getByTestId('complete-task').click();
  await expect(page.locator('#successOverlay')).toBeVisible();
  await page.locator('#closeDialog').click();
  await page.getByTestId('tab-home').click();
  await expect(page.locator('.activity-row').first()).toBeVisible();
});

test('mobile browser can log in and navigate', async ({ page }) => {
  await login(page, 'son', 'son1234');
  await page.getByTestId('tab-calendar').click();
  await expect(page.getByTestId('section-calendar')).toBeVisible();
  await page.getByTestId('tab-badges').click();
  await expect(page.getByTestId('section-badges')).toBeVisible();
});
