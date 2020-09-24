// @format
const jQuery = require("jquery");
const _ = require("lodash");
require("textarea-autosize");
const Mousetrap = require("mousetrap");
const container = require("Container");
const config = require("../../config.js");
require("../shared/GitGraph.js");

import PouchDB from "pouchdb";

const helpers = require("./doc-helpers");
const { tr } = require("../shared/translation.js");
import { Elm } from "../elm/Main";

/* === Global Variables === */

let lastActivesScrolled = null;
let lastColumnScrolled = null;
let lang;
let helpVisible;
let helpWidgetLauncher;

let remoteDB;
let gingko;
let TREE_ID;
let localHead;
let remoteHead;
let savedObjectIds = [];
const userStore = container.userStore;
const localStore = container.localStore;

const sessionStorageKey = "gingko-session-storage";

/* === Initializing App === */

initElmAndPorts();

async function initElmAndPorts() {
  let email = null;
  let sessionData = localStorage.getItem(sessionStorageKey) || null;
  let settings = {language: "en"};
  if (sessionData) {
    console.log("sessionData found")
    sessionData = JSON.parse(sessionData);
    email = sessionData.email;
    setUserDbs(sessionData.email);

    // Load user settings
    try {
      settings = await userStore.load();
    } catch (e) {
      console.log("failed", e)
    }
  }


  console.log("loaded settings" ,settings)
  const initFlags = { email: email, seed: Date.now(), language: settings.language};

  gingko = Elm.Main.init({
    node: document.getElementById("elm"),
    flags: initFlags,
  });

  // All messages from Elm
  gingko.ports.infoForOutside.subscribe(function (elmdata) {
    fromElm(elmdata.tag, elmdata.data);
  });

  window.checkboxClicked = (cardId, number) => {
    toElm([cardId, number], "docMsgs", "CheckboxClicked");
  };

  // Whenever localStorage changes in another tab, report it if necessary.
  window.addEventListener(
    "storage",
    function (event) {
      if (
        event.storageArea === localStorage &&
        event.key === sessionStorageKey
      ) {
        gingko.ports.userStateChanged.send(event.newValue);
      }
    },
    false
  );
}

function setUserDbs(email) {
  console.log("Inside setUserDbs", email, helpers.toHex(email));
  const userDbName = `userdb-${helpers.toHex(email)}`;
  let userDbUrl = config.COUCHDB_SERVER + "/" + userDbName;
  var remoteOpts = {
    skip_setup: true,
    fetch(url, opts) {
      return fetch(url, opts);
    },
  };
  remoteDB = new PouchDB(userDbUrl, remoteOpts);
  self.db = new PouchDB(userDbName);
  userStore.db(db, remoteDB);

  // Sync user settings
  PouchDB.sync(db, remoteDB, {live: true, retry: true, doc_ids: ["settings"]})
    .on('change', (ev) => {
      if (ev.direction === "pull") {
        gingko.ports.userSettingsChange.send(ev.change.docs[0]);
      }
    });

  // add docList design document
  let ddoc = {
    _id: "_design/testDocList",
    views: {
      docList: {
        map:
          "function (doc) {\n  if (/metadata/.test(doc._id)) {\n    emit(doc._id, doc);\n  }\n}",
      },
    },
    language: "javascript",
  };
  db.put(ddoc).catch(async (e) => e); // ignore conflict error

  // Update Elm on document list changes
  PouchDB.sync(db, remoteDB, { filter: "_view", view: "testDocList/docList", include_docs: true, live: true, retry: true })
    .on('change', (ev) => {
      if (ev.direction === "pull") {
        // New document list received, update Elm
        loadAndUpdateDocList();
      }
    });
}

async function deleteLocalUserDbs() {
  console.log("Deleting local copies of documents, for privacy.");
  await db.destroy();
}

/* === Elm / JS Interop === */

function toElm(data, portName, tagName) {
  let portExists = gingko.ports.hasOwnProperty(portName);
  let tagGiven = typeof tagName == "string";

  if (portExists) {
    var dataToSend;

    if (tagGiven) {
      dataToSend = { tag: tagName, data: data };
    } else {
      dataToSend = data;
    }
    gingko.ports[portName].send(dataToSend);
  } else {
    console.error("Unknown port", portName, data);
  }
}

