import { test, expect } from '@playwright/test';

const API_URL = 'http://localhost:8080';
const MAILPIT_URL = 'http://localhost:8025';

test.describe('Screenshot Debug', () => {
  // Skip in CI - this is a debug/screenshot utility
  test.skip(!!process.env.CI, 'Debug test - skipped in CI');

  test('screenshot games screen', async ({ page }) => {
  // First login a user
  const email = 'player1@test.local';
  const password = 'password123';

  // Login via API
  const loginRes = await fetch(`${API_URL}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });

  if (loginRes.status !== 200) {
    console.log('Login failed, user may not exist');
    // Take screenshot of login page instead
    await page.goto('/');
    await page.waitForTimeout(3000);
    await page.screenshot({ path: 'test-results/login-screen.png', fullPage: true });
    return;
  }

  const loginData = await loginRes.json();
  const accessToken = loginData.accessJwt;

  // Set the token in browser storage before navigating
  await page.goto('/');
  await page.waitForTimeout(2000);

  // Take screenshot of initial load
  await page.screenshot({ path: 'test-results/initial-load.png', fullPage: true });

  // Try to inject the token via localStorage/sessionStorage
  await page.evaluate((token) => {
    // Flutter web typically uses these for storage
    localStorage.setItem('accessToken', token);
    sessionStorage.setItem('accessToken', token);

    // Also try flutter secure storage format
    localStorage.setItem('flutter.accessToken', token);
  }, accessToken);

  // Reload and navigate to games
  await page.goto('/#/games');
  await page.waitForTimeout(4000);

  // Take screenshot of games screen
  await page.screenshot({ path: 'test-results/games-screen-debug.png', fullPage: true });

  // Also take screenshot after waiting longer
  await page.waitForTimeout(3000);
  await page.screenshot({ path: 'test-results/games-screen-after-wait.png', fullPage: true });

  console.log('Screenshots saved to test-results/');
  });
});
