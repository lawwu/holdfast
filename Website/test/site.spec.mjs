import { expect, test } from '@playwright/test';
import { base } from '../site.mjs';

test('read the docs and navigate without horizontal overflow', async ({ page }, info) => {
  const failures = [];
  page.on('pageerror', error => failures.push(error.message));
  await page.goto('./');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Keep your knowledge close.');
  await page.screenshot({ path: `test-results/${info.project.name}-home.png`, fullPage: true });
  await page.getByRole('link', { name: 'Get started', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Getting started');
  for (const path of ['guide/', 'packages/local-mlx/', 'development/releases/', 'architecture/']) {
    await page.goto(path);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBeTruthy();
  }
  await page.goto('explore/');
  await page.getByRole('link', { name: '← Holdfast documentation' }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('How Holdfast fits together');
  expect(failures).toEqual([]);
});

test('search finds the approval documentation', async ({ page }) => {
  await page.goto('./');
  await page.getByRole('button', { name: /Search/ }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByRole('textbox', { name: 'Search', exact: true }).fill('Undo');
  const result = dialog.locator('.pagefind-ui__result-link').first();
  await expect(result).toBeVisible();
  await result.click();
  await expect(page).toHaveURL(url => url.pathname.startsWith(base + '/') && url.pathname !== base + '/');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
});

test('theme selection remains readable', async ({ page }, info) => {
  await page.goto('getting-started/');
  const menu = page.getByRole('button', { name: 'Menu', exact: true });
  if (await menu.isVisible()) await menu.click();
  await page.getByRole('combobox', { name: 'Select theme' }).selectOption('dark');
  if (await menu.isVisible()) await menu.click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.screenshot({ path: `test-results/${info.project.name}-dark.png`, fullPage: true });
});
