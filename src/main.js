const { app, BrowserWindow } = require("electron");
const path = require("path");

function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    icon: path.join(__dirname, "assets", "icon.png"),
    webPreferences: { nodeIntegration: false }
  });

  win.loadURL("https://pdf.drawboard.com/");
}

app.whenReady().then(createWindow);
