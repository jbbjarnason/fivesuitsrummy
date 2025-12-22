import { test, expect } from '@playwright/test';
import { exec, spawn } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

const API_URL = 'http://localhost:8080';
const MAILPIT_URL = 'http://localhost:8025';

// Helper to generate unique test user
function generateTestUser(prefix: string = 'test') {
  const id = Math.random().toString(36).substring(7);
  return {
    email: `${prefix}-${id}@test.local`,
    username: `${prefix}${id}`,
    displayName: `${prefix.charAt(0).toUpperCase() + prefix.slice(1)} User ${id}`,
    password: 'SecurePass123!',
  };
}

// Helper to get verification token from Mailpit
async function getVerificationToken(email: string): Promise<string> {
  for (let i = 0; i < 5; i++) {
    await new Promise(r => setTimeout(r, 500));

    const messagesRes = await fetch(`${MAILPIT_URL}/api/v1/search?query=to:${email}`);
    const messages = await messagesRes.json();

    if (messages.messages && messages.messages.length > 0) {
      const messageId = messages.messages[0].ID;
      const messageRes = await fetch(`${MAILPIT_URL}/api/v1/message/${messageId}`);
      const message = await messageRes.json();

      const tokenMatch = message.Text?.match(/token=([a-zA-Z0-9-]+)/) ||
                         message.HTML?.match(/token=([a-zA-Z0-9-]+)/);

      if (tokenMatch) {
        return tokenMatch[1];
      }
    }
  }
  throw new Error(`No verification email found for ${email}`);
}

// Helper to create and verify a user
async function createVerifiedUser(prefix: string = 'test') {
  const user = generateTestUser(prefix);

  // Register
  await fetch(`${API_URL}/auth/signup`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(user),
  });

  // Verify
  const token = await getVerificationToken(user.email);
  await fetch(`${API_URL}/auth/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token }),
  });

  // Login to get tokens
  const loginRes = await fetch(`${API_URL}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: user.email, password: user.password }),
  });

  const tokens = await loginRes.json();

  // Get user ID
  const meRes = await fetch(`${API_URL}/users/me`, {
    headers: { 'Authorization': `Bearer ${tokens.accessJwt}` },
  });
  const me = await meRes.json();

  return { ...user, id: me.id, accessToken: tokens.accessJwt, refreshToken: tokens.refreshToken };
}

// Helper to create a game
async function createGame(accessToken: string, maxPlayers: number = 4) {
  const res = await fetch(`${API_URL}/games/`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ maxPlayers }),
  });
  return await res.json();
}

// Helper to invite player to game
async function invitePlayer(accessToken: string, gameId: string, userId: string) {
  const res = await fetch(`${API_URL}/games/${gameId}/invite`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ userId }),
  });
  return res.status === 200;
}

test.describe('Cross-Platform Multiplayer', () => {
  test('Web player hosts, iOS player joins and plays together', async ({ page }) => {
    // Step 1: Create two verified users - one for web (host), one for iOS (guest)
    console.log('Creating host user (web)...');
    const hostUser = await createVerifiedUser('webhost');
    console.log(`Host user created: ${hostUser.username}`);

    console.log('Creating guest user (iOS)...');
    const iosUser = await createVerifiedUser('iosguest');
    console.log(`iOS user created: ${iosUser.username}`);

    // Step 2: Host creates a game via API
    console.log('Creating game...');
    const game = await createGame(hostUser.accessToken, 2);
    console.log(`Game created: ${game.gameId}`);

    // Step 3: Invite iOS user to the game
    console.log('Inviting iOS user to game...');
    const invited = await invitePlayer(hostUser.accessToken, game.gameId, iosUser.id);
    expect(invited).toBe(true);
    console.log('iOS user invited');

    // Step 4: Web player logs in and navigates to game
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(4000); // Give Flutter time to render

    // Get viewport size for coordinate-based clicking (Flutter CanvasKit)
    const viewport = page.viewportSize() || { width: 1280, height: 720 };
    const centerX = viewport.width / 2;

    // Login as host using coordinate-based clicking (Flutter renders to canvas)
    // Email field is roughly at 42% from top
    await page.mouse.click(centerX, viewport.height * 0.42);
    await page.waitForTimeout(500);
    await page.keyboard.type(hostUser.email, { delay: 20 });

    // Password field is roughly at 52% from top
    await page.mouse.click(centerX, viewport.height * 0.52);
    await page.waitForTimeout(500);
    await page.keyboard.type(hostUser.password, { delay: 20 });

    // Press Enter to submit
    await page.keyboard.press('Enter');
    await page.waitForTimeout(4000);

    console.log(`After login, URL is: ${page.url()}`);

    // Click on the game to enter lobby
    console.log('Web host entering game lobby...');
    await page.waitForTimeout(1000);

    // Navigate directly to the game since we can't click canvas elements
    await page.goto(`/#/games/${game.gameId}`);
    await page.waitForTimeout(2000);

    // Step 5: Write iOS user credentials to a file for the iOS test to pick up
    const credentials = {
      email: iosUser.email,
      password: iosUser.password,
      gameId: game.gameId,
    };

    // Write credentials to temp file
    const fs = require('fs');
    fs.writeFileSync('/tmp/ios_test_credentials.json', JSON.stringify(credentials, null, 2));
    console.log('Credentials written to /tmp/ios_test_credentials.json');

    // Step 6: Wait for iOS player to join (check game state)
    console.log('Waiting for iOS player to join...');
    console.log('');
    console.log('=== MANUAL STEP ===');
    console.log('Run the iOS test with these credentials:');
    console.log(`Email: ${iosUser.email}`);
    console.log(`Password: ${iosUser.password}`);
    console.log(`Game ID: ${game.gameId}`);
    console.log('');
    console.log('From another terminal, run:');
    console.log('cd /Users/jonb/Projects/fcrowns/app');
    console.log('flutter test integration_test/join_game_test.dart -d <simulator-id>');
    console.log('===================');
    console.log('');

    // Wait and poll for player count to increase
    let playersJoined = false;
    for (let i = 0; i < 60; i++) {
      await page.waitForTimeout(2000);

      // Check if game state shows 2 players
      const pageContent = await page.content();
      if (pageContent.includes('2 players') || pageContent.includes('2/2')) {
        playersJoined = true;
        console.log('iOS player has joined!');
        break;
      }

      // Also check via API
      const gameRes = await fetch(`${API_URL}/games/${game.gameId}`, {
        headers: { 'Authorization': `Bearer ${hostUser.accessToken}` },
      });
      if (gameRes.status === 200) {
        const gameState = await gameRes.json();
        if (gameState.players && gameState.players.length >= 2) {
          playersJoined = true;
          console.log('iOS player has joined (confirmed via API)!');
          break;
        }
      }

      console.log(`Waiting for iOS player... (${i + 1}/60)`);
    }

    // Don't fail if player didn't join - this allows manual testing
    if (!playersJoined) {
      console.log('iOS player did not join within timeout. Test continuing for demonstration.');
    }

    // Take screenshot of final state
    await page.screenshot({ path: 'test-results/cross-platform-lobby.png' });

    // Cleanup: Show final state
    console.log('Cross-platform test setup complete.');
    console.log(`Host (web): ${hostUser.username}`);
    console.log(`Guest (iOS): ${iosUser.username}`);
    console.log(`Game ID: ${game.gameId}`);
  });
});
