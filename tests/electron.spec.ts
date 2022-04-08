import { _electron as electron, test, expect, ElectronApplication, Page, BrowserContext } from "@playwright/test";
const path = require('path')
import * as fs from 'fs/promises';
import * as fsStd from 'fs';

let electronApp: ElectronApplication;
let homeWindow: Page;
let newDocWindow : Page;
let context: BrowserContext;


test.beforeAll( async () => {
  electronApp = await electron.launch({ args: ["./app"] });
  context = electronApp.context();
  await context.tracing.start({ screenshots: true, snapshots: true });
  homeWindow = await electronApp.firstWindow();
})


test.describe('Check Home Page', async () => {
  test('Check Title', async () => {
    const title = await homeWindow.title();
    expect(title).toBe("Gingko Writer - Home");
  })

  test('Opens New Document', async () => {
    await homeWindow.click("#new-doc-button");
    newDocWindow = await electronApp.windows()[0]
    expect(newDocWindow).toBeTruthy();
    await expect(newDocWindow).toHaveTitle("Gingko Writer Desktop");
  })

  test('Can type in box and save', async  () => {
    const textarea = await newDocWindow.locator('textarea.edit');
    await textarea.focus()
    await newDocWindow.keyboard.type('Hi!');
    await expect(textarea).toHaveValue('Hi!')
    await newDocWindow.keyboard.press('Control+Enter');

    const savedCardView = await newDocWindow.locator('.card.active .view');
    await expect(savedCardView).toHaveText('Hi!');
  })

  test('Saves to file properly', async () => {
    const dir = '/home/adriano/Dropbox/Notes/';
    const files = await fs.readdir(dir);
    const latestFile =
      files
        .filter(async (file) => (await fs.stat(path.join(dir, file))).isFile())
        .map((file) => {
          let stats = fsStd.statSync(path.join(dir, file));
          return {file: file, mtime: stats.mtime};
        })
        .sort((a, b) => b.mtime.getTime() - a.mtime.getTime())
        .map(x => x.file)[0];
    const fileContents = await fs.readFile(path.join(dir, latestFile), {encoding: "utf8"});
    expect(fileContents).toEqual('<gingko-card id="1">\n\nHi!\n\n</gingko-card>');
  })

  test('Splits card correctly on Control+J', async () => {
    // Enter for edit mode
    await newDocWindow.keyboard.press('Enter');
    const rootCardTextarea = await newDocWindow.locator('textarea.edit');
    await expect(rootCardTextarea).toBeFocused();

    // Add '\nSomething'
    await newDocWindow.keyboard.press('Enter');
    await newDocWindow.keyboard.type('Something');

    // Split down
    await newDocWindow.keyboard.press('Control+J');
    const rootCard = await newDocWindow.locator('#card-1 .view');
    await expect(rootCard).toHaveText('Hi!\nSomething',{useInnerText: true});

    // Add text to newly split card
    const newCard = await newDocWindow.locator('textarea.edit');
    await expect(rootCardTextarea).toBeFocused();
    await newDocWindow.keyboard.type('xyzuvw');
    await newDocWindow.keyboard.press('ArrowLeft');
    await newDocWindow.keyboard.press('ArrowLeft');
    await newDocWindow.keyboard.press('ArrowLeft');
    await newDocWindow.keyboard.press('Control+J');
  })
})


test.afterAll( async () => {
  await context.tracing.stop({ path: 'tests/tracing/trace.zip' });
  await electronApp.close();
})