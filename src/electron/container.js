const fs = require("fs-extra");
const path = require("path");
const { remote, shell } = require("electron");
const { ipcRenderer: ipc } = require("electron-better-ipc");
import { execFile } from "child_process";
const {app, dialog} = remote;
const Store = require("electron-store");


const sendTo = ipc.send;
const callMain = ipc.callMain;
const answerMain = ipc.answerMain;
const msgWas = (...args) => {
  ipc.on(...args);
};
const showMessageBox = dialog.showMessageBox;
const openExternal = shell.openExternal;
const userStore = new Store({name: "config"});
const browserWindow = remote.getCurrentWindow();


const getInitialDocState = () => {
  return browserWindow.initialDocState;
};


const saveFile = async (jsonData, filePath) => {
  await fs.writeFile(filePath, JSON.stringify(jsonData, undefined, 2));
  const fileStats = await fs.stat(filePath);
  console.log(fileStats);
  return fileStats.mtimeMs;
};


const exportDocx = async (data, defaultPath) => {
  if (data && typeof data.replace === "function") {
    data = (process.platform === "win32") ? data.replace(/\n/g, "\r\n") : data;
  } else {
    throw new Error("invalid data sent for export");
  }

  var options =
    { title: "Export to MS Word"
    , defaultPath: defaultPath ? defaultPath.replace(".gko", "") : path.join(app.getPath("documents"),"Untitled.docx")
    , filters:  [ {name: "Word Files", extensions: ["docx"]} ]
    };

  let {filePath} = await dialog.showSaveDialog(options);

  if(typeof filePath == "string"){
    let tmpMarkdown = path.join(app.getPath("temp"), path.basename(filePath) + ".md");

    fs.writeFile(tmpMarkdown, data, (err) => {
      if (err) throw new Error("export-docx writeFile failed");

      let pandocPath = path.join(__dirname, "/../../pandoc");

      // pandoc file is copied by electron-builder
      // so we need to point to the src directory when running with `npm run electron`
      // TODO : Fix this.
      if (!app.isPackaged) {
        switch (process.platform) {
          case "linux":
            pandocPath = path.join(__dirname, "/../../src/bin/linux/pandoc");
            break;

          case "win32":
            pandocPath = path.join(__dirname, "/../../src/bin/win/pandoc.exe");
            break;

          case "darwin":
            pandocPath = path.join(__dirname, "/../../src/bin/mac/pandoc");
            break;
        }
      }

      execFile( pandocPath
        , [ tmpMarkdown
          , "--from=gfm+hard_line_breaks"
          , "--to=docx"
          , `--output=${filePath}`
          , "--verbose"
          ]
        , ( err, stdout, stderr) => {
            if (err) {
              throw err;
            }

            fs.unlink(tmpMarkdown, (err) => {
              if (err) {
                throw err;
              }

              let exportSuccessNotification = new Notification("Export Suceeded", {
                body: "Saved as " + path.basename(filePath)
              });

              exportSuccessNotification.onclick = () => {
                shell.openItem(filePath);
              };
            });
        });
    });
  }
};


const exportJson = async (data, defaultPath) => {
  var options =
    { title: "Export JSON"
    , defaultPath: defaultPath ? defaultPath.replace(".gko", "") : path.join(app.getPath("documents"),"Untitled.json")
    , filters:  [ {name: "Gingko JSON (*.json)", extensions: ["json"]}
                , {name: "All Files", extensions: ["*"]}
                ]
    };

  let {filePath} = await dialog.showSaveDialog(options);

  return new Promise(
    (resolve, reject) => {
      if(filePath){
        fs.writeFile(filePath, JSON.stringify(data, undefined, 2), (err) => {
          if (err) {
            reject(new Error("export-json writeFile failed"));
            return;
          }
          resolve(data);
        });
      } else {
        reject(new Error("no export path chosen"));
        return;
      }
    }
  );
};

const exportTxt = (data, defaultPath) => {
  return new Promise(
    async (resolve, reject) => {
      if (data && typeof data.replace === "function") {
        data = (process.platform === "win32") ? data.replace(/\n/g, "\r\n") : data;
      } else {
        reject(new Error("invalid data sent for export"));
        return;
      }

      var saveFile = function(filepath) {
        fs.writeFile(filepath, data, (err) => {
          if (err) {
            reject(new Error("export-txt writeFile failed"));
            return;
          }
          ipc.send("doc:last-export-set", filepath);
          let exportSuccessNotification = new Notification("Export Suceeded", {
            body: "Saved as " + path.basename(filepath)
          });

          exportSuccessNotification.onclick = () => {
            shell.openItem(filepath);
          };
          resolve(data);
        });
      };

      if(defaultPath) {
        saveFile(defaultPath);
      } else {
        var options =
          { title: "Export TXT"
          , defaultPath: defaultPath ? defaultPath.replace(".gko", "") : path.join(app.getPath("documents"),"Untitled.txt")
          , filters:  [ {name: "Text File", extensions: ["txt"]}
                      , {name: "All Files", extensions: ["*"]}
                      ]
          };


        let {filePath} = await dialog.showSaveDialog(options);

        if(filePath){
          saveFile(filePath);
        } else {
          reject(new Error("no export path chosen"));
          return;
        }
      }
    }
  );
};

export
  { sendTo
  , msgWas
  , callMain
  , answerMain
  , getInitialDocState
  , userStore
  , openExternal
  , showMessageBox
  , saveFile
  , exportDocx
  , exportJson
  , exportTxt
  };
