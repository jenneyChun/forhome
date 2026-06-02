const path = require('path');
const { defineConfig, devices } = require('@playwright/test');

const repoRoot = path.join(__dirname, '..');

module.exports = defineConfig({
  testDir: path.join(__dirname, 'e2e'),
  timeout: 30000,
  expect: { timeout: 5000 },
  outputDir: path.join(repoRoot, 'log', 'playwright-results'),
  reporter: [['html', { outputFolder: path.join(repoRoot, 'log', 'playwright-report'), open: 'never' }], ['list']],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8080',
    trace: 'on-first-retry'
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 820 } } },
    { name: 'mobile', use: { ...devices['Pixel 5'] } }
  ],
  webServer: {
    command: 'powershell -NoProfile -ExecutionPolicy Bypass -File server/server.ps1 -Port 8080',
    cwd: repoRoot,
    url: 'http://127.0.0.1:8080/api/health',
    reuseExistingServer: true,
    timeout: 20000
  }
});