const fromElm = (msg, data) => {
  console.debug("fromElm", msg, data);
  let cases = {
    // === SPA ===

    StoreUser: () => {
      if (data == null) {
        localStorage.removeItem(sessionStorageKey);
        deleteLocalUserDbs();
      } else {
        localStorage.setItem(
          sessionStorageKey,
          JSON.stringify(_.omit(data, "seed"))
        );
        setUserDbs(data.email);
        setTimeout(() => gingko.ports.userLoginChange.send(data), 0);
      }
    },

    // === Dialogs, Menus, Window State ===

    Alert: () => {
      alert(data);
    },

    ConfirmCancelCard: () => {
      let tarea = document.getElementById("card-edit-" + data[0]);

      if (tarea === null) {
        console.log("tarea not found");
      } else {
        if (tarea.value === data[1] || confirm(tr.areYouSureCancel[lang])) {
          toElm(null, "docMsgs", "CancelCardConfirmed");
        }
      }
    },

    // === Database ===

    InitDocument: async () => {
      TREE_ID = data;

      const now = Date.now();
      let metadata = {
        _id: data + "/metadata",
        docId: data,
        name: null,
        createdAt: now,
        updatedAt: now,
      };
      await db.put(metadata).catch(async (e) => e);

      localStore.db(db, data);
      let store = await localStore.load();
      toElm(store, "docMsgs", "LocalStoreLoaded");
    },

    LoadDocument: async () => {
      TREE_ID = data;

      localStore.db(db, data);
      let store = await localStore.load();
      toElm(store, "docMsgs", "LocalStoreLoaded");

      let metadata = await db.get("metadata").catch(async (e) => e);
      if (!metadata.error) {
        toElm(metadata, "docMsgs", "MetadataSaved");
      }

      load(); // load local
      //pull(); // sync remote

      // Set up regular *fetch*
      let options  = {selector: { _id: { $regex: `${TREE_ID}/` } }, live: true, retry: true};
      db.replicate.from(remoteDB, options)
        .on('change', async (ev) => {
          console.log("ev.docs", ev.docs);
          let maybeRemoteHead = _.find(ev.docs, ["_id", TREE_ID + "/heads/master"]);
          if (typeof maybeRemoteHead !== "undefined") {
            // Track remote head value
            remoteHead = maybeRemoteHead;

            // Rearrange data to format expected by Elm
            let mappedDocs = ev.docs.map((doc) => {
              doc._id = unprefix(doc._id);
              return doc;
            });
            let groupFn = (d) => (d.hasOwnProperty("type") ? d.type : d._id);
            let toSend = _.groupBy(mappedDocs, groupFn);

            // Get new head, or possible conflict/branching history.
            let newHead = await db
              .get(prefix("heads/master"), { conflicts: true })
              .catch(async (e) => e);

            if (newHead.hasOwnProperty("_conflicts")) {
              let conflictHead = await db.get(prefix("heads/master"), {
                rev: newHead._conflicts[0],
              });
              console.log("auto:conflictHead", conflictHead);
              if (!_.isEqual(remoteHead, conflictHead)) {
                let setHead = (r) => {
                  return r._id == prefix("heads/master") ? conflictHead : r;
                };
                toSend.ref = toSend.ref.map(setHead);
                toSend.conflict = newHead;
              } else {
                toSend.conflict = conflictHead;
              }
            }

            // Send new documents to Elm for merging.
            console.log(toSend)
            toElm(toSend, "docMsgs", "DataReceived");
          }
        })
        .on('error', (err) => console.log("pull change error", err))
    },

    GetDocumentList: () => {
      loadAndUpdateDocList();
    },

    RequestDelete: async () => {
      if (confirm("Are you sure you want to delete this document?")) {
        let docsFetch = await remoteDB.allDocs({
          startkey: data + "/",
          endkey: data + "/\ufff0",
        });

        let docsToDelete = docsFetch.rows.map((r) => {
          return { _id: r.id, _rev: r.value.rev, _deleted: true };
        });

        // Delete from local and remote DBs
        remoteDB.bulkDocs(docsToDelete);
        await db.bulkDocs(docsToDelete);

        // Get new (local) list of documents
        loadAndUpdateDocList();
      }
    },

    SaveData: async () => {
      // Store ids of refs, so we can send back updated _rev.
      const refIds = data.data.refs.map((r) => r._id);

      // Keep objects that are not saved in database.
      const newCommits = data.data.commits.filter(
        (o) => !savedObjectIds.includes(o._id)
      );
      const newTreeObjects = data.data.treeObjects.filter(
        (o) => !savedObjectIds.includes(o._id)
      );

      // Remove conflicts if head is updated
      let savedHead = await db
        .get(prefix("heads/master"), { conflicts: true })
        .catch(async (e) => e);
      if (savedHead.hasOwnProperty("_conflicts")) {
        let revToDelete = savedHead._conflicts[0];
        await db.remove(prefix("heads/master"), revToDelete);
      }

      // Save to database, and add successes to savedObjectIds.
      const rows = [...newCommits, ...newTreeObjects, ...data.data.refs];
      const toSave = rows.map((r) => {
        r._id = prefix(r._id);
        return r;
      });
      const responses = await db.bulkDocs(toSave);
      const savedIds = responses.filter((r) => r.ok).map((o) => o.id);
      savedObjectIds = savedObjectIds.concat(savedIds);

      // Send updated _revs for successful ref saves.
      const savedRefs = responses
        .map((r) => {
          r.id = unprefix(r.id);
          return r;
        })
        .filter((r) => refIds.includes(r.id) && r.ok);
      toElm(savedRefs, "docMsgs", "DataSaved");

      // Send new changes to remote
      push();

      // Set updatedAt field
      data.metadata.updatedAt = Date.now();
      fromElm("SaveMetadata", data.metadata);
    },

    SaveImportedData: async () => {
      let savePromises = data.map((doc) => {
        let dataRows = [
          ...doc.data.commits,
          ...doc.data.treeObjects,
          ...doc.data.refs,
          doc.metadata,
        ];
        let toSave = dataRows.map((r) => {
          r._id = doc.id + "/" + r._id;
          return _.omit(r, "_rev");
        });
        return remoteDB.bulkDocs(toSave);
      });
      await Promise.all(savePromises);
      toElm(null, "importComplete");
    },

    // === DOM ===

    ActivateCards: () => {
      lastActivesScrolled = data.lastActives;
      lastColumnScrolled = data.column;

      helpers.scrollHorizontal(data.column, data.instant);
      helpers.scrollColumns(data.lastActives, data.instant);

      localStore.set("last-active", data.cardId);
    },

    DragStart: () => {
      data.dataTransfer.setData("text", "");
      toElm(data.target.id.replace(/^card-/, ""), "docMsgs", "DragStarted");
    },

    FlashCurrentSubtree: () => {
      let addFlashClass = function () {
        jQuery(".card.active").addClass("flash");
        jQuery(".group.active-descendant").addClass("flash");
      };

      let removeFlashClass = function () {
        jQuery(".card.active").removeClass("flash");
        jQuery(".group.active-descendant").removeClass("flash");
      };

      addFlashClass();
      setTimeout(removeFlashClass, 200);
    },

    TextSurround: () => {
      let id = data[0];
      let surroundString = data[1];
      let tarea = document.getElementById("card-edit-" + id);

      if (tarea === null) {
        console.log("Textarea not found for TextSurround command.");
      } else {
        let start = tarea.selectionStart;
        let end = tarea.selectionEnd;
        if (start !== end) {
          let text = tarea.value.slice(start, end);
          let modifiedText = surroundString + text + surroundString;
          document.execCommand("insertText", true, modifiedText);
        }
      }
    },

    SetCursorPosition: () => {
      let pos = data[0];
      setTimeout(() => document.activeElement.setSelectionRange(pos, pos), 0);
    },

    // === UI ===
    SaveMetadata: async () => {
      data._id = prefix(data._id);
      let saveRes = await db.put(data).catch(async (e) => e);
      if (saveRes.ok) {
        await db.replicate.to(remoteDB, { doc_ids: [prefix("metadata")] });
        data._rev = saveRes.rev;
        data._id = unprefix(data._id);
        toElm(data, "docMsgs", "MetadataSaved");
      } else {
        console.error(data, saveRes);
        toElm(null, "docMsgs", "MetadataSaveError");
      }
    },

    UpdateCommits: () => {},

    SetVideoModal: () => {
      userStore.set("video-modal-is-open", data);
    },

    SetLanguage: () => {
      userStore.set("language", data);
    },

    SetFonts: () => {},

    SetShortcutTray: () => {
      userStore.set("shortcut-tray-is-open", data);
    },

    // === Misc ===

    SocketSend: () => {},

    ConsoleLogRequested: () => console.error(data),
  };

  try {
    cases[msg]();
  } catch (err) {
    console.error("Unexpected message from Elm : ", msg, data, err);
  }
};

