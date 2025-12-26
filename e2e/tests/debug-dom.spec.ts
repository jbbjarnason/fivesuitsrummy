import { test, expect } from '@playwright/test';

test.describe('Debug DOM', () => {
  // Skip in CI - this is a debug utility
  test.skip(!!process.env.CI, 'Debug test - skipped in CI');

  test('debug flutter dom', async ({ page }) => {
  await page.goto('/');
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(5000);

  // Take screenshot
  await page.screenshot({ path: 'test-results/debug-page.png' });

  // Get all elements
  const html = await page.content();
  console.log('Page HTML length:', html.length);
  console.log('\n--- First 5000 chars ---\n', html.substring(0, 5000));

  // Check for various element types
  const inputs = await page.locator('input').count();
  const textareas = await page.locator('textarea').count();
  const contentEditables = await page.locator('[contenteditable]').count();
  const fltElements = await page.locator('[flt-text-editing]').count();
  const fltSemantics = await page.locator('flt-semantics').count();
  const canvas = await page.locator('canvas').count();

  console.log('\nElement counts:');
  console.log('  inputs:', inputs);
  console.log('  textareas:', textareas);
  console.log('  contentEditables:', contentEditables);
  console.log('  flt-text-editing:', fltElements);
  console.log('  flt-semantics:', fltSemantics);
  console.log('  canvas:', canvas);

  // Try to find any clickable text
  const emailText = await page.locator('text=Email').count();
  const loginText = await page.locator('text=Login').count();
  console.log('\nText elements:');
  console.log('  "Email":', emailText);
  console.log('  "Login":', loginText);

  // Click on Email and see what happens
  if (emailText > 0) {
    await page.click('text=Email');
    await page.waitForTimeout(1000);
    await page.screenshot({ path: 'test-results/debug-after-click.png' });

    // Check if any new input appeared
    const inputsAfter = await page.locator('input').count();
    console.log('  inputs after click:', inputsAfter);
  }
  });
});
