const Application = require("spectron").Application;
const {expect} = require("chai");
const electronPath = require("electron");
const path = require("path");
const fs = require("fs-extra");


describe("Application Start", function () {
  const app = new Application({
        path: electronPath,
        args: [path.join(__dirname, "../app")]
      });

  this.timeout(10000);

  beforeEach(() => {
    return app.start();
  });

  afterEach(function () {
    if (app && app.isRunning()) {
      return app.stop();
    }
  });

  it("should work", () => {
    expect(true).to.be.true;
  });

  it("should display Home window", async () => {
    const count = await app.client.getWindowCount();
    const title = await app.client.waitUntilWindowLoaded().getTitle();
    expect(count).to.eq(1);
    return expect(title).to.eq("Gingko - Home Screen");
  });

  it("should create a document window on clicking 'Blank'", async () => {
    await app.client.waitUntilWindowLoaded();
    await app.client.click("#template-new");
    await app.client.pause(600);
    await app.client.windowByIndex(0);
    const count = await app.client.getWindowCount();
    const title = await app.browserWindow.getTitle();
    expect(count).to.eq(1);
    return expect(title).to.eq("Untitled - Gingko");
  });
});


describe("Actions on Untitled Document", function () {
  const app = new Application({
        path: electronPath,
        env:
          { RUNNING_IN_SPECTRON: "1"
          , DIALOG_CHOICE: "0" // Close Without Saving
          },
        args: [path.join(__dirname, "../app"), "new"]
      });

  this.timeout(10000);

  before(() => {
    return app.start();
  });

  after(function () {
    if (app && app.isRunning()) {
      return app.stop();
    }
  });

  it("should show initial card", async () => {
    const cardExists = await app.client.isExisting("#card-1");
    expect(cardExists).to.be.true;
  });

  it("should switch to edit mode when pressing Enter", async () => {
    await app.client.keys(["Enter"]);
    const textareaExists = await app.client.waitForExist("#card-edit-1", 800);
    expect(textareaExists).to.be.true;
  });

  it("should have text \"Hello World\" in card after typing it", async () => {
    await app.client.keys(["Hello World"]);
    const textareaValue = await app.client.getValue("#card-edit-1");
    expect(textareaValue).to.equal("Hello World");
  });

  it("should have title \"*Untitled - Gingko\"", async () => {
    let windowTitle = await app.browserWindow.getTitle();
    expect(windowTitle).to.equal("*Untitled - Gingko");
  });

  it("should switch to navigation mode when pressing Ctrl+Enter", async () => {
    const step1 = await app.client.keys(["Control", "Enter"]);
    const cardViewExists = await app.client.waitForExist("#card-1 .view", 800);
    expect(cardViewExists).to.be.true;
  });

  it("should show \"Hello World\" in card view", async () => {
    const cardText = await app.client.getText("#card-1 .view");
    expect(cardText).to.equal("Hello World");
  });
  
});


describe("Actions on Loaded Document", function () {
  const app = new Application({
        path: electronPath,
        env:
          { RUNNING_IN_SPECTRON: "1"
          , DIALOG_CHOICE: "0" // Close Without Saving
          },
        args: [path.join(__dirname, "../app"), path.join(__dirname, "test-1.gko")]
      });

  this.timeout(10000);

  before(async () => {
    await fs.copy(path.join(__dirname, "source-test-1.gko"), path.join(__dirname, "test-1.gko"));
    return app.start();
  });

  after(() => {
    if (app && app.isRunning()) {
      return app.stop();
    }
  });

  it("should have loaded the cards and content", async () => {
    await app.client.waitUntilWindowLoaded();

    let cardContent = [];
    cardContent[0] = await app.client.$("#card-1").getText();
    cardContent[1] = await app.client.$("#card-node-2128918683").getText();
    cardContent[2] = await app.client.$("#card-node-1367859142").getText();
    cardContent[3] = await app.client.$("#card-node-1713013080").getText();
    cardContent[4] = await app.client.$("#card-node-1829485524").getText();

    expect(cardContent).to.eql([
      "This is the root card.",
      "The first child is here.",
      "Second child.",
      "A third one.",
      "And second child's child. A grandchild!",
    ]);
  });
});


after(async () => {
  await fs.unlink(path.join(__dirname, "test-1.gko"));
});