/* === Database === */

async function load() {
  let toSend = await loadDocData();
  if (toSend.ref) {
    toElm(toSend, "docMsgs", "DataReceived");
  }
}

async function pull() {
  // Get local head before replication.
  let localHead = await db.get(prefix("heads/master")).catch(async (e) => e);

  // Fetch remote changes for current document.
  let selector = { _id: { $regex: `${TREE_ID}/` } };
  await db.replicate.from(remoteDB, { selector }).catch(async (e) => e);

  let toSend = await loadDocData();

  // Get new head, or possible conflict/branching history.
  let newHead = await db
    .get(prefix("heads/master"), { conflicts: true })
    .catch(async (e) => e);

  // Add conflicts to data to be sent.
  if (newHead.hasOwnProperty("_conflicts")) {
    let conflictHead = await db.get(prefix("heads/master"), {
      rev: newHead._conflicts[0],
    });
    if (_.isEqual(localHead, conflictHead)) {
      let setHead = (r) => {
        return r._id == prefix("heads/master") ? conflictHead : r;
      };
      toSend.ref = toSend.ref.map(setHead);
      toSend.conflict = newHead;
    } else {
      toSend.conflict = conflictHead;
    }
  }

  // Finally, send all objects into Elm repo.
  if (toSend.ref) {
    toElm(toSend, "docMsgs", "DataReceived");
  }
  if (toSend.metadata) {
    toElm(toSend.metadata[0], "docMsgs", "MetadataSynced");
  }
}

