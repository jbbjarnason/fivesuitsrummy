import { test } from '@playwright/test';

const API_URL = 'http://localhost:8080';

test.describe('Screenshot Games', () => {
  // Skip in CI - requires pre-existing test user
  test.skip(!!process.env.CI, 'Debug test - skipped in CI');

  test('screenshot games screen after login', async ({ page }) => {
  await page.goto('/');
  await page.waitForTimeout(4000);
  await page.screenshot({ path: 'test-results/01-login-page.png', fullPage: true });

  const viewport = page.viewportSize() || { width: 1280, height: 720 };
  const centerX = viewport.width / 2;

  // Login
  await page.mouse.click(centerX, viewport.height * 0.47);
  await page.waitForTimeout(300);
  await page.keyboard.type('player1@test.local', { delay: 20 });
  await page.mouse.click(centerX, viewport.height * 0.56);
  await page.waitForTimeout(300);
  await page.keyboard.type('password123', { delay: 20 });
  await page.keyboard.press('Enter');

  await page.waitForTimeout(5000);
  await page.screenshot({ path: 'test-results/02-games-screen.png', fullPage: true });
  console.log('URL:', page.url());
  });
});