async function push() {
  let selector = { _id: { $regex: `${TREE_ID}/` } };
  await db.replicate.to(remoteDB, { selector }).catch(async (e) => e);
}

async function loadAndUpdateDocList() {
  let docList = await db.query("testDocList/docList").catch(async (e) => e);
  toElm(docList, "documentListChanged");
}

async function loadDocData() {
  // Get all local entries in db, and format in object to send to Elm.
  let result = await db.allDocs({
    include_docs: true,
    startkey: TREE_ID + "/",
    endkey: TREE_ID + "/\ufff0",
  });
  let mappedDocs = result.rows.map((r) => {
    r.doc._id = unprefix(r.doc._id);
    return r.doc;
  });
  let groupFn = (r) => (r.hasOwnProperty("type") ? r.type : r._id);
  return _.groupBy(mappedDocs, groupFn);
}

/* === Helper Functions === */

function prefix(id) {
  return TREE_ID + "/" + id;
}

function unprefix(id) {
  return id.slice(TREE_ID.length + 1);
}

/* === DOM Events and Handlers === */

// Prevent default events, for file dragging.
document.ondragover = document.ondrop = (ev) => {
  ev.preventDefault();
};

window.onresize = () => {
  if (lastActivesScrolled) {
    debouncedScrollColumns(lastActivesScrolled);
  }
  if (lastColumnScrolled) {
    debouncedScrollHorizontal(lastColumnScrolled);
  }
};

const debouncedScrollColumns = _.debounce(helpers.scrollColumns, 200);
const debouncedScrollHorizontal = _.debounce(helpers.scrollHorizontal, 200);

const editingInputHandler = function (ev) {
  toElm(ev.target.value, "docMsgs", "FieldChanged");
  selectionHandler(ev);
};

const selectionHandler = function () {
  if (document.activeElement.nodeName == "TEXTAREA") {
    let {
      selectionStart,
      selectionEnd,
      selectionDirection,
    } = document.activeElement;
    let length = document.activeElement.value.length;
    let [before, after] = [
      document.activeElement.value.substring(0, selectionStart),
      document.activeElement.value.substring(selectionStart),
    ];
    let cursorPosition = "other";

    if (length == 0) {
      cursorPosition = "empty";
    } else if (selectionStart == 0 && selectionEnd == 0) {
      cursorPosition = "start";
    } else if (selectionStart == length && selectionEnd == length) {
      cursorPosition = "end";
    } else if (selectionStart == 0 && selectionDirection == "backward") {
      cursorPosition = "start";
    } else if (selectionEnd == length && selectionDirection == "forward") {
      cursorPosition = "end";
    }

    toElm(
      {
        selected: selectionStart !== selectionEnd,
        position: cursorPosition,
        text: [before, after],
      },
      "docMsgs",
      "TextCursor"
    );
  }
};

document.onselectionchange = selectionHandler;

Mousetrap.bind(helpers.shortcuts, function (e, s) {
  toElm(s, "docMsgs", "Keyboard");

  if (helpers.needOverride.includes(s)) {
    return false;
  }
});

Mousetrap.bind(["tab"], function () {
  document.execCommand("insertText", false, "  ");
  return false;
});

Mousetrap.bind(["shift+tab"], function () {
  return true;
});

/* === DOM manipulation === */

const observer = new MutationObserver(function (mutations) {
  const isTextarea = function (node) {
    return node.nodeName == "TEXTAREA" && node.className == "edit mousetrap";
  };

  const isHelpWidget = function (node) {
    return node.nodeName == "IFRAME" && node.id == "launcher-frame";
  };

  let textareas = [];

  mutations.map((m) => {
    [].slice.call(m.addedNodes).map((n) => {
      if (isTextarea(n)) {
        textareas.push(n);
      } else if (isHelpWidget(n)) {
        helpWidgetLauncher = n;
        if (!helpVisible) {
          helpWidgetLauncher.style.visibility = "hidden";
        }
      } else {
        if (n.querySelectorAll) {
          let tareas = [].slice.call(n.querySelectorAll("textarea.edit"));
          textareas = textareas.concat(tareas);
        }
      }
    });
  });

  if (textareas.length !== 0) {
    textareas.map((t) => {
      t.oninput = editingInputHandler;
    });

    jQuery(textareas).textareaAutoSize();
  }
});

const observerConfig = { childList: true, subtree: true };

observer.observe(document.body, observerConfig);
